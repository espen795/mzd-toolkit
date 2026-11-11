#!/bin/sh
# mzd-remount-usb-rw.sh
# Remount Mazda MZD USB drive to read-write
# Firmware: 59.00.502 | Required: root access
# Works with: FAT32 (vfat) - NTFS is read-only, exFAT unsupported

LOG=/tmp/mzd-remount-usb-rw.log
echo "=== Remount USB RW ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Find USB mount point
USB_MOUNT=""
USB_DEV=""

echo "--- Looking for USB mounts ---" >> $LOG
ls -d /tmp/mnt/sd* 2>/dev/null >> $LOG

for dev in /tmp/mnt/sd* /mnt/sd*; do
    if [ -d "$dev" ]; then
        USB_MOUNT="$dev"
        echo "Found mount: $USB_MOUNT" >> $LOG
        break
    fi
done

if [ -z "$USB_MOUNT" ]; then
    echo "ERROR: No USB mount found!" >> $LOG
    echo "Available mounts:" >> $LOG
    mount >> $LOG 2>&1
    echo "NO_USB"
    exit 1
fi

# Determine device node
USB_DEV_NAME=$(basename $USB_MOUNT)
USB_DEV="/dev/$USB_DEV_NAME"
echo "Device: $USB_DEV" >> $LOG

# Check current status
echo "--- Test current status ---" >> $LOG
TESTFILE="$USB_MOUNT/.rw_test"
if touch "$TESTFILE" 2>/dev/null; then
    echo "USB is ALREADY read-write" >> $LOG
    rm "$TESTFILE"
    echo "Mount: $USB_MOUNT"
    echo "AL_RW"
    exit 0
else
    echo "USB is read-only, remounting..." >> $LOG
fi

# Remount to rw
echo "--- Remount $USB_MOUNT to rw ---" >> $LOG
mount -o remount,rw "$USB_MOUNT" >> $LOG 2>&1
REMOUNT_RESULT=$?
echo "Remount exit code: $REMOUNT_RESULT" >> $LOG

# If remount fails, try mounting again
if [ $REMOUNT_RESULT -ne 0 ]; then
    echo "--- Trying to mount again ---" >> $LOG
    umount "$USB_MOUNT" >> $LOG 2>&1
    mount -t vfat -o rw,umask=000 "$USB_DEV" "$USB_MOUNT" >> $LOG 2>&1
    REMOUNT_RESULT=$?
    echo "New mount exit code: $REMOUNT_RESULT" >> $LOG
fi

# Verify
echo "--- Verification ---" >> $LOG
if touch "$TESTFILE" 2>/dev/null; then
    echo "SUCCESS: USB is now read-write!" >> $LOG
    rm "$TESTFILE"
    echo "Mount: $USB_MOUNT"
    echo "Device: $USB_DEV"
    echo "SUCCESS"
    exit 0
else
    echo "FAILED: USB is still read-only" >> $LOG
    echo "Mount status:" >> $LOG
    mount >> $LOG 2>&1
    echo "FAILED"
    exit 1
fi
