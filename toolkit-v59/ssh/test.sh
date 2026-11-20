#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - SSH Test
# Test SSH connection from the MZD itself

echo "========================================"
echo " SSH Connectie Test"
echo "========================================"
echo ""

# Check IP
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -z "$IP" ]; then
    echo "ERROR: No IP address. WiFi not connected."
    exit 1
fi

echo "Local IP: $IP"
echo ""

# Test localhost
echo "Test 1: Localhost connection..."
if nc -z 127.0.0.1 22 2>/dev/null || netstat -tln 2>/dev/null | grep "127.0.0.1:22" > /dev/null; then
    echo "  OK - Port 22 open on localhost"
else
    echo "  FAIL - Port 22 not open on localhost"
fi

# Test own IP
echo ""
echo "Test 2: Own IP connection ($IP)..."
if nc -z "$IP" 22 2>/dev/null || netstat -tln 2>/dev/null | grep "$IP:22" > /dev/null; then
    echo "  OK - Port 22 open on $IP"
else
    echo "  FAIL - Port 22 not open on $IP"
    echo "  Check: netstat -tln"
fi

# Test 0.0.0.0
echo ""
echo "Test 3: All interfaces (0.0.0.0)..."
if netstat -tln 2>/dev/null | grep "0.0.0.0:22" > /dev/null; then
    echo "  OK - SSH listening on all interfaces"
else
    echo "  WARNING - SSH may be listening only on a specific interface"
    netstat -tln 2>/dev/null | grep ":22"
fi

# Ping gateway
echo ""
echo "Test 4: Network connectivity..."
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print $2}')
if [ -n "$GW" ]; then
    echo "  Gateway: $GW"
    ping -c 2 -W 3 "$GW" 2>/dev/null && echo "  OK - Gateway reachable" || echo "  FAIL - Gateway not reachable"
fi

# Firewall check
echo ""
echo "Test 5: Firewall status..."
if iptables -L -n 2>/dev/null | grep -q "dpt:36000"; then
    echo "  OK - Firewall rule for port 22 present"
else
    echo "  WARNING - No firewall rule for port 22"
    echo "  Add: iptables -I INPUT -p tcp --dport 36000 -j ACCEPT"
fi

# Summary
echo ""
echo "========================================"
echo " Summary"
echo "========================================"
echo "IP Address:   $IP"
echo "SSH Server:   $(ps | grep sshd | grep -v grep > /dev/null && echo 'RUNNING' || echo 'STOPPED')"
echo "Port 36000:  $(netstat -tln 2>/dev/null | grep -q ':36000 ' && echo 'OPEN' || echo 'CLOSED')"
echo ""
echo "Connect from another device with (port 36000 is THE port):"
echo "  ssh -p 36000 cmu@$IP -i \$TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
echo "  or with password from config/secrets.conf (MZD_SSH_PASSWORD)"
