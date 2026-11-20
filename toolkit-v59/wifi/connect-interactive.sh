#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/connect-interactive.sh (v4.8.0, punt 5.1)
# Interactive connect: scan -> choose AP -> choose security -> psk -> connect.
# PsK is read with echo OFF (stty -echo) and passed via env MZD_PSK
# passed on - NEVER as argv, NEVER in plaintext logs.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TD="${TOOLKIT_DIR:-$(dirname "$0")/..}"

echo "========================================"
echo " Interactieve WiFi Connect (v4.8.3)"
echo "========================================"
sh "$TD/wifi/driver-info.sh" 2>/dev/null
echo ""

echo "--- Starting scan (via NMS D-Bus, 15s timeout) ---"
# v4.8.1: NO more wpactrl scan - the NMS-owned wpa_supplicant does not
# reliably to wpa_cli (proven run r3 2026-11-03: scan_results empty, exit 4).
# Scan via com.jci.blm_nms D-Bus works (run r2 found YOUR_HOTSPOT_SSID).
if [ -S /tmp/dbus_service_socket ]; then
    IFCID=$(dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
        --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.GetInterfaceList 2>/dev/null \
        | grep -oE 'int32 [0-9]+' | awk '{print $2}' | tail -1)
    if [ -n "$IFCID" ]; then
        dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
            --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_StartScan int32:$IFCID int32:10 >/dev/null 2>&1
        sleep 6
        dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
            --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_GetScanResults int32:$IFCID 2>/dev/null \
            | grep -oE 'string "[^"]*"' | sed 's/string "//;s/"$//' > /tmp/mzd-scan.$$
    fi
fi
# Fallback: wpactrl if D-Bus not available
if [ ! -s /tmp/mzd-scan.$$ ]; then
    wifi_scan wlan0 8 2>/dev/null || wpactrl scan 2>/dev/null
    sleep 6
    run_with_timeout "wpactrl scan_results" 15 2>/dev/null | tail -n +2 > /tmp/mzd-scan.$$ 2>/dev/null
fi
N=$(wc -l < /tmp/mzd-scan.$$ 2>/dev/null || echo 0)
case "$N" in ''|*[!0-9]*) N=0 ;; esac
if [ "$N" -eq 0 ]; then
    echo "NO networks found (NMS + wpactrl both empty)"
    rm -f /tmp/mzd-scan.$$
    exit 4
fi
I=0
: > /tmp/mzd-aplist.$$
while read -r line; do
    SSID_LINE=$(echo "$line" | tr -d '\r')
    [ -z "$SSID_LINE" ] && continue
    # skip BSSID/empty lines: only show SSIDs (odd lines in dbus output)
    I=$((I+1))
    echo "$I|$SSID_LINE" >> /tmp/mzd-aplist.$$
    echo "  $I) $SSID_LINE"
done < /tmp/mzd-scan.$$
rm -f /tmp/mzd-scan.$$
echo ""
echo -n "Choose number (0 = cancel): "
read SEL
case "$SEL" in ''|*[!0-9]*|0) echo "Cancelled."; rm -f /tmp/mzd-aplist.$$; exit 1 ;; esac
LINE=$(grep "^$SEL|" /tmp/mzd-aplist.$$ 2>/dev/null)
rm -f /tmp/mzd-aplist.$$
[ -z "$LINE" ] && { echo "Invalid choice"; exit 1; }
SSID=$(echo "$LINE" | cut -d'|' -f2)
echo "Selected: SSID=$SSID"
# Security: check via NMS GetConfiguredNetworks whether the network is already known,
# otherwise assume WPA2 (most hotspots); user can supply psk.
SECTYPE=12; SECLABEL="WPA/WPA2"
echo "Security: $SECLABEL (secType=$SECTYPE)"

PSK=""
if [ "$SECTYPE" != "0" ]; then
    echo -n "Password for $SSID: "
    if command -v stty >/dev/null 2>&1; then
        stty -echo 2>/dev/null
        read PSK
        stty echo 2>/dev/null
        echo ""
    else
        read PSK
    fi
    [ -z "$PSK" ] && { echo "Empty password cancelled."; exit 1; }
fi

echo ""
echo "Connecting via NMS D-Bus..."
# psk via env, NEVER argv
MZD_PSK="$PSK" WIFI_SSID="$SSID" \
    sh "$TD/wifi/connect-nms.sh" "$SSID"
RC=$?
unset PSK MZD_PSK
echo ""
if [ $RC -eq 0 ]; then
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "SUCCESS: connected to $SSID, IP=$IP"
else
    echo "CONNECT FAILED (exit $RC) - see run-log in ${LOG_DIR:-/tmp}/runs/"
fi
exit $RC
