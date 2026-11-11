#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Fix v2
# Volledige WiFi reset en reconnect

TOOLKIT_DIR="${TOOLKIT_DIR:-}"
if [ -f "$TOOLKIT_DIR/config/settings.conf" ]; then
    . "$TOOLKIT_DIR/config/settings.conf"
fi

SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="***"

echo "========================================"
echo " WiFi Fix v2 - Volledige Reset"
echo "========================================"
echo ""
echo "Network: $SSID"

# Determine type
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "***" ] || [ "$PASSWORD" = "OPEN" ] || [ "$PASSWORD" = "open" ]; then
    echo "Type: OPEN network"
    IS_OPEN=1
else
    echo "Type: WPA/WPA2"
    IS_OPEN=0
fi
echo ""

echo "Step 1: Stop all WiFi processes..."
# v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - do NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
killall udhcpc 2>/dev/null
sleep 1

echo "Step 2: Interface down/up..."
ifconfig wlan0 down 2>/dev/null
sleep 2
ifconfig wlan0 up 2>/dev/null
sleep 2

echo "Step 3: wpa_supplicant config..."

if [ "$IS_OPEN" = "1" ]; then
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n    priority=1\n}\n' "$SSID" > /tmp/wpa_supplicant.conf
else
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\nnetwork={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n    proto=RSN WPA\n    pairwise=CCMP TKIP\n    group=CCMP TKIP\n    priority=1\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa_supplicant.conf
fi

echo "Step 4: Start wpa_supplicant..."
wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf 2>&1
sleep 4

echo "Step 5: DHCP renew (max 5 attempts)..."
killall udhcpc 2>/dev/null
sleep 1
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
DHCP_EXIT=$?

echo "Step 6: Firewall reset..."
iptables -F INPUT 2>/dev/null
# SECURITY (review 2026-10-30): NO default ACCEPT - only SSH port open
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null

echo ""
echo "========================================"
echo " Result"
echo "========================================"
echo ""
ifconfig wlan0
echo ""
wifi_status wlan0 || true   # v4.7.2 M1: wifi-compat ipv iwconfig
wifi_deadlock_check || true  # M1b

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo ""
    echo "SUCCESS: got IP address: $IP"
    echo ""
    echo "Test gateway:"
    GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
    if [ -n "$GW" ]; then
        ping -c 2 -W 3 "$GW" 2>/dev/null
    fi
else
    echo ""
    echo "FAILED: No IP (DHCP exit: $DHCP_EXIT)"
    echo ""
    echo "Try manually:"
    echo "  wifi_status wlan0   # v4.7.2: wifi-compat (no iwconfig on MZD)"
    echo "  wifi_deadlock_check # M1b: check wl12xx deadlock"
    echo "  udhcpc -i wlan0 -t 10 -T 3"
fi
