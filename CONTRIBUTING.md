# Contributing

Thanks for considering a contribution to the MZD Toolkit! This project runs on a real car head unit, so a few rules exist to keep everyone's CMU safe.

## Workflow

1. **Fork** this repository and create a branch: `git checkout -b feat/my-change`
2. Make your changes (see style rules below)
3. **Test on hardware** if your change touches anything CMU-facing (see below)
4. Open a **Pull Request** against `main` with a clear description and, for hardware-tested changes, the run logs

## Code style — this is critical

All scripts run on the CMU's **BusyBox sh** (kernel 3.0.35). That means:

- **POSIX sh only** — no `[[ ]]`, no arrays, no `<<<`, no process substitution `<()`, no `&>`. Validate every script with `sh -n` **and** `busybox sh -n`.
- **No `sed -i '...a ...\n...'`** — BusyBox sed can't handle `\n` in insert/append. Use a temp file + `echo` lines.
- **No `sed -E`** — use awk or plain sed.
- **No direct `timeout N cmd`** — BusyBox `timeout` misparses that form. Use the `run_with_timeout` helper from `lib/common.sh`.
- Source `lib/common.sh` at the top of every script (with the `TOOLKIT_LIB_LOADED` guard + fallback paths) so logging, `bootstrap_paths` and `trap_cleanup` work.
- Never hardcode USB mount paths (`/tmp/mnt/sdb1`) — use `bootstrap_paths`/`detect_usb` (exclude `sd_nav`).
- WiFi passwords go via the `MZD_PSK` env var or `secrets.conf` — **never** as argv (visible in `/proc/<pid>/cmdline`), never in plaintext logs.
- Never touch `eth0`, never write to `/config-mfg`, never start a second `wpa_supplicant` on `wlan0` (NMS owns it), never `killall wpa_supplicant`/`udhcpc` that belong to NMS.
- Firewall: targeted rules only (`iptables -I INPUT -p tcp --dport 36000 -j ACCEPT`). **Never** `iptables -P INPUT ACCEPT`.
- sshd config must stay within the OpenSSH 5.9p1 option set: no `UsePAM`, no `prohibit-password` (cmu is uid 0 → `PermitRootLogin yes`), rsa+dsa host keys only, no `-E` flag.

## No secrets — ever

`config/secrets.conf`, `config/settings.conf`, `ssh/id_mzd`, `ssh/id_mzd.pub`, `mzd-data/`, `runs/`, `run.env`, `*.seq`, `*.log` must never be committed. They are gitignored, and `tools/build-release.sh` **fails the build** if any of them appear in a release asset. Before pushing: `git status` and `git ls-files` should show none of them. Test locally with `sh tools/build-release.sh "" /tmp/test-release` — it must exit 0.

## Hardware testing (required for CMU-facing changes)

Changes to anything under `toolkit/` that runs on the CMU should be verified on a real unit before merge:

1. Build a release and put it on a FAT32 stick (`sha256sum -c SHA256SUMS` after copying).
2. Run the feature from the menu or directly; the run is logged automatically to `mzd-data/logs/runs/vX.Y.Z-<script>-b<boot8>-r<seq>/` (stdout/stderr/exit.code).
3. Cross-check with `dmesg`, `ifconfig`, `netstat -tln`, and D-Bus (`dbus-monitor --address unix:path=/tmp/dbus_service_socket`) where relevant.
4. Attach the run logs (with secrets scrubbed) to your PR.

Off-car, at minimum run `sh -n`/`busybox sh -n` over all scripts and the release build.

## Documentation

User-facing docs live in `README.md` and `docs/` (English, Markdown). Keep the feature matrix in `README.md` honest — mark things *tested on v59 hardware*, *experimental*, or *not working* as they are. Add a `CHANGELOG.md` entry for every user-visible change.

## Reporting bugs

Use the issue templates (`.github/ISSUE_TEMPLATE/`) — include firmware version (`/jci/version.ini`), kernel (`uname -a`), and logs from `mzd-data/logs/`.

## License

By contributing you agree your contributions are licensed under the MIT license (see `LICENSE`).
