# Usage

The master entry point is the menu:

```sh
sh /data_persist/mzd-toolkit/menu.sh     # after install (no USB stick needed)
sh /tmp/mnt/sdX1/mzd-toolkit/menu.sh     # straight from USB
```

Main menu: quick actions 1–5 (WiFi quick connect / SSH setup / all-in-one / dump to USB / CAN dump), then submenus 6–12 (WiFi, SSH, Network, Diagnostics, VIM/CAN, System, Tools). All scripts can also be run directly — no Shift key needed anywhere, everything is number-driven.

## Script groups

### `wifi/` — WiFi

| Script | Purpose |
|---|---|
| `connect-nms.sh [SSID] [PASS]` | Connect via Mazda's NMS D-Bus service (`com.jci.blm_nms` on `unix:path=/tmp/dbus_service_socket`). **Exit codes: 0 = got IP, 4 = connect failed (no IP), 5 = udhcpc fallback failed** (also 1 = no ifcId, 3 = no networkId). Pass the password via `MZD_PSK` env or `secrets.conf`, never as argv. |
| `connect-interactive.sh` | Scan via NMS, pick a numbered AP, enter PSK with echo off |
| `quick-connect.sh` | Connect using `WIFI_SSID` from settings.conf |
| `status.sh`, `scan.sh`, `check.sh` | Status / scan / full diagnosis (writes a diag log) |
| `disconnect.sh`, `reset-wifi.sh`, `fix.sh` | Disconnect / full reset / repair |
| `fix-powersave.sh`, `fix-powersave-permanent.sh` | Turn 802.11 power save **off** (runtime, and permanently via autorun hook) — fixes `deauth reason=7` and the wl12xx ELP watchdog |
| `fix-watchdog.sh` | Watchdog monitor + soft recovery hints |
| `usb-tether.sh` | USB tethering from an Android phone → `usb0`. **Exit codes: 0 = usb0 has IP, 4 = no tether device found, 5 = module load failed, 6 = no IP via DHCP** |
| `usb-dongle.sh` | USB WiFi dongle (rt2800usb, VID `148f`) as `wlan1` (experimental; Mazda GUI won't see it) |
| `ap-mode.sh` | CMU as its own AP (hostapd + udhcpd, SSID `CMU-<MAC>`) to avoid hotspot client isolation |
| `upgrade-firmware-v74.sh` / `rollback-firmware-v59.sh` | Swap the wl12xx station firmware (sha256-gated, NVS untouched, auto-rollback) / restore v59 |
| `swap-driver-v74.sh` / `rollback-driver-v59.sh` | Swap the wl12xx **host driver** .ko's (binary swap, same vermagic) / restore |
| `driver-info.sh`, `debug-v74.sh`, `scan-deep.sh`, ... | Diagnostics |

### `ssh/` — SSH access (port 36000, user `cmu`, uid 0)

| Script | Purpose |
|---|---|
| `start.sh` / `stop.sh` / `status.sh` / `test.sh` | Start/stop/status/test the daemon. Validates config first with `sshd -t -f`. |
| `deploy-key.sh` | Generate an **RSA-2048** keypair (`ssh/id_mzd` + `.pub`) and install the pubkey into `authorized_keys` |
| `fix-ssh.sh` / `fix-auth.sh` / `fix-port.sh` | Repair auth: find `id_mzd.pub` (persist → USB → generate on the CMU), strip CRLF, reject ed25519 keys, install into `/data_persist/dev/bin/authorized_keys` + `/tmp/mzd-sshd/authorized_keys` (chmod 600) |
| `set-password.sh` / `ssh-pwd.sh` | Password auth — **only works when `/` is writable** (verify with a `touch` test first; `mount -o remount,rw /` fails silently otherwise). v59 accepts **DES hashes only** (13 chars, no `$`): use `chpasswd` or `busybox cryptpw` without `-m`, and verify the hash afterwards with `grep "^cmu:" /etc/passwd | cut -d: -f2` |
| `setup-ssh.sh`, `quick-fix-working.sh`, `quick-ssh-eth.sh` | One-shot setups |
| `autorun` | Boot script installed to `/data_persist/dev/bin/autorun` |
| `sshd_config` | Template config (see below) |

**sshd_config restrictions for the v59 sshd (OpenSSH 5.9p1, Sep 2011):** only these options are supported — `Port`, `ListenAddress`, `PermitRootLogin yes` (mandatory: `cmu` is uid 0, `prohibit-password` is an *unsupported option* and `no` blocks all logins), `PasswordAuthentication`, `PubkeyAuthentication`, `AuthorizedKeysFile`, `PermitEmptyPasswords no`, `StrictModes`, `PidFile`, `LogLevel`, `Subsystem`. **No `UsePAM`** (unsupported option → sshd won't start), **no `sshd -E logfile`** (illegal option — use `LogLevel DEBUG3` and `logread` instead). Host keys: **rsa + dsa only** — copy the stock keys from `/etc/ssh/ssh_host_{rsa,dsa}_key`; never regenerate per start in `/tmp`, or clients get "host key changed" after reboot. Always validate with `sshd -t -f <config>` before starting, and check `netstat -tln | grep :36000` — if the port already LISTENs after an earlier autostart, don't kill and restart the daemon.

### `net/` — wired network

| Script | Purpose |
|---|---|
| `eth.sh` | `eth1` up/down/status/gateway |
| `eth1-dhcp.sh` | DHCP on `eth1`; `eth1-dhcp.sh static` → back to static `192.168.0.2/24` |
| `eth0-dhcp.sh` | **Do not use** — `eth0` must never be touched |
| `autostart-eth1-ssh.sh` | Boot autostart: bind ASIX `0b95:772a` and RTL8152 `0bda:8152`, wait (max ~10–60 s) for `/sys/class/net/eth1`, set static IP, start sshd |

### `system/` — system info & dumps

`info.sh`, `network.sh`, `storage.sh`, `process.sh`, `logs.sh`, `dmesg.sh`, `hardware.sh`, `dump.sh` (complete dump to USB), `os-map.sh`, `remount-rw.sh`, `unlock-os.sh`, `net-ssh-setup.sh` (standalone "get internet + SSH" from a single downloaded script).

### `tools/` — maintenance

| Script | Purpose |
|---|---|
| `install-ssh.sh`, `install-autostart.sh`, `install-terminal-menu.sh` | Permanent installs (autorun hooks, eth1+SSH autostart, GUI patch) |
| `add-terminal-menu.sh` | Adds a **Terminal** entry to Settings → System by patching `/jci/gui/apps/syssettings/js/syssettingsApp.js` (`_SystemTabHelperArray` + static definition + i18n dicts, `uiaId="diag"`, `ReadDTC testId=22`). Idempotent, `.org` backups, reboot required |
| `fix-warning.sh` | Removes the startup warning (patches `systemApp.js` disclaimer timer, adds `warning_ack` to autorun — never overwrites the autorun hooks) |
| `backup.sh` | Backup of configs + `/data_persist/dev` to USB (tar). For **full partition dd backups** see below |
| `watchdog.sh` | WiFi/SSH recovery watchdog: `once` (default) / `bg` (max 2 h) / `stop` / `status`; log `/tmp/watchdog-loop.log` or `mzd-data/logs/` |
| `can-monitor.sh`, `can-bus.sh`, `vehicle-data.sh`, `vim-dump-all.sh`, `vim-deep-dive.sh` | CAN-bus/VIM vehicle data via D-Bus (`once`/`bg`/`stop`/`status`) |
| `build-release.sh [version] [outdir]` | Build release assets (see below) |
| `cleanup.sh`, `monitor.sh`, `log-viewer.sh`, `gui-dump.sh`, `nvram.sh`, `serial-debug.sh`, `reverse-tunnel.sh`, `net-test.sh`, `firmware-info.sh`, `dbus-introspect.sh`, `ui.sh`, `fix-dump.sh`, `fix-usb-rw.sh` | Diagnostics & maintenance |

### `usb-helpers/` — USB stick management on the CMU

`mzd-find-usb.sh`, `mzd-mount-all.sh`, `mzd-mount-status.sh`, `mzd-mount-usb-manual.sh`, `mzd-remount-usb-rw[-v2].sh`, `mzd-remount-usb-ro.sh`, `mzd-remount-root-rw.sh`, `mzd-remount-root-ro.sh`, `mzd-fix-proc.sh`, `mzd-diag-usb.sh`, `mzd-stage-wifi-patch.sh` / `mzd-stage-wifi-restore.sh` (autorun hook patch/restore).

## Exit codes

| Script | Codes |
|---|---|
| `wifi/connect-nms.sh` | `0` IP obtained · `1` no ifcId · `3` no networkId · `4` connect failed (no IP) · `5` udhcpc fallback failed |
| `wifi/usb-tether.sh` | `0` usb0 has IP · `4` no tether device · `5` module load failed · `6` no IP via DHCP |
| `wifi/usb-dongle.sh` | `0` IP · `4` dongle not detected · `5` module/firmware missing · `6` connect failed |
| `tools/build-release.sh` | `0` OK · `1` secrets/runtime data detected in asset (build fails) |

## SSH from your PC

Port **36000**, user **`cmu`** (uid 0 = root).

```sh
# Linux / macOS — v59 compat flags are mandatory:
ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -p 36000 cmu@<CMU_IP> -i /path/to/id_mzd

```

Windows (OpenSSH client):

```powershell
ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -p 36000 cmu@<CMU_IP> -i C:\path\to\id_mzd
```

Password auth (only if `/` was writable and `ssh-pwd.sh` succeeded — DES hash in `/etc/passwd`):

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -p 36000 cmu@<CMU_IP>
# then enter the password from secrets.conf
```

If your tooling can't answer an interactive password prompt (e.g. automation) and `sshpass` isn't installed, drive it with Python `pexpect`:

```python
import pexpect
c = pexpect.spawn(
    'ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa '
    '-o StrictHostKeyChecking=no -o PreferredAuthentications=password '
    '-o NumberOfPasswordPrompts=1 -p 36000 cmu@<CMU_IP> "uname -a"',
    timeout=15, encoding='utf-8')
c.expect('[Pp]assword:')
c.sendline('YOUR_PASSWORD')
c.expect(pexpect.EOF)
print(c.before)
```

The firewall rule is a single targeted accept — never a blanket `iptables -P INPUT ACCEPT`:

```sh
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT
```

## Full partition backup (dd)

Identified partitions on the v59 CMU:

| Partition | Device | Size | Content |
|---|---|---|---|
| rootfs | `/dev/ffx01p1` | 478 MB | OS (read-only layer) |
| data | `/dev/ffx01p4` | ~307 MB | user data |
| persist | `/dev/mmcblk0p2` | 572 MB | persistent data (rw) |
| resources | `/dev/mmcblk0p1` | 3.1 GB | resources |

Procedure:

```sh
# 1. Make the USB stick writable
mount -o remount,rw /tmp/mnt/sdb1
# 2. Disable the hardware watchdog (dd under load can trigger a reboot)
echo 1 > '/sys/class/gpio/Watchdog Disable/value'
# 3. Raw dd in the background (survives SSH timeouts), bs=1M is fastest (~3-4 MB/s on the CMU)
nohup dd if=/dev/ffx01p1 of=/tmp/mnt/sdb1/backup-rootfs.img bs=1M > /tmp/dd-rootfs.log 2>&1 &
# 4. The resources partition is big — always raw dd of the device node,
#    NEVER tar on the /tmp/mnt/resources mountpoint (short reads, much slower)
nohup dd if=/dev/mmcblk0p1 of=/tmp/mnt/sdb1/backup-resources.img bs=1M > /tmp/dd-res.log 2>&1 &
# 5. Verify: file size must equal partition size; md5 spot-check start and end:
ls -l /tmp/mnt/sdb1/backup-*.img
dd if=/tmp/mnt/sdb1/backup-resources.img bs=1M count=5 2>/dev/null | md5sum
```

Note: after a while of inactivity the screen goes black (`jci_cpu_gauge -e` power-save) — that is not a crash; SSH and the backup keep running.

## Release builder

```sh
sh toolkit/tools/build-release.sh 4.8.21 /tmp/mzd-release
```

Produces in the output dir:

- `mzd-toolkit-vX.Y.Z.tar.gz` — **primary asset for the CMU** (BusyBox has tar+gzip, no unzip)
- `mzd-toolkit-vX.Y.Z.zip` — **PC only**
- `SHA256SUMS` — checksums for both

The build **fails** (exit 1) if the asset contains secrets or runtime data (`secrets.conf`, `config/settings.conf`, `ssh/id_mzd*`, `mzd-data/`, `runs/`, `run.env`, `*.seq`, logs).
