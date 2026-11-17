# NOR flash (SPI) recovery -- CH341A boot-select flip, hardware last resort

When every software route is dead (serial login refused, no network shell,
UI never comes up), the last resort is editing the 8 MB SPI-NOR chip that
holds the VFBL bootloader and the fail-safe image. This document describes
that procedure. It complements
[RECOVERY-BRICK.md](RECOVERY-BRICK.md), which covers the (preferred) serial
route that succeeded on 2026-11-17.

**Status of the facts below:** the CH341A procedure is a consolidation of
community practice plus our own offline NOR-dump analysis; the serial
`cmu`/`mzd` route made it unnecessary on the 2026-11-17 bootloop. Treat the
byte-flip as community-lore until verified against your own dump -- see
"Verify the trigger first" below.

## Hardware and safety rules

- **CH341A programmer + SOP8 clip** on the SPI-NOR chip (8 MB Macronix
  MX25L6405D / MX25L6445E, `m25p80` driver; boot log prints
  `found mx25l6405d`). Chip ID read should be Macronix `C2 20 17`.
- **3.3 V logic is mandatory.** Many black CH341A dongles put 5 V on the
  data lines -- that kills the NOR chip and/or the i.MX6. Measure first, or
  use a known 3.3 V mod / interposer. This is the classic way people brick
  here.
- **CMU must be powered off** while the clip is attached (no back-powering
  through the clip -- it corrupts reads).
- **Never write without two identical reads.** Read the full 8 MB twice (or
  three times), compare byte-for-byte; the original dump is never modified
  and is kept as the rollback image. If reads differ, re-seat the clip or
  desolder the chip -- do not flash.
- Software: AsProgrammer or NeoProgrammer on Windows, or `flashrom` on
  Linux (`flashrom -p ch341a_spi -r nor1.bin`, add `-c MX25L6405D` if
  multiple chips are detected). Verify after every write.
- Also useful in parallel: a 3.3 V serial adapter on the CMU (2S=TX ->
  adapter RX, adapter TX -> 2T=RX, GND, 115200 8N1) to watch the boot log.

## Known NOR layout (v59-class units) [analysis]

| offset | content |
|---|---|
| `0x10000` | boot-select byte: `FF` = normal boot, `00` = fail-safe/recovery (community-reported) |
| `0x13FF0` | VFBL "UserBoot" vector |
| `0xC0000` | VIP_APP (~213 KiB) |
| `0x20000` | ibc1 container holding the kernel cmdline record |
| `mtdblock5` | `/config-mfg` (read-only squashfs: authorized_keys, FGSN, WiFi calibration NVS, BT address, passwd, mfg-version.ini) -- **never write this** |

The NOR chip is **not** covered by the eMMC backups (`ffx01*`, `mmcblk0*`)
-- a NOR dump is the only backup of the bootloader + fail-safe image, so the
read step alone is already valuable.

## Verify the trigger first

Before flipping anything, open the dump in a hex editor and check:

1. Is byte `0x10000` really `FF` right now?
2. Does `0x10000` sit in a plausible flag/config block (VFBL header /
   boot-state area), not in the middle of code or of the fail-safe image?
3. Look for VFBL strings / boot-ok flags / boot counters in the dump to
   corroborate what the real trigger is.

Only flip if the dump supports it. The "flip `0x10000`" trick appears
verbatim in many write-ups, which suggests a single origin -- verify against
your own dump.

## Procedure

1. Remove the CMU from the car (battery negative terminal off, wait a few
   minutes), open the housing, locate the 8-pin SPI-NOR near the i.MX6.
   Photograph the chip marking and pin-1 dot (red clip wire goes to pin 1).
2. Power off, clip on, read the full 8 MB twice -> `nor1.bin`, `nor2.bin`;
   `cmp nor1.bin nor2.bin` must be identical. Copy `nor1.bin` to two
   separate places immediately.
3. Make a patched copy with the boot-select byte `0x10000` set to `00`
   (one byte changed: `0x010000: 0xFF -> 0x00`), keep it as a separate file.
4. Erase -> program the patched file -> verify.
5. Remove the clip, attach serial, power the unit (bench supply with
   current limit ~1.5 A, or back in the car; connector pins: 2R = 12 V
   permanent, 2Q = 12 V ACC, 2C/2D/2L = ground -- measure first).
6. Watch serial:
   - root shell or recovery menu -> run the fix from
     [RECOVERY-BRICK.md](RECOVERY-BRICK.md) (watchdog GPIO off, remount rw,
     sm.conf `devices` path back to
     `/jci/devices/svc-com-jci-cpp-devices.so`,
     `display=filtered-touchscreen0`, remove the wrapper script, repair
     `/etc/passwd`, sync), then
   - flash the **original** `nor1.bin` back (byte `0x10000` = `FF` again),
     erase -> program -> verify, and boot normally.
7. Alternative if the fail-safe gives no shell: put a stock **EU** `.up`
   (failsafe + reinstall for v59, single `.up` for v70+) on a FAT32 stick
   (<=32 GB, files in the root) and let the fail-safe updater run -- full
   reflash, all mods wiped, but guaranteed clean. Never use another
   region's `.up`. Custom `.up` files are impossible (JCI private keys).

An alternative NOR edit is patching the ibc1 cmdline record (NOR `0x20000`)
to `init=/bin/sh` for a direct root shell with no password -- requires a
correct CRC/padding in that record; if the CRC is wrong the bootloader
falls back to ibc2/fail-safe rather than bricking, and flashing `nor1.bin`
back restores everything.

## What does NOT work (verified / analysis)

- Dealer/MDS reflash over CAN: firmware is 1.5-2.5 GB, CAN is ~500 kbps --
  not a real path. Dealer procedure = USB fail-safe or unit replacement.
- Pulling the nav SD / fuse resets: does not fix an sm.conf bootloop.
- USB `jci-autorun` on stock **v59**: no auto-exec from USB (v74+ does run
  `jci-autorun` as root on USB insert -- see
  [RECOVERY-BRICK.md](RECOVERY-BRICK.md)).
- `reset_board="yes"` service failure never drops to a rescue shell -- `sm`
  just reboots the board.

## After recovery

Reinstall the CMU, verify a clean boot (no ~15 s reboot, no
`Failed to load the service` in the serial log), test display + touch +
audio + reverse camera + SSH, and keep the NOR dump plus the on-unit
`*.bak-rescue` files as your rollback set.
