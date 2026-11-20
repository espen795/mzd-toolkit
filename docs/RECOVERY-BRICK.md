# Recovery & brick prevention -- bootloop rescue (v59)

Lessons learned from real bootloop rescues on a Mazda MZD Connect Gen-1 CMU
(firmware v59.00.502A EU, i.MX6, BusyBox 1.19.2, IBC embedded bootloader
1.68.17). Read this **before** modifying anything in `/jci/sm/` or the
service configuration -- this is exactly the scenario that bricked a unit
into a watchdog bootloop, and (as of 2026-11-17) the scenario that was
successfully rescued over the serial console.

Facts are marked:

- **[verified]** -- observed on live hardware during the 2026-11-17 rescue
- **[analysis]** -- derived from rootfs / backup images, not live-tested

## The failure that causes a bootloop

The Service Manager (`sm`) loads every `jci_service` entry from
`/jci/sm/sm.conf` with `dlopen()`. If a service path points at a **shell
script instead of a `.so`**:

```
00:00:09.979 SM Failed to load the service: "/jci/devices/devices-wrapper.sh"
             dlerror: ELF file version does not match current one
00:00:10.004 SM detected that the service "devices" configured as reset_board="yes" exited.
             SM has to stop pinging watchdog now ... Expect a reboot in up to 5 seconds.
```

...and that service has **`reset_board="yes"`** in sm.conf (the `devices`
service does), `sm` stops pinging the hardware watchdog and the board
hard-resets:

```
~10.0 s : dlopen() fails on the .sh (ELF version mismatch)
~15 s   : watchdog reset   (observed loop period ~15-19 s)
```

`sm.conf` itself declares this behaviour:
`<sm_server ... watchdog_enable="true" reports_timeout="60000" sigkill_wait_before_reboot="5"/>`
-- `sm` is the process that pings the hardware watchdog; when a
`reset_board="yes"` service dies, `sm` deliberately stops pinging and lets
the board reset.

**Rule (the core lesson): a `jci_service` entry in `sm.conf` must always
point at a real ELF `.so`. Never point it at a `.sh` / wrapper script -- it
is `dlopen()`'d, so a script can never load.** If you want to wrap or filter
a service (e.g. a touch filter), do it via `LD_PRELOAD` on the original
`.so`, or as a separate service of your own -- never by replacing the `path=`
of an existing `reset_board="yes"` service with a script. Always keep a
backup (`sm.conf.bak`) before editing.

## Boot timeline (measured on live serial logs) [verified]

| time | event |
|---|---|
| ~0 s | IBC embedded bootloader banner, kernel starts |
| ~7 s | serial `login:` prompt appears |
| ~10.0 s | `devices` service crash (dlopen ELF mismatch) |
| ~15 s | watchdog reset (loop repeats every ~15-19 s) |

The usable window is therefore only **~3 s** between the login prompt and
the crash. An automated script logs in and reaches a root shell in ~0.15 s,
which is why automation (below) works where manual typing does not.

## Dead ends -- proven NOT to work (do not retry)

1. **Wrong passwords on serial [verified]**: `root`/`jci`, `cmu`/`jci` and
   `user`/`jci` all give `Login incorrect`.
2. **`user` login with a corrupted `/etc/passwd` [verified]**: on the
   rescued unit the `user` entry's shell field was literally `/bin/shsshd`,
   because an `echo "sshd:..." >> /etc/passwd` was appended to a file that
   did not end with a newline. Result:
   `login: can't execute '/bin/shsshd'` -> session closes immediately. This
   was self-inflicted corruption, not stock firmware -- but it means:
   **never append to `/etc/passwd` unless the existing file ends with a
   newline.**
3. **Bootloader interrupt via serial [analysis]**: the IBC embedded
   bootloader 1.68.17 does not accept break-keys over UART.
4. **USB autorun on stock v59 [analysis]**: `stage_usb.sh` mounts the stick
   (~11 s) but does NOT auto-execute `XX/autorun` content from it. Only
   `/data_persist/dev/bin/autorun` (on the persist partition, not on USB)
   runs as root. (On v74+ there IS a USB `jci-autorun` hook -- see
   "Post-v74 re-root via USB" below.)
5. **`set_nng_debug.sh` with `on load /tmp/mnt/sda1/sys.ini` [analysis]**:
   only creates a symlink, no code execution.
6. **`killall -STOP sm` alone [verified]**: pausing `sm` does NOT stop the
   reset -- `sm` is itself the watchdog pinger, and the hardware watchdog is
   what fires. The GPIO kill-switch (below) is the only thing that actually
   stops the reboot.

## Successful serial recovery (verified 2026-11-17)

**The serial console account `cmu` / `mzd` is a factory default present on
every unit: `cmu` is uid 0 (root) with shell `/bin/sh`** (the stock rootfs
image contains the `cmu` entry with a DES hash of `mzd`). Earlier rescue
attempts failed only because the wrong password (`jci`) was tried. With
`cmu`/`mzd` the login succeeds even inside the bootloop, because the login
prompt (~7 s) appears before the `devices` crash (~10 s).

### Wiring

- CMU connector pin **2S (TX)** -> adapter **RX**
- adapter **TX** -> CMU pin **2T (RX)**
- common **GND**
- **115200 baud, 8N1, 3.3 V** logic (console is `ttymxc1`)
- USB-serial adapters (Prolific PL2303, CH340, ...) all show up as a generic
  `/dev/ttyUSBx` with no device name -- **check `dmesg` after plugging in to
  see which one appeared**, and do a loopback test (adapter TX shorted to
  adapter RX, expect every byte echoed back) to prove the adapter works
  before blaming the wiring. On the rescue host one of the `/dev/ttyUSBx`
  devices belonged to an unrelated gadget -- never assume `ttyUSB0` is the
  CMU adapter.

### Procedure (as executed) [verified]

1. Attach serial, power the unit, watch the boot loop.
2. At the `login:` prompt (manually, or automated -- see below): log in as
   `cmu` / `mzd`. The shell prompt is `/tmp/root #`; `id` shows
   `uid=0(cmu) gid=0(root)`.
3. **First action, immediately** -- stop the watchdog:
   ```sh
   echo 1 > "/sys/class/gpio/Watchdog Disable/value"
   killall -STOP sm 2>/dev/null
   ```
   The GPIO line is the one that actually prevents the reset (verified);
   `killall -STOP sm` is belt-and-braces only. After the fix the GPIO node
   read back `0` yet the unit kept running for 3+ minutes -- the exact
   semantics of that GPIO are not fully understood, but writing `1` is what
   stops the reboot loop.
4. Make sure the rootfs is writable and back up before touching anything:
   ```sh
   mount -o remount,rw /
   mount -o remount,rw /jci 2>/dev/null
   cp /jci/sm/sm.conf /jci/sm/sm.conf.bak-rescue
   cp /etc/passwd /etc/passwd.bak-rescue
   ```
   (The rootfs is already rw per the kernel cmdline
   `root=/dev/mmcblk0p1 rootfstype=ext2 rw`, but `/jci` can be a separate
   mount -- remount it too.)
5. Fix the bootloop -- point `devices` back at the real `.so` and restore the
   display argument:
   ```sh
   sed -i -e 's|/jci/devices/devices-wrapper.sh|/jci/devices/svc-com-jci-cpp-devices.so|' \
          -e 's|display=mzd-touch-filtered|display=filtered-touchscreen0|' /jci/sm/sm.conf
   rm -f /jci/devices/devices-wrapper.sh
   ```
6. Neutralize any touch-filter block in the autorun. Comment out the whole
   `if ... fi` range, not just single lines -- a half-commented block leaves
   a `syntax error: unexpected "fi"` that kills everything after it in the
   autorun:
   ```sh
   sed -i '/^if .*touch-filter/,/^fi/s|^|#|' /data_persist/dev/bin/autorun
   ```
7. Repair `/etc/passwd` if it was corrupted:
   ```sh
   sed -i 's|^\(user:.*:/bin/sh\)sshd:.*|\1|' /etc/passwd
   echo >> /etc/passwd
   grep -q '^sshd:' /etc/passwd || echo 'sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin' >> /etc/passwd
   ```
8. Verify, then reboot:
   ```sh
   grep -c devices-wrapper /jci/sm/sm.conf    # must be 0
   grep display= /jci/sm/sm.conf               # filtered-touchscreen0
   grep '^user:' /etc/passwd                   # ends in :/bin/sh
   awk -F: 'NF!=7{print "BAD: " $0}' /etc/passwd
   sync; reboot
   ```

### Verification after reboot [verified]

A 75 s watch of the serial log after `reboot` showed: exactly one boot
banner, `com.jci.cpp.devices` loading at ~10.5 s, **no** `Failed to load`
and **no** `stop pinging watchdog`, and the system kept running (USB,
Bluetooth, navigation, GUI). Post-fix state on the unit: `id` =
`uid=0(cmu) gid=0(root)`; `sm.conf` devices path =
`/jci/devices/svc-com-jci-cpp-devices.so`; `/jci/devices/` contained only
`devices` + `svc-com-jci-cpp-devices.so`; `/etc/passwd` had a clean `user`
entry ending in `:/bin/sh` and a separate `sshd` entry.

### Automated version

`tools/recovery/cmu_serial_rescue.py` implements exactly the procedure
above as a state machine: it waits for the login prompt, logs in
`cmu`/`mzd`, sends the watchdog-disable line first, then fires the fix
commands and reports success on a `CMU_FIX_DONE_<rc>` marker. It retries
across boot cycles (max 8) and is **dry-run by default** -- pass
`--apply <SERIAL_DEV>` to actually open the port. See
`tools/recovery/README.md`.

If `cmu`/`mzd` is refused (`Login incorrect`), the live `/etc/passwd` was
changed by a previous owner -- go to the fallback routes below.

## Fallback routes (in order)

| # | route | status |
|---|---|---|
| 1 | Serial `cmu`/`mzd` + watchdog GPIO + sm.conf fix | **[verified]** primary, used 2026-11-17 |
| 2 | Self-heal via `/data_persist/dev/bin/autorun` | **[analysis]** root hook, see below |
| 3 | Early network shell via `start_network.sh` | **[analysis]** not needed |
| 4 | `.up` reflash (diagnostic menu code 99, or fail-safe menu) | standard, works when the UI boots |
| 5 | CH341A SPI-NOR edit | hardware last resort -- see [NOR-FLASH-RECOVERY.md](NOR-FLASH-RECOVERY.md) |

Route 2 detail [analysis]: `stage_3.sh` runs
`if [ -e /data_persist/dev/bin/autorun ]; then /data_persist/dev/bin/autorun & fi`
as **root**, and `/data_persist` is mounted before `stage_3` runs. A compact
autorun whose *first* line is
`echo 1 > "/sys/class/gpio/Watchdog Disable/value"` (no leading `sleep`)
executes inside the pre-crash window and can apply the same sm.conf fix on
every boot. A long `sleep` at the top of an autorun defeats this -- keep
rescue payloads free of leading sleeps. This route needs one-time write
access to `/data_persist` (via route 1, 4 or 5).

Route 3 detail [analysis]: `sm.conf` contains a `start_network` process
service (`/jci/scripts/start_network.sh`, comment "network support for
development or debugging") running as `cmu` (uid 0), early in the boot with
`reset_board="no"`. If it brings up `usb0`/`eth1` plus an `inetd` shell, you
get a comfortable root shell without the serial race.

## Post-v74 re-root via USB (v74.00.324A and later)

Different problem, same family: after updating to **v74+**, the updater's
`passwdupdate` step rebuilds the `/config-mfg` squashfs and overwrites
`authorized_keys` (only the Mazda key remains) and `passwd`, and the v74
rootfs replaces the stage scripts that called the autorun hook.
`/data_persist` itself survives the update.

On v74+ the update server (`svcjciupdatea.so`, `jci-autorun` string at
offset `0xa962ad0`) executes a file named **`jci-autorun` in the root of an
inserted USB stick as root, without any login**
(`system("(cd <mountdir> && jci-autorun) &")`). A FAT32 stick (<=16 GB) with
`jci-autorun` in its root can therefore, on USB insert while the car is on
ACC:

- reinstall `/data_persist/dev/bin/autorun` (persistent across reboots),
- re-plant the autorun hook in the stage scripts (`stage_1.sh`,
  `stage_wifi.sh`, `start_normal_mode.sh`),
- reinstall your own SSH `authorized_keys` (point sshd's
  `AuthorizedKeysFile` at `/data_persist/dev/authorized_keys`) and start
  sshd on your chosen port,
- restore the serial `cmu`/`mzd` login.

Keep your own keys, SSIDs and passphrases in the payload files on the
stick -- never hardcode them in shared scripts. Idempotent scripts are safe
to re-run. No NOR/mtd writes, so no added brick risk. (Whether this USB
hook fires inside a bootloop window was not tested -- in a bootloop, prefer
route 1.)

## What the rootfs image analysis showed [analysis]

- Backup `cmu_rootfs_*.img` is a MAST/JMET container; kernel cmdline is
  `root=/dev/mmcblk0p1 rootfstype=ext2 rw` -- the rootfs is **already
  read-write**, no remount needed (but remount `/jci` separately if it is
  a mount of its own).
- The 8 MB SPI-NOR (`m25p80` / `mx25l6405d`) is **not** part of the eMMC
  backup. It holds the fail-safe image + VFBL bootloader (mtd), and
  `/config-mfg` = mtdblock5 (read-only squashfs, 128 KB, 100% full -- never
  write to it, instant brick).
- There is no `/etc/inittab`; the serial `login:` prompt comes from BusyBox
  `getty`/`login` on `ttymxc1` (console=`ttymxc1,115200`).
- Boot chain: VFBL @ NOR 0x10000 -> "UserBoot" vector @ 0x13FF0 -> VIP_APP
  @ 0xC0000 -> Linux kernel from eMMC -> relfs rootfs -> sm stage_1..3.
- The CMU has A/B partition switching with boot-confirmation rollback
  (`REFLASH_SwitchActivePartition`, `bootdiag_report_failure/success`) --
  the official `.up` update mechanism uses this. Raw `dd` to a block device
  bypasses it and is a last resort only (needs a working SSH session and a
  fail-safe USB stick ready).

## Prevention checklist (before any mod)

- [ ] Full `dd` backup of `ffx01p1` (rootfs), `mmcblk0p2` (persist),
      `ffx01p4` (data) to USB -- `toolkit-v59/tools/backup.sh` (disable the
      hardware watchdog during dd:
      `echo 1 > '/sys/class/gpio/Watchdog Disable/value'`)
- [ ] `cp /jci/sm/sm.conf sm.conf.bak` before touching it
- [ ] **dlopen rule: every `jci_service` `path=` in sm.conf must be a
      `.so`, never a script** -- this is the exact root cause of the
      2026-11-17 bootloop
- [ ] Never leave `reset_board="yes"` on a service you patched
- [ ] Never append to `/etc/passwd` unless the file ends with a newline;
      keep a `passwd.bak`
- [ ] Never edit `/config-mfg` (read-only, 100% full squashfs -- brick risk)
- [ ] Never touch `eth0` (internal switch, no PHY); never `dd` to
      `mmcblk0p1` (resources -- contains the VFBL bootloader)
- [ ] Keep a 3.3 V serial adapter + the wiring above written down; the
      factory `cmu`/`mzd` serial login is the primary rescue route
- [ ] Keep a CH341A + the NOR procedure written down
      ([NOR-FLASH-RECOVERY.md](NOR-FLASH-RECOVERY.md)) -- last resort when
      the watchdog owns the boot loop
- [ ] Test every sm.conf change against dlopen semantics before rebooting
