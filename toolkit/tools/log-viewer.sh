#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Interactive Log Viewer
# View logs interactively with simple navigation

echo "========================================"
echo " MZD Log Viewer"
echo "========================================"
echo ""
# v4.8.1: logs leven in $LOG_DIR (= mzd-data/logs op USB root)
LOG_BASE="${LOG_DIR:-}"
[ -z "$LOG_BASE" ] && for usb in /tmp/mnt/sd* /mnt/sd*; do
    [ -d "$usb/mzd-data/logs" ] && LOG_BASE="$usb/mzd-data/logs" && break
done
[ -z "$LOG_BASE" ] && LOG_BASE="/tmp/toolkit-logs"
echo "Log base: $LOG_BASE"
echo ""
echo "Available logs:"
echo "  1. dmesg (kernel, last 50 lines)"
echo "  2. toolkit.log (all toolkit events)"
echo "  3. Livelogs (short lines per action)"
echo "  4. Run-logs (last 5, with exit codes)"
echo "  5. /tmp/mzd-*.log"
echo "  6. Autorun log (/tmp/mzd-autorun.log)"
echo ""
echo "  0. Back"
echo ""
echo -n "Choose log: "
read choice
echo ""

case "$choice" in
    1)
        echo "--- dmesg (last 50 lines) ---"
        dmesg 2>/dev/null | tail -50
        echo ""
        echo "--- dmesg WiFi ---"
        dmesg 2>/dev/null | grep -i -E "wlan|wifi|sdio|wl12xx"
        echo ""
        echo "--- dmesg USB ---"
        dmesg 2>/dev/null | grep -i -E "usb|sd[a-z]"
        ;;
    2)
        cat "$LOG_BASE/toolkit.log" 2>/dev/null | tail -60 || echo "No toolkit.log"
        ;;
    3)
        find "$LOG_BASE" -path "*livelogs*" -name "*.log" 2>/dev/null | while read -r f; do
            echo "=== $f ==="
            tail -20 "$f"
            echo ""
        done
        ;;
    4)
        for d in $(ls -td "$LOG_BASE"/runs/*/ 2>/dev/null | head -5); do
            echo "=== $d ==="
            echo "exit: $(cat "$d/exit.code" 2>/dev/null || echo '?')"
            tail -15 "$d/stdout.log" 2>/dev/null
            echo ""
        done
        ;;
    5)
        for f in /tmp/mzd-*.log; do
            if [ -f "$f" ]; then
                echo "=== $f ==="
                tail -20 "$f"
                echo ""
            fi
        done
        ;;
    6)
        cat /tmp/mzd-autorun.log 2>/dev/null || echo "No autorun log"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "Invalid choice"
        ;;
esac
