#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Scan v74
# Uses wifi_scan from lib/wifi-compat.sh (wpactrl, run_with_timeout)
# iwlist/iwconfig do NOT exist on the MZD (v4.7.2 M1)

echo "========================================"
echo " WiFi Scan v74 (wpa_cli)"
echo "========================================"
echo ""

echo "Step 1: Check wpa_supplicant..."
if ! ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "wpa_supplicant NOT running - starting with empty config..."
    printf 'ctrl_interface=/var/run/wpa_supplicant\n' > /tmp/wpa_scan.conf
    # v59 wl12xx: no nl80211 -> default driver (wext)
    wpa_supplicant -B -i wlan0 -c /tmp/wpa_scan.conf 2>&1
    sleep 3
fi

echo "Step 2: Start scan via wifi_scan (timeout 15s)..."
wifi_scan wlan0 5

echo ""
echo "Step 2b: wl12xx deadlock check (M1b)..."
wifi_deadlock_check || true

echo ""
echo "Step 3: Scan results (extra, direct)..."
run_with_timeout "wpactrl scan_results" 15 2>&1

echo ""
echo "Step 4: BSS details (first 5)"
wpactrl scan_results 2>/dev/null | tail -n +2 | head -5 | while read bssid flags level ssid; do
    echo "BSS: $bssid"
    wpactrl bss "$bssid" 2>/dev/null | head -15
    echo "---"
done

echo ""
echo "Step 5: Current status"
wpactrl status 2>&1
