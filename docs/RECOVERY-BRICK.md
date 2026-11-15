# Recovery & brick prevention — bootloop rescue (v59)

Lessons learned from a real bootloop rescue (2026-11-15, v59.00.502A EU,
FGSN redacted). Read this **before** modifying anything in `/jci/sm/` or the
service configuration — this is the scenario that bricked a unit into a
watchdog bootloop.

## The failure that causes a bootloop

The Service Manager (`sm`) loads each service from `/jci/sm/sm.conf` via
`dlopen()`. If a service path points at a **shell script instead of a `.so`**:

```
sm: dlopen("/jci/devices/devices-wrapper.sh") -> dlerror: ELF file version does not match current one
```

...and that service has **`reset_board="yes"`** in sm.conf, the watchdog stops
receiving pings and hard-reboots the board:

```
~10.1s:  ELF version mismatch on devices-wrapper.sh
~15s:    watchdog interrupt -> reboot   (loop every ~15-18 s)
```

**Rule: never point an `sm.conf` service at a `.sh` file, and never leave
`reset_board="yes"` on a service you patched.** Always keep a backup
(`sm.conf.bak`) before editing.

## Boot timeline (measured on live serial logs)

| time | event |
|---|---|
| ~3 s | serial login prompt appears |
| ~10.1 s | service crash (ELF mismatch) |
| ~11 s | USB stick (`sda1`) gets mounted |
| ~15 s | watchdog reboot |

## Dead ends — proven NOT to work on stock v59 (do not retry)

1. **Serial console login as `user` / `jci`** — the password is accepted, but
   `/etc/passwd` has shell `/bin/shsshd` (broken/nonexistent) →
   `login: can't execute '/bin/shsshd'` → session closes immediately. No shell.
   `root`/`jci` and `cmu`/`jci` → `Login incorrect`. There is **no `cmu` user**
   in stock `/etc/passwd` (only root/user/service/hmi/browser).
2. **Bootloader interrupt via serial** — IBC embedded bootloader 1.68.17 does
   not accept break-keys over UART.
3. **USB autorun on stock v59** — `stage_usb.sh` mounts the stick (~11 s) but
   does NOT auto-execute `XX/autorun` content. Only
   `/data_persist/dev/bin/autorun` (on the persist partition, not USB) runs as
   root — and in a bootloop you never get far enough for it to matter.
4. **`set_nng_debug.sh` with `on load /tmp/mnt/sda1/sys.ini`** — only creates a
   symlink, no code execution.

## What the rootfs image analysis showed

- Backup `cmu_rootfs_*.img` is a MAST/JMET container; kernel cmdline is
  `root=/dev/mmcblk0p1 rootfstype=ext2 rw` — the rootfs is **already
  read-write**, no remount needed.
- The 8 MB SPI-NOR (`m25p80` / `mx25l6405d`) is **not** part of the eMMC
  backup. It holds the fail-safe image + VFBL bootloader (mtd), and
  `/config-mfg` = mtdblock5 (read-only squashfs).

## The working recovery: SPI-NOR boot-select flip (hardware)

When software routes are dead, force the CMU into fail-safe/recovery mode by
flipping the boot-select byte in the NOR flash:

1. Open the CMU, clip a **CH341A SOP8 programmer** onto the SPI-NOR chip.
2. On a Windows PC with **AsProgrammer**: Read 8 MB → save `nor_backup.bin`.
3. Flip byte at offset **0x10000**: `FF` → `00` (boot-select) → Program.
4. Boot the CMU: it enters fail-safe/recovery, serial console gives **root
   without password**.
5. Fix the actual problem over serial, e.g.:
   ```sh
   sed -i 's|devices-wrapper.sh|svc-com-jci-cpp-devices.so|' /jci/sm/sm.conf
   sed -i 's|display=.*|display=filtered-touchscreen0|' /jci/sm/sm.conf
   rm /jci/devices/devices-wrapper.sh
   sync
   ```
   Keep `sm.conf.bak-rescue` / `autorun.bak-rescue` backups.
6. Flip byte 0x10000 back to `FF`, reboot → normal boot.

## Prevention checklist (before any mod)

- [ ] Full `dd` backup of `ffx01p1` (rootfs), `mmcblk0p2` (persist),
      `ffx01p4` (data) to USB — `tools/backup.sh` (disable the hardware
      watchdog during dd: `echo 1 > '/sys/class/gpio/Watchdog Disable/value'`)
- [ ] `cp /jci/sm/sm.conf sm.conf.bak` before touching it
- [ ] Never edit `/config-mfg` (read-only, 100% full squashfs — brick risk)
- [ ] Never touch `eth0` (internal switch, no PHY)
- [ ] Test every `sm.conf` change against `dlopen` semantics: service entries
      must be `.so` files, never scripts
- [ ] Keep a CH341A + the 0x10000 procedure written down — it is the last
      resort when the watchdog owns the boot loop
