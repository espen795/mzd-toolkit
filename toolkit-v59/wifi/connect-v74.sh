#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Connect v74
# Gebaseerd op firmware v74 analyse
# Laadt modules in juiste volgorde + gebruikt -Dnl80211

TOOLKIT_DIR="${TOOLKIT_DIR:-}"
if [ -f "$TOOLKIT_DIR/config/settings.conf" ]; then
    . "$TOOLKIT_DIR/config/settings.conf"
fi

SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="***"

echo "========================================"
echo " WiFi Connect v74 (Firmware-aware)"
echo "========================================"
echo ""
echo "Network: $SSID"
echo "WiFi Chip: TI WL1271/WL1283"
echo ""

# Check args
if [ -n "$1" ]; then
    SSID="$1"
fi
if [ -n "$2" ]; then
    PASSWORD="$2"
fi

echo "SSID: $SSID"
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "***" ] || [ "$PASSWORD" = "OPEN" ]; then
    echo "Type: OPEN"
    IS_OPEN=1
else
    echo "Type: WPA/WPA2"
    IS_OPEN=0
fi
echo ""

echo "Step 1: Load WiFi modules (correct order)..."
sh "$TOOLKIT_DIR/wifi/load-modules.sh"
echo ""

echo "Step 2: Firmware check..."
sh "$TOOLKIT_DIR/wifi/check-firmware.sh" 2>&1 | grep -E "OK|MISSING|PROBLEM|NVS"
echo ""

echo "Step 3: Cleanup old processes..."
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

echo "Step 4: Interface reset..."
ifconfig wlan0 down 2>/dev/null
sleep 2
ifconfig wlan0 up 2>/dev/null
sleep 2

echo "Step 5: rfkill unblock (if needed)..."
for r in /sys/class/rfkill/rfkill*; do
    if [ -f "$r/soft" ]; then
        echo 0 > "$r/soft" 2>/dev/null
        echo 0 > "$r/hard" 2>/dev/null
    fi
done
echo "rfkill: unblocked"
echo ""

echo "Step 6: wpa_supplicant config..."

if [ "$IS_OPEN" = "1" ]; then
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n    scan_ssid=1\n}\n' "$SSID" > /tmp/wpa_supplicant.conf
    echo "Config: OPEN network"
else
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n\nnetwork={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n    proto=RSN WPA\n    pairwise=CCMP TKIP\n    group=CCMP TKIP\n    scan_ssid=1\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa_supplicant.conf
    echo "Config: WPA-PSK"
fi

echo ""
echo "Step 7: start wpa_supplicant WITHOUT -D flag..."
# v59 wl12xx backport (ol_R5.SP4.01) does NOT support nl80211 ioctls:
# "ioctl[SIOCSIWMODE]: Operation not supported" etc. Default driver (wext) works.
# Try default first, only then -D wext as fallback.
wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf 2>&1
sleep 3

if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "wpa_supplicant RUNNING (default/wext)"
else
    echo "default failed, trying -D wext..."
    wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf -D wext 2>&1
    sleep 3
    if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
        echo "wpa_supplicant RUNNING (wext)"
    else
        echo "ERROR: wpa_supplicant did not start"
        exit 1
    fi
fi

echo ""
echo "Step 8: Waiting for WiFi connection (max 15 sec)..."
i=0
while [ $i -lt 15 ]; do
    sleep 1
    STATUS=$(wpactrl status 2>/dev/null | grep "wpa_state" | cut -d= -f2)
    if [ "$STATUS" = "COMPLETED" ]; then
        echo ""
        echo "WiFi CONNECTED (wpa_state=COMPLETED)"
        wpactrl status 2>/dev/null | grep -E "ssid|bssid|ip_address"
        break
    fi
    echo -n "."
    i=$((i + 1))
done
echo ""

echo "Step 9: Request DHCP (udhcpc)..."
# v74: udhcpc is busybox symlink
udhcpc -i wlan0 -n -q -t 10 -T 3 2>&1
DHCP_EXIT=$?
echo ""

echo "Step 10: Firewall open..."
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
# SECURITY (review 2026-10-30): NO default ACCEPT anymore
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
echo "Firewall: OK"
echo ""

echo "========================================"
echo " Result"
echo "========================================"
echo ""
ifconfig wlan0
echo ""
wifi_status wlan0 || true   # v4.7.2 M1: wifi-compat ipv iwconfig
wifi_deadlock_check || true  # M1b
echo ""

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "SUCCESS: IP = $IP"
    echo ""
    echo "Test internet:"
    ping -c 2 -W 3 8.8.8.8 2>/dev/null && echo "Internet OK" || echo "Ping failed"
    echo ""
    echo "SSH available: ssh root@$IP"
else
    echo "FAILED: No IP (DHCP exit: $DHCP_EXIT)"
    echo ""
    echo "--- Debug info ---"
    echo "wifi_status (compat):"
    wifi_status wlan0 || true
    wifi_deadlock_check || true  # M1b
    echo ""
    echo "wpa_cli status:"
    wpactrl status 2>/dev/null
    echo ""
    echo "Scan results:"
    wpactrl scan_results 2>/dev/null | head -10
    echo ""
    echo "dmesg WiFi:"
    dmesg 2>/dev/null | grep -i wlan | tail -10
fi
