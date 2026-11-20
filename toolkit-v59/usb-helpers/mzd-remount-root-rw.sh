#!/bin/sh
# mzd-remount-root-rw.sh
# Remount Mazda MZD root filesystem (/) to read-write
# Firmware: 59.00.502 | Requires: root access via XSS exploit

LOG=/tmp/mzd-remount-root-rw.log
echo "=== Remount Root RW ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Check current mount status
echo "--- Current mount status ---" >> $LOG
mount >> $LOG 2>&1
echo "" >> $LOG

# Test if we are already rw
echo "--- Test current status ---" >> $LOG
if touch /test_rw 2>/dev/null; then
    echo "Root is ALREADY read-write" >> $LOG
    rm /test_rw
    echo "AL_RW"
    exit 0
else
    echo "Root is read-only, remounting..." >> $LOG
fi

# Remount root to rw
echo "--- Remount to rw ---" >> $LOG
mount -o remount,rw / >> $LOG 2>&1
REMOUNT_RESULT=$?
echo "Remount exit code: $REMOUNT_RESULT" >> $LOG

if [ $REMOUNT_RESULT -ne 0 ]; then
    echo "ERROR: Remount failed!" >> $LOG
    # Try alternative method
    echo "--- Try /dev/ffx01p1 ---" >> $LOG
    mount -o remount,rw /dev/ffx01p1 / >> $LOG 2>&1
    REMOUNT_RESULT=$?
    echo "Alternative exit code: $REMOUNT_RESULT" >> $LOG
fi

# Verify
echo "--- Verification ---" >> $LOG
if touch /test_rw 2>/dev/null; then
    echo "SUCCESS: Root is now read-write!" >> $LOG
    rm /test_rw
    echo "--- New mount status ---" >> $LOG
    mount >> $LOG 2>&1
    echo "SUCCESS"
    exit 0
else
    echo "FAILED: Root is still read-only" >> $LOG
    echo "FAILED"
    exit 1
fi
