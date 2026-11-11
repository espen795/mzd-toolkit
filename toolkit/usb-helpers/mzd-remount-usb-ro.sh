#!/bin/sh
# mzd-remount-usb-ro.sh
# Remount Mazda MZD USB drive back to read-only
# Firmware: 59.00.502 | Requires: root access

LOG=/tmp/mzd-remount-usb-ro.log
echo "=== Remount USB RO ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Look for USB mount point
USB_MOUNT=""

for dev in /tmp/mnt/sd* /mnt/sd*; do
    if [ -d "$dev" ]; then
        USB_MOUNT="$dev"
        echo "Found mount: $USB_MOUNT" >> $LOG
        break
    fi
done

if [ -z "$USB_MOUNT" ]; then
    echo "ERROR: No USB mount found!" >> $LOG
    echo "NO_USB"
    exit 1
fi

# Sync first
echo "--- Sync ---" >> $LOG
sync
echo "Sync complete" >> $LOG

# Remount to ro
echo "--- Remount $USB_MOUNT to ro ---" >> $LOG
mount -o remount,ro "$USB_MOUNT" >> $LOG 2>&1
REMOUNT_RESULT=$?
echo "Remount exit code: $REMOUNT_RESULT" >> $LOG

# Verify
echo "--- Verification ---" >> $LOG
TESTFILE="$USB_MOUNT/.ro_test"
if touch "$TESTFILE" 2>/dev/null; then
    echo "FAILED: USB is still read-write!" >> $LOG
    rm "$TESTFILE"
    echo "FAILED"
    exit 1
else
    echo "SUCCESS: USB is now read-only" >> $LOG
    echo "Mount: $USB_MOUNT"
    echo "SUCCESS"
    exit 0
fi
