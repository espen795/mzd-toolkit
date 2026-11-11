#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Unlock OS
# Attempt to bypass OS read-only protection
# NOTE: can make the system unstable!

echo "========================================"
echo " OS Unlock Attempt"
echo "========================================"
echo ""
echo "WARNING: this can damage the system!"
echo "Make a backup first!"
echo ""
echo "Continue? (y/n)"
echo -n "Choice: "
read confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && [ "$confirm" != "yes" ] && [ "$confirm" != "YES" ] && [ "$confirm" != "j" ] && [ "$confirm" != "J" ] && [ "$confirm" != "ja" ] && [ "$confirm" != "JA" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "--- Method 1: Remount all partitions ---"
for part in / /jci /etc /usr /var /opt /home; do
    if mount 2>/dev/null | grep -q "on $part "; then
        echo "Remount $part rw..."
        mount -o remount,rw "$part" 2>&1
    fi
done

echo ""
echo "--- Method 2: /proc/sys write protection off ---"
echo "Check /proc/sys write protection..."
cat /proc/sys/kernel/tainted 2>/dev/null
echo ""

echo "--- Method 3: Check mount options ---"
cat /proc/mounts 2>/dev/null

echo ""
echo "--- Method 4: Block device remount ---"
echo "Block devices:"
ls -la /dev/mmcblk* 2>/dev/null | head -10
echo ""
echo "Partitions:"
cat /proc/partitions 2>/dev/null

echo ""
echo "--- Method 5: Direct block device write test ---"
# Find the root partition
ROOT_DEV=$(mount 2>/dev/null | grep " on / " | awk "{print \$1}")
echo "Root device: $ROOT_DEV"

echo ""
echo "--- Method 6: Mazda specific unlock ---"
echo "Searching Mazda unlock tools..."
find /jci -name "*unlock*" -o -name "*fsck*" -o -name "*rw*" 2>/dev/null | head -10

echo ""
echo "Check /jci/scripts for useful tools:"
ls /jci/scripts/ 2>/dev/null | head -30

echo ""
echo "--- Method 7: Boot partition check ---"
ls -la /boot/ 2>/dev/null || echo "No /boot"
cat /proc/cmdline 2>/dev/null

echo ""
echo "========================================"
echo " Unlock attempt complete"
echo "========================================"
echo ""
echo "Test writability now:"
for dir in / /jci /etc /usr /var /mnt/data_persist /tmp; do
    if touch "$dir/.unlock_test" 2>/dev/null; then
        echo "  $dir: WRITABLE"
        rm "$dir/.unlock_test" 2>/dev/null
    else
        echo "  $dir: read-only"
    fi
done
