#!/bin/sh
# MZD Toolkit - WiFi Connect v3
# Uses Mazda's own WiFi scripts (more reliable than wpa_supplicant)

# Source gedeelde library (met fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run

TOOLKIT_DIR="${TOOLKIT_DIR:-}"
if [ -f "$TOOLKIT_DIR/config/settings.conf" ]; then
    . "$TOOLKIT_DIR/config/settings.conf"
fi

SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="***"

echo "========================================"
echo " WiFi Connect v3 (Mazda native)"
echo "========================================"
echo ""
echo "Network: $SSID"
echo ""

# Check case sensitivity
echo "LET OP: WiFi SSID is HOOFDLETTERgevoelig!"
echo "In settings.conf staat: $SSID"
echo ""

# Check wlan0
if ! ifconfig wlan0 > /dev/null 2>&1; then
    echo "ERROR: wlan0 not found!"
    exit 1
fi

echo "Stap 1: Interface up..."
ifconfig wlan0 up 2>/dev/null
sleep 2

echo "Stap 2: Mazda WiFi scripts checken..."
echo ""
echo "--- stage_wifi.sh exists? ---"
if [ -f /jci/scripts/stage_wifi.sh ]; then
    echo "JA: /jci/scripts/stage_wifi.sh"
else
    echo "NEE"
fi

echo "--- wpa_supplicant.conf origineel? ---"
if [ -f /etc/wpa_supplicant.conf ]; then
    echo "JA: /etc/wpa_supplicant.conf"
    echo "Inhoud (eerste 20 regels):"
    # SECURITY (review M2): psk filteren
    grep -v 'psk=' /etc/wpa_supplicant.conf | head -20
else
    echo "NEE"
fi

echo ""
echo "Stap 3: Stop alle WiFi processen..."
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

echo "Step 4: run Mazda stage_wifi.sh (restores WiFi)..."
if [ -f /jci/scripts/stage_wifi.sh ]; then
    sh /jci/scripts/stage_wifi.sh 2>&1
    sleep 5
else
    echo "stage_wifi.sh not found, manual..."
fi

echo ""
echo "Step 5: Check WiFi status after stage_wifi (wifi-compat, NO iwconfig)..."
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b

echo ""
echo "Step 6: create WPA config for Mazda..."

# Bepaal type
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "***" ] || [ "$PASSWORD" = "OPEN" ] || [ "$PASSWORD" = "open" ]; then
    echo "Type: OPEN network"
    IS_OPEN=1
else
    echo "Type: WPA/WPA2"
    IS_OPEN=0
fi

# Maak config in /tmp (RAM, Mazda kan erbij)
if [ "$IS_OPEN" = "1" ]; then
    printf 'network={\n    ssid="%s"\n    key_mgmt=NONE\n    scan_ssid=1\n}\n' "$SSID" > /tmp/wpa.conf
else
    printf 'network={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n    scan_ssid=1\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa.conf
fi

echo "Config geschreven: /tmp/wpa.conf"
echo "Inhoud:"
# SECURITY (review M2): psk filteren + chmod 600
chmod 600 /tmp/wpa.conf 2>/dev/null
grep -v 'psk=' /tmp/wpa.conf
echo ""

echo "Step 7: start wpa_supplicant (default driver first)..."
# v59 wl12xx backport: NO nl80211 ioctls. Default (wext) works - try that FIRST.
wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf 2>&1
WPA1=$?
sleep 2

if ! ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "default failed, trying -D wext..."
    wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf -D wext 2>&1
    sleep 2
fi

if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "wpa_supplicant RUNNING"
else
    echo "ERROR: wpa_supplicant did not start"
fi

echo ""
echo "Step 8: Waiting for connection (max 15 sec)..."
i=0
while [ $i -lt 15 ]; do
    sleep 1
    # Check status via wpa_cli if available
    STATUS=$(wpactrl status 2>/dev/null | grep "wpa_state" | cut -d= -f2)
    if [ "$STATUS" = "COMPLETED" ]; then
        echo "WiFi connected! (wpa_state=COMPLETED)"
        break
    fi
    i=$((i + 1))
    echo -n "."
done
echo ""

echo ""
echo "Stap 9: WiFi status check (wifi-compat)..."
wifi_status wlan0 || true
echo ""

echo "Step 10: Request DHCP (max 5 attempts)..."
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1

echo ""
echo "========================================"
echo " Resultaat"
echo "========================================"
echo ""
ifconfig wlan0

echo ""
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "SUCCES: IP adres = $IP"
    echo ""
    echo "Test internet:"
    ping -c 2 -W 3 8.8.8.8 2>/dev/null && echo "Internet works!" || echo "Ping failed"
else
    echo "FAILED: No IP"
    echo ""
    echo "--- Debug (wifi-compat) ---"
    wifi_status wlan0 || true
    wifi_deadlock_check || true  # M1b
    echo ""
    echo "ps (wpa):"
    ps | grep wpa
    echo ""
    echo "wpa_cli status:"
    wpactrl status 2>/dev/null || echo "wpa_cli not working"
    echo ""
    echo "--- Try manually: ---"
    echo "  wpactrl status"
    echo "  wpactrl scan"
    echo "  wpactrl scan_results"
fi
