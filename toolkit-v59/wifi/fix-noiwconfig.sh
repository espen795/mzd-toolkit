#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi scripts without iwconfig
# iwconfig is NOT available on this MZD! (proven: "iwconfig: not found")
# v4.7.2 M1: use wifi_status/wifi_scan/wifi_deadlock_check from lib/wifi-compat.sh
# (was: /proc/net/wireless and wpa_cli inline)

echo "========================================"
echo " WiFi Status (wifi-compat, without iwconfig)"
echo "========================================"
echo ""

echo "--- wifi_status (wpactrl + /sys + ifconfig + /proc/net/wireless) ---"
wifi_status wlan0 || true
echo ""

echo "--- M1b deadlock check ---"
wifi_deadlock_check || true
echo ""

echo "--- wifi_scan (wpactrl, timeout) ---"
wifi_scan wlan0 3
echo ""

echo "--- /sys/class/net/wlan0 ---"
cat /sys/class/net/wlan0/operstate 2>/dev/null
echo "carrier: $(cat /sys/class/net/wlan0/carrier 2>/dev/null)"
echo "address: $(cat /sys/class/net/wlan0/address 2>/dev/null)"
echo ""

echo "--- IP config ---"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "IP: ${IP:-NONE}"
echo ""

echo "--- Routes ---"
route -n 2>/dev/null
echo ""

echo "--- Ping gateway ---"
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
if [ -n "$GW" ]; then
    echo "Gateway: $GW"
    ping -c 3 -W 3 "$GW" 2>&1
else
    echo "No gateway"
fi
