#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Collect Logs
# Collects all system logs

OUT="/tmp/mzd-logs.txt"
USB_LOG="${TOOLKIT_DIR}/logs"

echo "MZD Collect Logs - $(date)" > "$OUT"
echo "========================================" >> "$OUT"
echo "" >> "$OUT"

echo "Collecting logs..."

echo "--- dmesg (kernel log) ---" >> "$OUT"
dmesg >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- dmesg WiFi ---" >> "$OUT"
dmesg 2>/dev/null | grep -i wlan >> "$OUT" 2>&1
dmesg 2>/dev/null | grep -i wifi >> "$OUT" 2>&1
dmesg 2>/dev/null | grep -i sdio >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- dmesg USB ---" >> "$OUT"
dmesg 2>/dev/null | grep -i usb >> "$OUT" 2>&1
dmesg 2>/dev/null | grep -i sdb >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- dmesg SSH ---" >> "$OUT"
dmesg 2>/dev/null | grep -i ssh >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /var/log (if it exists) ---" >> "$OUT"
ls -la /var/log/ >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /var/log/messages ---" >> "$OUT"
cat /var/log/messages >> "$OUT" 2>&1 || echo "not found" >> "$OUT"
echo "" >> "$OUT"

echo "--- /var/log/syslog ---" >> "$OUT"
cat /var/log/syslog >> "$OUT" 2>&1 || echo "not found" >> "$OUT"
echo "" >> "$OUT"

echo "--- /tmp logs ---" >> "$OUT"
ls -la /tmp/*.log 2>/dev/null >> "$OUT"
for f in /tmp/*.log; do
    if [ -f "$f" ]; then
        echo "" >> "$OUT"
        echo "=== $f ===" >> "$OUT"
        tail -100 "$f" >> "$OUT" 2>&1
    fi
done
echo "" >> "$OUT"

echo "--- /mnt/data_persist logs ---" >> "$OUT"
ls -la /mnt/data_persist/*.log 2>/dev/null >> "$OUT"
ls -la /mnt/data_persist/**/*.log 2>/dev/null >> "$OUT"
echo "" >> "$OUT"

echo "--- jci logs ---" >> "$OUT"
ls -la /jci/log/ 2>/dev/null >> "$OUT"
ls -la /jci/logs/ 2>/dev/null >> "$OUT"
find /jci -name "*.log" 2>/dev/null >> "$OUT"
echo "" >> "$OUT"

echo "--- MZD own logs ---" >> "$OUT"
for f in /tmp/mzd-*.log /tmp/mzd-toolkit-*.log; do
    if [ -f "$f" ]; then
        echo "" >> "$OUT"
        echo "=== $f ===" >> "$OUT"
        cat "$f" >> "$OUT" 2>&1
    fi
done
echo "" >> "$OUT"

echo "--- Autorun log ---" >> "$OUT"
cat /tmp/mzd-autorun.log >> "$OUT" 2>&1 || echo "no autorun log" >> "$OUT"
echo "" >> "$OUT"

echo ""
echo "Log collection complete!"
echo "Output: $OUT"

# Show only the summary
wc -l "$OUT"
echo "lines"

# Copy to USB
if [ -d "$USB_LOG" ]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    cp "$OUT" "$USB_LOG/system-logs-$TIMESTAMP.txt" 2>/dev/null
    echo ""
    echo "Copied to USB: logs/system-logs-$TIMESTAMP.txt"

    # Also copy individual /tmp logs
    for f in /tmp/*.log; do
        if [ -f "$f" ]; then
            cp "$f" "$USB_LOG/$(basename $f)-$TIMESTAMP" 2>/dev/null
        fi
    done
    echo "Individual logs also copied."
else
    echo ""
    echo "WARNING: USB log directory not found: $USB_LOG"
fi
