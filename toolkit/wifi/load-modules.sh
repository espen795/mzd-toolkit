#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Load WiFi Kernel Modules
# Loads TI WL1271/WL1283 WiFi modules in CORRECT order
# Based on firmware v74 analysis

echo "========================================"
echo " WiFi Module Loader (TI WL1271)"
echo "========================================"
echo ""

echo "WiFi Chip: Texas Instruments WL1271/WL1283 (SDIO)"
echo ""

echo "--- Currently loaded modules ---"
cat /proc/modules 2>/dev/null | grep -E "rfkill|compat|cfg80211|mac80211|wl12xx|wlcore|ti" || echo "No WiFi modules loaded"
echo ""

# Module load order (BELANGRIJK!)
MODULES="rfkill compat cfg80211 mac80211 wlcore wl12xx wl12xx_sdio"

echo "--- Module load order ---"
echo "$MODULES" | tr " " "\n" | nl
echo ""

echo "--- Loading modules ---"
for mod in $MODULES; do
    echo -n "Load $mod... "
    if modprobe "$mod" 2>/dev/null; then
        echo "OK"
    else
        # Check if already loaded
        if grep -q "^$mod " /proc/modules 2>/dev/null; then
            echo "ALREADY LOADED"
        else
            echo "FAILED (may be normal if built-in)"
        fi
    fi
    sleep 0.5
done

echo ""
echo "--- Check resultaat ---"
echo "Loaded WiFi modules:"
cat /proc/modules 2>/dev/null | grep -E "rfkill|compat|cfg80211|mac80211|wl12xx|wlcore"
echo ""

echo "--- Check wlan0 interface ---"
if ifconfig wlan0 > /dev/null 2>&1; then
    echo "wlan0 AVAILABLE"
    ifconfig wlan0 | head -3
else
    echo "wlan0 NOT AVAILABLE - trying interface up..."
    ifconfig wlan0 up 2>&1
    sleep 2
    ifconfig wlan0 2>&1 | head -3
fi

echo ""
echo "--- Check rfkill status ---"
if [ -d /sys/class/rfkill ]; then
    for r in /sys/class/rfkill/rfkill*; do
        if [ -f "$r/name" ] && [ -f "$r/soft" ]; then
            name=$(cat "$r/name" 2>/dev/null)
            soft=$(cat "$r/soft" 2>/dev/null)
            hard=$(cat "$r/hard" 2>/dev/null)
            echo "rfkill $name: soft=$soft hard=$hard"
            if [ "$soft" = "1" ] || [ "$hard" = "1" ]; then
                echo "  -> WiFi is BLOCKED! Unblock with:"
                echo "     echo 0 > $r/soft"
            fi
        fi
    done
else
    echo "No rfkill devices"
fi

echo ""
echo "========================================"
echo " Module loading complete"
echo "========================================"
