# Installation

Step-by-step guide to get the MZD Toolkit running on a Mazda Connect CMU.

## 1. Prerequisites

- Mazda Connect CMU, firmware **v59.00.502** (recommended) or v74 (unstable — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md))
- **Root access on the CMU, with USB autorun already enabled.** Since v59.00.502 Mazda patched USB autorun — see **[ROOT-ACCESS.md](ROOT-ACCESS.md)** for the MP3/XSS workaround (mzd-connect-1-root), the Diagnostic-menu → JCI Test Mode method, or UART serial. This toolkit assumes the autorun hook (`/jci/scripts/stage_wifi.sh` → `/data_persist/dev/bin/autorun`) is already in place; `install.sh` extends it, it does not create it from scratch.
- A USB stick, **FAT32, MBR partition table**
- A PC (Linux/macOS/Windows) to prepare the stick and later to SSH in

## 2. Prepare the USB stick

On your PC:

```sh
# 1. Download the release assets (tar.gz + SHA256SUMS) from the Releases page
# 2. Verify integrity (USB sticks get corrupt — always check)
sha256sum -c SHA256SUMS

# 3. Format the stick as FAT32 with an MBR partition table
#    (Linux example — replace sdX with your stick!)
#    sudo umount /dev/sdX*
#    sudo mkfs.vfat -F 32 /dev/sdX1

# 4. Mount and extract the tar.gz to the stick ROOT
sudo mount /dev/sdX1 /mnt/usb
sudo tar -xzf mzd-toolkit-vX.Y.Z.tar.gz -C /mnt/usb/
#    -> creates /mnt/usb/mzd-toolkit/
# 5. Optionally copy SHA256SUMS too, so you can re-verify on the car:
sudo cp SHA256SUMS /mnt/usb/
sudo umount /mnt/usb
```

> The `.zip` release is **for the PC only** — the CMU's BusyBox has `tar`+`gzip` but **no `unzip`**. Always extract the `.tar.gz`.

Stick layout after extraction:

```
/mzd-toolkit/          <- the toolkit (menu.sh, install.sh, wifi/, ssh/, ...)
/mzd-toolkit-vX.Y.Z.tar.gz
/SHA256SUMS
/mzd-data/             <- created by install.sh: config/, state/, logs/, backups/, runs/
```

## 3. Install on the car

1. Start the car with the USB stick inserted.
2. **The menu does NOT autostart after install** — that is by design. After the
   first `install.sh` run (or after a reboot), start the menu manually:
   ```sh
   sh /data_persist/mzd-toolkit/menu.sh        # from the persist install (no stick needed)
   # or straight from USB:
   sh /tmp/mnt/sd*/mzd-toolkit/menu.sh         # glob: no Shift key on the CMU terminal, so `sd*` not `sdb1`
   ```
   What DOES autostart on every boot (via the autorun hook, no menu needed):
   WiFi connect, SSH on port 36000, and the eth1 dongle — see `net/autostart-eth1-ssh.sh`.
   To make the menu itself launch at boot, add one line to `/data_persist/dev/bin/autorun`:
   ```sh
   sh /data_persist/mzd-toolkit/menu.sh >> /tmp/mzd-menu.log 2>&1 &
   ```
3. `install.sh`:
   - copies the whole toolkit to `/data_persist/mzd-toolkit` (**persist-install** — after this the stick can be removed and everything keeps working after reboot),
   - installs the autorun hook into `/data_persist/dev/bin/autorun` (with a `.orig` backup and a fail-counter that restores the original after 3 consecutive boot failures),
   - creates `mzd-data/{config,state,logs,backups,runs}` on both the stick and `/data_persist`,
   - patches `stage_wifi.sh` **and** `stage_1.sh` hooks (idempotent, `.org` backups),
   - runs a USB health pre-flight (rw-check + `LOST.DIR` detection — reformat the stick if it warns).
4. Reboot the car. After reboot, WiFi + SSH autostart via `autorun` (the menu does not — start it manually as above, or add the autostart line).

### Switching between the terminal menu and the normal UI

- Menu → **System & security → 4. Start terminal (diag code 22)** opens the
  on-screen terminal directly (no GUI patch or reboot needed — uses the MMUI
  `ReadDTC` D-Bus call with `testId=22`, fallbacks `/jci/scripts/run-terminal.sh`
  and `sh /jci/scripts/systemHooks.sh 22`).
- Menu → **System & security → 5. Close terminal / back to UI** kills the
  terminal process and returns to the normal UI (`ivi-shell -f "Main"`).
- Menu → **System & security → 6. Add terminal to settings menu** patches the
  Settings GUI so a permanent **Terminal** entry appears under
  Settings → System (after About). This needs a **reboot** to load the patched
  JS (`Mute+Navi` 10 s). Without reboot, option 4 still works.
- From the terminal you can always return to the toolkit menu by running
  `sh /data_persist/mzd-toolkit/menu.sh` again.

## 4. Menu walkthrough

Main menu (v4.8.x) — quick actions on top, submenus below:

```
--- QUICK ACTIONS ---
  1. WiFi quick connect
  2. SSH setup (port 36000)
  3. All-in-one: WiFi + SSH + watchdog
  4. Dump everything to USB
  5. CAN/VIM dump to USB
--- MENUS ---
  6. WiFi        7. SSH        8. Network (USB-Ethernet)
  9. Diagnostics & logs   10. VIM/CAN   11. System & security   12. Tools
  0. Exit
```

Typical first run: **option 3** (all-in-one). Then verify (next section).

## 5. Verify

On the CMU (via menu → Diagnostics, or SSH):

```sh
ifconfig wlan0    # WiFi IP present?
ifconfig usb0     # USB tethering IP present?
ifconfig eth1     # LAN dongle IP present?
netstat -tln | grep 36000   # sshd LISTEN?
```

From your PC:

```sh
# v59 compat flags are MANDATORY — the CMU sshd (OpenSSH 5.9p1) only offers
# ssh-rsa/ssh-dss host keys and (for keys) ssh-rsa:
ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -p 36000 cmu@<CMU_IP> -i /path/to/id_mzd
```

Add the flags permanently to `~/.ssh/config`:

```
Host mzd-cmu
    HostName <CMU_IP>
    Port 36000
    User cmu
    IdentityFile /path/to/id_mzd
    HostKeyAlgorithms +ssh-rsa,ssh-dss
    PubkeyAcceptedAlgorithms +ssh-rsa
```

## 6. Configuration

Configuration lives in `mzd-data/config/` on the USB stick root (fallback: `toolkit/config/`):

- **`settings.conf`** — copy from `config/settings.conf.example`:
  ```sh
  WIFI_SSID="YOUR_SSID"
  WIFI_PASSWORD="OPEN"        # "OPEN"/empty = open network; real password goes in secrets.conf
  SSH_PORT=36000
  SSH_USER="cmu"
  ```
- **`secrets.conf`** — copy from `config/secrets.conf.example` (chmod 600):
  ```sh
  MZD_SSH_PASSWORD="..."      # only if you want password auth (see security warning in README)
  WIFI_PASSWORD="..."         # or MZD_PSK="..." for a secured WiFi network
  ```

**Never commit `secrets.conf`, `settings.conf`, or `ssh/id_mzd*` to git.** They are gitignored, and `tools/build-release.sh` scans every release asset and **fails the build** if any of them are present.

WiFi passwords are passed to the CMU via the `MZD_PSK` environment variable only — never as a command-line argument (that would be visible in `/proc/<pid>/cmdline`) and never in plaintext in logs.

## 7. Find the CMU's IP

- On the CMU: `wifi/status.sh` (or the menu header shows `Network: CONNECTED - IP: x.x.x.x`)
- Via USB tethering: `ifconfig usb0`
- Via LAN dongle: `ifconfig eth1` (static default `192.168.0.2/24` in autostart, or DHCP via `net/eth1-dhcp.sh`)
