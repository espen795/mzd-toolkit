#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Scan v2
# Scan for available networks (without iwlist/iwconfig - neither exists on MZD)
# v4.7.2 M1: wifi_scan() uit lib/wifi-compat.sh

echo "========================================"
echo " WiFi Scan v2"
echo "========================================"
echo ""

# Interface up
ifconfig wlan0 up 2>/dev/null
sleep 1

echo "Method 1: /proc/net/wireless"
echo "-----------------------------------"
cat /proc/net/wireless 2>/dev/null
echo ""

echo "Method 2: wifi_status (wpactrl + /sys + ifconfig, NO iwconfig)"
echo "-----------------------------------"
wifi_status wlan0 || echo "wifi_status gave no connected status"
echo ""
wifi_deadlock_check || true  # M1b: wl12xx deadlock detectie

echo "Method 3: /proc/net/wireless detail"
echo "-----------------------------------"
echo "This only shows connected status, not all networks."
echo ""

echo "Method 4: wpa_cli scan (if wpa_supplicant is running)"
echo "-----------------------------------"
if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "wpa_supplicant is running - start scan via wifi_scan (run_with_timeout)..."
    wifi_scan wlan0 3
else
    echo "wpa_supplicant is NOT running. Start connect.sh first"
fi
echo ""

echo "Method 5: Manual connect"
echo "-----------------------------------"
echo "If scan does not work, try connecting directly:"
echo ""
echo "For OPEN network:"
echo "  sh ${TOOLKIT_DIR}/wifi/connect.sh"
echo ""
echo "For network WITH password, first edit:"
echo "  ${TOOLKIT_DIR}/config/settings.conf"
echo ""
echo "Or use manual mode:"
echo "  sh ${TOOLKIT_DIR}/wifi/manual.sh"
