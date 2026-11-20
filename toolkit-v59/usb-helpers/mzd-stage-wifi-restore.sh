#!/bin/sh
# mzd-stage-wifi-restore.sh
# Restore original stage_wifi.sh from backup
# Firmware: 59.00.502

LOG=/tmp/mzd-stage-wifi-restore.log
echo "=== Stage WiFi Restore ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

STAGE_WIFI="/jci/scripts/stage_wifi.sh"
BACKUP="/mnt/data_persist/stage_wifi.sh.bak"

# Check backup
echo "--- Check backup ---" >> $LOG
if [ ! -f "$BACKUP" ]; then
    echo "ERROR: No backup found: $BACKUP" >> $LOG
    echo "NO_BACKUP"
    exit 1
fi
echo "Backup found" >> $LOG

# Check write access
echo "--- Check write access ---" >> $LOG
if ! touch /jci/scripts/.test_write 2>/dev/null; then
    echo "ERROR: /jci is read-only!" >> $LOG
    echo "Run first: sh mzd-remount-root-rw.sh" >> $LOG
    echo "READ_ONLY"
    exit 1
fi
rm /jci/scripts/.test_write
echo "Write access OK" >> $LOG

# Restore backup
echo "--- Restore backup ---" >> $LOG
cp "$BACKUP" "$STAGE_WIFI"
RESTORE_RESULT=$?
echo "Restore exit code: $RESTORE_RESULT" >> $LOG

if [ $RESTORE_RESULT -ne 0 ]; then
    echo "ERROR: Restore failed!" >> $LOG
    echo "FAILED"
    exit 1
fi

# Verify
echo "--- Verification ---" >> $LOG
if grep -q "MZD-AIO Hook" "$STAGE_WIFI" 2>/dev/null; then
    echo "ERROR: Hook is still present!" >> $LOG
    echo "FAILED"
    exit 1
else
    echo "SUCCESS: stage_wifi.sh restored" >> $LOG
    sync
    echo "SUCCESS"
    exit 0
fi
