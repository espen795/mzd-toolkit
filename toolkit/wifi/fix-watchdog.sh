#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# ============================================================
# MZD Toolkit - fix-watchdog.sh
# wl12xx watchdog monitor + auto soft-recovery + module params
#
# What it does:
# 1. Check /sys/module/wl12xx/parameters for watchdog/ps params
# 2. Start a monitor loop (background) that scans dmesg for
#    "watchdog interrupt" and "Unable to flush" and then immediately
#    does a soft recovery (wpa_cli reassociate) BEFORE the
#    chip fully hangs in a recovery loop.
# 3. Optional: count watchdogs in current dmesg
#
# Usage:
#   fix-watchdog.sh status   -> only show status/count
#   fix-watchdog.sh monitor  -> start background monitor
#   fix-watchdog.sh stop     -> stop monitor
#   fix-watchdog.sh params   -> show/change module parameters
#
# Works on: Mazda CMU v59/v74, BusyBox sh
# ============================================================

WLAN="${1:-wlan0}"
ACTION="${2:-status}"
[ "$1" = "status" ] || [ "$1" = "monitor" ] || [ "$1" = "stop" ] || [ "$1" = "params" ] && WLAN="wlan0" && ACTION="$1"
PIDFILE="/tmp/mzd-watchdog-monitor.pid"
LOG="/tmp/mnt/data_persist/mzd-toolkit-logs/watchdog-monitor.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG" 2>/dev/null; echo "$*"; }

# --- Check module parameters ---
show_params() {
    echo "=== wl12xx module parameters ==="
    if [ -d /sys/module/wl12xx/parameters ]; then
        for p in /sys/module/wl12xx/parameters/*; do
            echo "  $(basename $p) = $(cat $p 2>/dev/null)"
        done
    else
        echo "  /sys/module/wl12xx/parameters not found"
    fi
    echo ""
    echo "=== wl12xx_sdio module parameters ==="
    if [ -d /sys/module/wl12xx_sdio/parameters ]; then
        for p in /sys/module/wl12xx_sdio/parameters/*; do
            echo "  $(basename $p) = $(cat $p 2>/dev/null)"
        done
    else
        echo "  not found"
    fi
    echo ""
    echo "=== Try known params (dynamic_ps, watchdog) ==="
    for param in dynamic_ps no_ps watchdog_timeout; do
        p="/sys/module/wl12xx/parameters/$param"
        if [ -e "$p" ]; then
            echo "  $param exists (current: $(cat $p))"
            if [ -w "$p" ]; then
                echo "0" > "$p" 2>/dev/null && echo "    -> $param = 0 set (power save / watchdog off)"
            fi
        fi
    done
}

# --- Watchdog count in dmesg ---
count_watchdogs() {
    WD=$(dmesg 2>/dev/null | grep -c "watchdog interrupt received")
    TX=$(dmesg 2>/dev/null | grep -c "Unable to flush all TX buffers")
    echo "Watchdog interrupts in dmesg: $WD"
    echo "TX buffer flush timeouts:      $TX"
    echo ""
    echo "Last 5 wl12xx errors:"
    dmesg 2>/dev/null | grep -i "wl12xx.*ERROR" | tail -5
}

# --- Soft recovery: force reassociation without hardware reset ---
soft_recovery() {
    log "WATCHDOG/STALL detected - starting soft recovery..."
    wpactrl reassociate 2>/dev/null
    sleep 2
    wpactrl status 2>/dev/null | grep wpa_state
    # If still disconnected: scan + reconnect
    ST=$(wpactrl status 2>/dev/null | grep wpa_state | cut -d= -f2)
    if [ "$ST" != "COMPLETED" ]; then
        log "  Still $ST - triggering scan..."
        wpactrl scan 2>/dev/null
        sleep 3
        wpactrl reassociate 2>/dev/null
    fi
    # Turn power save off again (may have been reset after recovery)
    wpactrl set power_save off 2>/dev/null
    echo "on" > "/sys/class/net/$WLAN/power/control" 2>/dev/null
    log "Soft recovery done. Status: $(wpactrl status 2>/dev/null | grep wpa_state)"
}

# --- Monitor loop ---
monitor_loop() {
    log "=== Watchdog monitor started (PID $$) ==="
    LAST_WD=0
    echo $$ > "$PIDFILE"
    WD_ITER=0
    WD_MAX=720   # max 2 uur (720 x 10s)
    while [ "$WD_ITER" -lt "$WD_MAX" ]; do
        check_stop 2>/dev/null && { log "Stopped via STOP file"; break; }
        WD_ITER=$((WD_ITER + 1))
        WD=$(dmesg 2>/dev/null | grep -c "watchdog interrupt received")
        TX=$(dmesg 2>/dev/null | grep -c "Unable to flush all TX buffers")
        if [ "$WD" -gt "$LAST_WD" ]; then
            log "!!! NEW WATCHDOG INTERRUPT (total: $WD) !!!"
            soft_recovery
            LAST_WD=$WD
        elif [ "$TX" -gt 0 ] && [ $(( $(date +%s) % 30 )) -eq 0 ]; then
            # check every ~30s whether there are TX stalls
            CUR_TX=$(dmesg 2>/dev/null | grep -c "Unable to flush all TX buffers")
            if [ "$CUR_TX" -gt "${LAST_TX:-0}" ]; then
                log "TX buffer flush timeout detected (total: $CUR_TX) - preventive reassociate"
                wpactrl reassociate 2>/dev/null
                LAST_TX=$CUR_TX
            fi
        fi
        sleep 10
    done
}

case "$ACTION" in
    status)
        echo "=== MZD Watchdog Status ==="
        count_watchdogs
        if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            echo "Monitor loop: ACTIVE (PID $(cat $PIDFILE))"
        else
            echo "Monitor loop: NOT active"
        fi
        ;;
    params)
        show_params
        ;;
    monitor)
        # Stop old monitor if present
        if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            kill "$(cat $PIDFILE)" 2>/dev/null
            rm -f "$PIDFILE"
        fi
        # NON-BLOCKING: start in background, CLI returns immediately
        monitor_loop > /dev/null 2>&1 &
        echo $! > "$PIDFILE"
        echo "Watchdog monitor started in background (PID $(cat $PIDFILE))"
        echo "Max 2 hours. Log: see fix-watchdog.sh status"
        echo "Stop: sh fix-watchdog.sh stop  OR  sh stop-all.sh"
        ;;
    stop)
        if [ -f "$PIDFILE" ]; then
            kill "$(cat $PIDFILE)" 2>/dev/null && echo "Monitor stopped (PID $(cat $PIDFILE))" || echo "Monitor was not active"
            rm -f "$PIDFILE"
        else
            echo "No active monitor found"
        fi
        ;;
    *)
        echo "Usage: $0 [status|monitor|stop|params]"
        ;;
esac
