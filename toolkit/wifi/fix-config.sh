#!/bin/sh
# MZD Toolkit - Fix wpa_supplicant Config
# Restores config from backup or creates a new one

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run

echo "========================================"
echo " Fix wpa_supplicant Config"
echo "========================================"
echo ""

echo "--- Current config ---"
if [ -f /etc/wpa_supplicant.conf ]; then
    echo "/etc/wpa_supplicant.conf:"
    # SECURITY (review M2): filter out psk
    grep -v 'psk=' /etc/wpa_supplicant.conf
else
    echo "/etc/wpa_supplicant.conf does NOT exist"
fi
echo ""

echo "--- Backup config ---"
if [ -f /etc/wpa_supplicant.bak ]; then
    echo "/etc/wpa_supplicant.bak:"
    grep -v 'psk=' /etc/wpa_supplicant.bak
else
    echo "No backup found"
fi
echo ""

echo "--- Options ---"
echo "1. Restore from backup (.bak)"
echo "2. Create empty config (only ctrl_interface)"
echo "3. Create config for YOUR_HOTSPOT_SSID (open)"
echo "4. Cancel"
echo ""
echo -n "Choice: "
read choice

echo ""

case "$choice" in
    1)
        if [ -f /etc/wpa_supplicant.bak ]; then
            # Try /etc remount rw
            mount -o remount,rw /etc 2>/dev/null
            cp /etc/wpa_supplicant.bak /etc/wpa_supplicant.conf 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "Config restored from backup"
            else
                echo "Cannot write to /etc (read-only)"
                echo "Use /tmp config:"
                cp /etc/wpa_supplicant.bak /tmp/wpa_supplicant.conf
                echo "  -> /tmp/wpa_supplicant.conf"
            fi
        else
            echo "No backup found"
        fi
        ;;
    2)
        printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n' > /tmp/wpa_supplicant.conf
        echo "Empty config created: /tmp/wpa_supplicant.conf"
        ;;
    3)
        printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n\nnetwork={\n    ssid="YOUR_HOTSPOT_SSID"\n    key_mgmt=NONE\n    scan_ssid=1\n}\n' > /tmp/wpa_supplicant.conf
        echo "Config for YOUR_HOTSPOT_SSID (open): /tmp/wpa_supplicant.conf"
        ;;
    4)
        echo "Cancelled"
        exit 0
        ;;
    *)
        echo "Invalid choice"
        ;;
esac

echo ""
echo "--- New config ---"
# SECURITY (review M2): filter out psk + chmod 600
chmod 600 /tmp/wpa_supplicant.conf 2>/dev/null
grep -v 'psk=' /tmp/wpa_supplicant.conf 2>/dev/null
echo ""
echo "Restart wpa_supplicant? (y/n)"
echo -n "Choice: "
read restart
if [ "$restart" = "y" ] || [ "$restart" = "Y" ] || [ "$restart" = "yes" ] || [ "$restart" = "YES" ] || [ "$restart" = "j" ] || [ "$restart" = "J" ] || [ "$restart" = "ja" ] || [ "$restart" = "JA" ]; then
    # v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - DO NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
    sleep 1
    # v59 wl12xx: NO nl80211 ioctls -> start default (wext)
    wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf 2>&1
    sleep 3
    udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
    ifconfig wlan0 | head -3
fi
