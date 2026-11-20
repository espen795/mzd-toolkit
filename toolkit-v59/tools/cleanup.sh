#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Cleanup
# Removes temporary files

echo "========================================"
echo " MZD Cleanup"
echo "========================================"
echo ""

echo "Cleaning /tmp..."
rm -f /tmp/*.log 2>/dev/null
rm -f /tmp/*.tmp 2>/dev/null
rm -f /tmp/.test* 2>/dev/null
rm -rf /tmp/ssh 2>/dev/null
echo "  /tmp logs removed"

echo "Cleaning old backups (older than 7 days)..."
if [ -d ${TOOLKIT_DIR}/backups ]; then
    find ${TOOLKIT_DIR}/backups -name "*.tar" -mtime +7 -delete 2>/dev/null
    find ${TOOLKIT_DIR}/logs -name "*.txt" -mtime +7 -delete 2>/dev/null
    echo "  Old files removed"
fi

echo "Cleaning data_persist temp..."
rm -f /mnt/data_persist/*.tmp 2>/dev/null
rm -f /mnt/data_persist/.test* 2>/dev/null

echo ""
echo "Disk usage after cleanup:"
df -h /mnt/data_persist 2>/dev/null
df -h /tmp 2>/dev/null

echo ""
echo "Cleanup complete!"
