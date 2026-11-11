#!/bin/sh
# mzd-mount-usb-manual.sh
# Manually mount USB if automount does not work
# Firmware: 59.00.502

LOG=/tmp/mzd-mount-usb-manual.log
echo "=== Manual USB Mount ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# First find all block devices
echo "--- Find block devices ---" >> $LOG
ls -la /dev/sd* >> $LOG 2>&1

echo "" >> $LOG
echo "Available devices:" >> $LOG
DEVICES=""
for dev in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sda /dev/sdb; do
    if [ -b "$dev" ]; then
        DEVICES="$DEVICES $dev"
        echo "Found: $dev" >> $LOG
    fi
done

if [ -z "$DEVICES" ]; then
    echo "ERROR: No block devices found!" >> $LOG
    echo "Check if USB stick is connected" >> $LOG
    echo "--- dmesg ---" >> $LOG
    dmesg 2>/dev/null | tail -20 >> $LOG
    echo "NO_DEVICES"
    exit 1
fi

echo "" >> $LOG

# For each device, try to mount
for DEV in $DEVICES; do
    DEVNAME=$(basename "$DEV")
    MOUNT_POINT="/tmp/mnt/$DEVNAME"
    
    echo "--- Try $DEV ---" >> $LOG
    
    # Check if already mounted
    if mount 2>/dev/null | grep -q "$DEV"; then
        echo "$DEV is already mounted" >> $LOG
        mount | grep "$DEV" >> $LOG
        continue
    fi
    
    # Create mount point
    mkdir -p "$MOUNT_POINT"
    
    # Try to mount as vfat (FAT32)
    echo "Mount as vfat..." >> $LOG
    mount -t vfat -o rw,umask=000,noatime "$DEV" "$MOUNT_POINT" >> $LOG 2>&1
    R1=$?
    echo "vfat exit: $R1" >> $LOG
    
    if [ $R1 -eq 0 ]; then
        echo "SUCCESS: $DEV mounted on $MOUNT_POINT" >> $LOG
        # Test write
        if touch "$MOUNT_POINT/.test" 2>/dev/null; then
            echo "Write test: OK" >> $LOG
            rm "$MOUNT_POINT/.test"
        fi
        echo "Mount: $MOUNT_POINT"
        echo "Device: $DEV"
        echo "SUCCESS"
        exit 0
    fi
    
    # Try as auto (without -t)
    echo "Mount as auto..." >> $LOG
    mount -o rw,umask=000 "$DEV" "$MOUNT_POINT" >> $LOG 2>&1
    R2=$?
    echo "auto exit: $R2" >> $LOG
    
    if [ $R2 -eq 0 ]; then
        echo "SUCCESS: $DEV mounted on $MOUNT_POINT" >> $LOG
        if touch "$MOUNT_POINT/.test" 2>/dev/null; then
            echo "Write test: OK" >> $LOG
            rm "$MOUNT_POINT/.test"
        fi
        echo "Mount: $MOUNT_POINT"
        echo "Device: $DEV"
        echo "SUCCESS"
        exit 0
    fi
    
    # Try as ext2/3/4
    echo "Mount as ext..." >> $LOG
    mount -t ext2 -o rw "$DEV" "$MOUNT_POINT" >> $LOG 2>&1
    R3=$?
    mount -t ext3 -o rw "$DEV" "$MOUNT_POINT" >> $LOG 2>&1
    R4=$?
    mount -t ext4 -o rw "$DEV" "$MOUNT_POINT" >> $LOG 2>&1
    R5=$?
    echo "ext2/3/4 exits: $R3/$R4/$R5" >> $LOG
    
    if [ $R3 -eq 0 ] || [ $R4 -eq 0 ] || [ $R5 -eq 0 ]; then
        echo "SUCCESS: $DEV mounted as ext" >> $LOG
        echo "Mount: $MOUNT_POINT"
        echo "Device: $DEV"
        echo "SUCCESS"
        exit 0
    fi
    
    # Cleanup failed mount point
    rmdir "$MOUNT_POINT" 2>/dev/null
    echo "FAILED for $DEV" >> $LOG
    echo "" >> $LOG
done

echo "=== ALL ATTEMPTS FAILED ===" >> $LOG
echo "--- dmesg for errors ---" >> $LOG
dmesg 2>/dev/null | tail -30 >> $LOG
echo "FAILED"
exit 1
