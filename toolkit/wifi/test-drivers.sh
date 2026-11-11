#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Test wpa_supplicant Drivers
# Quickly test which driver works (for rapid prototyping)

echo "========================================"
echo " Test wpa_supplicant Drivers"
echo "========================================"
echo ""

SSID="YOUR_HOTSPOT_SSID"
# Read from settings if available
if [ -f ${TOOLKIT_DIR}/config/settings.conf ]; then
    . ${TOOLKIT_DIR}/config/settings.conf
    SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
fi

echo "Network: $SSID (open)"
echo ""

# Config for open network
printf 'ctrl_interface=/var/run/wpa_supplicant\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n}\n' "$SSID" > /tmp/wpa_test.conf

DRIVERS="nl80211 wext wired none"

for drv in $DRIVERS; do
    echo "--- Test driver: $drv ---"
    # v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - DO NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
    sleep 1
    
    if [ "$drv" = "none" ]; then
        wpa_supplicant -B -i wlan0 -c /tmp/wpa_test.conf 2>&1
    else
        wpa_supplicant -B -i wlan0 -c /tmp/wpa_test.conf -D "$drv" 2>&1
    fi
    
    sleep 2
    
    if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
        echo "  wpa_supplicant RUNNING with $drv"
        
        # Check status
        sleep 3
        STATUS=$(wpactrl status 2>/dev/null | grep "wpa_state" | cut -d= -f2)
        echo "  Status: $STATUS"
        
        if [ "$STATUS" = "COMPLETED" ]; then
            echo "  >>> $drv WORKS! <<<"
            wpactrl status 2>/dev/null | grep -E "ssid|bssid"
            echo ""
            echo "Use: wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf -D $drv"
            exit 0
        fi
    else
        echo "  wpa_supplicant did NOT start with $drv"
    fi
    echo ""
done

echo "No driver worked fully. Try connect-v74.sh"
