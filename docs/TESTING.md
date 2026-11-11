# Testing

What was — and was not — verified on real hardware. "Tested" below means: executed on an actual Mazda Connect CMU (firmware v59.00.502, kernel 3.0.35 ARMv7) with the run captured in `mzd-data/logs/runs/` (stdout/stderr/exit code) and, where relevant, cross-checked against `dmesg`, `ifconfig`, `netstat` and D-Bus introspection on the same boot.

## Tested on v59.00.502 hardware

| Area | What was verified | Evidence |
|---|---|---|
| WiFi via NMS | `connect-nms.sh` exit 0 with IP on the car's hotspot; scan → add network → select → connect → DHCP via NMS; udhcpc fallback; default-route repair after IP | run logs `connect-nms` (exit 0, IP assigned; later runs exit 4 with watchdog evidence) |
| wl12xx root cause | Deterministic FW watchdog crash `pc: 0x21b8e` preceded by "Unable to flush all TX buffers"; `deauth reason=3/7`; analysis in `toolkit/wifi/WIFI-ROOTCAUSE-ANALYSIS.md` from a full log dump | `dmesg` timeline in the dump, 20× TX-flush + 2× watchdog |
| Power-save fix | `fix-powersave*.sh` sets `/sys/module/wl12xx/parameters/ps=off` (not `on` — that was a real bug), `/sys/.../power/control=on`, rfkill unblock | run logs + dmesg before/after |
| Watchdog recovery | `tools/watchdog.sh once/bg/stop/status`; NMS `WIFI_Recovery` fallback; detects `watchdog interrupt` / `pc: 0x…` / TX-flush signatures | watchdog loop log |
| SSH pubkey | RSA-2048 keypair (`ssh/id_mzd`), pubkey in `/data_persist/dev/bin/authorized_keys` + `/tmp/mzd-sshd/authorized_keys` (600), sshd on 36000, connect from Linux with `-o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa` | successful `ssh -p 36000 cmu@<CMU_IP> -i id_mzd` sessions |
| SSH password | `chpasswd` → DES hash (13 chars, no `$`) in `/etc/passwd`; verified auth; SHA hashes proven to fail silently on v59 libcrypt | `/etc/passwd` dump + auth attempts |
| sshd 5.9p1 compat | `UsePAM`/`prohibit-password`/`-E`/ecdsa rejected; `PermitRootLogin yes` required (cmu is uid 0); stock `/etc/ssh` host keys copied; `sshd -t` validation | config-test output captured on screen |
| USB tethering (Samsung, RNDIS) | host mode `usbroleswitch=1`, `cdc_ether` before `rndis_host` v3, `new_id` bind `04e8:6863`, `usb0` up + `udhcpc` → IP; AOA PID `04e8:6860` proven **not** to produce usb0; Termux SSH back to CMU over usb0 verified | `usb-tether.sh` run logs exit 0, `ifconfig usb0` |
| LAN dongle eth1 | ASIX AX88772 (`0b95:772a`) via built-in `asix` → `eth1` registered (took ~58 s once), static IP set, ping gateway OK; RTL8152 (`0bda:8152`) via `cdc_ether` `new_id` bind; eth0 untouched | `dmesg` traces, `ifconfig eth1` |
| Terminal menu injection | `add-terminal-menu.sh` patch on real `syssettingsApp.js`: static + dynamic `_SystemTabHelperArray` entries, i18n dicts, `uiaId="diag"`; `node --check` OK; VM harness: SelectTerminal → `ReadDTC testId=22` to MMUI | patched GUI dump + test suite |
| Backup | `tools/backup.sh` (tar of configs + data_persist); raw `dd bs=1M` of `/dev/ffx01p1`, `/dev/ffx01p4`, `/dev/mmcblk0p2`, `/dev/mmcblk0p1` in background with watchdog disabled; size + md5 spot-checks | backup files, `ls -l`, `md5sum` samples |
| Release build | `tools/build-release.sh` → tar.gz + zip + SHA256SUMS; post-build verify catches planted secrets (dummy `secrets.conf` test detected → exit 1) | build logs, asset listing, `sha256sum -c` |
| Persist-install | Full toolkit copied to `/data_persist/mzd-toolkit` (atomic swap, `.old` rollback, exec-bits fixed, secrets excluded); works after stick removal + reboot; autorun runs from persist | boot without stick, menu from `/data_persist/mzd-toolkit/menu.sh` |
| Off-car test suites | `sh -n` / `busybox sh -n` clean on all scripts; mock suites: persist-bootstrap 15/15, usb-tether 18/18, driver-swap 21/21, terminal-menu node tests | test runner output |

## Not tested / known limitations

- **v74 firmware long-term** — watchdog loops and TX-flush storms observed; rollback to v59 is the supported path. A full v74 upgrade is explicitly not supported (region lock, autorun wipe, firewall drops 36000).
- **iOS USB tethering** — kernel has no `iph_eth`; not supported.
- **USB WiFi dongle (`wlan1`, rt2800usb)** — modules load with matching vermagic, but end-to-end stability on the road was not long-term tested; also invisible to the Mazda GUI (NMS only manages wlan0). Experimental.
- **Dongles other than ASIX AX88772 / RTL8152** — untested.
- **Password auth over WiFi** — works technically, but is brute-forceable; pubkey is the recommended method. Not a tested-hardening claim, a deliberate warning.
- **Long backups under load** — safe only with the hardware watchdog disabled; re-enable it afterwards.
- **USB-C / USB3 hubs** — not recognized (EHCI only); passive USB 2.0 hubs verified.
- **eth1 registration time** — can take up to ~60 s after boot; scripts wait, but don't be alarmed by the delay.
- **CMU clock is unset** (boots at 19700101) — log dirs use boot_id (`/proc/sys/kernel/random/boot_id`) + a persistent run counter instead of wall-clock time.

## How to re-run the off-car tests

```sh
sh toolkit/tools/build-release.sh "" /tmp/mzd-release-test   # packaging + secret-scan verify
sh -n $(find toolkit -name '*.sh')                           # syntax
busybox sh -n $(find toolkit -name '*.sh') 2>/dev/null || true
```

Hardware tests require the CMU: every menu action is logged to `mzd-data/logs/runs/vX.Y.Z-<script>-b<boot8>-r<seq>/{stdout.log,stderr.log,exit.code,meta.env}`, so a failing feature always leaves an audit trail on the stick.
