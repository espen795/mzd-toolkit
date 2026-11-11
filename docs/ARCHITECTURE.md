# Architecture — Mazda Connect CMU internals

What the toolkit hooks into. All facts verified on a v59.00.502 CMU (kernel 3.0.35, ARMv7, Freescale i.MX6).

## OS & kernel

- Kernel **3.0.35**, ARMv7, i.MX6 SoC; BusyBox userland.
- BusyBox has **`tar` + `gzip`, but no `unzip`** — hence tar.gz as the primary release format.
- No `iw` / `iwconfig` / `iwlist` — WiFi must be driven via `wpa_cli`/`wpactrl`, `/sys/class/net/wlan0/...`, `/proc/net/wireless`, `ifconfig`.
- No system D-Bus bus — only the JCI service bus (below).
- `/tmp` is RAM (tmpfs) and disappears on reboot; the OS itself (`/`) is read-only (relfs over `/dev/ffx01p1`); **`/data_persist` (and `/mnt/data_persist`) is the proven writable, persistent location** — note the mount path varies per boot (`/data_persist`, `/mnt/data_persist`, `/tmp/mnt/data_persist`; the toolkit auto-detects all three).
- `/config-mfg` is a read-only, 100%-full squashfs on mtdblock5 — never write to it (brick risk).

## GUI (JCI-IHU)

- The head unit UI is the **Opera-based JCI-IHU** page `/jci/gui/index.html`.
- It talks to backend services over **three websockets**:
  - MMUI — port **2700**
  - DBAPI — port **2766**
  - AppSDK — port **2800**
- The visible skin is an **NNG-Lua skin** shipped as `skin/*.zip`.
- Settings app: `/jci/gui/apps/syssettings/js/syssettingsApp.js` — the System tab list is built from `_SystemTabHelperArray` (dynamic) plus a static definition and i18n dicts (`syssettingsAppDict_*.js`). The toolkit's terminal patch (`tools/add-terminal-menu.sh`) adds a `"terminal"` entry (index 8, after About) to all three and routes `framework.sendEventToMmui("diag", "ReadDTC", { payload: { testId: 22 } })` — `uiaId` must be the literal `"diag"` (the testdiag service `svcjcitestdiag`), not `this.uiaId` ("syssettings"), or the event is silently dropped and the tab hangs on "Loading".
- `systemApp.js` contains the startup disclaimer timer (patched 3500→0 by `tools/fix-warning.sh`).

## D-Bus (JCI service bus)

- Address: **`unix:path=/tmp/dbus_service_socket`** — no `--system` bus exists.
- Monitor passively: `dbus-monitor --address unix:path=/tmp/dbus_service_socket "interface='com.jci.vbs.eem'"`
- Key services:
  - `com.jci.blm_nms` at `/com/jci/blm_nms` — **NMS owns wpa_supplicant and udhcpc on wlan0**. WiFi workflow: `GetInterfaceList` → `GetInterfaceParams(ifcId)` → `WIFI_SetMode(ifcId, 1=CLIENT)` → `WIFI_StartScan` → `WIFI_GetScanResults` → `WIFI_AddNetwork(ifcId, struct(ssid,bssid,secType,hidden,pass))` (secType 0=open, 4=WPA, 8=WPA2, 12=WPA+WPA2) → `WIFI_SelectNetwork` → `Connect`. Note: `WIFI_EnableNetwork` does **not** exist on the v59 NMS (`UnknownMethod`). `WIFI_Recovery` is the recovery call. Never start a second wpa_supplicant on wlan0 ("Operation not supported") and never kill NMS's processes.
  - `com.jci.vbs.eem` — vehicle data signals (e.g. `DR_SOC_MON` state-of-charge, speed, ignition, brake) — meaningful with ignition on.
  - `com.jci.testdiag` — diagnostic service behind `ReadDTC`.
- `dbus-send` needs `--reply-timeout=8000` — without it a NoReply blocks ~25 s.

## Partitions

| Device | Partition | Size | Notes |
|---|---|---|---|
| `/dev/ffx01p1` | rootfs | 478 MB | OS, read-only layer |
| `/dev/ffx01p4` | data | ~307 MB | user data |
| `/dev/mmcblk0p2` | persist | 572 MB | `/data_persist`, **writable + persistent** |
| `/dev/mmcblk0p1` | resources | 3.1 GB | raw dd only, never tar the mountpoint |

## Autorun hook

Boot chain: `/jci/scripts/stage_wifi.sh` (and `stage_1.sh`) → **`/data_persist/dev/bin/autorun`**. `install.sh` patches both stage scripts (idempotent, `.org` backups) so `autorun` runs at every boot; `autorun` starts WiFi (NMS), SSH (port 36000), the eth1 autostart, and includes a fail-counter that restores `autorun.orig` after 3 consecutive failed boots. Since firmware v59.00.502 Mazda patched USB autorun, so the hook must first be re-enabled by an external method (serial/ID7 — see the related projects in the README).

## WiFi hardware

- TI **WL1271** on SDIO (`wl12xx` backport driver `ol_R5.SP4.01-2-g1aa2c8e`, chip firmware `Rev 7.3.10.10.136` on v59; v74 ships `wl128x-fw-4-sr.bin` FRev 7.3.10.0.142). The chip has a firmware watchdog deadlock in the TX-flush/power-save path (see `wifi/WIFI-ROOTCAUSE-ANALYSIS.md`) — mitigated by power save off; the board-specific NVS calibration (`wl1271-nvs.bin`) must never be overwritten.
- `wpa_cli` only works with an explicit interface; the toolkit's `wpactrl()` auto-detects the ctrl socket at runtime (`/var/run/wpa_supplicant-wlan0/` → `/var/run/wpa_supplicant` → fallback `-i wlan0`).

## USB

- EHCI (USB 2.0) host only — no xHCI/USB3. Plain USB 2.0 hubs work; USB-C hubs with their own controller don't.
- Kernel 3.0.35 has `asix` built in (ASIX AX88772), `usbnet`, and `CONFIG_USB_NET_CDCETHER/NCM=m` (generic alias matches any CDC vendor). **No `rndis_host`, no `iph_eth`** in the stock config — the toolkit ships cross-compiled `rndis_host` v3 and `cdc_ether`/`cdc_ncm`/`r8152` modules (see below).
- `eth0` = internal processor switch without a physical PHY — never touch it. USB ethernet registers as `eth1`; phone tethering as `usb0`.

## Cross-compiling kernel modules (.ko)

Modules must match `vermagic = 3.0.35 SMP preempt mod_unload ARMv7`. The v74 rootfs ships .ko files with exactly this vermagic, so many modules can be taken from there as-is. For new compiles (see `docs/driver-compilation/` in the dev repo and `drivers/` here), the working recipe for kernel 3.0.35 with a modern gcc is:

```sh
# .config: CONFIG_ARM_UNWIND off (else Unknown symbol __aeabi_unwind_cpp_pr0)
#          CONFIG_DEBUG_INFO off (else BusyBox insmod rejects .debug_* sections)
#          CONFIG_FUNCTION_TRACER=y, CONFIG_FRAME_POINTER=y, CONFIG_PREEMPT=y
#          CONFIG_USB_NET_RNDIS_HOST=m (or the driver you need)
yes '' | make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig
cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h   # gcc12 shim
# Makefile + arch/arm/Makefile: add -fno-pic -fno-pie (gcc-12 defaults to PIE
#   -> Unknown symbol _GLOBAL_OFFSET_TABLE_)
# arch/arm/Makefile: -march=armv7-a -> -march=armv7-a+fp
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- prepare modules_prepare
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=drivers/net/usb modules
# verify: vermagic == "3.0.35 SMP preempt mod_unload ARMv7"
```

Load order matters: `cdc_ether` **before** `rndis_host`. Upload .ko files to the CMU in base64 chunks of ~3000 chars (`echo -n`) — one giant heredoc line fails with "truncated base64 input" on BusyBox.

## Release packaging

`tools/build-release.sh` stages `toolkit/`, excludes runtime/secrets, and emits `mzd-toolkit-vX.Y.Z.tar.gz` (primary, for the CMU), `.zip` (PC only, built via `zip` or python3 `zipfile`), and `SHA256SUMS`; a post-build verify fails the build if any secrets/runtime paths appear in the assets.
