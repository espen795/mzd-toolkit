#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Process Info
# List of all processes

OUT="/tmp/mzd-process.txt"
echo "MZD Process Info - $(date)" > "$OUT"
echo "========================================" >> "$OUT"
echo "" >> "$OUT"

echo "--- ps (all processes) ---" >> "$OUT"
ps >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- ps aux (if available) ---" >> "$OUT"
ps aux >> "$OUT" 2>&1 || echo "ps aux not supported" >> "$OUT"
echo "" >> "$OUT"

echo "--- ps -ef (if available) ---" >> "$OUT"
ps -ef >> "$OUT" 2>&1 || echo "ps -ef not supported" >> "$OUT"
echo "" >> "$OUT"

echo "--- /proc/*/cmdline (all processes with args) ---" >> "$OUT"
for p in /proc/[0-9]*; do
    if [ -d "$p" ]; then
        pid=$(basename "$p")
        cmd=$(cat "$p/cmdline" 2>/dev/null | tr "\0" " ")
        if [ -n "$cmd" ]; then
            echo "PID $pid: $cmd" >> "$OUT"
        fi
    fi
done
echo "" >> "$OUT"

echo "--- Top processes (most CPU) ---" >> "$OUT"
for p in /proc/[0-9]*; do
    if [ -f "$p/stat" ]; then
        pid=$(basename "$p")
        name=$(cat "$p/comm" 2>/dev/null)
        state=$(awk "{print \$3}" "$p/stat" 2>/dev/null)
        ppid=$(awk "{print \$4}" "$p/stat" 2>/dev/null)
        echo "PID: $pid  PPID: $ppid  State: $state  Name: $name" >> "$OUT"
    fi
done

echo ""
echo "Process info complete!"
echo "Output: $OUT"
cat "$OUT"

# Copy to USB
if [ -d ${TOOLKIT_DIR}/logs ]; then
    cp "$OUT" ${TOOLKIT_DIR}/logs/process-info-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null
    echo ""
    echo "Copied to USB: logs/process-info-*.txt"
fi
