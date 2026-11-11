#!/bin/sh
# MZD Toolkit - WiFi Diagnostics
# Checks everything about WiFi status

# Source shared library (with fallback) - for log_to_usb
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run

echo "========================================"
echo " WiFi Complete Diagnose"
echo "========================================"
echo ""

echo "=== 1. Interface Status ==="
ifconfig wlan0 2>/dev/null || echo "wlan0 NOT AVAILABLE"
echo ""

echo "=== 2. Wireless Status (wifi-compat, NO iwconfig) ==="
wifi_status wlan0 || true
wifi_deadlock_check || true  # M1b
echo ""

echo "=== 3. Processes ==="
echo "--- wpa_supplicant ---"
ps | grep wpa_supplicant | grep -v grep || echo "NOT running"
echo "--- udhcpc ---"
ps | grep udhcpc | grep -v grep || echo "NOT running"
echo ""

echo "=== 4. Config Files ==="
echo "--- /tmp/wpa_supplicant.conf ---"
# SECURITY (review M2): psk filteren
grep -v 'psk=' /tmp/wpa_supplicant.conf 2>/dev/null || echo "does not exist"
echo ""
echo "--- /tmp/wpa.conf ---"
grep -v 'psk=' /tmp/wpa.conf 2>/dev/null || echo "does not exist"
echo ""
echo "--- /etc/wpa_supplicant.conf ---"
grep -v 'psk=' /etc/wpa_supplicant.conf 2>/dev/null || echo "does not exist"
echo ""

echo "=== 5. wpa_cli status (if available) ==="
wpactrl status 2>/dev/null || echo "wpa_cli not working"
echo ""

echo "=== 6. wpa_cli scan (if wpa_supplicant is running) ==="
if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    wpactrl scan 2>/dev/null
    sleep 3
    wpactrl scan_results 2>/dev/null || echo "No scan results"
else
    echo "wpa_supplicant not running - start connect.sh first"
fi
echo ""

echo "=== 7. IP Configuration ==="
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "IP address: ${IP:-NONE}"
echo ""
echo "Route table:"
route -n 2>/dev/null || cat /proc/net/route
echo ""

echo "=== 8. Kernel Messages (WiFi) ==="
dmesg 2>/dev/null | grep -i -E "wlan|wifi|sdio|bcmdhd|firmware" | tail -20
echo ""

echo "=== 9. Firmware/Driver Info ==="
echo "--- Modules ---"
cat /proc/modules 2>/dev/null | grep -i -E "wlan|wifi|bcmdhd|80211" || echo "No WiFi modules found"
echo ""
echo "--- Firmware files ---"
ls -la /lib/firmware/ 2>/dev/null | head -20
ls -la /lib/firmware/brcm/ 2>/dev/null || echo "No brcm firmware dir"
echo ""

echo "=== 10. Mazda Specific ==="
echo "--- stage_wifi.sh ---"
ls -la /jci/scripts/stage_wifi.sh 2>/dev/null && head -30 /jci/scripts/stage_wifi.sh || echo "Not found"
echo ""
echo "--- /jci/scripts/ WiFi related ---"
ls /jci/scripts/ 2>/dev/null | grep -i -E "wifi|wlan|net|wpa" || echo "No WiFi scripts"
echo ""

echo "========================================"
echo " Diagnostics complete"
echo "========================================"
