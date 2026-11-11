#!/bin/sh
# MZD Toolkit - eth0-dhcp.sh (v4.8.26)
# Sets eth0 (internal CMU ethernet to the car switch) to DHCP.
# Normally /jci/scripts/start_network.sh already does this at boot.
# Useful if eth0 is down or has no IP.
#
# Use on CMU:
#   sh /data_persist/mzd-toolkit/net/eth0-dhcp.sh

# Wait for eth0
_i=0
while [ $_i -lt 10 ] && [ ! -d "/sys/class/net/eth0" ]; do
    sleep 1; _i=$((_i+1))
done
[ ! -d "/sys/class/net/eth0" ] && { echo "ERROR: eth0 not present"; exit 1; }

ifconfig eth0 0.0.0.0 up 2>/dev/null
if command -v udhcpc >/dev/null 2>&1; then
    echo "udhcpc on eth0..."
    udhcpc -i eth0 -f -q -n 2>&1 &
    sleep 3
elif [ -x /jci/scripts/start_network.sh ]; then
    sh /jci/scripts/start_network.sh 2>&1
    sleep 3
fi
IP=$(ifconfig eth0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "eth0 IP: ${IP:-NONE}"
ifconfig eth0 2>/dev/null | grep -E "inet addr|UP"
route -n 2>/dev/null | grep eth0
