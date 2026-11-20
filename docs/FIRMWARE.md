# Firmware — versions, layout, rollback

## 1. Version numbering

Mazda CMU firmware versions look like `59.00.502` or `74.00.324A`:

- First field = major platform generation (`59` = the v59 line shipped in
  2017-era cars, `70`/`74` = later generations).
- The full build identifier is embedded in the image, e.g.:

```
MAZ_CMU-150_59.00.502   flavor cmu150_EU   build 2017-05-09
```

- Adjacent builds exist within a line (the v59 image records `prior
  58.78.006`, `next 59.00.503`).
- The suffix letter on v74 builds (e.g. `74.00.324A`) is a regional/variant
  marker (NA vs EU hardware is identical).

The authoritative component list is **`/jci/version.ini`** — it contains every
component's version (`JCI_BLM_*`, `CPP_*`, `GUI_*`, `MMUI_*`, `VUI_*`, …). The
toolkit's `tools/firmware-info.sh` / dump scripts capture it in `SUMMARY.txt`,
which makes it diff-able between firmware generations.

## 2. The v59.00.502 USB-autorun patch — and what it means

Starting with **v59.00.502**, Mazda patched out the USB autorun mechanism that
earlier firmwares had. Consequence:

> You cannot simply drop a `autorun` script on a USB stick and have the CMU run
> it. Autorun must first be **re-enabled via a serial or ID7-based method**.

The established community methods:

- https://github.com/Trevelopment/cmu-autorun — ID7 recovery zip that installs an
  `autorun` script into `/data_persist/dev/bin/`
- https://github.com/mzd-evo/mzd-connect-1-root — root-access research for the
  MZD Connect 1, including the MP3/XSS vector used to unlock ID7 on v59.00.502

Once autorun is in place, the hook chain is:

```
/jci/scripts/stage_wifi.sh  →  /data_persist/dev/bin/autorun
```

(see ARCHITECTURE-CMU.md). This toolkit's `install.sh` **extends** that
`autorun` (with `.orig` backup + fail-counter); it does not create the initial
hook.

## 3. v59 vs v74 — what differs (and why we recommend v59)

Same kernel (3.0.35), same wpa_supplicant (v2.6), same driver backport — but
different WiFi chip firmware and different autorun/USB policy:

| Component | v59 | v74 | Note |
|---|---|---|---|
| wl12xx station firmware (`wl128x-fw-4-sr.bin`) | **Rev 7.3.10.10.136** | **FRev 7.3.10.0.142** | v74 is newer — but on our hardware it produced **more** watchdog crashes, not fewer |
| wl12xx multi-role firmware (`wl128x-fw-4-mr.bin`) | Rev 7.3.10.10.136 | Rev 7.5.7.0.50 | v74 much newer |
| USB autorun | patched out | **compiled out** — `UPDATEA_SYS_SRV_enableUsbDbgScript` is const `0` in `svcjciupdatea.so` (disassembly-proven); sticks mount but never execute. Serial `cmu` login (uid 0) is the working root route | see V74.md |
| SSH | stock sshd on port 36000, keys in `/data_persist` | stock sshd reads `AuthorizedKeysFile /config-mfg/authorized_keys` (Mazda key only); own sshd needed (`ssh/sshd_config_v74`). `neutralizeid7` deletes the autorun hook on every update | see V74.md |
| Firewall | permissive | `jci-fw.sh`: `-P INPUT DROP` + ICMP echo-request dropped; TCP 36000 accepted (not on wlan0) | ping fails, SSH works — see V74.md |
| GUI terminal | `ReadDTC testId=22` works via `systemHooks.sh 22` | stock v74 drops testId=22 (`startSystemScripts.sh` knows only code 11); terminal = diag menu item 10 (page 2) | patch startSystemScripts.sh to delegate — see V74.md |
| stage scripts | content + hook points | shebang-only (empty) except `start_network.sh` (root, loads usbnet/asix, eth1, sshd) | hook still works via `sm` |

**WiFi stability:** the wl12xx watchdog panic root cause (WIFI.md) is *worse*
on v74 in practice — the TX-flush/hardware-watchdog recovery loop was observed
on both, and the v74 `sr.bin` (.142) did **not** fix it on this board's NVS
calibration. The toolkit ships `wifi/rollback-firmware-v59.sh` (also reachable
as **Tools → menu option 10**): rollback to v59 is the recommended stable
configuration. The board-specific NVS calibration (`wl1271-nvs.bin`) must always
stay the one belonging to your own unit.

## 4. version.ini component list

`/jci/version.ini` holds one entry per subsystem, for example
`JCI_BLM_*`, `CPP_*`, `GUI_*`, `MMUI_*`, `VUI_*`, plus flags like
`JCI_VR_PRESENT="NO"`. Use it to:

- confirm the exact firmware you are on,
- diff two firmware generations component-by-component (the v59 dump's
  `SUMMARY.txt` is directly diff-able against a v74 extract),
- detect region flavor (`cmu150_EU` etc.).

## 5. Build date strings

Build dates appear both in the image name (`…_59.00.502`, build `2017-05-09`)
and in the kernel banner (`Thu Oct 27 14:55:44 PKT 2016`). When comparing two
dumps, always compare **both** — the kernel banner date and the
`version.ini`/`SUMMARY.txt` build date are independent.

## 6. Rootfs diff: v59 vs v74 (image analysis, 2026-11)

Both images use the same **MAST container** (magic `MAST` at offset `0x40`,
page size `0x1000`, hardware serial at `0x58`, trailing `JMET`/`META` blocks)
over a **relfs** (Datalight Reliance Nitro v2.7) filesystem. Both contain
kernel **3.0.35 SMP preempt mod_unload ARMv7** (i.MX6) and **BusyBox v1.19.2**;
v74 ships **OpenSSH 5.9p1**. v74 is ~5x larger (478 MB vs 94 MB) and is a
strict superset of v59: **1,395 extra file paths** (849 -> 2,244 unique
paths), **0 removed** - so a technical rollback to v59 is possible.

Highlights of what is new in v74:

| Area | v59 | v74 | Note |
|---|---:|---:|---|
| `/jci` total paths | 471 | 954 | incl. 206 new native-GUI PNGs (rear-camera UI assets) |
| `/etc` total paths | 60 | 168 | new: `/etc/dbus-1/` (2 buses), `/etc/bluetooth/`, CA certs |
| `/config-mfg` | 6 | 9 | + `eol_test_date.dat`, `fvt_test_date.dat`, `mfg-version.ini` |
| `/data_persist` | 6 | 24 | + extended logging dirs; `dev/bin/autorun` hook present in both |
| D-Bus `com.jci.*` names | 442 | 1,265 | 823 new, 0 removed; v74 adds an `hmi.conf` bus |
| SSH config | 8 files | 16 files | **`sshd_config` byte-identical**; v74 adds ECDSA host key + client files |

Security-relevant findings in the v74 rootfs:

- `sshd_config` is **byte-identical** in v59 and v74: `Port 36000`,
  `PermitRootLogin yes`, `PubkeyAuthentication yes`,
  `AuthorizedKeysFile /config-mfg/authorized_keys`,
  `PasswordAuthentication no`. `/config-mfg` lives in NOR flash (`mtdblock5`,
  read-only) and is **never overwritten by a `.up` update** - the SSH pubkey
  route keeps working after every firmware update.
- v74 adds a developer-mode GUI hook:
  `/jci/gui/common/js/developer_mode_GuiConfig.js` is copied by
  `developer_mode.sh` to `/data/integration/developer_mode_GuiConfig.js` and
  loaded by `index.html` if present there.
- v74 ships more credential material in the rootfs (`/jci/keys/private_key.pem`,
  `/etc/cert/user.prv`), a USB auth daemon (`/usr/sbin/usb_authd`) and PPP auth
  hooks - a larger attack surface than v59.
- New in v74: region SKU files under `/jci_mazda/` (`sku_eu.ini`, `sku_na.ini`,
  ...), CarPlay-related libs (`libjciahaservice.so`), AppSDK plugins, NNG
  navigation debug configs.

## 7. Updating to v74.00.324A EU N - procedure summary and warnings

v74.00.324A is the **final firmware** for the Gen-1 CMU-150 (no further
standalone updates). It cumulatively contains all code of v55/v56/v58/v59/v70
(140+ bugfixes since v56). Since 2023, **v70.00.100 is no longer needed as an
intermediate step**: from v56.00.100 or higher (e.g. v59.00.502A) you can go
straight to v74.00.324A. It is a **single-file update** - the failsafe image is
bundled inside the `.up` and installs automatically (no separate failsafe.up).

Source: community update guide by user "ASH8" (Mazda3Revolution thread
"CONNECT Update Firmware"), cross-checked 2026-11-16. Status: procedure
**[reported by community]**, file hashes verified locally.

### Preconditions (all required)

1. **Strong car battery** (max 4 years old) or a 12V charger connected during
   the update; weak battery = brick risk. Alternative: a second 12V battery in
   parallel via jumper cables (red-red, black-black).
2. **Press the pedals every <20 min** (brake on automatic, clutch on manual);
   set an 18-minute countdown timer. If the CMU powers off during the update,
   it can brick.
3. **USB flash drive <=16 GB, FAT32** (not exFAT!), freshly formatted, with
   **only** the `.up` file on it - no other files, folders or pictures. No
   micro-SD in an adapter. 2017+ models also accept 32 GB. Use the **top USB
   port**, leave the lower one empty. Drives with an LED indicator are
   recommended.
4. **Parking brake ON** (including eBrake).
5. **Remove the navigation SD card** (only while the car is OFF); reinsert it
   only after the update is 100% complete. A bootloop after the update is
   usually caused by the SD card being present during the update.
6. **Key fob inside the car** (e.g. in the console).
7. **Engine NOT running** - a running engine makes the PCM talk to the IC/CMU
   and can block read/write, causing a stall or brick.

Extra preparation: disconnect all USB cables, Bluetooth and WiFi from phones
before starting; remove Mazda pairings and turn Bluetooth off on all paired
phones; radio ON at low volume (you must hear it); remove dashcams and other
USB devices; download to a PC first, then copy the `.up` to the clean USB;
on Windows show hidden files and delete everything except the `.up` (incl.
"System Volume Information"); Mac users must remove `.DS_Store`/`.AppleDouble`
files (e.g. with BlueHarvest) or the CMU will not see the file.

### Update steps

1. Car OFF, SD card removed, parking brake ON, engine off, key fob inside.
2. Insert the USB stick (only the `.up` file) into the **top** USB port.
3. Switch the car to **ACC** (press Start/Stop once without a pedal).
4. In the Test Screen (diagnostic menu), find the update file via **#99**
   (USB search).
5. Select the **"Reinstallation Package"** (e.g.
   `cmu150_EU_74.00.324A_update.up`).
6. Start the update. Once started: **never stop, never remove the USB** until
   100% complete. Total install time: **38-55 minutes**.

During the update: a black/empty screen for +15 min at the start is **normal**;
a progress bar "stuck" at 23% or 89% is still running; a blinking USB LED means
the CMU is reading/writing (good); if the LED stops blinking or you see
"make sure USB inserted" / "INSTALL NOT SUCCESSFUL", pull the USB and reinsert
it immediately - the update restarts automatically (keep pressing the pedals);
"Validation Failed / Failed to validate package certificate" usually means the
drive is too large (>16 GB on 2014-2016 cars) or has hidden files - use another
drive.

When finished you see:

```
***Version 74.00.324 Software Install was Successful
Please Turn ACC off and on again for changes to take effect***
```

Then: press Start/Stop once (IGNITION), press again (all OFF), reinsert the
navigation SD card (M-logo first), wait a minute, start the car again, and
(recommended) do a **Factory Reset** (Settings -> System -> Reset, engine
running, SD card removed).

### WARNING: updating to v74 removes known root routes

- v74.00.324A **automatically removes** most tweaks/customizations (AIO etc.).
  Installing tweaks on v74 has been reported to cause WiFi problems, Bluetooth
  issues and Android Auto/CarPlay crashes that cannot be undone.
- The classic USB-tweak path is gone on v74 (see section 3 above: autorun
  blocked, serial is not a working login). What **does** survive an update to
  v74 is the stock SSH on port 36000 with the pubkey in
  `/config-mfg/authorized_keys` (NOR flash, never overwritten) and the
  `jci-autorun` USB hook present in the v74 binary - see
  [ROOT-ACCESS.md](ROOT-ACCESS.md) sections 1-5.
- If a `reinstall.up` wipes `/data_persist` (`cleandatapersist/`), the toolkit
  and autorun must be redeployed after the update (via `jci-autorun` on USB or
  manually over SSH port 36000).
- Bootloop/restart after the v74 update: remove the SD card and do a Factory
  Reset (engine running, SD card out). A cracked/aged display can block the
  Test Screen and prevent the update from starting.

## 8. Rollback procedure

1. Menu → **Tools → 10** (`wifi/rollback-firmware-v59.sh`), or run the script
   directly on the CMU.
2. It restores the v59 WiFi firmware set (`wl128x-fw-4-sr.bin` Rev
   7.3.10.10.136 etc.) while **keeping your board's `wl1271-nvs.bin`**.
3. Reboot the CMU (Mute + Navi, 10 s).
4. Verify with `wifi/check-firmware.sh` (prints FRev + sha256 of the loaded
   firmware) and `dmesg | grep -c "watchdog interrupt"` over a drive.
