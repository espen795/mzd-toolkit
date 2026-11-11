#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Deep WiFi Scan
# If wpa_cli scan_results is empty, try this

echo "========================================"
echo " Deep WiFi Scan"
echo "========================================"
echo ""

echo "Problem: wpa_cli scan_results is EMPTY"
echo "Possible causes:"
echo "  1. AP sends no beacons (hidden SSID)"
echo "  2. 5GHz only hotspot (MZD is 2.4GHz only)"
echo "  3. wpa_supplicant scan not working properly"
echo "  4. rfkill block"
echo ""

echo "--- 1. Check rfkill ---"
for r in /sys/class/rfkill/rfkill*; do
    if [ -d "$r" ]; then
        echo "$(basename $r): name=$(cat $r/name 2>/dev/null) soft=$(cat $r/soft 2>/dev/null) hard=$(cat $r/hard 2>/dev/null)"
    fi
done
echo ""
# Try soft unblock (hard is hardware, cannot be done in software)
for r in /sys/class/rfkill/rfkill*/soft; do
    echo 0 > "$r" 2>/dev/null && echo "Unblocked: $r"
done
echo ""

echo "--- 2. Check wlan0 state ---"
echo "operstate: $(cat /sys/class/net/wlan0/operstate 2>/dev/null)"
echo "carrier: $(cat /sys/class/net/wlan0/carrier 2>/dev/null)"
echo "flags: $(cat /sys/class/net/wlan0/flags 2>/dev/null)"
echo ""

echo "--- 3. Force scan met wpa_cli ---"
wpactrl scan 2>&1
sleep 2
echo "Scan started, waiting..."
sleep 5
wpactrl scan_results 2>/dev/null
echo ""

echo "--- 4. Try scan on different channels ---"
# wl12xx supports 2.4GHz channels 1-14
for ch in 1 6 11; do
    echo "Scan channel $ch..."
    wpactrl scan freq=2412 2>/dev/null  # channel 1
    sleep 1
done
sleep 3
wpactrl scan_results 2>/dev/null
echo ""

echo "--- 5. Check dmesg for scan errors ---"
dmesg 2>/dev/null | grep -i -E "scan|wlan|wl12xx" | tail -20
echo ""

echo "--- 6. Try manual connect (without scan) ---"
echo "If we know the SSID, we can connect directly:"
echo "  wpactrl add_network"
echo "  wpactrl set_network 0 ssid '\"YOUR_HOTSPOT_SSID\"'"
echo "  wpactrl set_network 0 key_mgmt NONE"
echo "  wpactrl enable_network 0"
echo "  wpactrl select_network 0"
echo ""
echo "--- 7. Do this automatically now ---"
wpactrl remove_network all 2>/dev/null
NETID=$(wpactrl add_network 2>/dev/null | tail -1)
echo "Network ID: $NETID"
wpactrl set_network "$NETID" ssid '"YOUR_HOTSPOT_SSID"' 2>&1
wpactrl set_network "$NETID" key_mgmt NONE 2>&1
wpactrl set_network "$NETID" scan_ssid 1 2>&1
wpactrl enable_network "$NETID" 2>&1
wpactrl select_network "$NETID" 2>&1

echo ""
echo "Waiting for connection (15 sec)..."
i=0
while [ $i -lt 15 ]; do
    check_stop 2>/dev/null && { echo "Stopped"; break; }
    sleep 1
    STATE=$(wpactrl status 2>/dev/null | grep "wpa_state" | cut -d= -f2)
    echo -n "[$STATE]"
    if [ "$STATE" = "COMPLETED" ]; then
        echo ""
        echo "CONNECTED!"
        break
    fi
    i=$((i + 1))
done
echo ""

echo "--- Final status ---"
wpactrl status 2>/dev/null
echo ""

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -z "$IP" ]; then
    echo "No IP - DHCP..."
    udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
fi
echo "IP: ${IP:-NONE}"
