# MZD USB Remount Scripts

Standalone scripts for Mazda MZD Connect (firmware 59.00.502) to remount filesystems.

## ⚠️ Vereisten

- **Root access** via XSS exploit (`autorun` — without .sh — runs as root; archived legacy mistakenly called it `autorun.sh`)
- USB stick with these scripts in the root
- Firmware 59.00.502 (getest)

## 📁 Scripts

| Script | Functie |
|--------|---------|
| `mzd-mount-status.sh` | Toon status van root + USB mounts |
| `mzd-find-usb.sh` | Find and show all USB drives |
| `mzd-remount-root-rw.sh` | Remount `/` (root OS) to read-write |
| `mzd-remount-root-ro.sh` | Remount `/` back to read-only |
| `mzd-remount-usb-rw.sh` | Remount USB to read-write |
| `mzd-remount-usb-ro.sh` | Remount USB back to read-only |
| `mzd-stage-wifi-patch.sh` | Patch `stage_wifi.sh` met autorun hook |
| `mzd-stage-wifi-restore.sh` | Herstel originele `stage_wifi.sh` |

## 🚀 Usage

### In the Mazda terminal:

```sh
# First check the status
sh /tmp/mnt/sdb1/mzd-mount-status.sh

# Make root rw (for /jci, /etc modifications)
sh /tmp/mnt/sdb1/mzd-remount-root-rw.sh

# Make USB rw (for writing log files)
sh /tmp/mnt/sdb1/mzd-remount-usb-rw.sh

# Patch stage_wifi.sh (requires root rw)
sh /tmp/mnt/sdb1/mzd-stage-wifi-patch.sh

# Back to read-only (safety measure)
sh /tmp/mnt/sdb1/mzd-remount-root-ro.sh
sh /tmp/mnt/sdb1/mzd-remount-usb-ro.sh
```

## 📊 Filesystem support

| Filesystem | Support | Opmerking |
|------------|---------|-----------|
| **FAT32 (vfat)** | ✅ Volledig | Aanbevolen formaat |
| **NTFS** | ⚠️ Read-only | No write support in kernel 3.0.35 |
| **exFAT** | ❌ Not supported | Kernel 3.0.35 has no exFAT driver |
| **ext2/3/4** | ✅ Full | Works, but auto-mount may not |

**Recommendation:** Format USB as **FAT32** with **MBR** partition table.

## ⚠️ Waarschuwingen

1. **Watchdog bootloop:** Foutieve `stage_wifi.sh` kan bootloop veroorzaken
2. **Always backup:** Scripts automatically make a backup to `/mnt/data_persist/`
3. **Sync before unmount:** Always run `sync` before removing the USB
4. **Terminal limits:** No shift key, so no `|`, `>`, `&`, `$`

## 🔧 Troubleshooting

### "Read-only file system" error
```sh
# Root rw maken
sh /tmp/mnt/sdb1/mzd-remount-root-rw.sh

# USB rw maken
sh /tmp/mnt/sdb1/mzd-remount-usb-rw.sh
```

### stage_wifi.sh hook does not work
```sh
# Check placement (hook must be BEFORE exit)
tail -10 /jci/scripts/stage_wifi.sh

# Restore and re-patch
sh /tmp/mnt/sdb1/mzd-stage-wifi-restore.sh
sh /tmp/mnt/sdb1/mzd-remount-root-rw.sh
sh /tmp/mnt/sdb1/mzd-stage-wifi-patch.sh
```

### USB not detected
```sh
# Check mounts
sh /tmp/mnt/sdb1/mzd-find-usb.sh

# Check block devices
ls /dev/sd*

# Mount manually (FAT32)
mkdir -p /tmp/mnt/sdb1
mount -t vfat -o rw,umask=000 /dev/sdb1 /tmp/mnt/sdb1
```

## 📝 Logs

All scripts log to `/tmp/mzd-*.log`. Copy these to USB for analysis:

```sh
cp /tmp/mzd-*.log /tmp/mnt/sdb1/logs/
```
