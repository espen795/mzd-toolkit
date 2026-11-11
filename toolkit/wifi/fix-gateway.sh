#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Fix Gateway Ping
# WiFi is connected (got IP) but ping to gateway fails
# Possible causes: firewall on AP, wrong route, ARP problem

echo "========================================"
echo " Gateway Ping Fix"
echo "========================================"
echo ""

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
MASK=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*Mask://" | sed "s/ .*//")

echo "IP: $IP"
echo "Gateway: $GW"
echo "Netmask: $MASK"
echo ""

echo "--- Step 1: Check ARP table ---"
cat /proc/net/arp 2>/dev/null
echo ""

echo "--- Step 2: Ping gateway (3x) ---"
if [ -n "$GW" ]; then
    ping -c 3 -W 3 "$GW" 2>&1
fi
echo ""

echo "--- Step 3: Ping broadcast ---"
if [ -n "$IP" ] && [ -n "$MASK" ]; then
    # Calculate broadcast (simple: x.x.x.255 for /24)
    BCAST=$(echo "$IP" | sed "s/\.[0-9]*$/.255/")
    echo "Broadcast: $BCAST"
    ping -c 2 -W 2 -b "$BCAST" 2>&1
fi
echo ""

echo "--- Step 4: Check wpa_cli status ---"
wpactrl status 2>/dev/null
echo ""

echo "--- Step 5: Force DHCP renew ---"
killall udhcpc 2>/dev/null
sleep 1
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1
echo ""
ifconfig wlan0 2>/dev/null | head -4
echo ""

echo "--- Step 6: Check default route ---"
route -n 2>/dev/null
echo ""
echo "If no default route: add:"
echo "  route add default gw $GW wlan0"
if [ -n "$GW" ]; then
    route add default gw "$GW" wlan0 2>&1
    route -n 2>/dev/null
fi
echo ""

echo "--- Step 7: Ping gateway again ---"
if [ -n "$GW" ]; then
    ping -c 3 -W 3 "$GW" 2>&1
fi
echo ""

echo "--- Step 8: Ping 8.8.8.8 (internet) ---"
ping -c 2 -W 5 8.8.8.8 2>&1
echo ""

echo "--- Step 9: Check firewall (local) ---"
iptables -L -n 2>/dev/null | head -10
echo ""

echo "--- Step 10: Check wlan0 stats ---"
echo "RX packets: $(cat /sys/class/net/wlan0/statistics/rx_packets 2>/dev/null)"
echo "TX packets: $(cat /sys/class/net/wlan0/statistics/tx_packets 2>/dev/null)"
echo "RX errors: $(cat /sys/class/net/wlan0/statistics/rx_errors 2>/dev/null)"
echo "TX errors: $(cat /sys/class/net/wlan0/statistics/tx_errors 2>/dev/null)"
echo ""

echo "========================================"
echo " Analysis complete"
echo "========================================"
echo ""
echo "If ping to gateway still fails:"
echo "  - Check whether phone hotspot internet sharing is on"
echo "  - Check whether firewall on phone blocks traffic"
echo "  - Try another WiFi network"
echo "  - Check wpa_cli status for 'DISCONNECTED' vs 'COMPLETED'"
