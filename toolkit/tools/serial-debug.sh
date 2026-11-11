#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Serial/UART Debug
# Check for serial ports and debug options

echo "========================================"
echo " Serial/UART Debug"
echo "========================================"
echo ""

echo "--- Available tty devices ---"
ls -la /dev/tty* 2>/dev/null
echo ""

echo "--- Serial ports in /sys ---"
ls -la /sys/class/tty/ 2>/dev/null
echo ""

echo "--- Check for UART/serial in kernel ---"
dmesg 2>/dev/null | grep -i -E "serial|uart|tty|amba|pl011" | head -20
echo ""

echo "--- Mazda-specific debug ports ---"
# Mazda often has a debug UART on specific GPIO
ls -la /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
echo ""

echo "--- GPIO debug (if available) ---"
ls /sys/class/gpio/ 2>/dev/null
cat /sys/kernel/debug/gpio 2>/dev/null | head -30
echo ""

echo "--- JCI debug tools ---"
ls -la /jci/bin/ 2>/dev/null | grep -i -E "debug|test|diag|log"
echo ""

echo "--- jci-dialog test ---"
if [ -x /jci/bin/jci-dialog ]; then
    echo "jci-dialog available:"
    /jci/bin/jci-dialog --help 2>&1 | head -20
else
    echo "jci-dialog not found"
fi
