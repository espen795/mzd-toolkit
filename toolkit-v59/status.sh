#!/bin/sh
# ============================================================
# MZD Toolkit - Status of running processes
# Shows which toolkit scripts are running + how to stop them
# ============================================================

echo "========================================"
echo " MZD Toolkit - Running Processes"
echo "========================================"
echo ""

PID_DIR="/tmp/toolkit-pids"

echo "--- Registered processes (via PID files) ---"
if [ -d "$PID_DIR" ]; then
    found=0
    for pf in "$PID_DIR"/*; do
        [ -f "$pf" ] || continue
        pid=$(basename "$pf")
        name=$(cat "$pf" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            echo "  PID $pid: $name (RUNNING)"
            found=1
        else
            echo "  PID $pid: $name (dead - cleaning up)"
            rm -f "$pf"
        fi
    done
    [ "$found" = "0" ] && echo "  (none)"
else
    echo "  (PID dir does not exist)"
fi

echo ""
echo "--- Watchdog/monitor processes ---"
ps 2>/dev/null | grep -E "watchdog|monitor|vehicle-data|scan-deep" | grep -v grep | while read line; do
    echo "  $line"
done

echo ""
echo "--- STOP file status ---"
if [ -f /tmp/toolkit-stop/STOP ]; then
    echo "  STOP file PRESENT - loops will stop!"
    echo "  Remove with: rm /tmp/toolkit-stop/STOP"
else
    echo "  no STOP file (normal)"
fi

echo ""
echo "========================================"
echo " To stop EVERYTHING:"
echo "   sh \"\$TOOLKIT_DIR/stop-all.sh\"  (or from menu: Stop everything)"
echo "========================================"
