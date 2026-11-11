#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Manual WiFi Connect
# Step-by-step manual WiFi connection
# For when the automatic scripts do not work

echo "========================================"
echo " Handmatige WiFi Connectie"
echo "========================================"
echo ""
echo "We will connect step by step."
echo "Press Enter after each step."
echo ""

echo "--- Step 1: Check interface ---"
ifconfig wlan0 2>/dev/null || echo "wlan0 not found!"
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 2: Interface up ---"
ifconfig wlan0 up 2>/dev/null
sleep 2
ifconfig wlan0
wifi_status wlan0 || true   # v4.7.2 M1: wifi-compat instead of iwconfig (does not exist on MZD)
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 3: Stop old processes ---"
# v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - DO NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
killall udhcpc 2>/dev/null
sleep 1
echo "Processes stopped"
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 4: Enter SSID ---"
echo "Enter the WiFi network name (SSID):"
echo -n "SSID: "
read SSID
echo ""
echo "Network: $SSID"
echo ""
echo "Is this an OPEN network? (y/n)"
echo -n "Choice: "
read is_open

echo ""
echo "--- Step 5: Write config ---"
if [ "$is_open" = "y" ] || [ "$is_open" = "Y" ] || [ "$is_open" = "yes" ] || [ "$is_open" = "YES" ] || [ "$is_open" = "j" ] || [ "$is_open" = "J" ] || [ "$is_open" = "ja" ] || [ "$is_open" = "JA" ]; then
    echo "OPEN network config..."
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n}\n' "$SSID" > /tmp/wpa_supplicant.conf
    chmod 600 /tmp/wpa_supplicant.conf 2>/dev/null
else
    echo "Enter the WiFi password:"
    echo -n "Password: "
    read PASSWORD
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\nnetwork={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa_supplicant.conf
    chmod 600 /tmp/wpa_supplicant.conf 2>/dev/null
fi
echo "Config written to /tmp/wpa_supplicant.conf"
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 6: Start wpa_supplicant ---"
wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf 2>&1
sleep 3
echo ""
ps | grep wpa_supplicant | grep -v grep && echo "wpa_supplicant RUNNING" || echo "wpa_supplicant NOT RUNNING"
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 7: Check WiFi status (wifi-compat) ---"
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 8: Request DHCP ---"
echo "This can take a moment (max 15 seconds)..."
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
echo ""
echo "Press Enter..."
read dummy

echo "--- Step 9: Result ---"
ifconfig wlan0
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo ""
if [ -n "$IP" ]; then
    echo "SUCCESS! IP address: $IP"
    echo ""
    echo "Test internet:"
    ping -c 2 -W 3 8.8.8.8 2>/dev/null && echo "Internet works!" || echo "Ping failed"
else
    echo "NO IP address obtained"
    echo ""
    echo "Try DHCP again:"
    echo "  udhcpc -i wlan0 -t 10 -T 3"
fi
