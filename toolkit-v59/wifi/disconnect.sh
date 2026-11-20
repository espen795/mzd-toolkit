#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - WiFi Disconnect

echo "========================================"
echo " WiFi Uitschakelen"
echo "========================================"
echo ""

echo "stopping wpa_supplicant..."
# v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - do NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
sleep 1

echo "stopping udhcpc..."
killall udhcpc 2>/dev/null
sleep 1

echo "Interface down..."
ifconfig wlan0 down 2>/dev/null
sleep 1

echo ""
echo "WiFi is disabled."
ifconfig wlan0 2>/dev/null || echo "(interface down)"
