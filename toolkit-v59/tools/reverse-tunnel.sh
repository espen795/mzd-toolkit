#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Reverse SSH Tunnel
# Creates a reverse tunnel to a server (for remote access without port forwarding)

echo "========================================"
echo " Reverse SSH Tunnel"
echo "========================================"
echo ""
echo "This creates a reverse tunnel to a server."
echo "You can then log in to the Mazda from the server."
echo ""

# Config
echo "Server settings:"
echo -n "Server IP/host: "
read SERVER
echo -n "Server SSH port (default 22): "
read SPORT
SPORT=${SPORT:-22}
echo -n "Server user: "
read SUSER
echo -n "Remote port on server (e.g. 2222): "
read RPORT

echo ""
echo "Configuration:"
echo "  Server: $SUSER@$SERVER:$SPORT"
echo "  Remote port: $RPORT"
echo "  Local port: 22 (SSH)"
echo ""
echo "Connect from server with:"
echo "  ssh -p $RPORT root@localhost"
echo ""
echo -n "Continue? (y/n): "
read confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && [ "$confirm" != "yes" ] && [ "$confirm" != "YES" ] && [ "$confirm" != "j" ] && [ "$confirm" != "J" ] && [ "$confirm" != "ja" ] && [ "$confirm" != "JA" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "--- Check WiFi ---"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -z "$IP" ]; then
    echo "ERROR: No WiFi connection!"
    exit 1
fi
echo "WiFi IP: $IP"
echo ""

echo "--- Check SSH ---"
if ! ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
    echo "SSH not running - starting..."
    sh ${TOOLKIT_DIR}/ssh/start.sh
    sleep 2
fi
echo ""

echo "--- Start reverse tunnel ---"
echo "ssh -R $RPORT:localhost:36000 $SUSER@$SERVER -p $SPORT -N -f"
echo ""
echo "Note: You need SSH keys or a password on the server."
echo ""
echo "Test tunnel:"
ssh -R $RPORT:localhost:36000 $SUSER@$SERVER -p $SPORT -N -f 2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "Tunnel active!"
    echo ""
    echo "Connect from server with:"
    echo "  ssh -p $RPORT root@localhost"
    echo ""
    echo "Stop tunnel:"
    echo "  killall ssh"
else
    echo ""
    echo "Starting tunnel failed."
    echo "Check:"
    echo "  - WiFi connection"
    echo "  - Server reachable (ping $SERVER)"
    echo "  - SSH credentials correct"
    echo "  - Port $RPORT free on server"
fi
