#!/bin/sh
# MZD Toolkit - Fix SSH Port
# Mazda sshd runs on port 36000 (not 22!)
# This script starts sshd on port 22 AND 36000

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

echo "========================================"
echo " SSH Port Fix (22 + 36000)"
echo "========================================"
echo ""
echo "Mazda sshd_config has: Port 36000"
echo "We also start sshd on port 22"
echo ""

# Check current sshd
if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
    echo "sshd already running. Ports:"
    netstat -tln 2>/dev/null | grep sshd
    echo ""
fi

echo "--- Start sshd on port 36000 (THE port (design decision) ---"
# Create config for port 36000
mkdir -p /tmp/ssh22
cat > /tmp/ssh22/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
# SECURITY (review 2026-10-30): root login only via key
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/ssh22/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
PidFile /tmp/ssh22/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
EOF

echo "Config: /tmp/ssh22/sshd_config"
echo "HostKey: /etc/ssh/ssh_host_rsa_key (existing)"
echo ""

# Start sshd on port 36000
/usr/sbin/sshd -f /tmp/ssh22/sshd_config 2>&1
sleep 2

echo ""
echo "--- Check port ---"
netstat -tln 2>/dev/null | grep -E ":36000"
echo ""

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "========================================"
    echo " SSH now reachable on (port 36000 is THE port (design decision):"
    echo "   ssh -p 36000 cmu@$IP -i $TOOLKIT_DIR/ssh/id_mzd"
    echo "========================================"
else
    echo "No IP - WiFi not connected"
fi

echo ""
echo "--- Firewall (port 36000 only) ---"
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
iptables -L -n 2>/dev/null | grep -E "36000"
