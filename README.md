# Mazda MZD Toolkit

A shell-script toolkit for the **Mazda Connect CMU** (the infotainment head unit) — WiFi connectivity, SSH access, USB tethering, wired LAN via USB dongle, vehicle data over D-Bus, full partition backups, and a GUI terminal shortcut. Runs entirely on the car, delivered on a FAT32 USB stick.

> **Target hardware:** Mazda Connect CMU, firmware **v59.00.502** (also tested against v74 firmware behavior), kernel **3.0.35 ARMv7** (Freescale i.MX6), BusyBox userland, OpenSSH 5.9p1.

## What it is

The CMU is a Linux box. Once you have root on it (via any known exploit — serial, ID7, or the autorun method), this toolkit gives you:

- **WiFi** — connect to a hotspot through Mazda's own NMS D-Bus service (no second `wpa_supplicant`), plus power-save fixes for the flaky TI WL1271 chip
- **SSH** — a working SSH daemon on port **36000**, user `cmu` (uid 0), RSA-2048 pubkey auth (password auth optional, see warnings)
- **USB tethering** — internet on the CMU from an Android phone (`usb0`, CDC-ECM/NCM)
- **Wired LAN** — USB ethernet dongle as `eth1` (ASIX AX88772 / Realtek RTL8152)
- **Watchdog** — background WiFi recovery monitor
- **Vehicle data** — CAN-bus / VIM signals via the JCI D-Bus service bus
- **Backups** — full `dd` partition backups to USB
- **Terminal menu** — patches the Settings GUI to add a Terminal entry
- **Release builder** — `tools/build-release.sh` produces `tar.gz` + `zip` + `SHA256SUMS` with a built-in secrets scan

## Feature matrix

| Feature | Status | Notes |
|---|---|---|
| WiFi connect via NMS D-Bus (`wifi/connect-nms.sh`) | ✅ Tested on v59 hardware | Exit codes 0/4/5; power-save disabled to avoid wl12xx watchdog |
| WiFi watchdog recovery (`tools/watchdog.sh`) | ✅ Tested | `once` / `bg` / `stop` / `status` |
| WiFi power-save fix (`fix-powersave*.sh`) | ✅ Tested | `deauth reason=7` disappears when power save is off |
| v74 firmware rollback (`wifi/rollback-firmware-v59.sh`) | ✅ Tested | v74 `sr.bin` (FRev .142) caused **more** watchdog crashes on this chip; rollback to v59 recommended |
| SSH daemon on port 36000 | ✅ Tested | OpenSSH 5.9p1 compat: RSA-2048 keys only, `ssh-rsa`/`ssh-dss` host keys, no `UsePAM`, no `-E` flag |
| SSH pubkey auth | ✅ Tested | RSA-2048 via `authorized_keys` in `/data_persist/dev/bin` + `/tmp/mzd-sshd` |
| SSH password auth | ⚠️ Works only if `/` is writable | v59 libcrypt accepts **DES hashes only** (13 chars, no `$` prefix); brute-forceable over WiFi — prefer pubkey |
| USB tethering (Android, CDC) | ✅ Tested | Samsung RNDIS PID `04e8:6863` works with `rndis_host` v3; AOA/MTP PID `04e8:6860` does **not** give `usb0`; iOS tethering **not supported** (no `iph_eth` in kernel) |
| USB ethernet dongle `eth1` | ⚠️ Experimental | ASIX AX88772 (`0b95:772a`) via built-in `asix`; RTL8152 (`0bda:8152`) via `cdc_ether` + `new_id` bind (no `r8152` module needed); registration can take up to ~60 s after boot |
| Terminal menu patch (`tools/add-terminal-menu.sh`) | ✅ Tested | Patches `syssettingsApp.js` `_SystemTabHelperArray` with `uiaId="diag"`; reboot required |
| Full partition backup (`tools/backup.sh`, dd) | ✅ Tested | Long-running; disable the hardware watchdog first; verify sizes after |
| CAN/VIM vehicle data (`tools/can-monitor.sh`, `tools/vehicle-data.sh`) | ✅ Tested | Passive D-Bus monitor; meaningful data needs ignition on |
| Release builder (`tools/build-release.sh`) | ✅ Tested | tar.gz primary (CMU has no `unzip`), zip for PC, SHA256SUMS, post-build secrets scan that fails the build |
| v74 long-term stability | ❌ Not working | Watchdog resets + TX flush loops; roll back to v59 |
| Other USB dongles (non-ASIX/RTL8152) | ❓ Untested | |
| iOS USB tethering | ❌ Not working | kernel lacks `iph_eth` |

## Requirements

- Mazda Connect CMU with firmware **v59.00.502** (v74 partially supported, see above)
- **Root access already obtained** — from v59.00.502 onward USB autorun is patched out by Mazda, so it must first be re-enabled (MP3/XSS, diagnostic menu, or serial — see [docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md))
- A **FAT32-formatted USB stick** (MBR partition table); the CMU has `tar`+`gzip` but **no `unzip`** — always use the `.tar.gz` release on the car
- A PC to prepare the stick and to SSH from

## Quick start

> **Step 0 — root first.** This toolkit does NOT root the CMU. On firmware
> v59.00.502+ USB autorun is patched by Mazda — enable it first via the
> **MP3/XSS workaround**, the **Diagnostic menu → JCI Test Mode**, or **UART
> serial**. Full details + exact USB layout + screenshots: **[docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md)**.

1. On a PC, download the latest `mzd-toolkit-vX.Y.Z.tar.gz` (+ `SHA256SUMS`) from the Releases page.
2. Verify the checksum: `sha256sum -c SHA256SUMS`
3. Format a USB stick as **FAT32 (MBR)** and extract the archive to the stick root:
   `tar -xzf mzd-toolkit-vX.Y.Z.tar.gz -C /mnt/usb/` → creates `mzd-toolkit/`
4. Start the car with the stick inserted. The existing autorun hook fires
   `install.sh`; **the menu does not autostart — start it manually**:
   ```sh
   sh /data_persist/mzd-toolkit/menu.sh     # after persist-install (no stick needed)
   sh /tmp/mnt/sd*/mzd-toolkit/menu.sh      # from USB — glob, the CMU terminal has no Shift key
   ```
   What *does* autostart on every boot: WiFi connect, SSH on 36000, eth1 dongle.
5. In the menu choose **3. All-in-one: WiFi + SSH + watchdog** — or drive the pieces individually.
   The menu is **numeric-only** (type a number — the CMU terminal has no Shift key).
   **Menu ↔ UI switching:** System & security → **4** starts the on-screen terminal
   (diag code 22 via MMUI, no patch/reboot needed), **5** closes it back to the
   normal UI. To make the menu itself a permanent shortcut, add one line to
   `/data_persist/dev/bin/autorun`:
   ```sh
   sh /data_persist/mzd-toolkit/menu.sh >> /tmp/mzd-menu.log 2>&1 &
   ```
   Or patch the Settings GUI for a permanent Terminal entry:
   System & security → **6** (needs a reboot to load the patched JS).
6. From your PC:
   ```sh
   ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa \
       -p 36000 cmu@<CMU_IP> -i id_mzd
   ```

See [docs/INSTALL.md](docs/INSTALL.md) for the full walkthrough and [docs/USAGE.md](docs/USAGE.md) for every menu option and script.

## Terminal shortcut & switching menu/UI

- **System & security -> 4** starts the on-screen terminal instantly (MMUI
  `ReadDTC` D-Bus call with `testId=22`; fallbacks `/jci/scripts/run-terminal.sh`
  and `sh /jci/scripts/systemHooks.sh 22`) - no GUI patch, no reboot needed.
- **System & security -> 5** closes the terminal and returns to the normal UI:
  `killall terminal` / `pkill terminal` / `kill -9 $(pidof terminal)`, then
  `ivi-shell -f "Main"`.
- **System & security -> 6** adds a permanent **Terminal** entry to
  Settings -> System via `tools/add-terminal-menu.sh` (quoted JS strings,
  `sendEventToMmui("diag", "ReadDTC", { payload : { testId : 22 } })`);
  reboot the CMU (Mute+Navi 10 s) to load the patched JS. Without reboot,
  option 4 still works.
- Optional: autostart the menu itself at boot - add one line to
  `/data_persist/dev/bin/autorun`:
  `sh /data_persist/mzd-toolkit/menu.sh >> /tmp/mzd-menu.log 2>&1 &`

## Safety warnings

- **You are root on the head unit.** Anything you run can brick the CMU. Read before you run.
- **Make a full backup before any modification** (`tools/backup.sh` / dd; see docs/USAGE.md). Backups are slow — run them in the background (`nohup`) and **disable the hardware watchdog** during dd (`echo 1 > '/sys/class/gpio/Watchdog Disable/value'`) to avoid reboots under heavy I/O load.
- **Never touch `eth0`.** It is the internal processor switch without a physical PHY; changing it corrupts routing. USB dongles register as `eth1`/`usb0` — use only those.
- **Never touch `/config-mfg`.** It is a read-only, 100%-full squashfs; writing to it is a brick risk.
- **Password auth on port 36000 is brute-forceable over WiFi.** Prefer RSA-2048 pubkey auth. If you use a password, make it long and random.
- **WiFi passwords are never passed as command-line arguments** (visible in `/proc/<pid>/cmdline`) — use `MZD_PSK` env var or `secrets.conf`.
- **Never commit secrets.** `config/secrets.conf`, `config/settings.conf`, and `ssh/id_mzd*` are gitignored, and `tools/build-release.sh` fails the build if any of them end up in a release asset.
- USB sticks get corrupt on this system (FAT errors, `LOST.DIR` are proven in logs) — always verify `SHA256SUMS`, and reformat the stick if you see `LOST.DIR`.

## How this was built

This toolkit was developed **with AI assistance** (Mistral Large 4 agents) iterating against a **real CMU with live logs**: every run's stdout/stderr/exit code was captured on the car (`mzd-data/logs/runs/...`), kernel logs (`dmesg`) were analyzed after each change, and every fix was verified on hardware before being marked "tested". The WiFi root-cause analysis (`wifi/WIFI-ROOTCAUSE-ANALYSIS.md`) is a direct example: a deterministic firmware watchdog crash (`pc: 0x21b8e`, repeated TX-flush timeouts) was isolated from kernel logs, and the fixes (power save off, NMS-only connect, firmware rollback path) were validated against it.

## What works / what doesn't

**Works (verified on v59.00.502 hardware):** WiFi via NMS, watchdog recovery, SSH pubkey (RSA-2048) and password (DES hash) on port 36000, Android USB tethering (CDC and Samsung RNDIS with rndis_host v3), ASIX AX88772 + RTL8152 on `eth1`, terminal menu injection, dd backups, release build + sha256.

**Doesn't / not tested:** v74 firmware long-term stability (watchdog loops → roll back to v59), iOS tethering, USB WiFi dongles other than rt2800 (experimental `wlan1` path), dongles other than ASIX/RTL8152, long-running backups under load without the watchdog disabled.

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md) — USB stick prep, install, verification
- [docs/ROOT-ACCESS.md](docs/ROOT-ACCESS.md) — how to get root + USB autorun first (MP3/XSS workaround, diagnostic menu, UART)
- [docs/USAGE.md](docs/USAGE.md) — menu, all scripts, exit codes, SSH client commands
- [docs/PUBLISH-PIPELINE.md](docs/PUBLISH-PIPELINE.md) — how this repo is published from internal research (translation + secret scan + deploy key)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — known failure modes and fixes
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — CMU internals (GUI, D-Bus, partitions, autorun)
- [docs/TESTING.md](docs/TESTING.md) — what was tested on real hardware
- [CHANGELOG.md](CHANGELOG.md) — version history
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to contribute
- [LICENSE](LICENSE) — MIT

## Related projects

- [MZD-AIO / mazdatweaks](https://github.com/Trevelopment/MZD-AIO) — the well-known all-in-one tweaks installer (mazdatweaks.com)
- [mazdatweaks](https://github.com/Trevelopment/mazdatweaks) — individual tweaks collection
- [cmu-autorun](https://github.com/Trevelopment/cmu-autorun) — autorun/recovery scripts for re-enabling USB autorun on patched firmware
- [mzd-connect-1-root](https://github.com/mzd-evo/mzd-connect-1-root) — root access research for the MZD Connect 1

## License

MIT — see [LICENSE](LICENSE). Use at your own risk; the authors are not responsible for bricked head units.
