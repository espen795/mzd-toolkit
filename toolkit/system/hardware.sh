#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Hardware Info
# Collect hardware information

OUT="/tmp/mzd-hardware.txt"
echo "MZD Hardware Info - $(date)" > "$OUT"
echo "========================================" >> "$OUT"
echo "" >> "$OUT"

echo "--- CPU Info ---" >> "$OUT"
cat /proc/cpuinfo >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Memory Info ---" >> "$OUT"
cat /proc/meminfo >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Version ---" >> "$OUT"
cat /proc/version >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Devices (lspci if available) ---" >> "$OUT"
lspci >> "$OUT" 2>&1 || echo "lspci not available" >> "$OUT"
echo "" >> "$OUT"

echo "--- USB Devices (lsusb if available) ---" >> "$OUT"
lsusb >> "$OUT" 2>&1 || echo "lsusb not available" >> "$OUT"
echo "" >> "$OUT"

echo "--- /sys devices ---" >> "$OUT"
ls /sys/class/ >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Network devices ---" >> "$OUT"
ls /sys/class/net/ >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Block devices ---" >> "$OUT"
ls /sys/block/ >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Input devices ---" >> "$OUT"
ls /sys/class/input/ >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- tty/serial ---" >> "$OUT"
ls -la /dev/tty* /dev/serial* 2>/dev/null >> "$OUT"
echo "" >> "$OUT"

echo "--- GPIO (if available) ---" >> "$OUT"
ls /sys/class/gpio/ 2>/dev/null >> "$OUT" || echo "no gpio" >> "$OUT"
echo "" >> "$OUT"

echo "--- Modules (lsmod) ---" >> "$OUT"
cat /proc/modules >> "$OUT" 2>&1 || lsmod >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Interrupts ---" >> "$OUT"
cat /proc/interrupts >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- IO Ports ---" >> "$OUT"
cat /proc/ioports >> "$OUT" 2>&1
echo "" >> "$OUT"

echo ""
echo "Hardware info complete!"
echo "Output: $OUT"
wc -l "$OUT"
echo "lines"
cat "$OUT" | head -50

# Copy to USB
if [ -d ${TOOLKIT_DIR}/logs ]; then
    cp "$OUT" ${TOOLKIT_DIR}/logs/hardware-info-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null
    echo ""
    echo "Copied to USB: logs/hardware-info-*.txt"
fi
