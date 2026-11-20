#!/bin/sh
# mzd-diag-usb.sh
# Diagnose USB mount problems on Mazda MZD
# Firmware: 59.00.502

LOG=/tmp/mzd-diag-usb.log
echo "=== USB Diagnostics ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "User: $(whoami)" >> $LOG
echo "Host: $(hostname)" >> $LOG
echo "" >> $LOG

echo "--- 1. /proc mount status ---" >> $LOG
if [ -d /proc ]; then
    echo "/proc directory exists" >> $LOG
    if [ -f /proc/mounts ]; then
        echo "/proc/mounts exists" >> $LOG
    else
        echo "ERROR: /proc/mounts does NOT exist!" >> $LOG
        echo "Fix: mount -t proc proc /proc" >> $LOG
    fi
else
    echo "ERROR: /proc directory does NOT exist!" >> $LOG
fi
echo "" >> $LOG

echo "--- 2. Block devices (/dev/sd*) ---" >> $LOG
ls -la /dev/sd* 2>/dev/null >> $LOG || echo "No /dev/sd* devices found" >> $LOG
echo "" >> $LOG

echo "--- 3. Block devices (/dev/mmcblk*) ---" >> $LOG
ls -la /dev/mmcblk* 2>/dev/null >> $LOG || echo "No /dev/mmcblk* devices" >> $LOG
echo "" >> $LOG

echo "--- 4. /tmp/mnt directory ---" >> $LOG
ls -la /tmp/mnt/ 2>/dev/null >> $LOG || echo "/tmp/mnt does not exist" >> $LOG
echo "" >> $LOG

echo "--- 5. All mounts ---" >> $LOG
mount >> $LOG 2>&1
echo "" >> $LOG

echo "--- 6. /proc/mounts (grep sd) ---" >> $LOG
if [ -f /proc/mounts ]; then
    grep -i "sd" /proc/mounts >> $LOG 2>&1 || echo "No sd entries in /proc/mounts" >> $LOG
else
    echo "Cannot read /proc/mounts" >> $LOG
fi
echo "" >> $LOG

echo "--- 7. sysfs block info ---" >> $LOG
for dev in /sys/block/sd*; do
    if [ -d "$dev" ]; then
        echo "Device: $dev" >> $LOG
        DEVNAME=$(basename "$dev")
        # Check read-only status
        if [ -f "$dev/ro" ]; then
            RO=$(cat "$dev/ro")
            echo "  ro: $RO" >> $LOG
        fi
        if [ -f "$dev/force_ro" ]; then
            FORCE_RO=$(cat "$dev/force_ro")
            echo "  force_ro: $FORCE_RO" >> $LOG
        fi
        # List partitions
        for part in "$dev"/sd*; do
            if [ -d "$part" ]; then
                PARTNAME=$(basename "$part")
                echo "  Partition: $PARTNAME" >> $LOG
                if [ -f "$part/ro" ]; then
                    PART_RO=$(cat "$part/ro")
                    echo "    ro: $PART_RO" >> $LOG
                fi
                if [ -f "$part/size" ]; then
                    SIZE=$(cat "$part/size")
                    echo "    size: $SIZE sectors" >> $LOG
                fi
            fi
        done
    fi
done
echo "" >> $LOG

echo "--- 8. dmesg (last 20 lines) ---" >> $LOG
dmesg 2>/dev/null | tail -20 >> $LOG || echo "dmesg not available" >> $LOG
echo "" >> $LOG

echo "--- 9. Test write to every mount ---" >> $LOG
for mnt in /tmp/mnt/sd*; do
    if [ -d "$mnt" ]; then
        echo "Test: $mnt" >> $LOG
        if touch "$mnt/.write_test" 2>/dev/null; then
            echo "  RESULT: WRITE OK" >> $LOG
            rm "$mnt/.write_test"
        else
            echo "  RESULT: READ-ONLY or no access" >> $LOG
        fi
    fi
done
echo "" >> $LOG

echo "=== END DIAGNOSTICS ===" >> $LOG

# Compact output for screen
echo "=== USB DIAGNOSTICS ==="
echo "Time: $(date)"
echo ""
echo "--- /proc status ---"
if [ -f /proc/mounts ]; then
    echo "/proc/mounts: OK"
else
    echo "/proc/mounts: MISSING! (mount -t proc proc /proc)"
fi
echo ""
echo "--- Block devices ---"
ls /dev/sd* 2>/dev/null || echo "No /dev/sd* found"
echo ""
echo "--- /tmp/mnt ---"
ls -la /tmp/mnt/ 2>/dev/null || echo "/tmp/mnt empty or does not exist"
echo ""
echo "--- Mounts (sd only) ---"
mount 2>/dev/null | grep -i "sd" || echo "No sd mounts"
echo ""
echo "--- Write test ---"
for mnt in /tmp/mnt/sd*; do
    if [ -d "$mnt" ]; then
        if touch "$mnt/.test" 2>/dev/null; then
            echo "$mnt: WRITABLE"
            rm "$mnt/.test"
        else
            echo "$mnt: READ-ONLY"
        fi
    fi
done
echo ""
echo "Full log: $LOG"
