#!/bin/sh
# ============================================================
# can-log.sh -- detached CAN trip-logger on the CMU.
# Logs ALL decoded CAN frames + raw frames to a USB stick (sdx1),
# until the car stops (no CAN traffic => auto-stop).
#
# NO writes to CMU flash. Only reads from the CAN interface and
# writes to USB.
#
# Usage (on the CMU, via SSH):
#   sh can-log.sh start [iface]
#   sh can-log.sh stop
#   sh can-log.sh status
#
# Env overrides:
#   LOG_DIR   - where logs go (default: auto-detect USB, NEVER /tmp)
#   IDLE_STOP - seconds without CAN traffic = auto-stop (default 60)
#   IFACE     - CAN interface (default: first can* in /sys/class/net)
# ============================================================
DIR="$(cd "$(dirname "$0")" && pwd)"
KCD="$DIR/mazda-can-unified.kcd"
PIDFILE="/tmp/can-log.pid"
STOPFILE="/tmp/can-log.stop"
IDLE_STOP="${IDLE_STOP:-60}"
IFACE="${IFACE:-}"

find_usb() {
    # sd_nav EXCLUDED (navigation SD). First writable /tmp/mnt/sd* or /mnt/sd*.
    for d in /tmp/mnt/sd[a-z]1 /tmp/mnt/sd[a-z] /mnt/sd[a-z]1 /mnt/sd[a-z]; do
        [ -d "$d" ] || continue
        case "$d" in *nav*) continue ;; esac
        if touch "$d/.mzdtest" 2>/dev/null; then
            rm -f "$d/.mzdtest"
            echo "$d"
            return 0
        fi
    done
    return 1
}

start() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && {
        echo "can-log already running (pid $(cat "$PIDFILE"))"; exit 0; }
    rm -f "$STOPFILE"
    [ -z "$IFACE" ] && IFACE="$(ls /sys/class/net 2>/dev/null | grep '^can' | head -n 1)"
    [ -z "$IFACE" ] && { echo "ERROR: no can* interface" >&2; exit 1; }
    command -v candump >/dev/null 2>&1 || { echo "ERROR: candump not present" >&2; exit 1; }

    USB="${LOG_DIR:-$(find_usb)}"
    [ -z "$USB" ] && { echo "ERROR: no writable USB (sd_nav excluded). Plug in sdx1." >&2; exit 1; }
    LOGDIR="$USB/can-logs"
    mkdir -p "$LOGDIR"
    # CMU clock is empty (epoch) => boot-id + uptime in the file name
    BOOT="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-8)"
    TS="b${BOOT:-x}-u$(cut -d. -f1 /proc/uptime | tr -d ' ')"
    LOG="$LOGDIR/canlog-$TS.log"
    RAW="$LOGDIR/canlog-$TS.raw"

    # detached: nohup + own session, survives logout of the SSH session
    nohup sh -c '
        DIR="'"$DIR"'"; KCD="'"$KCD"'"; IFACE="'"$IFACE"'"
        LOG="'"$LOG"'"; RAW="'"$RAW"'"; IDLE="'"$IDLE_STOP"'"
        LAST=$(date +%s)
        echo "# can-log start $(date) iface=$IFACE log=$LOG idle_stop=${IDLE}s" >> "$LOG"
        candump "$IFACE" 2>/dev/null | while IFS= read -r line; do
            NOW=$(date +%s)
            echo "$line" >> "$RAW"
            echo "$line" | python3 "$DIR/kcd_decode.py" "$KCD" --compact >> "$LOG" 2>/dev/null
            # idle detection: if no frame for >IDLE seconds -> auto-stop
            if [ $((NOW - LAST)) -ge "$IDLE" ]; then
                echo "# idle ${IDLE}s no CAN traffic -> stop $(date)" >> "$LOG"
                break
            fi
            LAST=$NOW
            [ -f /tmp/can-log.stop ] && { echo "# stopfile present -> stop $(date)" >> "$LOG"; break; }
        done
        echo "# can-log end $(date)" >> "$LOG"
        rm -f '"$PIDFILE"'
    ' >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "can-log started (pid $(cat "$PIDFILE"))"
        echo "  iface=$IFACE  log=$LOG"
        echo "  raw=$RAW"
        echo "  auto-stops after ${IDLE_STOP}s without CAN traffic (car off) or via: $0 stop"
    else
        echo "ERROR: logger did not start -- check $LOG" >&2
        exit 1
    fi
}

stop() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        touch "$STOPFILE"
        kill "$(cat "$PIDFILE")" 2>/dev/null
        pkill -f "candump.*can" 2>/dev/null
        rm -f "$PIDFILE"
        echo "can-log stopped"
    else
        rm -f "$PIDFILE" "$STOPFILE"
        echo "can-log was not running"
    fi
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "RUNNING pid=$(cat "$PIDFILE")"
        USB="$(find_usb)"
        [ -n "$USB" ] && ls -lh "$USB"/can-logs/ 2>/dev/null | tail -5
    else
        echo "NOT ACTIVE"
    fi
}

case "${1:-}" in
    start)  shift; [ -n "$1" ] && IFACE="$1"; start ;;
    stop)   stop ;;
    status) status ;;
    *) echo "Usage: $0 {start [iface]|stop|status}"; echo "Env: LOG_DIR=... IDLE_STOP=60 IFACE=can0" ;;
esac
