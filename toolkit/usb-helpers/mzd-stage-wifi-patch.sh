#!/bin/sh
# mzd-stage-wifi-patch.sh
# Patch stage_wifi.sh with autorun hook (requires root + remount rw)
# Firmware: 59.00.502
# CRITICAL: hook must go BEFORE the exit line, not after it!

LOG=/tmp/mzd-stage-wifi-patch.log
echo "=== Stage WiFi Patch ===" > $LOG
echo "Tijd: $(date)" >> $LOG
echo "" >> $LOG

STAGE_WIFI="/jci/scripts/stage_wifi.sh"
BACKUP="/mnt/data_persist/stage_wifi.sh.bak"
AUTORUN="/mnt/data_persist/dev/bin/autorun"

# Check if stage_wifi.sh exists
echo "--- Check stage_wifi.sh ---" >> $LOG
if [ ! -f "$STAGE_WIFI" ]; then
    echo "ERROR: $STAGE_WIFI not found!" >> $LOG
    echo "ERROR"
    exit 1
fi
echo "stage_wifi.sh found" >> $LOG

# Check if we have write access
echo "--- Check write access ---" >> $LOG
if ! touch /jci/scripts/.test_write 2>/dev/null; then
    echo "ERROR: /jci is read-only!" >> $LOG
    echo "Run first: sh mzd-remount-root-rw.sh" >> $LOG
    echo "READ_ONLY"
    exit 1
fi
rm /jci/scripts/.test_write
echo "Write access OK" >> $LOG

# Make backup (only if it does not exist yet)
echo "--- Backup ---" >> $LOG
if [ ! -f "$BACKUP" ]; then
    cp "$STAGE_WIFI" "$BACKUP"
    echo "Backup created: $BACKUP" >> $LOG
else
    echo "Backup already exists: $BACKUP" >> $LOG
fi

# Check if hook already exists
echo "--- Check bestaande hook ---" >> $LOG
if grep -q "MZD-AIO Hook" "$STAGE_WIFI" 2>/dev/null; then
    echo "Hook already exists!" >> $LOG
    echo "AL_GEPATCHED"
    exit 0
fi

# Patch stage_wifi.sh - insert hook BEFORE exit
# Use sed 'i' (insert) not sed 'r' (read/append)
echo "--- Patch stage_wifi.sh ---" >> $LOG
# v4.7.5 M5 (gate 0046b92): BusyBox sed does NOT swallow '\n' in 'i' as newline -> tmpfile+echo pattern
if ! grep -q '^exit' "$STAGE_WIFI" 2>/dev/null; then
    echo "ERROR: no '^exit' line in $STAGE_WIFI (empty or unexpected) - abort" >> $LOG
    echo "FAILED_NO_EXIT"
    exit 1
fi
TMPF=$(mktemp 2>/dev/null || echo "/tmp/stage_wifi_patch.$$")
grep -v '^exit' "$STAGE_WIFI" > "$TMPF" 2>/dev/null
echo "# MZD-AIO Hook" >> "$TMPF"
echo "if [ -x /mnt/data_persist/dev/bin/autorun ]; then" >> "$TMPF"
echo "    /mnt/data_persist/dev/bin/autorun &" >> "$TMPF"
echo "fi" >> "$TMPF"
echo "exit" >> "$TMPF"
cat "$TMPF" > "$STAGE_WIFI" 2>/dev/null
PATCH_RESULT=$?
rm -f "$TMPF"
PATCH_RESULT=$?
echo "Patch exit code: $PATCH_RESULT" >> $LOG

if [ $PATCH_RESULT -ne 0 ]; then
    echo "ERROR: Patch failed!" >> $LOG
    echo "FAILED"
    exit 1
fi

# v4.7.5: post-check syntax - a broken hook may NEVER silently continue
if ! sh -n "$STAGE_WIFI" 2>/dev/null; then
    echo "ERROR: stage_wifi.sh syntax check failed after patch" >> $LOG
    echo "FAILED_SYNTAX"
    exit 1
fi

# Verify placement
echo "--- Verificatie ---" >> $LOG
HOOK_LINE=$(grep -n "MZD-AIO Hook" "$STAGE_WIFI" | cut -d: -f1)
EXIT_LINE=$(grep -n "^exit" "$STAGE_WIFI" | head -1 | cut -d: -f1)
echo "Hook line: $HOOK_LINE" >> $LOG
echo "Exit line: $EXIT_LINE" >> $LOG

if [ -n "$HOOK_LINE" ] && [ -n "$EXIT_LINE" ]; then
    if [ "$HOOK_LINE" -lt "$EXIT_LINE" ]; then
        echo "SUCCESS: Hook placed correctly (before exit)" >> $LOG
        # Show relevant part of file
        echo "--- stage_wifi.sh tail ---" >> $LOG
        tail -10 "$STAGE_WIFI" >> $LOG
        sync
        echo "SUCCESS"
        exit 0
    else
        echo "ERROR: Hook placed WRONG (after exit)!" >> $LOG
        echo "Restore backup: cp $BACKUP $STAGE_WIFI" >> $LOG
        echo "WRONG_PLACEMENT"
        exit 1
    fi
else
    echo "ERROR: Could not find hook or exit!" >> $LOG
    echo "FAILED"
    exit 1
fi
