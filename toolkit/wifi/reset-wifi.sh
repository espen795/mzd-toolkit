#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Reset (hard)
# Restarts WiFi completely - use when everything is stuck

echo "========================================"
echo " WiFi HARD Reset"
echo "========================================"
echo ""
echo "WARNING: this resets ALL WiFi settings!"
echo ""

echo "Step 1: Stop EVERYTHING..."
# v4.7.5: NEVER killall wpa_supplicant — NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill our own instance if it is NOT from NMS — check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - do NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
killall udhcpc 2>/dev/null
killall dhclient 2>/dev/null
sleep 2

echo "Step 2: Interface down..."
ifconfig wlan0 down 2>/dev/null
sleep 2

echo "Step 3: Reload driver (if possible)..."
# Try to reload bcmdhd driver (Broadcom chip in Mazda)
rmmod bcmdhd 2>/dev/null && echo "bcmdhd removed" || echo "bcmdhd not loaded or cannot remove"
sleep 1
modprobe bcmdhd 2>/dev/null && echo "bcmdhd loaded" || echo "bcmdhd cannot be loaded"
sleep 2

echo "Step 4: Interface up..."
ifconfig wlan0 up 2>/dev/null
sleep 2

echo "Step 5: Check interface (wifi-compat, NO iwconfig on MZD)..."
ifconfig wlan0 2>/dev/null || echo "wlan0 not available!"
echo ""
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b
echo ""

echo "Step 6: Run Mazda stage_wifi.sh..."
if [ -f /jci/scripts/stage_wifi.sh ]; then
    echo "stage_wifi.sh found, running..."
    sh /jci/scripts/stage_wifi.sh 2>&1
    sleep 5
else
    echo "stage_wifi.sh NOT found"
fi

echo ""
echo "Step 7: Check after reset (wifi-compat)..."
ifconfig wlan0 2>/dev/null
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b
echo ""

echo "Step 8: Restore original Mazda WiFi config?"
if [ -f /etc/wpa_supplicant.conf ]; then
    echo "Original config found: /etc/wpa_supplicant.conf"
    echo "Contents:"
    # SECURITY (review M2): filter psk
    grep -v 'psk=' /etc/wpa_supplicant.conf
    echo ""
    echo "Use this one? (y/n)"
    echo -n "Choice: "
    read use_orig
    if [ "$use_orig" = "y" ] || [ "$use_orig" = "Y" ] || [ "$use_orig" = "yes" ] || [ "$use_orig" = "YES" ] || [ "$use_orig" = "j" ] || [ "$use_orig" = "J" ] || [ "$use_orig" = "ja" ] || [ "$use_orig" = "JA" ]; then
        cp /etc/wpa_supplicant.conf /tmp/wpa_supplicant.conf
        wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf 2>&1
        sleep 3
        udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
    fi
else
    echo "No original config found"
fi

echo ""
echo "========================================"
echo " Reset complete"
echo "========================================"
echo ""
echo "Next step: connect to WiFi:"
echo "  sh ${TOOLKIT_DIR}/wifi/connect.sh"
