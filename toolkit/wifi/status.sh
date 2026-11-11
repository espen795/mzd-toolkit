#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Status

echo "========================================"
echo " WiFi Status"
echo "========================================"
echo ""

echo "--- Interface Info ---"
ifconfig wlan0 2>/dev/null || echo "wlan0 not found"

echo ""
echo "--- Wireless Info (wifi-compat: NO iwconfig on MZD) ---"
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b: wl12xx deadlock detectie

echo ""
echo "--- IP Configuration ---"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
MASK=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*Mask://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "IP Address: $IP"
    echo "Netmask:   $MASK"
else
    echo "IP Address: NONE (not connected)"
fi

echo ""
echo "--- Route Table ---"
route -n 2>/dev/null || cat /proc/net/route

echo ""
echo "--- DNS ---"
cat /etc/resolv.conf 2>/dev/null || echo "No resolv.conf"

echo ""
echo "--- Ping Test (gateway) ---"
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
if [ -n "$GW" ]; then
    echo "Gateway: $GW"
    ping -c 2 -W 3 "$GW" 2>/dev/null || echo "Ping failed"
else
    echo "No gateway found"
fi
