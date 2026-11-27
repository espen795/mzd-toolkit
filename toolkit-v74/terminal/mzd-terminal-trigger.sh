#!/bin/sh
# MZD Terminal trigger — gestart door busybox inetd (127.0.0.1:9997) bij elke TCP-connect.
# Reden: MMUI dropt ReadDTC(diag) vanuit syssettings-context, dus de GUI-klik
# opent alleen een WebSocket naar 127.0.0.1:9997 en wij starten de terminal direct.
exec </dev/null >/dev/null 2>&1
LOG=/tmp/mzd-terminal-trigger.log
STAMP=/tmp/mzd-terminal-trigger.last
NOW=$(date +%s)
LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
# debounce: negeer herhaalde connects binnen 5 s
if [ $((NOW - LAST)) -lt 5 ]; then
    echo "$(date) debounce skip" >> "$LOG"
    exit 0
fi
echo "$NOW" > "$STAMP"
if pidof terminal >/dev/null 2>&1; then
    echo "$(date) terminal draait al -> focus" >> "$LOG"
    export XDG_RUNTIME_DIR=/tmp
    ivi-shell -f "Wayland Terminal" >/dev/null 2>&1
    ivi-shell -z "Wayland Terminal":10000 >/dev/null 2>&1
    exit 0
fi
echo "$(date) start systemHooks.sh 22" >> "$LOG"
setsid sh /jci/scripts/systemHooks.sh 22 >> "$LOG" 2>&1 &
exit 0
