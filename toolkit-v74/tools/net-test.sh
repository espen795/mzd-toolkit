#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Network Test Suite
# Complete network test suite

echo "========================================"
echo " MZD Network Test Suite"
echo "========================================"
echo ""

TEST_HOST="8.8.8.8"
TEST_DNS="google.com"

echo "Test 1: Interface status"
ifconfig wlan0 2>/dev/null | head -3
echo ""

echo "Test 2: IP address check"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "  IP: $IP - OK"
else
    echo "  IP: NONE - WiFi not connected"
fi
echo ""

echo "Test 3: Gateway ping"
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
if [ -n "$GW" ]; then
    echo "  Gateway: $GW"
    ping -c 3 -W 3 "$GW" 2>/dev/null && echo "  OK" || echo "  FAILED"
else
    echo "  No gateway - FAILED"
fi
echo ""

echo "Test 4: DNS resolve"
if nslookup "$TEST_DNS" 2>/dev/null | grep -q "Address"; then
    echo "  DNS resolve $TEST_DNS - OK"
else
    echo "  DNS resolve - FAILED (or nslookup not available)"
    # Try gethostbyname via /etc/hosts
    grep "$TEST_DNS" /etc/hosts 2>/dev/null && echo "  In /etc/hosts" || echo "  Not in /etc/hosts"
fi
echo ""

echo "Test 5: Internet ping (8.8.8.8)"
ping -c 3 -W 5 "$TEST_HOST" 2>/dev/null && echo "  OK" || echo "  FAILED"
echo ""

echo "Test 6: Internet ping (google.com)"
ping -c 3 -W 5 "$TEST_DNS" 2>/dev/null && echo "  OK" || echo "  FAILED"
echo ""

echo "Test 7: Port 22 (SSH) local"
if netstat -tln 2>/dev/null | grep -q ":36000 "; then
    echo "  Port 22 OPEN - OK"
else
    echo "  Port 22 CLOSED - SSH not running"
fi
echo ""

echo "Test 8: Port 22 from outside (from gateway)"
if [ -n "$GW" ]; then
    # This only works if we have a tool that can talk back
    echo "  Cannot test from the MZD itself"
    echo "  Test from another device: nc -zv $IP 22"
fi
echo ""

echo "Test 9: Firewall check"
if iptables -L -n 2>/dev/null | grep -q "Chain INPUT"; then
    DROP_COUNT=$(iptables -L INPUT -n 2>/dev/null | grep -c "DROP")
    REJECT_COUNT=$(iptables -L INPUT -n 2>/dev/null | grep -c "REJECT")
    echo "  DROP rules: $DROP_COUNT, REJECT rules: $REJECT_COUNT"
    if [ "$DROP_COUNT" -gt 0 ] || [ "$REJECT_COUNT" -gt 0 ]; then
        echo "  WARNING: Firewall may be blocking traffic"
    else
        echo "  Firewall looks OK"
    fi
else
    echo "  iptables not available"
fi
echo ""

echo "Test 10: ARP table (who is on the network)"
cat /proc/net/arp 2>/dev/null || arp -a 2>/dev/null
echo ""

echo "========================================"
echo " Test Suite complete"
echo "========================================"
