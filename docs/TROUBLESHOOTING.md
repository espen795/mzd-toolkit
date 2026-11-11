# Troubleshooting

Known failure modes on the v59 CMU, with root causes and fixes. All of these were observed on real hardware with logs.

## WiFi

### `deauth ... reason=7` / connection drops after ~3 minutes

**Cause:** 802.11 power save (ELP mode) on the TI WL1271 triggers a firmware-level watchdog deadlock: the TX queue stalls ("Unable to flush all TX buffers"), the chip stops servicing the hardware watchdog, and it force-restarts (`watchdog interrupt received!`, deterministic crash PC). After recovery the loop repeats.

**Fix:** disable power save — the CMU has no `iw`/`iwconfig`, so:

```sh
sh wifi/fix-powersave.sh            # runtime: /sys/class/net/wlan0/power/control=on,
                                    # /sys/module/wl12xx/parameters/ps=off, rfkill unblock
sh wifi/fix-powersave-permanent.sh  # same + autorun hook so it survives reboot
```

Note the module param must be **`off`**, not `on` — writing `on` to `/sys/module/wl12xx/parameters/ps` *enables* driver power save and makes it worse.

### v74 firmware instability (watchdog resets, TX flush storms)

**Symptom:** after copying the v74 `wl128x-fw-4-sr.bin` (FRev 7.3.10.0.142), logs show *more* watchdog interrupts than v59 (e.g. 11× watchdog + 92× "Unable to flush TX buffers" → DHCP gets no lease).

**Fix:** roll back to the v59 firmware: menu **Tools → 10 (rollback firmware v59)**, or `sh wifi/rollback-firmware-v59.sh`. `connect-nms.sh` also prints this hint automatically when it detects watchdog/TX-flush counts in `dmesg`.

**Do not do a full v74 upgrade:** it region-locks the CMU, wipes the autorun hook, empties the stage scripts, and its firewall drops port 36000 on wlan0.

### WiFi connects but no internet ("Network is unreachable" despite an IP)

**Cause:** missing default route (udhcpc sometimes fails with `SIOCDELRT: No such process`), or hotspot **AP isolation** (client-to-client blocked on phone hotspots).

**Fix:** `connect-nms.sh` now adds `route add default gw <GW> wlan0` automatically (GW from the ARP table, fallback `.1`). For AP isolation, run the CMU as its own AP: `sh wifi/ap-mode.sh` (hostapd + udhcpd, SSID `CMU-<MAC>`), or use USB tethering instead.

### D-Bus calls return empty / `ERR(1)`

**Cause:** the CMU has **no system bus** — only the JCI service bus at `unix:path=/tmp/dbus_service_socket`. Never use `--system`; when the socket is briefly absent (dbus-daemon restart, it lives on tmpfs), `connect-nms.sh` retries 3× with a 2 s pause and an 8 s `--reply-timeout` per call.

## USB tethering

### No `usb0` appears

Checklist:

1. **Phone must expose a CDC interface (class 02/06 or 02/0d), not RNDIS.** Samsung phones in Android-Auto/AOA mode expose only MTP+ACM (PID `04e8:6860`) — tethering silently falls back. Turn **Android Auto OFF** and enable **USB tethering**, which switches to RNDIS PID `04e8:6863` (works with the cross-compiled `rndis_host` v3) or CDC.
2. **Host mode must be 1:** `echo 1 > /proc/driver/usbroleswitch/0/mode` (0 = device/AOA, 1 = host).
3. **Module load order matters:** `insmod cdc_ether.ko` **first**, then `rndis_host.ko` (rndis_host depends on cdc_ether). The bundled `wifi/cdc-modules/` (usbnet/cdc_ether/cdc_ncm) come from the v74 rootfs — vermagic `3.0.35 SMP preempt mod_unload ARMv7` matches v59 exactly. If the device was enumerated *before* insmod, bind it manually: `echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id`.
4. Use an **original USB data cable** — charge-only cables show nothing in `lsusb`.
5. `usb-tether.sh` prints on-screen USB diagnostics (VID:PID + interface classes) and flags a phone stuck in RNDIS mode (class `e0`/subclass `01`) — the CMU kernel supports CDC-ECM/NCM and (with rndis_host v3) RNDIS, but **not** iPhone `iph_eth`.

Exit codes: `4` no tether device, `5` module load failed, `6` no DHCP lease.

## LAN dongle (eth1)

- **Never touch `eth0`** — internal switch without PHY; changing it corrupts routing. Leave eth0 DHCP to JCI's own `start_network.sh`.
- `eth1` registration can take up to **~60 s after boot** — wait for `/sys/class/net/eth1` before `ifconfig`.
- Dongle types: **ASIX AX88772** (`0b95:772a`, built-in `asix` module: `echo "0b95 772a" > /sys/bus/usb/drivers/asix/new_id`) and **Realtek RTL8152** (`0bda:8152`, via `cdc_ether` + `new_id`). Identify yours first: `dmesg | grep -iE "asix|r8152|eth1.*register"`.
- The CMU has **EHCI (USB 2.0) only, no xHCI/USB3** — USB-C hubs with their own controller are not recognized; use a plain passive USB 2.0 hub. High-power devices (>500 mA) need a powered hub.
- If the dongle disappears when you unplug the USB stick, they share the bus — install to `/data_persist` (persist-install) so SSH works without the stick.

## SSH

### "Permission denied (publickey)" with a valid key

Checklist:

1. **Key type must be RSA** (`ssh-keygen -t rsa -b 2048`). The v59 sshd rejects ed25519 with "unknown key type ssh-ed25519". Verify: `ssh-keygen -l -f id_mzd.pub` must say `(RSA)`, not `(ED25519)`.
2. The pubkey must be in **both** `/data_persist/dev/bin/authorized_keys` and `/tmp/mzd-sshd/authorized_keys`, `chmod 600` (`ssh/fix-ssh.sh` does this; it searches persist → USB → generates on the CMU, and strips CRLF).
3. Client must offer `ssh-rsa`: add `-o PubkeyAcceptedAlgorithms=+ssh-rsa` (and `-o HostKeyAlgorithms=+ssh-rsa,ssh-dss`).
4. `AuthorizedKeysFile` in the config must point at those paths; run `sshd -t -f <config>` to validate.
5. Privilege-separation user must exist: `grep "^sshd:" /etc/passwd || echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd`, plus `mkdir -p /var/empty /var/run/sshd`.

### Password auth fails silently

- v59 libcrypt accepts **DES hashes only** (13 chars, no `$` prefix). A `$5$`/`$6$` SHA hash fails *without any error message*. Set the password with `echo "cmu:PASSWORD" | chpasswd` (uses the system libcrypt → DES automatically), then verify: `grep "^cmu:" /etc/passwd | cut -d: -f2` must be 13 chars and not start with `$`.
- Password auth only works if `/` is writable. `mount -o remount,rw /` can fail **silently** — always verify with `touch /etc/.rwtest && rm /etc/.rwtest` before writing `/etc/passwd`, and verify the hash landed afterwards. If `/` stays read-only, pubkey is the only route.
- Security: password auth on 36000 is exposed on the car's WiFi network and is brute-forceable. Prefer pubkey; if you must use a password, make it long and random.

### sshd won't start

- Config validation errors on OpenSSH 5.9p1: **no `UsePAM`** ("Unsupported option UsePAM" → sshd refuses to start), no `PermitRootLogin prohibit-password` (unsupported; `cmu` is uid 0 so it must be `yes`), no ecdsa/ed25519 `HostKey` lines (rsa + dsa only), **no `-E logfile` flag** ("illegal option -- -E"; use `LogLevel DEBUG3` + `logread`).
- Always copy the **stock** host keys from `/etc/ssh/ssh_host_{rsa,dsa}_key` — regenerating them per start in `/tmp` makes clients fail after reboot.
- Check the port before starting: if `netstat -tln | grep :36000` already shows LISTEN after an earlier autostart, do **not** `killall sshd` and restart — that kills the working daemon.

### "Host key changed" after reboot

The host keys were regenerated on a previous start. Copy the stock `/etc/ssh/ssh_host_{rsa,dsa}_key` into the sshd config's key paths and `rm ~/.ssh/known_hosts` entry (or use `StrictHostKeyChecking=no` for testing only).

### Firewall

```sh
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT
```

Never `iptables -P INPUT ACCEPT` — that is a security regression and was deliberately removed from all scripts.

## USB stick corruption

FAT errors and `LOST.DIR` on this system are proven causes of corrupt copies (e.g. a one-bit-off `.ko` fails the sha256 check). If the toolkit's USB health pre-flight warns: reformat the stick FAT32/MBR, re-extract, and verify with `sha256sum -c SHA256SUMS` (on the car: `cd /tmp/mnt/sdb1 && sha256sum -c SHA256SUMS`).

## Release build

`tools/build-release.sh` **fails the build (exit 1)** if a release asset contains `secrets.conf`, `config/settings.conf`, `ssh/id_mzd*`, `mzd-data/`, `runs/`, `run.env` or `*.seq`. If it fails, find the leaked file (`git status`, `git ls-files`) and remove it — never ship secrets.

## Collecting diagnostics

```sh
sh system/dump.sh        # everything to USB (network, processes, configs, dmesg, logs...)
sh wifi/copy-logs-usb.sh # copy mzd-data/logs (incl. per-run logs with exit codes) to USB
# logs live in: $USB_MOUNT/mzd-data/logs/  (runs/vX.Y.Z-<script>-b<boot8>-r<seq>/{stdout,stderr,exit.code})
# and /tmp/mzd-autorun.log for the boot hook
```

When filing a bug (see `.github/ISSUE_TEMPLATE/`), include the firmware version (`/jci/version.ini`), kernel (`uname -a`), and the relevant run logs from `mzd-data/logs/`.
