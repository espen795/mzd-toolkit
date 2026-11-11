#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Storage Info
# All storage/mount information

OUT="/tmp/mzd-storage.txt"
echo "MZD Storage Info - $(date)" > "$OUT"
echo "========================================" >> "$OUT"
echo "" >> "$OUT"

echo "--- df -h (disk free) ---" >> "$OUT"
df -h >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- df -h (all filesystems) ---" >> "$OUT"
df -h -a >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- mount ---" >> "$OUT"
mount >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/mounts ---" >> "$OUT"
cat /proc/mounts >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/partitions ---" >> "$OUT"
cat /proc/partitions >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- lsblk (if available) ---" >> "$OUT"
lsblk >> "$OUT" 2>&1 || echo "lsblk not available" >> "$OUT"
echo "" >> "$OUT"

echo "--- block devices ---" >> "$OUT"
ls -la /dev/sd* /dev/mmcblk* /dev/mtd* 2>/dev/null >> "$OUT"
echo "" >> "$OUT"

echo "--- USB mounts detail ---" >> "$OUT"
for d in /tmp/mnt/*; do
    if [ -d "$d" ]; then
        echo "" >> "$OUT"
        echo "Mount: $d" >> "$OUT"
        echo "  Read/Write test:" >> "$OUT"
        if touch "$d/.test_write" 2>/dev/null; then
            echo "    WRITABLE" >> "$OUT"
            rm "$d/.test_write" 2>/dev/null
        else
            echo "    READ-ONLY" >> "$OUT"
        fi
        echo "  Contents (first 20):" >> "$OUT"
        ls -la "$d" 2>/dev/null | head -20 >> "$OUT"
        echo "  Disk usage:" >> "$OUT"
        df -h "$d" 2>/dev/null >> "$OUT"
    fi
done
echo "" >> "$OUT"

echo "--- /mnt detail ---" >> "$OUT"
ls -la /mnt/ >> "$OUT" 2>&1
for d in /mnt/*; do
    if [ -d "$d" ]; then
        echo "" >> "$OUT"
        echo "Directory: $d" >> "$OUT"
        ls -la "$d" >> "$OUT" 2>&1 | head -20
    fi
done
echo "" >> "$OUT"

echo "--- data_persist info ---" >> "$OUT"
echo "Mount:" >> "$OUT"
mount | grep data_persist >> "$OUT" 2>&1
echo "Write test:" >> "$OUT"
if touch /mnt/data_persist/.test_write 2>/dev/null; then
    echo "  WRITABLE" >> "$OUT"
    rm /mnt/data_persist/.test_write 2>/dev/null
else
    echo "  READ-ONLY" >> "$OUT"
fi
echo "Usage:" >> "$OUT"
df -h /mnt/data_persist >> "$OUT" 2>&1
echo "Contents:" >> "$OUT"
ls -la /mnt/data_persist/ >> "$OUT" 2>&1
echo "dev/bin:" >> "$OUT"
ls -la /mnt/data_persist/dev/bin/ >> "$OUT" 2>&1

echo ""
echo "Storage info complete!"
echo "Output: $OUT"
cat "$OUT"

# Copy to USB
if [ -d ${TOOLKIT_DIR}/logs ]; then
    cp "$OUT" ${TOOLKIT_DIR}/logs/storage-info-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null
    echo ""
    echo "Copied to USB: logs/storage-info-*.txt"
fi
