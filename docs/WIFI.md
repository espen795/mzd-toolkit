# WiFi — TI WL1271 (wl12xx) deep dive

Root-cause analysis and fixes for the CMU's built-in WiFi. Everything below was
proven against kernel logs from a live v59.00.502 unit.

## 1. Hardware & software stack

| Layer | Value |
|---|---|
| Chip | **TI WL1271**, on SDIO (mmc0, high-speed SDIO card at address 0001) |
| Interrupt | out-of-band GPIO 378 (`[irq/378-wl12xx]`) — *not* in-band SDIO DAT1 |
| Driver | `wl12xx` backport **`ol_R5.SP4.01-2-g1aa2c8e`** (compiled 2013), `wl12xx_sdio` |
| Firmware (v59) | **`Rev 7.3.10.10.136`** (`wl128x-fw-4-sr.bin` station role) |
| Firmware (v74) | `FRev 7.3.10.0.142` (sr.bin), `Rev 7.5.7.0.50` (mr.bin) — newer, but **worse in practice on this board** |
| Board calibration | `wl1271-nvs.bin` → symlinked to `/var/run/wl1271-nvs.bin`; **board-specific, keep your own** |
| wpa_supplicant | v2.6, started by NMS with `-c /tmp/wpa_supplicant.conf` |
| Tools present | `wpa_cli`, `wpa_supplicant`, `ifconfig`, `dmesg` — **no `iw`, no `iwconfig`, no `iwlist`** |

## 2. Root cause: deterministic firmware watchdog panic

The instability is a **firmware-level watchdog crash in the WL1271**, triggered
by 802.11 power save (ELP mode) combined with an SDIO bus stall during TX
buffer flush. It is *not* an AP-side problem.

Event timeline from the kernel log (timestamps = seconds since boot):

```
t=35.3    wl12xx: driver version: ol_R5.SP4.01-2-g1aa2c8e
t=37.5    wl12xx: firmware booted (Rev 7.3.10.10.136)
t=716-724 2x "authentication with <AP-MAC> timed out" + 4x "Unable to flush TX buffers"
t=733.4   wlan0: associated / wl12xx: Association completed
t=733.9   WARNING Unable to flush all TX buffers, timed out (500 ms)
t=928.3   ERROR watchdog interrupt received! starting recovery     ← FW PANIC, pc: 0x21b8e
t=928.8   ERROR no active RX BA session on tid: 0 / tid: 6         ← RX aggregation state corrupt
t=956.9   WARNING Unable to flush all TX buffers
t=957.0   deauthenticating from <AP-MAC> by local choice (reason=3)
t=985-986 5x "authenticate ... timed out"
t=987.7   ERROR watchdog interrupt received! starting recovery     ← SECOND PANIC, same pc: 0x21b8e
t=988+    10x "direct probe ... timed out" + 3x "Unable to flush TX buffers"
```

In one dump: **20× "Unable to flush all TX buffers", 2× watchdog interrupt
(both `pc=0x21b8e`), 1× deauth reason=3.**

### Why this is a firmware bug, not interference

1. **`pc=0x21b8e` is identical in both watchdogs** → deterministic crash at one
   code location, not a random hardware fault. It sits in the TX-flush /
   power-save-exit path.
2. **"Unable to flush all TX buffers" always precedes the watchdog** → the
   firmware cannot drain pending TX packets within 500 ms; the TX path
   deadlocks, the FW stops servicing the watchdog timer, and the HW watchdog
   fires a full chip restart.
3. **Watchdog ~195 s after association** → fits a power-save trigger: after a
   period of no traffic the chip enters ELP (Extreme Low Power) sleep and the
   wake-up sequence over SDIO deadlocks.
4. **After recovery, "no active RX BA session on tid 0/6"** → RX aggregation
   state is corrupt; the crash is in the BA/session-management path.
5. **`deauth reason=3`** = "disassociated by local choice" — wpa_supplicant
   gives up because the AP is unreachable *due to the TX stall*. It is a
   **symptom**, not the cause. (reason=7 is the "class 3 frame received from
   nonassociated STA" variant seen when power save is left on.)

### Contributing factors

- Old driver backport `ol_R5.SP4.01` (2013) — known queue-credit race
  conditions; newer `ol_R5.SP7.01+` releases carry fixes we can't use on
  kernel 3.0.35.
- Firmware `Rev 7.3.10.10.136` is older than v74's `.142` build — but copying
  v74's sr.bin onto v59 did **not** fix it (NVS calibration is board-specific).
- 802.11 power save (ELP) active by default in wpa_supplicant v2.6.
- Aggressive power-save APs (e.g. a phone hotspot: short DTIM, aggressive PS)
  are demanding for the WL1271.
- No power-save-off setting in the toolkit's wpa_supplicant.conf.
- Kernel 3.0.35 (2016) — none of the upstream wlcore ELP fixes.

### What it is NOT

Not an AP/interference problem (the AP answers probes; auth timeouts are caused
by the TX stall). Not DHCP/routing (the link dies at L2). Not a module-load or
NVS-calibration problem (the chip boots and associates fine). Not random
hardware failure (deterministic PC).

## 3. v59 vs v74 stability

| | v59 | v74 |
|---|---|---|
| driver | `ol_R5.SP4.01-2-g1aa2c8e` | same backport |
| sr firmware | Rev 7.3.10.10.136 | FRev 7.3.10.0.142 |
| mr firmware | Rev 7.3.10.10.136 | Rev 7.5.7.0.50 |
| observed watchdog crashes | yes | **more** — rollback to v59 recommended |

`wifi/rollback-firmware-v59.sh` (menu Tools → 10) restores the v59 firmware set
while keeping your board's NVS.

## 4. Fixes (in priority order)

All scripts are in `toolkit/wifi/` and written for BusyBox sh using only
`wpa_cli`, `ifconfig`, `/sys`, `/proc`, `dmesg` (no `iw`).

### P1 — disable power save (immediate effect, no reboot)

```sh
wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 set power_save off
echo on > /sys/class/net/wlan0/power/control      # prevent runtime suspend
```
(`wifi/fix-powersave.sh`, `fix-powersave-permanent.sh`)

With power save off the chip never enters ELP sleep → no ELP wake/sleep SDIO
race → no TX-flush deadlock → no watchdog interrupt. Trade-off: higher WiFi
power draw (acceptable — the CMU is powered while the car is on).

⚠️ wpa_cli's control socket is **per-interface**: plain `wpa_cli -i wlan0`
fails with "non-global ctrl_ifname". Always use
`wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 ...` (the toolkit wraps this
in a `wpactrl` helper).

### P2 — wpa_supplicant.conf tuning (`optimize-wpa.sh`)

```conf
ap_scan=1
scan_interval=10
bgscan="simple:1:-70:30"
fast_reauth=1
pmf=0            # phone hotspots don't do 802.11w
disable_pmksa=1
```

### P3 — watchdog monitor (`fix-watchdog.sh`, `tools/watchdog.sh`)

A loop that greps `dmesg` for `watchdog interrupt` and immediately does a soft
recovery (`wpa_cli reassociate`; fallback: NMS D-Bus `WIFI_Recovery`) *before*
the chip fully wedges. Run it as `tools/watchdog.sh bg` for background mode.
Kill only *your own* `udhcpc` (check the pid path) — never NMS's.

### P4 — firmware swap (last resort)

`upgrade-firmware-v74.sh` copies v74's `wl128x-fw-4-sr.bin` (FRev .142) onto v59 —
**keep the v59 NVS**. In practice this did not help on our board; rollback to
v59 is the stable config.

## 5. Connecting — go through NMS, never a second wpa_supplicant

NMS (`com.jci.blm_nms` on the service bus) owns wpa_supplicant + udhcpc.
`wifi/connect-nms.sh` drives it:

```
GetInterfaceList → GetInterfaceParams(wlan0) → WIFI_SetMode(1) →
WIFI_StartScan → WIFI_GetScanResults →
WIFI_GetConfiguredNetworks / WIFI_AddNetwork (or UpdateNetworkPass) →
WIFI_SelectNetwork(ifcId, netId) → Connect →
poll GetInterfaceParams for an IP (≤30 s) → udhcpc fallback
```

⚠️ **`WIFI_EnableNetwork` does NOT exist on v59's NMS** — calling it returns
`org.freedesktop.DBus.Error.UnknownMethod`. The correct sequence is
`SelectNetwork` + `Connect` only.

All D-Bus calls here use `--address="unix:path=/tmp/dbus_service_socket"`.

WiFi passwords go via the `MZD_PSK` env var or `secrets.conf` — never as a
command-line argument (visible in `/proc/<pid>/cmdline`).

## 6. USB WiFi dongle alternative (experimental)

`wifi/usb-dongle.sh` + `rt2800-modules/` + `rt2800-firmware/` bring up a
**USB rt2800 dongle as `wlan1`** (modules included, firmware files included).
Useful when the internal WL1271 is too unstable; untested beyond rt2800.

## 7. AP mode

`wifi/ap-mode.sh` turns the CMU into an access point (hostapd) so a laptop/phone
can connect *to the car* (e.g. for SSH when no hotspot is around).

## 8. Verification checklist

```sh
wifi/status.sh
wifi/driver-info.sh                 # FRev + sha256 of loaded firmware
dmesg | grep -c "watchdog interrupt"   # should stay 0 after the power-save fix
dmesg | grep "Unable to flush"         # should disappear too
ifconfig wlan0
```
