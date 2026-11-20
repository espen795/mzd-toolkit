#!/bin/sh
# ============================================================
# MZD Toolkit - Watchdog v2 (NON-BLOCKING)
#
# Usage:
#   sh watchdog.sh once    -> one-time check (default)
#   sh watchdog.sh bg      -> start in background (max 2 hours)
#   sh watchdog.sh stop    -> stop background watchdog
#   sh watchdog.sh status  -> show status
# ============================================================

PIDFILE="/tmp/toolkit-pids/watchdog.pid"
LOGFILE="/tmp/watchdog-loop.log"
for usb in /tmp/mnt/sd* /mnt/sd*; do
    [ -d "$usb/mzd-data/logs" ] && LOGFILE="$usb/mzd-data/logs/watchdog-loop.log" && break
    [ -d "$usb/mzd-toolkit/logs" ] && LOGFILE="$usb/mzd-toolkit/logs/watchdog-loop.log" && break
done

ACTION="${1:-once}"

check_once() {
    echo "--- Watchdog check $(date) ---"
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    if [ -z "$IP" ]; then
        echo "WiFi: NOT CONNECTED - fixing..."
        sh ${TOOLKIT_DIR}/wifi/connect-simple.sh > /dev/null 2>&1
    else
        echo "WiFi: OK ($IP)"
    fi
    if ! ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
        echo "SSH: INACTIVE - starting..."
        sh ${TOOLKIT_DIR}/ssh/quick-fix-working.sh > /dev/null 2>&1
    else
        echo "SSH: OK"
    fi
}

case "$ACTION" in
    stop)
        if [ -f "$PIDFILE" ]; then
            pid=$(cat "$PIDFILE")
            kill -9 "$pid" 2>/dev/null && echo "Watchdog $pid stopped" || echo "was not running"
            rm -f "$PIDFILE"
        else
            echo "No watchdog active"
        fi
        exit 0
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Watchdog ACTIVE (PID $(cat "$PIDFILE")) - log: $LOGFILE"
            tail -5 "$LOGFILE" 2>/dev/null
        else
            echo "Watchdog NOT active"
        fi
        exit 0
        ;;
    once)
        check_once
        exit 0
        ;;
    bg|"")
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Watchdog already running (PID $(cat "$PIDFILE"))"
            exit 0
        fi
        ;;
esac

# Background watchdog - max 2 hours (120 iterations x 60s)
mkdir -p "$(dirname "$PIDFILE")"
cat > /tmp/watchdog-loop.sh << 'LOOPEOF'
#!/bin/sh
PIDFILE="/tmp/toolkit-pids/watchdog.pid"
LOGFILE="__LOGFILE__"
echo $$ > "$PIDFILE"
I=0
MAX=120   # 120 x 60s = 2 uur max
while [ "$I" -lt "$MAX" ]; do
    [ -f /tmp/toolkit-stop/STOP ] && { echo "$(date) STOP - watchdog ends" >> "$LOGFILE"; break; }
    I=$((I+1))
    {
        echo "=== $(date) watchdog iter $I/$MAX ==="
        IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        if [ -z "$IP" ]; then
            echo "WiFi down - reassociating..."
            wpactrl reassociate 2>/dev/null
            wpactrl set power_save off 2>/dev/null
            udhcpc -i wlan0 -n -q -t 3 -T 2 2>/dev/null
        else
            echo "WiFi OK: $IP"
        fi
        ps | grep sshd | grep -v grep > /dev/null || echo "SSH down!"
    } >> "$LOGFILE" 2>&1
    sleep 60
done
echo "=== watchdog done $(date) ===" >> "$LOGFILE"
rm -f "$PIDFILE"
LOOPEOF
sed -i "s|__LOGFILE__|$LOGFILE|g" /tmp/watchdog-loop.sh
chmod +x /tmp/watchdog-loop.sh

nohup /tmp/watchdog-loop.sh > /dev/null 2>&1 &
echo $! > "$PIDFILE"
echo "Watchdog started in background (PID $(cat "$PIDFILE"))"
echo "Log: $LOGFILE | Max 2 hours"
echo "Stop: sh watchdog.sh stop  OR  sh stop-all.sh"
