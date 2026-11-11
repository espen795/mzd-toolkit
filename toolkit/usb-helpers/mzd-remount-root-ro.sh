#!/bin/sh
# mzd-remount-root-ro.sh
# Remount Mazda MZD root filesystem (/) back to read-only
# Firmware: 59.00.502 | Requires: root access

LOG=/tmp/mzd-remount-root-ro.log
echo "=== Remount Root RO ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Sync first to force all writes to disk
echo "--- Sync ---" >> $LOG
sync
echo "Sync complete" >> $LOG

# Remount back to ro
echo "--- Remount to ro ---" >> $LOG
mount -o remount,ro / >> $LOG 2>&1
REMOUNT_RESULT=$?
echo "Remount exit code: $REMOUNT_RESULT" >> $LOG

if [ $REMOUNT_RESULT -ne 0 ]; then
    echo "ERROR: Remount to ro failed!" >> $LOG
    echo "--- Try /dev/ffx01p1 ---" >> $LOG
    mount -o remount,ro /dev/ffx01p1 / >> $LOG 2>&1
    REMOUNT_RESULT=$?
    echo "Alternative exit code: $REMOUNT_RESULT" >> $LOG
fi

# Verify
echo "--- Verification ---" >> $LOG
if touch /test_ro 2>/dev/null; then
    echo "FAILED: Root is still read-write!" >> $LOG
    rm /test_ro
    echo "FAILED"
    exit 1
else
    echo "SUCCESS: Root is now read-only" >> $LOG
    echo "--- New mount status ---" >> $LOG
    mount >> $LOG 2>&1
    echo "SUCCESS"
    exit 0
fi
