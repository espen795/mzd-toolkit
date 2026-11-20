#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Network Diagnose
# Complete network diagnose

OUT="/tmp/mzd-network-diag.txt"
echo "MZD Network Diagnose - $(date)" > "$OUT"
echo "========================================" >> "$OUT"
echo "" >> "$OUT"

echo "Collecting network info..."

echo "--- ifconfig (alle interfaces) ---" >> "$OUT"
ifconfig -a >> "$OUT" 2>&1
echo "" >> "$OUT"

# v4.7.2 M1: iwconfig does NOT exist on MZD - wifi_status via wifi-compat.sh
echo "--- wifi_status (wpactrl + /sys + ifconfig; NO iwconfig) ---" >> "$OUT"
wifi_status wlan0 >> "$OUT" 2>&1 || echo "wifi_status: not connected" >> "$OUT"
echo "" >> "$OUT"
echo "--- wl12xx deadlock check (M1b) ---" >> "$OUT"
wifi_deadlock_check >> "$OUT" 2>&1 || true
echo "" >> "$OUT"

echo "--- route -n ---" >> "$OUT"
route -n >> "$OUT" 2>&1 || cat /proc/net/route >> "$OUT"
echo "" >> "$OUT"

echo "--- /proc/net/route ---" >> "$OUT"
cat /proc/net/route >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/net/arp ---" >> "$OUT"
cat /proc/net/arp >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/net/wireless ---" >> "$OUT"
cat /proc/net/wireless >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/net/tcp ---" >> "$OUT"
cat /proc/net/tcp >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /proc/net/udp ---" >> "$OUT"
cat /proc/net/udp >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- netstat -tln ---" >> "$OUT"
netstat -tln >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- netstat -tlnp ---" >> "$OUT"
netstat -tlnp >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- netstat -rn ---" >> "$OUT"
netstat -rn >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /etc/resolv.conf ---" >> "$OUT"
cat /etc/resolv.conf >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /etc/hosts ---" >> "$OUT"
cat /etc/hosts >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /etc/network/interfaces ---" >> "$OUT"
cat /etc/network/interfaces >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- /etc/wpa_supplicant.conf ---" >> "$OUT"
cat /etc/wpa_supplicant.conf >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- iptables -L -n ---" >> "$OUT"
iptables -L -n >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- iptables -L -n -v ---" >> "$OUT"
iptables -L -n -v >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- iptables -t nat -L -n ---" >> "$OUT"
iptables -t nat -L -n >> "$OUT" 2>&1
echo "" >> "$OUT"

echo "--- Ping tests ---" >> "$OUT"
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
echo "Gateway: $GW" >> "$OUT"
ping -c 4 -W 5 "$GW" >> "$OUT" 2>&1 || echo "Gateway ping failed" >> "$OUT"
echo "" >> "$OUT"

# DNS test
echo "DNS test (8.8.8.8)..." >> "$OUT"
ping -c 2 -W 5 8.8.8.8 >> "$OUT" 2>&1 || echo "DNS ping failed" >> "$OUT"

echo ""
echo "Network diagnose complete!"
echo "Output: $OUT"
cat "$OUT"

# Copy to USB
if [ -d ${TOOLKIT_DIR}/logs ]; then
    cp "$OUT" ${TOOLKIT_DIR}/logs/network-diag-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null
    echo ""
    echo "Copied to USB: logs/network-diag-*.txt"
fi
