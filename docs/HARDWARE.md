# Hardware — Mazda Connect CMU (MAZ_CMU-150)

Deep reference for the head unit this toolkit targets. Everything below was
verified on a live `MAZ_CMU-150_59.00.502` (`cmu150_EU`) unit unless noted.

## 1. Models and SoC

| Property | Value |
|---|---|
| Board / model string | `MAZ_CMU-150` (Connectivity Master Unit, 150 series) |
| Flavor | `cmu150_EU` (region variants exist: NA, etc. — same hardware) |
| SoC | Freescale/NXP **i.MX6**, **ARMv7-A** (Cortex-A9 class), hard-float ABI |
| Kernel | **Linux 3.0.35**, built with gcc 4.5.2, `#1 SMP PREEMPT ... 2016` |
| Userland | BusyBox (insmod v1.19.2, sh, tar+gzip, base64, **no `unzip`**) |
| Bootloader string | `xse-cmu-01.01.238_armv7le` (seen in build strings) |

Kernel identity, as reported on the unit:

```
Linux version 3.0.35 (bsp@jci) (gcc version 4.5.2) #1 SMP PREEMPT Thu Oct 27 14:55:44 PKT 2016
```

The exact `vermagic` of every loadable module must therefore be:

```
3.0.35 SMP preempt mod_unload ARMv7
```

## 2. Memory, storage, partitions

The internal storage is split across two devices. The layout below is from a
live `mount`/`df` dump on v59:

| Partition | Device node | Size | Contents | Mount behavior |
|---|---|---|---|---|
| Rootfs | `/dev/ffx01p1` | 478 MB | OS + JCI framework (`/jci`, `/usr`, `/etc`, …) | mounted at `/` as `relfs`, **read-only by default** (`ro,noatime`); can be remounted `rw` for tweaks (`mount -o remount,rw /`) |
| Data | `/dev/ffx01p4` | 307 MB | User settings | `/tmp/mnt/data`, `relfs rw` |
| Persist | `/dev/mmcblk0p2` | 572 MB | Persistent storage (favorites, **the proven writable path**: `/data_persist` / `/tmp/mnt/data_persist`) | `relfs rw` — this is where the toolkit installs itself |
| Resources | `/dev/mmcblk0p1` | 3.1 GB | Navigation maps, VUI voices, media assets | `/tmp/mnt/resources`, `relfs ro` |

Actual mount table excerpt (v59):

```
/dev/ffx01p1   on /                type relfs (ro,noatime)
/dev/ffx01p4   on /tmp/mnt/data    type relfs (rw,noatime)
/dev/mmcblk0p2 on /tmp/mnt/data_persist type relfs (rw,noatime)
/dev/mmcblk0p1 on /tmp/mnt/resources    type relfs (ro,noatime)
```

`/data_persist` is the canonical path Mazda's own scripts use; it is a bind/symlink
into `/tmp/mnt/data_persist`. **All persistent toolkit state lives there** —
`/data_persist/dev/bin/autorun` is the autorun hook (see ARCHITECTURE-CMU.md).

### relfs quirks

- `relfs` resets every file's `mtime` to boot time on each mount. Content is
  **not** overwritten — but "when was this file changed?" troubleshooting is
  impossible from timestamps alone.
- `/` (rootfs) is read-only out of the box. Verify writability with a touch
  test before relying on it:
  ```sh
  mount -o remount,rw / && touch /.rwtest && rm /.rwtest && echo "rootfs writable"
  ```
- There is a **read-only, 100%-full squashfs at `/config-mfg`**. Never write to
  it — that is a brick risk. It does, however, contain an `authorized_keys` used
  by the stock sshd (see SSH-V59.md).

### Backup warning

`tar`/`gzip` over `/tmp/mnt/resources` produces `short read` errors and corrupt
archives, and `gzip -9` is so CPU-heavy it takes ~15 min for 400 MB. The only
proven-safe full backup is a raw `dd` of the block devices to an external USB
stick mounted `rw` (see `tools/backup.sh`).

## 3. Display and input

- **Screen: 800×480** (landscape). The GUI is an Opera Presto 2.12 page
  (`/jci/gui/index.html`), and the Mazda skin layer renders bitmaps from
  `ui_jci_mazda/800_480/`.
- **Reboot shortcut: hold Mute + Navi for ~10 seconds** — this forces a CMU
  reboot. Required after patching GUI JavaScript (the patched `.js` is only
  loaded at HMI start).
- The CMU has **no built-in microphone** (`JCI_VR_PRESENT="NO"` in
  `/jci/version.ini`); handsfree audio uses the car's mic over Bluetooth.
- After a power loss the RTC resets — the clock shows **1970-01-01** and log
  file names carry the `19700101-…` prefix until NTP/manual time sync.

## 4. USB subsystem

- **EHCI only — no xHCI.** The USB ports are USB 2.0 only. USB-C hubs with
  xHCI are *not* recognized; use plain USB 2.0 hubs. Ports are scarce: the CMU
  has a limited number, so a persist-install (toolkit on `/data_persist`, stick
  removable) is strongly recommended over running everything off the stick.
- USB power stays on while the unit is awake (`DO_USB_PWR_EN` GPIO = 1);
  a black screen does not mean USB/SSH died.
- Host/device role switching is exposed via
  `/proc/driver/usbroleswitch/0/mode` — set it to `1` for **host mode** when
  attaching dongles/phones.
- BusyBox `base64 -d` chokes on long single-line heredocs ("truncated base64
  input"). When uploading binaries over SSH, echo the base64 **line by line**
  (e.g. 76-char wrapped) into a file, then `base64 -d` the file. See
  DRIVER-COMPILATION.md §upload.

## 5. Networking hardware

| Interface | Hardware | Notes |
|---|---|---|
| `eth0` | i.MX6 internal MAC, **no external PHY** — not physically connected | **Never touch `eth0`.** Bringing it up/down or changing its config corrupts routing and switch state. |
| `wlan0` | **TI WL1271** on SDIO (mmc0, high-speed SDIO card), out-of-band IRQ on GPIO 378 | Driver `wl12xx` backport `ol_R5.SP4.01-2-g1aa2c8e`, firmware `Rev 7.3.10.10.136`. See WIFI.md for the watchdog root cause. |
| `eth1` / `usb0` | USB dongles / phone tethering | ASIX AX88772, Realtek RTL8152, Samsung RNDIS — see NETWORKING.md. |

## 6. Watchdog

The CMU has a **hardware watchdog** exposed as a GPIO:

```sh
echo 1 > '/sys/class/gpio/Watchdog Disable/value'   # disable
echo 0 > '/sys/class/gpio/Watchdog Disable/value'   # enable
```

The unit can unexpectedly reboot under heavy load or idle detection. For long
operations (full `dd` backups, big copies) disable it first, and re-enable
afterwards.

## 7. SPI / VIM chip

The Vehicle Interface Module (VIM) — the chip that actually talks CAN — sits
behind the SoC over **SPI**, not on a kernel CAN controller:

- `spidev` is loaded; `/dev/spidev1.0` and `/dev/spidev3.0` exist (readable
  only by the `cmu` user).
- Interrupts for `spi_imx` are on IRQs 63, 64, 66.
- The kernel has **no CAN support at all** (`# CONFIG_CAN is not set`) — there
  is no `/dev/can0` and no SocketCAN. See CANBUS-VIM.md.
