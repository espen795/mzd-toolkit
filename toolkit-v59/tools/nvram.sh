#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - NVRAM/EEPROM Tools
# Reads and writes NVRAM/EEPROM values (if accessible)

echo "========================================"
echo " MZD NVRAM/EEPROM Tools"
echo "========================================"
echo ""

echo "--- NVRAM devices ---"
ls -la /dev/nvram /dev/mtd* /dev/ubi* 2>/dev/null
find /sys -name "*nvram*" -o -name "*eeprom*" 2>/dev/null | head -10
echo ""

echo "--- Mazda config storage ---"
# Mazda often stores config in /mnt/data_persist
ls -la /mnt/data_persist/ 2>/dev/null
echo ""
find /mnt/data_persist -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.dat" 2>/dev/null | head -20
echo ""

echo "--- Read NVRAM (if /dev/nvram exists) ---"
if [ -c /dev/nvram ]; then
    echo "NVRAM size:"
    ls -la /dev/nvram
    echo ""
    echo "First 256 bytes (hex):"
    dd if=/dev/nvram bs=256 count=1 2>/dev/null | od -A x -t x1z | head -20
    echo ""
    echo "As string (first 256 bytes):"
    dd if=/dev/nvram bs=256 count=1 2>/dev/null | strings | head -20
else
    echo "/dev/nvram not available"
fi
echo ""

echo "--- Mazda specifieke storage ---"
# Check for Mazda config files
for f in /mnt/data_persist/*.dat /mnt/data_persist/*.bin /mnt/data_persist/config*; do
    if [ -f "$f" ]; then
        echo "Found: $f ($(wc -c < "$f") bytes)"
        echo "  First 100 bytes:"
        head -c 100 "$f" | od -A x -t x1z | head -8
        echo ""
    fi
done

echo "--- Backup NVRAM/config ---"
BACKUP_DIR="${TOOLKIT_DIR}/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ -c /dev/nvram ]; then
    echo "Backup NVRAM to USB..."
    dd if=/dev/nvram of="$BACKUP_DIR/nvram-$TIMESTAMP.bin" 2>/dev/null
    echo "  -> $BACKUP_DIR/nvram-$TIMESTAMP.bin"
fi

# Backup Mazda config
if [ -d /mnt/data_persist ]; then
    echo "Backup data_persist config..."
    cp -r /mnt/data_persist/aio "$BACKUP_DIR/aio-$TIMESTAMP" 2>/dev/null
    cp -r /mnt/data_persist/dev "$BACKUP_DIR/dev-$TIMESTAMP" 2>/dev/null
    echo "  -> $BACKUP_DIR/"
fi
