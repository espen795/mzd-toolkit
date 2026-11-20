#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Quick WiFi Test
# Quick test without long scripts - for rapid prototyping
# Use this to test quickly without swapping the USB stick

echo "========================================"
echo " Quick WiFi Test"
echo "========================================"
echo ""

echo "[1/6] Modules check..."
cat /proc/modules 2>/dev/null | grep -E "wl12xx|wlcore|cfg80211" && echo "  Modules OK" || echo "  Modules MISSING - loading..."
for mod in rfkill compat cfg80211 mac80211 wlcore wl12xx wl12xx_sdio; do
    modprobe $mod 2>/dev/null && echo "  $mod loaded" || true
done

echo ""
echo "[2/6] Firmware check..."
ls -la /lib/firmware/ti-connectivity/wl1271-nvs.bin 2>/dev/null && echo "  NVS OK" || echo "  NVS MISSES!"

echo ""
echo "[3/6] rfkill unblock..."
for r in /sys/class/rfkill/rfkill*/soft; do
    echo 0 > "$r" 2>/dev/null && echo "  unblocked"
done

echo ""
echo "[4/6] Interface up..."
ifconfig wlan0 down 2>/dev/null
sleep 1
ifconfig wlan0 up 2>/dev/null
sleep 2
ifconfig wlan0 | head -2

echo ""
echo "[5/6] wpa_supplicant..."
# v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - DO NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
sleep 1

# Read SSID from settings or ask
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
if [ -f "$TOOLKIT_DIR/config/settings.conf" ]; then
    . "$TOOLKIT_DIR/config/settings.conf"
fi
SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="***"

if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "***" ]; then
    printf 'ctrl_interface=/var/run/wpa_supplicant\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n}\n' "$SSID" > /tmp/wpa.conf
    echo "  Config: OPEN ($SSID)"
else
    printf 'ctrl_interface=/var/run/wpa_supplicant\nnetwork={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa.conf
    echo "  Config: WPA ($SSID)"
fi

# v59 wl12xx backport: nl80211 ioctls not supported -> default driver (wext)
wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf 2>&1
sleep 3
ps | grep wpa_supplicant | grep -v grep > /dev/null && echo "  wpa_supplicant RUNNING" || { echo "  default failed, trying wext..."; wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf -D wext 2>&1; sleep 2; ps | grep wpa_supplicant | grep -v grep > /dev/null && echo "  wpa_supplicant RUNNING (wext)" || echo "  wpa_supplicant FAILED"; }

echo ""
echo "[6/6] DHCP..."
killall udhcpc 2>/dev/null
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1

echo ""
echo "========================================"
echo " Resultaat"
echo "========================================"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "IP: ${IP:-NONE}"
echo ""
ifconfig wlan0 2>/dev/null | head -3
echo ""
wpactrl status 2>/dev/null | grep -E "wpa_state|ssid|bssid" || echo "wpa_cli status failed"
