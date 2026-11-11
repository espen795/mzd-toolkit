#!/bin/sh
# ============================================================
# MZD Toolkit - optimize-wpa.sh
# Optimize wpa_supplicant config for WL1271 stability
#
# Optimizations:
# - ap_scan=1 (efficient scanning, less channel hopping)
# - scan_interval=10 (less frequent scanning = less TX flush)
# - bgscan simple with long interval (fewer background scans)
# - fast_reauth=1 (faster reauth after short disconnect)
# - disable_pmksa=1 (no PMKSA caching issues with iPhone hotspot)
# - pmf=0 (iPhone hotspot does not support 802.11w)
# - disable_p2p / p2p_disabled=1 (no P2P = less multirole pressure)
#
# Works on: Mazda CMU v59/v74, BusyBox sh, wpa_supplicant v2.6
# ============================================================

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run

SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="${WIFI_PASSWORD:-}"
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
[ -f "$TOOLKIT_DIR/config/settings.conf" ] && . "$TOOLKIT_DIR/config/settings.conf"
SSID="${WIFI_SSID:-$SSID}"
PASSWORD="${WIFI_PASSWORD:-$PASSWORD}"

CONF="/tmp/wpa_supplicant.conf"
BAK="/tmp/wpa_supplicant.conf.bak-optimize-$(date +%s)"
LOG="/tmp/mnt/data_persist/mzd-toolkit-logs/optimize-wpa-$(date +%s).log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() { echo "$*" | tee -a "$LOG" 2>/dev/null; echo "$*"; }

log "========================================"
log " MZD optimize-wpa.sh - $(date)"
log " SSID: $SSID"
log "========================================"

# Backup existing config
[ -f "$CONF" ] && cp "$CONF" "$BAK" && log "Backup: $BAK"

# --- Bouw geoptimaliseerde config ---
log ""
log "[1/4] Generating new wpa_supplicant.conf..."

{
    echo "ctrl_interface=/var/run/wpa_supplicant"
    echo "update_config=1"
    echo ""
    echo "# --- WL1271 stabiliteit optimalisaties ---"
    echo "ap_scan=1"
    # NOTE: scan_interval/fast_reauth/disable_pmksa/p2p_disabled/bgscan are
    # NOT valid global fields in wpa_supplicant v2.6 on v59 (kernel 3.0.35).
    # "unknown global field" -> WHOLE config parse fails -> no connection.
    # Only ap_scan is valid here; tuning belongs in the network{} block.
    echo ""
    if [ -n "$PASSWORD" ] && [ "$PASSWORD" != "***" ] && [ "$PASSWORD" != "OPEN" ]; then
        echo "network={"
        echo "    ssid=\"$SSID\""
        echo "    psk=\"$PASSWORD\""
        echo "    key_mgmt=WPA-PSK"
        echo "    proto=RSN WPA"
        echo "    pairwise=CCMP TKIP"
        echo "    group=CCMP TKIP"
        echo "    pmf=0"
        echo "    priority=1"
        echo "    scan_ssid=1"
        echo "}"
        log "  Network: WPA/WPA2 with psk"
    else
        echo "network={"
        echo "    ssid=\"$SSID\""
        echo "    key_mgmt=NONE"
        echo "    priority=1"
        echo "}"
        log "  Network: OPEN"
    fi
} > "$CONF"

# SECURITY (review M2): restrictive permissions on wpa config with psk
chmod 600 "$CONF" 2>/dev/null

log "  Config written to $CONF:"
# do NOT log psk (review M2)
grep -v 'psk=' "$CONF" | tee -a "$LOG"

# --- Restart wpa_supplicant with new config ---
log ""
log "[2/4] restarting wpa_supplicant..."
# v4.7.5: NEVER killall wpa_supplicant — NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill our own instance if it is NOT from NMS — check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - do NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
sleep 2
ifconfig wlan0 down 2>/dev/null
sleep 1
ifconfig wlan0 up 2>/dev/null
sleep 2

wpa_supplicant -B -i wlan0 -c "$CONF" 2>&1 | tee -a "$LOG"
sleep 4

log ""
log "[3/4] Power save OFF (see fix-powersave.sh) ..."
wpactrl set power_save off 2>/dev/null
echo "on" > /sys/class/net/wlan0/power/control 2>/dev/null

log ""
log "[4/4] Connect + DHCP..."
wpactrl scan 2>/dev/null
sleep 3
wpactrl reassociate 2>/dev/null
sleep 3

# DHCP
killall udhcpc 2>/dev/null
sleep 1
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1 | tee -a "$LOG"

log ""
log "========================================"
log " Result:"
log "========================================"
ifconfig wlan0 2>/dev/null | tee -a "$LOG"
log ""
wpactrl status 2>/dev/null | tee -a "$LOG"

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    log ""
    log "SUCCESS: IP = $IP"
    GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print $2}')
    [ -n "$GW" ] && ping -c 2 -W 3 "$GW" 2>&1 | tee -a "$LOG"
else
    log ""
    log "No IP yet - check wpa_state above"
fi
log ""
log "Monitor watchdogs: dmesg | grep -c 'watchdog interrupt'"
log "Log: $LOG"
log "========================================"
