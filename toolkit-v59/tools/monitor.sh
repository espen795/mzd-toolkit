#!/bin/sh
# ============================================================
# MZD Toolkit - System Monitor v2
# NON-BLOCKING: starts in background, CLI returns immediately.
#
# Usage:
#   sh monitor.sh          -> start monitor in background (5 min max)
#   sh monitor.sh once     -> one-time check, direct result
#   sh monitor.sh stop     -> stop running monitor
#   sh monitor.sh status   -> show status
# Stop alles: sh stop-all.sh
# ============================================================

PIDFILE="/tmp/toolkit-pids/monitor.pid"
LOGFILE="/tmp/monitor.log"
# v4.8.1: log to $LOG_DIR (mzd-data/logs on USB) if present
for usb in /tmp/mnt/sd* /mnt/sd*; do
    [ -d "$usb/mzd-data/logs" ] && LOGFILE="$usb/mzd-data/logs/monitor.log" && break
    [ -d "$usb/mzd-toolkit/logs" ] && LOGFILE="$usb/mzd-toolkit/logs/monitor.log" && break
done

ACTION="${1:-bg}"

case "$ACTION" in
    stop)
        if [ -f "$PIDFILE" ]; then
            pid=$(cat "$PIDFILE")
            kill -9 "$pid" 2>/dev/null && echo "Monitor $pid stopped" || echo "Monitor $pid was not running"
            rm -f "$PIDFILE"
        else
            echo "No monitor active"
        fi
        exit 0
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Monitor ACTIVE (PID $(cat "$PIDFILE"))"
            echo "Last log lines:"
            tail -10 "$LOGFILE" 2>/dev/null
        else
            echo "Monitor NOT active"
        fi
        exit 0
        ;;
    once)
        # One-time check - direct result, does not block
        echo "=== MZD Monitor (one-time) $(date) ==="
        cat /proc/loadavg 2>/dev/null
        head -3 /proc/meminfo 2>/dev/null
        for t in /sys/class/thermal/thermal_zone*/temp; do
            [ -f "$t" ] && echo "  temp: $(( $(cat "$t" 2>/dev/null) / 1000 ))C"
        done
        IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        echo "WiFi IP: ${IP:-none}"
        ps 2>/dev/null | head -6
        exit 0
        ;;
    bg|"")
        # Check if already active
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Monitor already running (PID $(cat "$PIDFILE")) - log: $LOGFILE"
            echo "Stop with: sh monitor.sh stop"
            exit 0
        fi
        ;;
esac

# ============================================================
# Background monitor - max 5 minutes (60 iterations x 5s)
# ============================================================
mkdir -p "$(dirname "$PIDFILE")"

cat > /tmp/monitor-loop.sh << 'LOOPEOF'
#!/bin/sh
PIDFILE="/tmp/toolkit-pids/monitor.pid"
LOGFILE="__LOGFILE__"
echo $$ > "$PIDFILE"
echo "=== Monitor started $(date) (max 5 min) ===" >> "$LOGFILE"
I=0
MAX=60   # 60 x 5s = 5 minuten max
while [ "$I" -lt "$MAX" ]; do
    # STOP check
    [ -f /tmp/toolkit-stop/STOP ] && { echo "STOP - monitor ends" >> "$LOGFILE"; break; }
    I=$((I+1))
    {
        echo "--- $(date) (iter $I/$MAX) ---"
        cat /proc/loadavg 2>/dev/null
        head -3 /proc/meminfo 2>/dev/null
        IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        echo "WiFi: ${IP:-none}"
    } >> "$LOGFILE" 2>&1
    sleep 5
done
echo "=== Monitor done $(date) after $I iterations ===" >> "$LOGFILE"
rm -f "$PIDFILE"
LOOPEOF

sed -i "s|__LOGFILE__|$LOGFILE|g" /tmp/monitor-loop.sh
chmod +x /tmp/monitor-loop.sh

# Start in background - CLI returns IMMEDIATELY
nohup /tmp/monitor-loop.sh > /dev/null 2>&1 &
echo $! > "$PIDFILE"
echo "Monitor started in background (PID $(cat "$PIDFILE"))"
echo "Log: $LOGFILE"
echo "Max 5 minutes, then it stops by itself."
echo "Stop: sh monitor.sh stop  OR  sh stop-all.sh"
echo "Status:  sh monitor.sh status"
