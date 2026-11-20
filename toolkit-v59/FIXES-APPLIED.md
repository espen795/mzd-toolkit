# MZD Toolkit — Fixes Applied (2026-10-30)

Based on the 2026-10-30 review. All fixes are BusyBox-compatible (tested with `sh -n`).

## CRITICAL fixes

### C1 — `tools/fix-warning.sh`: corrupt path fixed
- Line 83 had an ellipsis character (`SYSAPP…mApp.js`) so the systemApp.js patch was never applied.
- Now: `SYSAPP="/jci/gui/apps/system/js/systemApp.js"` — the disclaimer-timer 3500->0 patch works again.

### C2 — `tools/vehicle-data.sh`: `run_with_timeout` bug
- `run_with_timeout "pull_data"` spawned a child shell in which the function did not exist.
- Now `pull_data` is called directly in watch and once mode.

### C3 — Security fixes (QUICK-FIX.sh, ssh/fix-auth.sh, ssh/fix-port.sh, ssh/start.sh, ssh/sshd_config, ssh/set-password.sh, wifi/fix.sh, wifi/connect-v74.sh, install.sh, tools/install-terminal-menu.sh)
- ❌ Hardcoded password hash `$5$phNsaxam...` removed from QUICK-FIX.sh.
- ❌ `PermitEmptyPasswords yes` → **`no`** overal.
- ❌ `PermitRootLogin yes` → **`prohibit-password`** everywhere (root login only via SSH key; `cmu` is the uid-0 user).
- ❌ `iptables -P INPUT ACCEPT` removed — only specific ports (22, 36000) are accepted.
- Password: from `$SSH_PASSWORD` env var if set, otherwise **strong random** (32 hex chars via `/dev/urandom`), shown on screen once, never in logs.
- `ssh/set-password.sh` now generates a random password instead of "jci".

## MAJOR fixes

### M1 — BusyBox `sed \n` problem solved
All `sed -i '...a ...\n...'` / `sed -i '/.../i ...\n...'` patterns replaced by temp file + `echo` lines:
- `install.sh` (stage_wifi.sh hook)
- `tools/install-ssh.sh` (stage_wifi.sh hook)
- `tools/install-terminal-menu.sh` (autorun hook + stage hook)
- `tools/fix-warning.sh` (stage_1.sh hook)
- `wifi/fix-powersave.sh` (wpa_supplicant.conf regels)

### M2 — WiFi psk leak fixed
- `wifi/optimize-wpa.sh`: `cat "$CONF" | tee -a "$LOG"` → `grep -v 'psk=' "$CONF" | tee -a "$LOG"` + `chmod 600`.
- `wifi/debug-v74.sh`: all wpa config cats filtered with `grep -v 'psk='`.
- `wifi/check.sh`, `wifi/connect.sh`, `wifi/reset-wifi.sh`, `wifi/fix-config.sh`, `wifi/manual.sh`: psk filtered when showing + `chmod 600` on generated configs.

### M3 — Verkeerde hook in `tools/install-terminal-menu.sh`
- Step 4 now patches **`stage_1.sh`** (with `.org` backup) instead of `stage_wifi.sh` — consistent with WARNING-FIX-V2.md section 5 (v74: stage_wifi.sh is empty).

### M4 — `wifi/upgrade-firmware-v74.sh` checksum + verification
- SHA256 of the source file is logged.
- If `$MZD_FW_SHA256` env var is set → strict check against known-good hash (exit 1 on mismatch).
- After copying: `cmp -s` verification that the copy is byte-identical.
- Typo "FOurie:" → "ERROR:" corrected.

### M5 — Alle scripts sourcen nu `lib/common.sh` + `trap_cleanup`
- 42 scripts in `wifi/`, `ssh/`, `system/`, `tools/` + `install.sh` now have at the top:
  ```sh
  [ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . /mnt/sdb1/mzd-toolkit/lib/common.sh 2>/dev/null
  trap_cleanup 2>/dev/null
  ```
- Now they all log via `log_to_usb` and have a clean Ctrl+C handler.

## Verificatie

```
sh -n on all 67 .sh files: 0 failures
No bashisms ([[ ]], arrays, <<<, <(), &>)
No hardcoded hashes/passwords anymore
No PermitRootLogin yes / PermitEmptyPasswords yes
No iptables -P INPUT ACCEPT
No sed \n patterns anymore
All scripts source common.sh (except lib/ and menu.lib/)
```

---

# v4.7.5 — Fixes Applied (2026-11-01, design v2 @ 0046b92)

Based on `docs/designs/toolkit-v475-2026-11-01.md` v2 (goldfish R1-R15
processed) and the logs of 2026-11-01. See the v4.7.5 changelog for
the full overview.

## M1 — D-Bus JCI-socket only (fix: 0 D-Bus services / ERR(1))
- `lib/common.sh` `jci_dbus_send`/`jci_dbus_monitor`: NO `--system`
  fallback anymore — if `/tmp/dbus_service_socket` is missing: explicit error
  + return 1.
- `wifi/connect-nms.sh`: retry 3x 2s before fail (socket can be briefly gone during
  dbus-daemon restart), still without `--system`.
- Also fixed: `system/os-map.sh`, `tools/can-monitor.sh` (own
  jci_dbus_send with --system fallback).

## M2 — wpactrl() + run_with_timeout busybox-guard
- `lib/wifi-compat.sh`: new `wpactrl()` with runtime auto-detect of the
  ctrl-socket (`/var/run/wpa_supplicant-wlan0/` → `/var/run/wpa_supplicant`
  → fallback `-i wlan0`). All direct `wpa_cli -i` calls go via wpactrl.
- `run_with_timeout`: probe/cache in `_TOOLKIT_TIMEOUT_MODE` (gnu → gnu-t →
  background+kill). Busybox `timeout 15 cmd` fails — the guard catches this.
- `wifi_deadlock_check` now also matches `pc: 0x...` (FW panic).

## M3 — SSH pubkey-only via data_persist, NEVER /config-mfg
- `/config-mfg` is squashfs ro + 100% full → NEVER touch it (brick-risk).
- New `ssh/deploy-key.sh` (ed25519 keypair `ssh/id_mzd`); autorun puts the
  pubkey in `/mnt/data_persist/dev/bin/authorized_keys` (dedup, chmod 600).
- Own sshd port 22 primary (pubkey-only, `PasswordAuthentication no`,
  `PermitRootLogin prohibit-password`); stock port 36000 secondary.
- All hardcoded passwords removed; no more `iptables -P INPUT ACCEPT`
  (only `-I INPUT --dport 22 -j ACCEPT`).

## M4 — wl128x sr.bin swap v74 (path A, GATED)
- `wifi/upgrade-firmware-v74.sh`: NO `killall wpa_supplicant` (NMS is the
  owner); after rmmod/insmod explicit NMS re-init via `WIFI_Recovery` or
  mode-toggle. NVS untouched. Backup + cmp + auto-rollback.
- Strict sha256 check (default of the v74 sr.bin file).
- Gate: 48h power-save baseline → 24-48h A/B watchdog-count → auto-rollback
  on count >0 within 24h; boot-fail detection (no "firmware booted"
  within 30s → restore backup in autorun).

## M5 — busybox-proof
- `tools/gui-dump.sh`: sed -E → awk masking + `[ -s ]` check (no 0-byte).
- `usb-helpers/mzd-stage-wifi-patch.sh`: sed `i\n` → tmpfile+echo + pre-check
  (`^exit`) + post-check (`sh -n`).

## M6 — FIX-ALL / autorun / QUICK-FIX rewrite
- NMS connect only (no own wpa_supplicant), no `-P INPUT ACCEPT`,
  no jci password, `wpactrl` in watchdog with NMS WIFI_Recovery fallback,
  `killall udhcpc` only if own (pid-path check).

## M7 — Packaging/release (docs)
- `tools/build-release.sh`: VERSION default → 4.7.5 (tar.gz primary, zip
  secondary, SHA256SUMS manifest — was already so).
- Docs updated: v4.7.5 CHANGELOG (new), USAGE.md, TROUBLESHOOTING.md,
  README.txt, README.md.
