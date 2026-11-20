#!/bin/sh
# mzd-fix-proc.sh
# Fix /proc mount if missing (needed for mount commands)
# Firmware: 59.00.502

LOG=/tmp/mzd-fix-proc.log
echo "=== Fix /proc ===" > $LOG
echo "Time: $(date)" >> $LOG
echo "" >> $LOG

# Check if /proc exists as directory
echo "--- Check /proc directory ---" >> $LOG
if [ -d /proc ]; then
    echo "/proc directory exists" >> $LOG
else
    echo "/proc directory does NOT exist, creating..." >> $LOG
    mkdir -p /proc
fi

# Check if /proc/mounts exists
if [ -f /proc/mounts ]; then
    echo "/proc/mounts already exists" >> $LOG
    echo "--- /proc/mounts contents (first 5) ---" >> $LOG
    head -5 /proc/mounts >> $LOG
    echo "PROC_OK"
    exit 0
fi

# Mount /proc
echo "--- Mount /proc ---" >> $LOG
mount -t proc proc /proc >> $LOG 2>&1
MOUNT_RESULT=$?
echo "Mount exit code: $MOUNT_RESULT" >> $LOG

if [ $MOUNT_RESULT -ne 0 ]; then
    # Try alternative
    echo "--- Alternative: mount -t proc none /proc ---" >> $LOG
    mount -t proc none /proc >> $LOG 2>&1
    MOUNT_RESULT=$?
    echo "Alternative exit code: $MOUNT_RESULT" >> $LOG
fi

# Verify
if [ -f /proc/mounts ]; then
    echo "SUCCESS: /proc is mounted" >> $LOG
    echo "--- /proc/mounts contents ---" >> $LOG
    cat /proc/mounts >> $LOG
    echo "SUCCESS"
    exit 0
else
    echo "FAILED: /proc mount failed" >> $LOG
    echo "Possibly proc support is not in kernel" >> $LOG
    echo "FAILED"
    exit 1
fi
