# Changelog

All notable changes to the MZD Toolkit. Versions v4.7.1–v4.8.21 were developed 2026-11-01 through 2026-11-09, each verified on real CMU hardware (v59.00.502) with captured run logs.

## [4.8.21] - 2026-11-09
- Current release line; version single-sourced in `lib/common.sh` (`TOOLKIT_VERSION`).

## [4.8.20] - 2026-11-09
- Review-pass blocker fixes: `PermitRootLogin yes` restored (cmu is uid 0), password-auth setting no longer clobbered, autorun kill-guard (don't restart sshd if 36000 already LISTENs), eth1/eth0 IP fallback, explicit lib paths for the flat persist copy, stable host keys copied from `/etc/ssh`, all `AuthorizedKeysFile` paths use `/data_persist`.

## [4.8.19] - 2026-11-09
- v59 sshd is OpenSSH 5.9p1 (2011): removed `UsePAM`, `prohibit-password`, ecdsa/ed25519 host keys from all configs; DES hash via `chpasswd`; supported option set documented.

## [4.8.18] - 2026-11-09
- Client-side v59-compat flags (`HostKeyAlgorithms=+ssh-rsa,ssh-dss`, `PubkeyAcceptedAlgorithms=+ssh-rsa`) documented/baked into helpers — modern OpenSSH clients otherwise refuse the old host key types.

## [4.8.17] - 2026-11-09
- Persist-mode key fix: `fix-ssh.sh`/`deploy-key.sh`/`start.sh` find `id_mzd.pub` in `/data_persist/mzd-toolkit/ssh/` first, then USB, then generate an RSA key on the CMU; pubkey deployed to both authorized_keys paths without reboot.

## [4.8.16] - 2026-11-09
- RSA-2048 keys only (v59 sshd rejects ed25519); `chpasswd` for DES hashes; rsa+dsa host keys only; pubkey install works without USB/reboot; persist-mode lookups.

## [4.8.15] - 2026-11-09
- DES-crypt password auth (13-char hash, validated) proven necessary on v59; ASIX AX88772 (`0b95:772a`) dongle binding + eth1 wait loop; explicit static ifconfig for eth1.

## [4.8.14] - 2026-11-08
- Terminal patch fixed to send `ReadDTC` with literal `uiaId="diag"` (was `this.uiaId` → event silently dropped, tab stuck on "Loading"); new `ensure_root_rw()` with real touch-test; `ssh-pwd.sh` verifies the hash after writing `/etc/passwd`.

## [4.8.13] - 2026-11-07
- Terminal menu patch also adds the **static** `_SystemTabHelperArray` entry (index 8 after About) — fixes System tab hanging on "Loading"; verified with `node --check` against a real v59 GUI dump.

## [4.8.12] - 2026-11-06
- RTL8152 (`0bda:8152`) eth1 binding via `cdc_ether` new_id; static `192.168.0.2/24` on eth1 (eth0 untouched); password SSH with priv-sep user/dirs; autostart eth1+SSH at boot via `net/autostart-eth1-ssh.sh` + `tools/install-autostart.sh`.

## [4.8.11] - 2026-11-05
- SSH survives reboot (own sshd keeps the key, host-key fallback to `/etc/ssh`); RTL8152 dongle support via `cdc_ether` + `new_id` bind + driver compilation guide; net/ssh helper scripts.

## [4.8.10] - 2026-11-05
- Fixed sysfs `new_id` binding path in `usb-tether.sh` (VID:PID now read correctly); on-screen USB diagnostics at tether failure (flags RNDIS-mode phones); `copy-logs-usb.sh` copies every writable USB stick incl. persist logs.

## [4.8.9] - 2026-11-04
- Fixed persist-mode boot: `TOOLKIT_DIR` no longer escapes the toolkit root; empty USB mountpoints no longer block persist detection; `menu.sh` finds its lib from any cwd; menu/SSH info recognize `usb0`/`wlan1`; tether hint prints the correct SSH target (CMU IP, not the phone gateway).

## [4.8.8] - 2026-11-04
- On-car fixes: install.sh no longer overwrites the new persist-first autorun with a legacy heredoc; exec-bits set on all persist scripts; `.ko` sha mismatch downgraded to a warning (kernel vermagic is the real gate); `/data_persist` path auto-detected across its 3 mount variants; persist logs copied to USB.

## [4.8.7] - 2026-11-04
- **Persist-install**: whole toolkit copied to `/data_persist/mzd-toolkit` (atomic swap, rollback, secrets excluded) so the stick can be removed; `bootstrap_paths` falls back to persist without USB; autorun is persist-first; new standalone `system/net-ssh-setup.sh` (internet + SSH from one downloaded script).

## [4.8.6] - 2026-11-03
- USB tethering from Android as `usb0` via bundled `usbnet`/`cdc_ether`/`cdc_ncm` modules (v74 rootfs, matching vermagic); CDC device detection + `new_id` bind; udhcpc on usb0. RNDIS/iOS not supported by the stock kernel config. Documented EHCI-only USB (USB 2.0 hubs only).

## [4.8.5] - 2026-11-03
- wl12xx **host driver** binary swap (v74 .ko's, identical vermagic, sha256-gated, backup + auto-rollback, NMS re-init, boot fail-safe); `swap-driver-v74.sh` / `rollback-driver-v59.sh`; chip firmware stays v59 (v74 sr.bin caused more watchdogs). 21/21 off-car mock tests.

## [4.8.4] - 2026-11-03
- Experimental USB WiFi dongle as `wlan1` (rt2800usb, VID `148f`, modules from v74 rootfs + `rt2870.bin` firmware); own wpa_supplicant on wlan1 (NMS/wlan0 untouched); invisible to the Mazda GUI.

## [4.8.3] - 2026-11-03
- Live menu output also to the run log (mkfifo+tee when TTY); AP-mode via hostapd+udhcpd (`CMU-<MAC>`); safer udhcpc fallback + auto-hint to roll back v59 firmware on watchdog/TX-flush; `fix-warning.sh` never overwrites autorun; hooks in both `stage_wifi.sh` and `stage_1.sh`; System menu can launch the terminal directly via `ReadDTC testId=22` (no GUI patch/reboot needed).

## [4.8.2] - 2026-11-03
- Removed invalid `UsePAM` (sshd failed to start; priv-sep user added instead); default-route repair after IP (`route add default gw`); AP-mode to bypass hotspot client isolation; terminal patch also patches i18n dicts (reboot required); new `rollback-firmware-v59.sh`.

## [4.8.1] - 2026-11-03
- `dbus-send --reply-timeout=8000` (NoReply no longer blocks ~25 s); wall-clock 30 s deadline for the IP wait; fixed `ps=on`→`ps=off` bug; interactive scan via NMS D-Bus; streamlined menu with quick actions; logs consistently under `mzd-data/logs/`.

## [4.8.0] - 2026-11-02
- `mzd-data/` layout on the stick (config/state/logs/backups/runs, survives toolkit deletion); per-run logs with exit codes and psk-scrubbed output; boot_id-based run dirs (CMU clock is unset); runtime USB mount detection (83 scripts migrated off hardcoded paths); fail-fast exit-code contract for connect-nms (0/1/3/4/5); PSK via `MZD_PSK` env only; `WIFI_EnableNetwork` removed (UnknownMethod on v59); interactive connect; terminal menu patch with tests; release builder with post-build secrets scan.

## [4.7.6] - 2026-11-01
- Port 36000 everywhere; password auth from gitignored `secrets.conf` (own sshd on 36000, DES hash); open-network WiFi as default; robustness fixes in autorun/menu hints.

## [4.7.5] - 2026-11-01
- D-Bus JCI-socket only (no `--system` fallback); `wpactrl()` runtime socket detection + busybox-safe `run_with_timeout`; pubkey-only SSH via `/data_persist` (never `/config-mfg`); gated v74 sr.bin swap with auto-rollback; busybox-proofing (no `sed \n`, no `sed -E`); FIX-ALL/autorun rewrite; tar.gz-primary packaging with SHA256SUMS.

## [4.7.2] - 2026-11-01
- New `lib/wifi-compat.sh` (no iw/iwconfig on the CMU): `wifi_status`/`wifi_scan`/`wifi_deadlock_check`; all iwconfig call sites replaced; SSH start rewritten with port ordering fix; autorun fail-safe with backup/restore.

## [4.7.1] - 2026-11-01
- USB health pre-flight (rw-check, `LOST.DIR`, FAT-error detection) in all entry points; tar.gz primary in dumps.
