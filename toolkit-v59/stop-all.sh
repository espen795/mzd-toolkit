#!/bin/sh
# ============================================================
# MZD Toolkit - STOP ALL
# Stops ALL running toolkit scripts (monitor, watchdog, etc.)
# Usage: sh stop-all.sh
# Or from menu: option "Stop everything"
# ============================================================

STOP_DIR="/tmp/toolkit-stop"
PID_DIR="/tmp/toolkit-pids"

# Source common if possible (v4.8.0: own dir first, then detected USB)
[ -f "$(dirname "$0")/lib/common.sh" ] && . "$(dirname "$0")/lib/common.sh"
if [ "${TOOLKIT_LIB_LOADED:-0}" != "1" ]; then
    for _d in /tmp/mnt/sd* /mnt/sd*; do
        [ -f "$_d/mzd-toolkit/lib/common.sh" ] && case "$_d" in *nav*) ;; *) . "$_d/mzd-toolkit/lib/common.sh" && break ;; esac
    done
fi
type detect_usb >/dev/null 2>&1 && detect_usb

echo "========================================"
echo " MZD Toolkit - STOP EVERYTHING"
echo "========================================"

# 1. Create STOP file (loops stop within 1 iteration)
mkdir -p "$STOP_DIR"
touch "$STOP_DIR/STOP"
# Also on USB if mounted (so scripts running from USB also stop)
# v4.8.0: all sd* mounts (sd_nav excluded) + mzd-data/STOP
for usb in /tmp/mnt/sd* /mnt/sd*; do
    [ -d "$usb" ] || continue
    case "$usb" in *nav*) continue ;; esac
    [ -d "$usb/mzd-toolkit" ] && touch "$usb/mzd-toolkit/STOP" 2>/dev/null
    [ -d "$usb/mzd-data" ] && touch "$usb/mzd-data/STOP" 2>/dev/null
done
echo "STOP file created"

# 2. Kill all registered PIDs
if [ -d "$PID_DIR" ]; then
    for pf in "$PID_DIR"/*; do
        [ -f "$pf" ] || continue
        pid=$(basename "$pf")
        name=$(cat "$pf" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            echo "  kill $pid ($name)"
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$pf"
    done
fi

# 3. Fallback: kill by process names (all toolkit processes)
echo "Killing remaining toolkit processes..."
for proc in mzd-watchdog.sh watchdog.sh monitor.sh vehicle-data.sh fix-watchdog.sh scan-deep.sh; do
    pids=$(pgrep -f "$proc" 2>/dev/null)
    for pid in $pids; do
        # Do not kill ourselves
        [ "$pid" = "$$" ] && continue
        echo "  kill -9 $pid ($proc)"
        kill -9 "$pid" 2>/dev/null
    done
done

# 4. Kill watchdog started in FIX-ALL.sh
pids=$(pgrep -f "mzd-watchdog" 2>/dev/null)
for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    echo "  kill watchdog $pid"
    kill -9 "$pid" 2>/dev/null
done

echo ""
echo "Running processes after stop:"
ps 2>/dev/null | grep -E "watchdog|monitor|vehicle-data|scan-deep|fix-watchdog" | grep -v grep || echo "  (no toolkit processes left)"
echo ""
echo "========================================"
echo " DONE - everything stopped"
echo "========================================"
