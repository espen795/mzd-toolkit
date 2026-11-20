#!/bin/sh
# mzd-mount-status.sh
# Show mount status of root filesystem and USB drives
# Firmware: 59.00.502

LOG=/tmp/mzd-mount-status.log
echo "=== Mount Status ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "Host: $(hostname)" >> $LOG
echo "User: $(whoami)" >> $LOG
echo "" >> $LOG

echo "--- All mounts ---" >> $LOG
mount >> $LOG 2>&1
echo "" >> $LOG

echo "--- Root filesystem test ---" >> $LOG
if touch /test_root_rw 2>/dev/null; then
    echo "Root (/): READ-WRITE" >> $LOG
    rm /test_root_rw
else
    echo "Root (/): READ-ONLY" >> $LOG
fi
echo "" >> $LOG

echo "--- /jci test ---" >> $LOG
if touch /jci/test_rw 2>/dev/null; then
    echo "/jci: READ-WRITE" >> $LOG
    rm /jci/test_rw
else
    echo "/jci: READ-ONLY" >> $LOG
fi
echo "" >> $LOG

echo "--- /etc test ---" >> $LOG
if touch /etc/test_rw 2>/dev/null; then
    echo "/etc: READ-WRITE" >> $LOG
    rm /etc/test_rw
else
    echo "/etc: READ-ONLY" >> $LOG
fi
echo "" >> $LOG

echo "--- /mnt/data_persist test ---" >> $LOG
if touch /mnt/data_persist/test_rw 2>/dev/null; then
    echo "/mnt/data_persist: READ-WRITE (always)" >> $LOG
    rm /mnt/data_persist/test_rw
else
    echo "/mnt/data_persist: READ-ONLY (UNEXPECTED!)" >> $LOG
fi
echo "" >> $LOG

echo "--- USB mounts ---" >> $LOG
for dev in /tmp/mnt/sd* /mnt/sd*; do
    if [ -d "$dev" ]; then
        echo "Mount: $dev" >> $LOG
        # Test write access
        if touch "$dev/.test_rw" 2>/dev/null; then
            echo "  Status: READ-WRITE" >> $LOG
            rm "$dev/.test_rw"
        else
            echo "  Status: READ-ONLY" >> $LOG
        fi
        # Show contents (max 10 files)
        echo "  Inhoud:" >> $LOG
        ls "$dev" 2>/dev/null | head -10 >> $LOG
        echo "" >> $LOG
    fi
done

echo "" >> $LOG
echo "--- Block devices ---" >> $LOG
ls /dev/sd* 2>/dev/null >> $LOG
ls /dev/mmcblk* 2>/dev/null >> $LOG
ls /dev/ffx* 2>/dev/null >> $LOG
ls /dev/mtdblock* 2>/dev/null >> $LOG

echo "=== End ===" >> $LOG

# Output to screen (compact)
echo "=== MOUNT STATUS ==="
echo "Time: $(date)"
echo ""
echo "--- Filesystems ---"
if touch /test_root_rw 2>/dev/null; then
    echo "Root (/):         RW"
    rm /test_root_rw
else
    echo "Root (/):         RO"
fi
if touch /jci/test_rw 2>/dev/null; then
    echo "/jci:             RW"
    rm /jci/test_rw
else
    echo "/jci:             RO"
fi
if touch /etc/test_rw 2>/dev/null; then
    echo "/etc:             RW"
    rm /etc/test_rw
else
    echo "/etc:             RO"
fi
echo "/mnt/data_persist: RW (always)"
echo ""
echo "--- USB Drives ---"
for dev in /tmp/mnt/sd* /mnt/sd*; do
    if [ -d "$dev" ]; then
        if touch "$dev/.test_rw" 2>/dev/null; then
            echo "$dev: RW"
            rm "$dev/.test_rw"
        else
            echo "$dev: RO"
        fi
    fi
done
echo ""
echo "Full log: $LOG"
