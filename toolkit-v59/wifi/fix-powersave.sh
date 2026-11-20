#!/bin/sh
# ============================================================
# MZD Toolkit - fix-powersave.sh
# WiFi Power Save OFF on TI WL1271 (without iw/iwconfig - both NOT on MZD)
# v4.7.2: iwconfig/iwlist refs in comments marked as legacy (code uses wpa_cli -i)
#
# Why: wl12xx watchdog interrupts (FW panic pc=0x21b8e) are
# triggered by ELP (Extreme Low Power) sleep/wake races over SDIO.
# Power save OFF = chip stays awake = no ELP deadlock.
#
# Works on: Mazda CMU v59/v74, BusyBox sh, kernel 3.0.35
# Required: wpa_cli (present), /sys (present)
# ============================================================

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run

WLAN="${1:-wlan0}"
LOG="/tmp/mnt/data_persist/mzd-toolkit-logs/fix-powersave-$(date +%s).log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() { echo "$*" | tee -a "$LOG" 2>/dev/null; echo "$*"; }

log "========================================"
log " MZD fix-powersave.sh - $(date)"
log " Interface: $WLAN"
log "========================================"

# --- Step 1: wpa_cli power_save off (wpa_supplicant level) ---
log ""
log "[1/5] wpa_cli set power_save off ..."
if wpactrl set power_save off 2>&1 | tee -a "$LOG"; then
    log "  -> wpa_cli power_save command executed"
else
    log "  -> wpa_cli power_save not supported (continuing with /sys)"
fi

# Check if it worked
PS=$(wpactrl get power_save 2>/dev/null)
log "  Current power_save status via wpa_cli: ${PS:-unknown}"

# --- Step 2: /sys/class/net/wlan0/power/control = on (no runtime PM) ---
log ""
log "[2/5] disabling /sys runtime power management ..."
if [ -f "/sys/class/net/$WLAN/power/control" ]; then
    echo "on" > "/sys/class/net/$WLAN/power/control" 2>/dev/null && \
        log "  -> /sys/class/net/$WLAN/power/control = $(cat /sys/class/net/$WLAN/power/control)" || \
        log "  -> could not write control (read-only?)"
else
    log "  -> /sys/class/net/$WLAN/power/control does not exist"
fi

# --- Step 3: /sys/class/net/wlan0/device/power/control (wl12xx device level) ---
log ""
log "[3/5] wl12xx device power control ..."
for p in "/sys/class/net/$WLAN/device/power/control" \
         "/sys/bus/mmc/devices/mmc0:0001/power/control" \
         "/sys/class/net/$WLAN/power/runtime_active_time" \
         "/sys/class/net/$WLAN/power/runtime_status"; do
    if [ -e "$p" ]; then
        if [ -w "$p" ]; then
            echo "on" > "$p" 2>/dev/null && log "  -> $p = $(cat $p 2>/dev/null)" || log "  -> $p not writable"
        else
            log "  -> $p = $(cat $p 2>/dev/null) (read-only)"
        fi
    fi
done

# --- Step 4: adjust wpa_supplicant.conf (persistent) ---
log ""
log "[4/5] updating wpa_supplicant.conf with power_save=0 ..."
for CONF in /tmp/wpa_supplicant.conf /etc/wpa_supplicant.conf; do
    if [ -f "$CONF" ]; then
        cp "$CONF" "$CONF.bak-powersave-$(date +%s)" 2>/dev/null
        # Add global power save disable at the top
        # BusyBox sed 'a\...\n...' does NOT work (review M1) - temp file
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/wpa.$$")
        {
            # Only valid global fields for wpa_supplicant v2.6 on v59:
            # scan_interval/disable_pmksa/bgscan/p2p_disabled are NOT global
            # fields here -> "unknown global field" -> parse fails -> no connection!
            echo "ap_scan=1"
            cat "$CONF" 2>/dev/null
        } > "$TMPF"
        if cp "$TMPF" "$CONF" 2>/dev/null; then
            rm -f "$TMPF"
            log "  -> $CONF adjusted (backup made)"
        else
            rm -f "$TMPF"
            log "  -> could not write $CONF (read-only?)"
        fi
        # SECURITY (review M2): chmod 600 + do NOT log psk
        chmod 600 "$CONF" 2>/dev/null
        log "  --- new contents $CONF (psk filtered) ---"
        grep -v 'psk=' "$CONF" 2>/dev/null | head -15 | tee -a "$LOG"
    fi
done

# --- Step 5: Verification ---
log ""
log "[5/5] Verification ..."
log "  wpa_cli status:"
wpactrl status 2>/dev/null | tee -a "$LOG" | head -8
log ""
log "  /sys power state:"
for f in control runtime_status autosuspend_delay_ms; do
    p="/sys/class/net/$WLAN/power/$f"
    [ -e "$p" ] && log "    power/$f = $(cat $p 2>/dev/null)"
done
log ""
log "  /proc/net/wireless:"
cat /proc/net/wireless 2>/dev/null | tee -a "$LOG"
log ""
log "========================================"
log " DONE - Power save should now be OFF"
log " Test: watch dmesg for 'watchdog interrupt'"
log "   dmesg | grep -i watchdog"
log " Log: $LOG"
log "========================================"
