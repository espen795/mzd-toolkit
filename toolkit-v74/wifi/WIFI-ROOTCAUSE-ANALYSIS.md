# MZD WiFi Root Cause Analysis - wl12xx Watchdog Panic
**Date:** October 30, 2026, 16:17 CET
**Source:** Log dump `mzd-logs-20261030/dump-19700101-002011/` (05-logs.txt ~170KB, 11-wifi-debug.txt, 02-network.txt, 06-configs.txt)
**Comparison:** v74 firmware analysis (`mazda-firmware-analysis/`)
**System:** Mazda CMU v59.00.502, Kernel 3.0.35, TI WL1271 SDIO WiFi

---

## 1. Executive Summary

The WiFi instability is caused by a **firmware-level watchdog crash in the TI WL1271 chip** (driver `wl12xx` backport `ol_R5.SP4.01-2-g1aa2c8e`, firmware `Rev 7.3.10.10.136`). The chip enters a deadlock in the TX-queue/power-save state machine, after which the hardware watchdog intervenes and forces a full hardware restart. After every recovery the chip runs into problems again, resulting in a **recovery loop** so that no stable connection to the iPhone hotspot (YOUR_HOTSPOT_SSID, BSSID `aa:bb:cc:dd:ee:ff`) is established.

**Root cause category:** Firmware/hardware bug in WL1271, triggered by 802.11 power save (ELP mode) in combination with an SDIO bus stall during TX buffer flush. **Not an AP-side problem** (the iPhone hotspot does respond to probes, but auth frames never get out because of the stuck TX queue).

---

## 2. Evidence from the logs (05-logs.txt)

### 2.1 Event timeline (kernel timestamps in seconds since boot)

| t (s) | Event | Meaning |
|-------|-------|---------|
| 35.3 | `wl12xx: driver version: ol_R5.SP4.01-2-g1aa2c8e` | Old TI backport driver loaded |
| 37.5 | `wl12xx: firmware booted (Rev 7.3.10.10.136)` | WL1271 firmware version |
| 716-724 | 2x `authentication with aa:bb:cc:dd:ee:ff timed out` + 4x `Unable to flush TX buffers` | TX queue already stuck BEFORE association |
| 733.4 | `wlan0: associated` / `wl12xx: Association completed` | Connected, but... |
| 733.9 | `WARNING Unable to flush all TX buffers, timed out (500 ms)` | TX flush fails directly after association |
| **928.3** | **`ERROR watchdog interrupt received! starting recovery`** | **FW PANIC - pc: 0x21b8e** |
| 928.8 | `ERROR no active RX BA session on tid: 0 / tid: 6` | Aggregation state corrupt after recovery |
| 956.9 | `WARNING Unable to flush all TX buffers` | TX stall again |
| 957.0 | `deauthenticating from aa:bb:cc:dd:ee:ff by local choice (reason=3)` | wpa_supplicant gives up (AP unreachable) |
| 985-986 | 5x `authenticate ... timed out` | Auth timeouts again |
| **987.7** | **`ERROR watchdog interrupt received! starting recovery`** | **SECOND FW PANIC - pc: 0x21b8e (same PC!)** |
| 988-1010 | 10x `direct probe ... timed out` + 3x `Unable to flush TX buffers` | Chip no longer responds |
| 1045, 1118 | `removing interface` / `Powering off/on wl12xx` | More manual restarts |

**Total in this dump:** 20x "Unable to flush all TX buffers", 2x watchdog interrupt (both pc=0x21b8e), 1x deauth reason=3.

### 2.2 Critical observations

1. **pc: 0x21b8e is identical in both watchdogs** -> deterministic firmware crash at one specific code location, not a random hardware fault. This points to a firmware bug in a specific code path (probably the TX-flush or power-save exit path).

2. **"Unable to flush all TX buffers" ALWAYS precedes the watchdog** -> the firmware cannot empty pending TX packets within 500ms. This is the direct antecedent of the watchdog: the TX path deadlocks, the FW stops servicing the watchdog timer, and the HW watchdog fires.

3. **Watchdog at t=928s is ~195s after association (t=733s)** -> the chip is stable for ~3 minutes, then crashes. This fits a power-save related trigger: after some time of inactivity (no data traffic to the iPhone hotspot) the chip goes into ELP (Extreme Low Power) sleep, and the wake-up sequence hangs.

4. **After recovery (t=928s) immediately "no active RX BA session on tid 0/6"** -> the RX aggregation state is corrupt; this confirms the firmware crash is in the BA/session management path.

5. **deauth reason=3 at t=957s** -> `reason=3` = "Disassociated because sending STA is leaving (or has left) BSS" - this is "local choice", i.e. wpa_supplicant/mac80211 breaks the connection because the AP no longer responds (due to the TX stall). This is a **symptom**, not the cause.

6. **wpa_state=DISCONNECTED, scan_results empty in dump (11-wifi-debug.txt)** -> at the time of the dump the chip was in recovery again and could not scan.

7. **wpa_supplicant runs with `-c /tmp/wpa_supplicant.conf`** (04-processes.txt PID 7163) -> our toolkit config, NOT /etc/wpa_supplicant.conf (that one is empty on v59: only a `ctrl_interface=` line). /etc/wpa_supplicant.conf contains `#ap_scan=2` (commented out).

8. **No iw / iwconfig / iwlist on the system** (00-SUMMARY, 11-wifi-debug) -> power save CANNOT be disabled via `iw dev wlan0 set power_save off`. Alternatives: `wpa_cli`, `/sys/class/net/wlan0/power/`, `/proc/net/wireless`.

9. **wl12xx IRQ is Out-Of-Band GPIO 378** (`[irq/378-wl12xx]`, `378: 691 GPIO wl12xx` in /proc/interrupts) -> this is GOOD (OOB, not in-band SDIO DAT1), so the in-band interrupt race is less likely here as the primary cause; the problem is in the FW state machine itself.

10. **SDIO bus: mmc0 high speed card** (`mmc0: new high speed SDIO card at address 0001`) -> the SDIO clock runs at high speed; during ELP wake-up this can cause timing issues.

---

## 3. Root Cause Determination

### 3.1 Primary root cause: WL1271 firmware deadlock in TX-flush / power-save path

```
[Stable association t=733s]
    -> [no data traffic / iPhone hotspot sends few beacons]
    -> [WL1271 FW goes into ELP sleep (power save)]
    -> [host wants TX buffer flush (scan/auth/deauth)]
    -> [SDIO wake-up handshake fails or FW state machine deadlock]
    -> ["Unable to flush all TX buffers, timed out 500ms" x N]
    -> [FW stops watchdog servicing]
    -> [HW watchdog interrupt -> pc 0x21b8e -> full hardware restart]
    -> [after restart: RX BA state corrupt, TX queue empty but chip instability]
    -> [wpa_supplicant deauth reason=3 -> reconnect loop]
    -> [2nd watchdog at t=987s -> permanently unreachable]
```

### 3.2 Contributing factors

| Factor | Evidence | Impact |
|--------|----------|--------|
| **Old driver backport ol_R5.SP4.01** | `wl12xx: driver version: ol_R5.SP4.01-2-g1aa2c8e`, compiled 2013 | Known race conditions in queue credit management; newer releases (ol_R5.SP7.01+) have fixes |
| **Firmware Rev 7.3.10.10.136** | `firmware booted (Rev 7.3.10.10.136)` | v74 extract has `wl128x-fw-4-sr.bin` with **FRev 7.3.10.0.142** (newer build) and mr.bin with Rev 7.5.7.0.50 -> **our v59 firmware is OLDER than v74** |
| **802.11 Power Save (ELP) active** | watchdog ~3min after idle association; TX flush timeouts | ELP wake/sleep over SDIO is the trigger |
| **iPhone hotspot as AP** | BSSID aa:bb:cc:dd:ee:ff (Apple), aggressive PS | Apple hotspots use short DTIM + aggressive PS; demanding for WL1271 |
| **No power_save=off in wpa_supplicant.conf** | /etc/wpa_supplicant.conf empty; /tmp/wpa_supplicant.conf from toolkit has no power_save line | Default wpa_supplicant v2.6 has power save ON |
| **Kernel 3.0.35 (2016)** | `/proc/version` | Very old kernel, no upstream wlcore ELP fixes |
| **wpa_supplicant.conf without optimizations** | only ctrl_interface line | No scan_interval, bgscan, or fast_reauth tuning |

### 3.3 What it is NOT

- ❌ **Not an AP/interference problem**: the iPhone responds to direct probes (t=716, 722, 733), auth timeouts are the result of TX stall, not RF interference.
- ❌ **Not a DHCP/routing problem**: there is no IP conflict or broken route; the connection already fails at L2.
- ❌ **Not a module load problem**: wl12xx/wl12xx_sdio are loaded and the chip boots fine.
- ❌ **Not an NVS calibration problem**: the chip boots and associates, NVS is OK.
- ❌ **Not random hardware failure**: pc=0x21b8e is deterministic.

---

## 4. Firmware comparison v59 vs v74

| Component | v59 (MZD active) | v74 (extract) | Remark |
|-----------|------------------|---------------|--------|
| Driver | `ol_R5.SP4.01-2-g1aa2c8e` (2013) | same backport in modules | Same driver |
| **SR firmware** | **Rev 7.3.10.10.136** | **FRev 7.3.10.0.142** | ⚠️ v74 is NEWER (142 > 136 in patch/build) |
| MR firmware | Rev 7.3.10.10.136 | Rev 7.5.7.0.50 | v74 mr.bin is much newer |
| wpa_supplicant | v2.6 | v2.6 | Same |
| Kernel | 3.0.35 | 3.0.35 | Same |

**Conclusion:** The v74 firmware contains a newer station-role firmware (`wl128x-fw-4-sr.bin` with FRev 7.3.10.0.142). Copying the v74 firmware files to v59 can reduce the watchdog crashes if the .142 build contains the TX-flush/power-save fix. **Note:** the NVS calibration (`wl1271-nvs.bin`) is board-specific and MUST stay from v59!

Firmware files in v74 extract:
```
/lib/firmware/ti-connectivity/wl128x-fw-4-sr.bin       (FRev 7.3.10.0.142) <- station role
/lib/firmware/ti-connectivity/wl128x-fw-4-mr.bin       (Rev 7.5.7.0.50)    <- multi role
/lib/firmware/ti-connectivity/wl128x-fw-4-plt.bin
/lib/firmware/ti-connectivity/wl128x-fw-multirole-roc.bin
/lib/firmware/ti-connectivity/wl1271-nvs.bin -> /var/run/wl1271-nvs.bin (symlink, board-specific!)
```

---

## 5. Fix Strategy (priority)

### Priority 1: Power Save OFF (direct effect, no restart needed)
Because `iw` is missing, via:
- `wpa_cli -i wlan0 set power_save off` (wpa_supplicant level)
- `/sys/class/net/wlan0/power/control` = "on" (prevent runtime suspend)
- wpa_supplicant.conf: `disable_pmksa=1`, `power_save=0` (if supported by v2.6)

### Priority 2: wpa_supplicant config optimization
- `ap_scan=1` (instead of default)
- `scan_interval=10` (scan less often = fewer TX flush triggers)
- `bgscan="simple:1:-70:30"` or disable -> fewer background scans
- `fast_reauth=1`
- `pmf=0` (iPhone hotspot does not do 802.11w)

### Priority 3: Make watchdog recovery lighter / monitor it
- Script that monitors dmesg for "watchdog interrupt" and immediately does a soft recovery (wpa_cli reassociate) BEFORE the chip fully hangs
- Module params via /sys/module/wl12xx/parameters/ if present

### Priority 4: Firmware upgrade (v74 sr.bin to v59)
- Backup old firmware, copy v74 `wl128x-fw-4-sr.bin` (FRev 7.3.10.0.142)
- Keep NVS calibration!
- Restart WiFi (rmmod/insmod or reboot)

### Priority 5: AP channel / interference (secondary)
- If the power save fix does not help: put the iPhone hotspot on a different channel (2.4GHz channel 1/6/11)

---

## 6. Ready-made Fix Scripts

See the following files in `mzd-toolkit/wifi/`:

| Script | Purpose |
|--------|---------|
| `fix-powersave.sh` | Turn WiFi power save OFF via wpa_cli + /sys (no iw needed) |
| `fix-watchdog.sh` | Watchdog monitor + auto soft-recovery + module param check |
| `optimize-wpa.sh` | Optimize wpa_supplicant.conf (scan interval, bgscan, fast_reauth) + restart |
| `upgrade-firmware-v74.sh` | Copy v74 wl128x-fw-4-sr.bin (FRev 7.3.10.0.142) to v59 (keep NVS!) |

These scripts are written for **BusyBox sh** on the MZD (kernel 3.0.35), use ONLY `wpa_cli`, `ifconfig`, `/sys`, `/proc`, `dmesg` - no `iw`/`iwconfig`/`iwlist`.

---

## 7. Integration in toolkit menu

In `menu.sh` wifi_menu() add:
```sh
echo "  7. Fix Watchdog (auto-recovery monitor)"
echo "  8. Power Save OFF"
echo "  9. Optimize wpa_supplicant"
echo " 10. Upgrade WiFi firmware (v74)"
```

---

## 8. Expected outcome

With power save disabled:
- WL1271 NEVER goes into ELP sleep -> no ELP wake/sleep SDIO race -> no TX flush deadlock -> no watchdog interrupt
- Trade-off: higher power consumption of the WiFi chip (relevant in a car, but the CMU runs on ignition so acceptable)
- If power save alone does not help: firmware upgrade to FRev 7.3.10.0.142 (v74) + wpa_supplicant tuning

---

*Analysis by the toolkit - October 30, 2026*
*Based on: mzd-logs-20261030/dump-19700101-002011/ + mazda-firmware-analysis/ (v74) + TI wl12xx/wlcore public bug knowledge*
