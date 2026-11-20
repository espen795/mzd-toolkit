# V74 access -- regaining root after a v74 update, and keeping it

Verified on real hardware running **v74.00.324A EU N** (`JCI_SW_VER
MAZ_CMU-150_74.00.324`, kernel 3.0.35 armv7l, OpenSSH 5.9p1) in 2026-11.
Everything below describes what a v74 `.up` update actually does to your
access and the routes that were proven to work afterwards.

## 1. What a v74 update destroys -- and what survives

A v74 `.up` update **overwrites the eMMC rootfs** (`/`, a relfs on
`/dev/ffx01p1`). Consequences:

- Your patched `/etc/ssh/sshd_config` and every boot hook you planted in the
  rootfs are **gone**.
- `/data_persist` **survives** (`cleandatapersist` only wipes
  `log/dumps` above 150 MB), so a previously stored
  `/data_persist/dev/bin/authorized_keys` is still there -- but nothing
  points to it anymore.
- `/config-mfg` is a read-only squashfs on NOR (`/dev/mtdblock5`, 128K,
  100% full) and **survives the update**, but the update step
  `passwdupdate` remounts it read-write and commits **Mazda's own
  `authorized_keys`** (one Mazda RSA key) plus a fresh `passwd` via
  `config-update.sh --commit`. Your key was never in there.

## 2. Why direct SSH fails on a fresh v74

Stock v74 `sshd_config` (byte-identical to v59):

```
Port 36000
AuthorizedKeysFile /config-mfg/authorized_keys
PasswordAuthentication no
PermitRootLogin yes
```

`/config-mfg/authorized_keys` contains **only the Mazda key**, so your key
is rejected. The fix is your **own sshd** whose `AuthorizedKeysFile` points
at `/data_persist/dev/bin/authorized_keys`:

```
Port 2222
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /data_persist/dev/bin/authorized_keys
UsePrivilegeSeparation no
StrictModes no
PidFile /tmp/mzd-sshd/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
```

Notes:

- Use port **2222** to avoid a respawn conflict with the stock sshd on
  36000; run it entirely from `/tmp` so no rootfs write is needed.
- v74 runs **OpenSSH 5.9 -- no ed25519**. An RSA key is mandatory; connect
  with `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa,ssh-dss`.
- Rootfs is read-only; make it writable with
  `mount -o remount,rw,sync /` (the `sync` is required -- plain
  `remount,rw` fails on v74).
- `/etc/passwd` is a symlink to the read-only `/config-mfg/passwd`
  (`$5$` hash), so `chpasswd` fails. Replace the symlink with a real file
  in rw `/etc` if you want password login.

## 3. Persistence: the start_network.sh hook (and neutralizeid7)

- Update step **`neutralizeid7`** deletes `/data_persist/dev/bin/autorun`
  (plus `00-*`, `01-*`, `99-*.autorun`, `adb`) during **every** update --
  so after each `.up` you must re-deploy your autorun/bring-up.
- v74 stage scripts (`stage_1.sh` ... `stage_ir.sh`) are shebang-only (empty),
  but `sm` still executes them, so a hook line in them still works.
- The reliable hook point is **`/jci/scripts/start_network.sh`**: it has
  real content, runs as root at boot (loads `usbnet`/`asix`, starts eth1
  DHCP, starts the stock sshd). Append:

  ```sh
  [ -x /data_persist/dev/sshd-up.sh ] && /data_persist/dev/sshd-up.sh > /data_persist/dev/sshd-up.boot.log 2>&1 &
  ```

  Keep a backup (`start_network.sh.mzdbak`) and `sh -n` both files.
  The relfs rootfs is **not** wiped on reboot -- only on a firmware update --
  so this hook survives reboots but not the next `.up`.

Bring-up script contents (run at every boot): eth1 static
`192.168.0.2/24` point-to-point (peer `192.168.0.1/24`, no gateway),
`rp_filter` off (`/proc/sys/net/ipv4/conf/{all,eth1}/rp_filter = 0`),
firewall opened on the link, and your own sshd on 2222 with the
`/data_persist` key.

## 4. jci-autorun USB hook is compiled out on v74

The `jci-autorun` USB hook **exists** in the v74 binary
`jci/reflash/svcjciupdatea.so` but is **hard-disabled**:

- Flag `UPDATEA_SYS_SRV_enableUsbDbgScript` lives in `.rodata` at
  **`0x43958`**, value **`0`** -- a read-only const with no relocation
  (GOT entry `0x5953c`, `R_ARM_RELATIVE` addend `0x43958`).
- Both call sites check `*flag == 1` before calling
  `SearchAndExecUSBDbgScript`:
  - `updatea_sys_usb_AttachedDevEvent` @ **`0x2c02c`**
    (`ldr r3,[r4,#0x374]` -> GOT -> `0x43958`; `ldr r3,[r3]`; `cmp r3,#1`; `bne skip`)
  - `updatea_sys_usb_GetStorageDevicesListFromUSBMGR` @ **`0x2cef8`** -- same check
- Because the value is always 0, the check is always false and the hook
  **never fires** on v74.

What the hook would do if enabled
(`UPDATEA_SYS_SRV_SearchAndExecUSBDbgScript` @ **`0x1f7c8``): scan every USB
partition for a file named exactly `jci-autorun` in its root and run
`system("(cd <mountdir> && jci-autorun) &")` **as root, no login**. Mazda
shut this debug facility off in production firmware.

## 5. Serial console: `cmu` root login works on v74

- The `user` account's shell is literally `/bin/shsshd` (broken) -- that
  login is a dead end.
- **`cmu` serial login works on stock v74 and is uid 0 (root)**.
  115200 8N1. Set a known password for `cmu` (real `/etc/passwd` file with a
  DES hash, since the symlinked one has an unknown `$5$` hash) to get
  `cmu`/`mzd` over serial. Only one program at a time on the COM port.
- Serial is therefore a **working root route on v74** -- use it (or the diag
  terminal, testId 11) to deploy the bring-up script in section 3.

## 6. Firewall: ICMP is dropped, TCP 36000 is accepted

`start_network.sh` always runs `jci-fw.sh start WCP`, which on v74 does:

```
$IPTABLES -P INPUT DROP
$IPTABLES -A INPUT -p icmp --icmp-type echo-request -j DROP   # rule ~130: ping dies
$IPTABLES -A INPUT -p tcp --dport 36000 -m state --state NEW,ESTABLISHED -j ACCEPT  # rule ~115: SSH allowed (not on wlan0)
```

Symptom: `ping <CMU_IP>` fails from your laptop while SSH works -- that is
expected, not a link problem. Fix in your bring-up:

```
iptables -I INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -I INPUT 1 -i eth1 -j ACCEPT
```

Also disable `rp_filter` if you see ARP working but `connect timed out`.

## 7. Rescue-stick procedure (and why it will not fire on v74)

The designed rescue stick: a FAT32 stick (<=16 GB) with a file named
exactly **`jci-autorun`** (LF-only line endings, executable) in its root,
plus the payload (autorun re-install, sshd start, `iptables` ICMP accept)
and a `RESCUE_LOG.txt` written back to the stick. Insert it **before
power-on** so the boot-time USB mount scan (`stage_usb`, ~11 s) sees it,
then check `RESCUE_LOG.txt` on the stick.

**On v74 this does not fire** -- the hook is compiled out (section 4), so the stick
is mounted but never executed; this was verified, and it is why earlier
rescue sticks "did nothing" (not timing, not CRLF, not the USB port).
Working rescue routes on stock v74, least to most invasive:

1. **Serial `cmu` login** (uid 0) -> run the bring-up commands by hand.
2. **Diag menu terminal** (`ReadDTC testId=11` -> dialog -> manual tap) ->
   same commands; or patch `/jci/scripts/startSystemScripts.sh` to delegate
   any code other than 11 to `systemHooks.sh "$1"`, which re-enables
   `testId=22` from the GUI.
3. **CH341A SPI-NOR flash** -- hardware failsafe, always available
   (see `docs/NOR-FLASH-RECOVERY.md`).

## 8. Connecting once bring-up is done

```
ssh -i /path/to/id_rsa -o IdentitiesOnly=yes \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa,ssh-dss \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -p 2222 cmu@<CMU_IP>
```

-> uid=0(cmu), Linux 3.0.35 armv7l. From a remote host, add your own
`-o ProxyCommand="ssh ... -W %h:%p <JUMP_HOST>"`.
