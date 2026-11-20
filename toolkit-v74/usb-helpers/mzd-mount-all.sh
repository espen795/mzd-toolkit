#!/bin/sh
# mzd-mount-all.sh
# All-in-one script: fix /proc, diagnose, and remount USB to rw
# Firmware: 59.00.502

SCRIPT_DIR="${USB_MOUNT}"
LOG=/tmp/mzd-mount-all.log

echo "=== MZD Mount All ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Try to find script directory
if [ ! -d "$SCRIPT_DIR" ]; then
    for d in /tmp/mnt/sd* /mnt/sd*; do
        if [ -d "$d" ]; then
            SCRIPT_DIR="$d"
            break
        fi
    done
fi

echo "Script dir: $SCRIPT_DIR" >> $LOG
echo "" >> $LOG

# Step 1: Fix /proc
if [ -f "$SCRIPT_DIR/mzd-fix-proc.sh" ]; then
    echo "--- Step 1: Fix /proc ---" >> $LOG
    sh "$SCRIPT_DIR/mzd-fix-proc.sh" >> $LOG 2>&1
    echo "" >> $LOG
else
    echo "--- Step 1: Fix /proc (inline) ---" >> $LOG
    if [ ! -f /proc/mounts ]; then
        mkdir -p /proc 2>/dev/null
        mount -t proc proc /proc 2>/dev/null
        echo "/proc mount attempt done" >> $LOG
    fi
fi

# Step 2: Diagnose
if [ -f "$SCRIPT_DIR/mzd-diag-usb.sh" ]; then
    echo "--- Step 2: Diagnose ---" >> $LOG
    sh "$SCRIPT_DIR/mzd-diag-usb.sh" >> $LOG 2>&1
    echo "" >> $LOG
fi

# Step 3: Remount USB rw
if [ -f "$SCRIPT_DIR/mzd-remount-usb-rw-v2.sh" ]; then
    echo "--- Step 3: Remount USB RW ---" >> $LOG
    sh "$SCRIPT_DIR/mzd-remount-usb-rw-v2.sh" >> $LOG 2>&1
    R=$?
    echo "Remount exit: $R" >> $LOG
    echo "" >> $LOG
else
    echo "--- Step 3: Remount USB RW (inline) ---" >> $LOG
    # Inline remount logic
    for mnt in /tmp/mnt/sd*; do
        if [ -d "$mnt" ]; then
            DEV="/dev/$(basename $mnt)"
            echo "Trying $mnt ($DEV)..." >> $LOG
            
            # Test first
            if touch "$mnt/.test" 2>/dev/null; then
                echo "  Already RW" >> $LOG
                rm "$mnt/.test"
                continue
            fi
            
            # Remount attempts
            mount -o remount,rw "$mnt" >> $LOG 2>&1
            mount -o remount,rw "$DEV" "$mnt" >> $LOG 2>&1
            
            # Umount + mount
            sync
            umount "$mnt" 2>/dev/null
            mount -t vfat -o rw,umask=000 "$DEV" "$mnt" >> $LOG 2>&1
            
            # Test
            if touch "$mnt/.test" 2>/dev/null; then
                echo "  SUCCESS!" >> $LOG
                rm "$mnt/.test"
            else
                echo "  FAILED" >> $LOG
            fi
        fi
    done
fi

# Step 4: Show final status
echo "--- Step 4: Final status ---" >> $LOG
echo "Mounts:" >> $LOG
mount >> $LOG 2>&1
echo "" >> $LOG
echo "Write tests:" >> $LOG
for mnt in /tmp/mnt/sd*; do
    if [ -d "$mnt" ]; then
        if touch "$mnt/.test" 2>/dev/null; then
            echo "$mnt: RW" >> $LOG
            rm "$mnt/.test"
        else
            echo "$mnt: RO" >> $LOG
        fi
    fi
done

echo "" >> $LOG
echo "=== DONE ===" >> $LOG

# Output to screen
echo "=== MZD MOUNT ALL ==="
echo "Time: $(date)"
echo ""
echo "--- /proc status ---"
if [ -f /proc/mounts ]; then echo "OK"; else echo "MISSING"; fi
echo ""
echo "--- USB Mounts ---"
for mnt in /tmp/mnt/sd*; do
    if [ -d "$mnt" ]; then
        if touch "$mnt/.test" 2>/dev/null; then
            echo "$mnt: RW"
            rm "$mnt/.test"
        else
            echo "$mnt: RO"
        fi
    fi
done
echo ""
echo "Log: $LOG"
