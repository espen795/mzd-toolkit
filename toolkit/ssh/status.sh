#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - SSH Status

echo "========================================"
echo " SSH Status"
echo "========================================"
echo ""

echo "--- Processes ---"
ps | grep -E "sshd|dropbear" 2>/dev/null || echo "No SSH processes"

echo ""
echo "--- Ports ---"
netstat -tln 2>/dev/null | grep ":36000 " || echo "Port 36000 not open"

echo ""
echo "--- Firewall ---"
iptables -L -n 2>/dev/null | grep "22" || echo "No firewall rule for 22"

echo ""
echo "--- Config files ---"
ls -la /mnt/data_persist/dev/bin/sshd_config 2>/dev/null || echo "No config in data_persist"
ls -la /etc/ssh/ 2>/dev/null || echo "No /etc/ssh"

echo ""
echo "--- IP Address ---"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "IP: $IP"
    echo "SSH connect: ssh root@$IP"
else
    echo "No IP - WiFi not connected"
fi
