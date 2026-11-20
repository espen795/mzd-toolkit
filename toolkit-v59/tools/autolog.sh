#!/bin/sh
# ============================================================
# autolog.sh v2 - D-Bus vehicle-data autologger for the Mazda CMU
#
# Start from /data_persist/dev/bin/autorun (background) or manually via SSH:
#   sh /data_persist/dev/bin/autolog.sh
#
# Writes per boot/start:
#   <usb>/dbus-logs/dbus-b<bootid>-u<uptime>.raw   full dbus-monitor output
#   <usb>/dbus-logs/dbus-b<bootid>-u<uptime>.meta  start/stop/heartbeat + reason
#
# Differences vs. v1:
#  - dbus-monitor writes directly to the file: no shell loop with two
#    `date` forks per line (v1: ~400 forks/s while driving on the CMU).
#  - Fully detached with setsid (fallback nohup); trap on TERM/HUP/INT
#    always writes a stop line with reason.
#  - `sync` every 30 s, so little is lost on power loss / reboot.
#  - Real PID in the pidfile (v1 wrote a literal "$!" -> duplicate loggers).
#  - Waits up to 180 s for /tmp/dbus_service_socket instead of exiting
#    silently when D-Bus is not up yet.
#  - No separate .log file: v1's contained only headers, no values.
#
# Stop: automatically when the .raw has not grown for $IDLE_STOP seconds
# (engine off), or:  touch /tmp/mzd-dbus-autolog.stop
#
# Requires: dbus-monitor on the CMU, a writable USB stick (the navigation
# SD slot is excluded). Analyze the .raw on a PC with tools/trip-analysis/.
# PRIVACY: the raw file contains GPS coordinates and timestamps - personal
# data. Do not publish it.
# ============================================================

PIDFILE=/tmp/mzd-dbus-autolog.pid
STOPFILE=/tmp/mzd-dbus-autolog.stop
SOCK="${SOCK:-/tmp/dbus_service_socket}"
IDLE_STOP="${IDLE_STOP:-60}"
TICK=10

# --- internal worker mode (runs detached) ---
if [ "$1" = "--worker" ]; then
    RAW="$2"; META="$3"
    MONPID=""
    stamp() { echo "$(cut -d' ' -f1 /proc/uptime)s $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$META"; }
    finish() {
        [ -n "$MONPID" ] && kill "$MONPID" 2>/dev/null
        stamp "STOP reason=$1 bytes=$(wc -c < "$RAW" 2>/dev/null)"
        sync
        rm -f "$PIDFILE"
        exit 0
    }
    trap 'finish signal-TERM' TERM
    trap 'finish signal-HUP' HUP
    trap 'finish signal-INT' INT
    echo $$ > "$PIDFILE"
    rm -f "$STOPFILE"

    W=0
    while [ ! -S "$SOCK" ] && [ $W -lt 180 ]; do sleep 5; W=$((W + 5)); done
    [ -S "$SOCK" ] || finish "no-dbus-socket-after-180s"

    stamp "START pid=$$ raw=$RAW idle_stop=${IDLE_STOP}s"
    dbus-monitor --address "unix:path=$SOCK" >> "$RAW" 2>> "$META" &
    MONPID=$!
    stamp "dbus-monitor pid=$MONPID"

    LASTSIZE=-1; IDLE=0; N=0
    while :; do
        sleep $TICK
        [ -f "$STOPFILE" ] && finish stopfile
        kill -0 "$MONPID" 2>/dev/null || { MONPID=""; finish dbus-monitor-stopped; }
        SIZE=$(wc -c < "$RAW" 2>/dev/null || echo 0)
        if [ "$SIZE" = "$LASTSIZE" ]; then IDLE=$((IDLE + TICK)); else IDLE=0; fi
        LASTSIZE=$SIZE
        [ $IDLE -ge "$IDLE_STOP" ] && finish "idle-${IDLE_STOP}s"
        N=$((N + 1))
        if [ $((N % 3)) -eq 0 ]; then sync; stamp "hb bytes=$SIZE"; fi
    done
fi

# --- starter mode ---
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "dbus-autolog already running (pid $(cat "$PIDFILE"))"
    exit 0
fi

find_usb() {
    # the navigation SD slot is always excluded
    for d in /tmp/mnt/sd[a-z]1 /tmp/mnt/sd[a-z] /mnt/sd[a-z]1 /mnt/sd[a-z]; do
        [ -d "$d" ] || continue
        case "$d" in *nav*) continue ;; esac
        if touch "$d/.mzdtest" 2>/dev/null; then rm -f "$d/.mzdtest"; echo "$d"; return 0; fi
    done
    return 1
}

USB="${LOG_USB:-$(find_usb)}"
if [ -z "$USB" ]; then
    echo "$(date) dbus-autolog: no writable USB stick, not started"
    exit 1
fi
LOGDIR="$USB/dbus-logs"
mkdir -p "$LOGDIR"
BOOT="$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null)"
UPT="$(cut -d. -f1 /proc/uptime)"
BASE="$LOGDIR/dbus-b${BOOT:-x}-u${UPT:-0}"

SELF="$0"
case "$SELF" in /*) ;; *) SELF="$(pwd)/$SELF" ;; esac
if command -v setsid >/dev/null 2>&1; then
    setsid sh "$SELF" --worker "$BASE.raw" "$BASE.meta" < /dev/null > /dev/null 2>&1 &
else
    nohup sh "$SELF" --worker "$BASE.raw" "$BASE.meta" < /dev/null > /dev/null 2>&1 &
fi
sleep 2
echo "dbus-autolog started: pid $(cat "$PIDFILE" 2>/dev/null) raw=$BASE.raw"
