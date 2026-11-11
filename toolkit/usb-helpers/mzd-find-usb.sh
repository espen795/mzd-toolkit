#!/bin/sh
# mzd-find-usb.sh
# Find and show all USB mounts with status
# Firmware: 59.00.502

LOG=/tmp/mzd-find-usb.log
echo "=== Find USB ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

echo "--- /tmp/mnt listing ---" >> $LOG
ls -la /tmp/mnt/ >> $LOG 2>&1
echo "" >> $LOG

echo "--- All sd mounts ---" >> $LOG
for dev in /tmp/mnt/sd*; do
    if [ -d "$dev" ]; then
        echo "" >> $LOG
        echo "Mount: $dev" >> $LOG
        
        # Device node
        DEVNAME=$(basename "$dev")
        echo "Device: /dev/$DEVNAME" >> $LOG
        
        # Test write
        if touch "$dev/.test" 2>/dev/null; then
            echo "Status: READ-WRITE" >> $LOG
            rm "$dev/.test"
        else
            echo "Status: READ-ONLY" >> $LOG
        fi
        
        # List files (max 20)
        echo "Files:" >> $LOG
        ls "$dev" 2>/dev/null | head -20 >> $LOG
    fi
done

echo "" >> $LOG
echo "--- Block devices ---" >> $LOG
ls -la /dev/sd* 2>/dev/null >> $LOG

echo "" >> $LOG
echo "--- Mount output (grep sd) ---" >> $LOG
mount >> $LOG 2>&1

# Compact output for screen
echo "=== USB DETECT ==="
echo "Time: $(date)"
echo ""
FOUND=0
for dev in /tmp/mnt/sd*; do
    if [ -d "$dev" ]; then
        FOUND=1
        DEVNAME=$(basename "$dev")
        if touch "$dev/.test" 2>/dev/null; then
            STATUS="RW"
            rm "$dev/.test"
        else
            STATUS="RO"
        fi
        echo "$dev ($STATUS)"
        echo "  Device: /dev/$DEVNAME"
        echo "  Files:  $(ls "$dev" 2>/dev/null | head -5 | tr '\n' ' ')"
        echo ""
    fi
done

if [ $FOUND -eq 0 ]; then
    echo "No USB mounts found"
    echo ""
    echo "Available block devices:"
    ls /dev/sd* 2>/dev/null
fi

echo "Log: $LOG"
