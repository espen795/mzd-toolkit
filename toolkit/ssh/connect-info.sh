#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - SSH Connect Info
# Shows how to connect from outside

echo "========================================"
echo " SSH Connection Info"
echo "========================================"
echo ""

IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "MZD IP address: ${IP:-NOT CONNECTED}"
echo ""

echo "--- sshd processes ---"
ps 2>/dev/null | grep sshd | grep -v grep
echo ""

echo "--- Open ports ---"
netstat -tln 2>/dev/null | grep -E ":36000"
echo ""

echo "--- Firewall ---"
iptables -L -n 2>/dev/null | grep -E "22|36000|ACCEPT" | head -5
echo ""

echo "========================================"
if [ -n "$IP" ]; then
    echo " CONNECT FROM PHONE/PC (port 36000 is THE port (design decision):"
    echo "========================================"
    echo ""
    echo "  v59 sshd offers ONLY ssh-rsa + ssh-dss host keys (2016 build)."
    echo "  Modern OpenSSH client refuses ssh-rsa/ssh-dss by default!"
    echo ""
    if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
        echo "  ssh -p 36000 cmu@$IP     (password from config/secrets.conf)"
    else
        echo "  ssh -p 36000 cmu@$IP -i $TOOLKIT_DIR/ssh/id_mzd     (pubkey)"
    fi
    echo ""
    echo "  IMPORTANT - v59 compat flags (otherwise: 'no matching host key type'):"
    echo "    ssh -p 36000 -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa cmu@$IP"
    echo ""
    echo "  Of permanent in ~/.ssh/config:"
    echo "    Host mzd cmu"
    echo "      HostName $IP"
    echo "      Port 36000"
    echo "      User cmu"
    echo "      HostKeyAlgorithms +ssh-rsa,ssh-dss"
    echo "      PubkeyAcceptedAlgorithms +ssh-rsa"
    echo ""
    echo "  Termux example:"
    echo "    ssh -p 36000 -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa cmu@$IP -i /sdcard/mzd/id_mzd"
    echo ""
    echo "  If 'Connection refused':"
    echo "    - Check if sshd is running: ps | grep sshd"
    echo "    - Check port: netstat -tln | grep 36000"
    echo "    - Check firewall: iptables -L -n"
else
    echo " WiFi not connected - no SSH possible"
    echo "========================================"
    echo "  Run first: sh wifi/connect-nms.sh   (open network: WIFI_PASSWORD=OPEN in settings.conf)"
fi
echo ""
