#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Firmware Info
# Collects all firmware version information

echo "========================================"
echo " MZD Firmware Info"
echo "========================================"
echo ""

echo "--- JCI Version ---"
cat /jci/version.ini 2>/dev/null
echo ""

echo "--- All version files ---"
find /jci -name "version*" -o -name "*.ver" -o -name "*.fw" 2>/dev/null | head -20
echo ""

echo "--- /proc/version ---"
cat /proc/version
echo ""

echo "--- Kernel module versions ---"
cat /proc/modules 2>/dev/null | head -30
echo ""

echo "--- WiFi firmware ---"
dmesg 2>/dev/null | grep -i -E "firmware|fw|brcm|bcmdhd" | head -20
echo ""
ls -la /lib/firmware/ 2>/dev/null
ls -la /lib/firmware/brcm/ 2>/dev/null
echo ""

echo "--- Bluetooth firmware (if present) ---"
ls -la /lib/firmware/BCM* /lib/firmware/brcm/BCM* 2>/dev/null
echo ""

echo "--- Mazda specific files ---"
find /jci -name "*.bin" -o -name "*.rom" -o -name "*.fw" 2>/dev/null | head -10
echo ""

echo "--- Bootloader info ---"
cat /proc/cmdline 2>/dev/null
echo ""

echo "--- Partition table ---"
cat /proc/partitions 2>/dev/null
echo ""
cat /proc/mtd 2>/dev/null || echo "No MTD (flash) devices"
