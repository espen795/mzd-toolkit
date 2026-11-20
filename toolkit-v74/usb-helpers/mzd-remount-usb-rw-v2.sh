#!/bin/sh
# mzd-remount-usb-rw-v2.sh
# Robust USB remount to rw with extensive diagnostics
# Firmware: 59.00.502

LOG=/tmp/mzd-remount-usb-rw-v2.log
echo "=== USB Remount RW v2 ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Step 1: Make sure /proc is mounted
echo "--- Step 1: /proc check ---" >> $LOG
if [ ! -f /proc/mounts ]; then
    echo "/proc/mounts missing, mounting /proc..." >> $LOG
    mkdir -p /proc 2>/dev/null
    mount -t proc proc /proc 2>/dev/null
    if [ -f /proc/mounts ]; then
        echo "/proc now mounted" >> $LOG
    else
        echo "WARNING: /proc mount failed, some checks will not work" >> $LOG
    fi
else
    echo "/proc is already mounted" >> $LOG
fi
echo "" >> $LOG

# Step 2: Look for ALL possible USB mounts
echo "--- Step 2: Look for USB mounts ---" >> $LOG
USB_MOUNTS=""
for mnt in /tmp/mnt/sd* /mnt/sd*; do
    if [ -d "$mnt" ]; then
        USB_MOUNTS="$USB_MOUNTS $mnt"
        echo "Found: $mnt" >> $LOG
    fi
done

if [ -z "$USB_MOUNTS" ]; then
    echo "ERROR: No USB mounts found!" >> $LOG
    echo "" >> $LOG
    echo "Available block devices:" >> $LOG
    ls /dev/sd* 2>/dev/null >> $LOG
    echo "" >> $LOG
    echo "All mounts:" >> $LOG
    mount >> $LOG 2>&1
    echo "NO_USB"
    exit 1
fi
echo "" >> $LOG

# Step 3: For every mount, try to make it rw
SUCCESS=0
for USB_MOUNT in $USB_MOUNTS; do
    echo "--- Processing: $USB_MOUNT ---" >> $LOG
    
    # Determine device name
    MOUNT_BASE=$(basename "$USB_MOUNT")
    USB_DEV="/dev/$MOUNT_BASE"
    echo "Device: $USB_DEV" >> $LOG
    
    # Check if device exists
    if [ ! -b "$USB_DEV" ]; then
        echo "Device $USB_DEV is not a block device!" >> $LOG
        # Look for alternative device name
        echo "Looking in /dev for sd devices..." >> $LOG
        ls -la /dev/sd* >> $LOG 2>&1
        continue
    fi
    
    # Test current status
    echo "Testing current status..." >> $LOG
    if touch "$USB_MOUNT/.test_rw" 2>/dev/null; then
        echo "$USB_MOUNT is ALREADY read-write" >> $LOG
        rm "$USB_MOUNT/.test_rw"
        SUCCESS=1
        continue
    fi
    
    # Step 3a: Check sysfs read-only flag
    echo "--- Check sysfs ro flags ---" >> $LOG
    SYSFS_DEV="/sys/block/${MOUNT_BASE%1}/${MOUNT_BASE}"
    SYSFS_DISK="/sys/block/${MOUNT_BASE%1}"
    
    if [ -f "$SYSFS_DEV/ro" ]; then
        RO_VAL=$(cat "$SYSFS_DEV/ro" 2>/dev/null)
        echo "sysfs $SYSFS_DEV/ro = $RO_VAL" >> $LOG
        if [ "$RO_VAL" = "1" ]; then
            echo "Device is read-only in sysfs, trying to release..." >> $LOG
            echo 0 > "$SYSFS_DEV/ro" 2>/dev/null
            if [ -f "$SYSFS_DISK/force_ro" ]; then
                echo 0 > "$SYSFS_DISK/force_ro" 2>/dev/null
            fi
        fi
    fi
    
    # Step 3b: Try blockdev --setrw (if available)
    if which blockdev >/dev/null 2>&1; then
        echo "--- blockdev --setrw ---" >> $LOG
        blockdev --setrw "$USB_DEV" >> $LOG 2>&1
        blockdev --getro "$USB_DEV" >> $LOG 2>&1
    fi
    
    # Step 3c: Try remount with mount point
    echo "--- Remount via mount point ---" >> $LOG
    mount -o remount,rw "$USB_MOUNT" >> $LOG 2>&1
    R1=$?
    echo "Exit code: $R1" >> $LOG
    
    if [ $R1 -eq 0 ]; then
        # Verifieer
        if touch "$USB_MOUNT/.test_rw" 2>/dev/null; then
            echo "SUCCESS via mount point!" >> $LOG
            rm "$USB_MOUNT/.test_rw"
            SUCCESS=1
            continue
        fi
    fi
    
    # Step 3d: Try remount with device + mount point
    echo "--- Remount via device + mount point ---" >> $LOG
    mount -o remount,rw "$USB_DEV" "$USB_MOUNT" >> $LOG 2>&1
    R2=$?
    echo "Exit code: $R2" >> $LOG
    
    if [ $R2 -eq 0 ]; then
        if touch "$USB_MOUNT/.test_rw" 2>/dev/null; then
            echo "SUCCESS via device+mount!" >> $LOG
            rm "$USB_MOUNT/.test_rw"
            SUCCESS=1
            continue
        fi
    fi
    
    # Step 3e: Try umount + mount again
    echo "--- Umount + mount again ---" >> $LOG
    sync
    umount "$USB_MOUNT" >> $LOG 2>&1
    sleep 1
    
    # Mount again with explicit options
    mount -t vfat -o rw,umask=000,noatime "$USB_DEV" "$USB_MOUNT" >> $LOG 2>&1
    R3=$?
    echo "Exit code: $R3" >> $LOG
    
    if [ $R3 -eq 0 ]; then
        if touch "$USB_MOUNT/.test_rw" 2>/dev/null; then
            echo "SUCCESS via umount+mount!" >> $LOG
            rm "$USB_MOUNT/.test_rw"
            SUCCESS=1
            continue
        fi
    fi
    
    # Step 3f: Check dmesg for errors
    echo "--- dmesg check ---" >> $LOG
    dmesg 2>/dev/null | tail -5 >> $LOG
    
    echo "FAILED for $USB_MOUNT" >> $LOG
    echo "" >> $LOG
done

echo "=== RESULT ===" >> $LOG
if [ $SUCCESS -eq 1 ]; then
    echo "SUCCESS: At least 1 USB is rw" >> $LOG
    echo "Mounts: $USB_MOUNTS" >> $LOG
    echo "SUCCESS"
    exit 0
else
    echo "FAILED: Could not make any USB rw" >> $LOG
    echo "See log for details: $LOG" >> $LOG
    echo "FAILED"
    exit 1
fi
