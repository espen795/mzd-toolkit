#!/bin/sh
# MZD Toolkit - eth1-dhcp.sh (v4.8.26)
# Set eth1 to DHCP (instead of static 192.168.0.2).
# Requires: DHCP server on the other end of the cable (laptop/router).
# On the CMU: /jci/scripts/start_eth1_dhcp.sh already does this at boot,
# but if eth1 is unregister'd (USB dongle out/in) you must do this manually.
#
# Usage on CMU:
#   sh /data_persist/mzd-toolkit/net/eth1-dhcp.sh          -> DHCP on eth1
#   sh /data_persist/mzd-toolkit/net/eth1-dhcp.sh static   -> back to 192.168.0.2

MODE="${1:-dhcp}"

# Wait for eth1 (max 15s)
_i=0
while [ $_i -lt 15 ] && [ ! -d "/sys/class/net/eth1" ]; do
    sleep 1; _i=$((_i+1))
done
if [ ! -d "/sys/class/net/eth1" ]; then
    echo "ERROR: eth1 not present after 15s - check USB dongle"
    exit 1
fi

if [ "$MODE" = "static" ]; then
    ifconfig eth1 192.168.0.2 netmask 255.255.255.0 up 2>&1
    echo "eth1 static: 192.168.0.2"
else
    # DHCP: use udhcpc (busybox) or the JCI script
    ifconfig eth1 0.0.0.0 up 2>/dev/null
    if command -v udhcpc >/dev/null 2>&1; then
        echo "starting udhcpc on eth1..."
        udhcpc -i eth1 -f -q -n 2>&1 &
        sleep 3
    elif [ -x /jci/scripts/start_eth1_dhcp.sh ]; then
        sh /jci/scripts/start_eth1_dhcp.sh 2>&1
        sleep 3
    else
        echo "ERROR: no udhcpc and no start_eth1_dhcp.sh"
        exit 1
    fi
    IP=$(ifconfig eth1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "eth1 DHCP IP: ${IP:-NONE}"
    if [ -z "$IP" ]; then
        echo "ERROR: no DHCP lease - is there a DHCP server on the other end?"
        exit 1
    fi
fi

echo "eth1 status:"
ifconfig eth1 2>/dev/null | grep -E "inet addr|HWaddr|UP"
route -n 2>/dev/null | grep eth1
