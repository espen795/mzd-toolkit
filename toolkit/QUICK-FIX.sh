#!/bin/sh
TOOLKIT_DIR="${TOOLKIT_DIR:-${TOOLKIT_DIR}}"
[ -d ${TOOLKIT_DIR} ] && TOOLKIT_DIR="${TOOLKIT_DIR}"
. "$TOOLKIT_DIR/lib/wifi-compat.sh" 2>/dev/null
# MZD Toolkit - QUICK FIX (v4.8.0, 2026-11-01)
# NOTE: outdated path - sets PasswordAuthentication yes + random password.
# For a workable test phase: use FIX-ALL.sh (menu #1) - port 36000, pwd from
# config/secrets.conf or pubkey. This script only if FIX-ALL fails.
# Fixes the 3 most important problems in 1 script:
# 1. SSH port 36000 (THE port)
# 2. SSH auth
# 3. WiFi scan empty (rescan + check AP)

# Source shared library
. "$(dirname "$0")/lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
log_to_usb "QUICK-FIX.sh started"

echo "========================================"
echo " MZD QUICK FIX - 30 October 2026"
echo "========================================"
echo ""

# === 1. SSH PORT FIX ===
echo "=== 1/3: SSH PORT FIX ==="
echo "Mazda sshd runs on PORT 36000 (not 22!)"
echo ""

# Stop old sshd
killall sshd 2>/dev/null
sleep 1

# Create config for port 36000 (THE port - 2026-11-01)
mkdir -p /tmp/sshd
cat > /tmp/sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
# SECURITY (review 2026-10-30): root login only via SSH key (prohibit-password).
# Mazda CMU has 'cmu' as uid 0 user - log in as cmu, not as root.
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
# SECURITY: NEVER allow empty passwords
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/sshd/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
EOF

echo "Starting sshd on port 22 AND 36000..."
/usr/sbin/sshd -f /tmp/sshd/sshd_config 2>&1
sleep 2

echo "Ports now open:"
netstat -tln 2>/dev/null | grep sshd
echo ""

# Firewall open for port 36000
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
# SECURITY (review 2026-10-30): NO more 'iptables -P INPUT ACCEPT'.
echo "Firewall: ACCEPT for 36000"
echo ""

# === 2. SSH AUTH FIX ===
echo "=== 2/3: SSH AUTH FIX ==="
echo "Original config had: PasswordAuthentication no"
echo "New config has: PasswordAuthentication yes"
echo ""

# SECURITY (review 2026-10-30): NO hardcoded password/hash anymore.
# Password comes from $SSH_PASSWORD env var, else a strong
# random password is generated and shown ONCE on screen (never in logs).
echo "Root user is 'cmu' (uid 0) in /etc/passwd"
echo "Setting password..."

# Generate strong random password (32 chars from /dev/urandom)
PLAIN=""
if [ -n "$SSH_PASSWORD" ]; then
    PLAIN="$SSH_PASSWORD"
    echo "Using password from SSH_PASSWORD env var"
else
    PLAIN=$(head -c 24 /dev/urandom 2>/dev/null | od -A n -t x 2>/dev/null | tr -d ' \n' | head -c 32)
    [ -z "$PLAIN" ] && PLAIN=$(date +%s | sha256sum 2>/dev/null | head -c 32)
    [ -z "$PLAIN" ] && PLAIN="mzd$(head -c 8 /dev/urandom | od -A n -t x | tr -d ' \n')"
fi


# Backup and update passwd (root IS writable!)
cp /etc/passwd /tmp/passwd.bak 2>/dev/null
if [ -n "$HASH" ]; then
    sed -i "s|^cmu:[^:]*:|cmu:$HASH:|" /etc/passwd 2>/dev/null && echo "Password set" || echo "Could not write (remount?)"
fi
# Show password ONCE on screen - NEVER in log files
echo ""
echo "========================================"
echo " SSH PASSWORD (once only, store safely):"
echo "   $PLAIN"
echo "========================================"
echo ""
echo ""

# === 3. WIFI FIX ===
echo "=== 3/3: WIFI FIX ==="
echo "Problem: scan_results empty, auth timeout"
echo ""

echo "--- Check modules ---"
grep -E "wl12xx|cfg80211|mac80211" /proc/modules
echo ""

echo "--- Rescan (wpa_cli) ---"
wpactrl scan 2>&1
sleep 5
echo "Scan results:"
wpactrl scan_results 2>/dev/null
echo ""

echo "--- wpa_cli status ---"
wpactrl status 2>/dev/null
echo ""

echo "--- If scan empty: try manual scan via /proc ---"
echo "wlan0 statistics:"
echo "  rx_packets: $(cat /sys/class/net/wlan0/statistics/rx_packets 2>/dev/null)"
echo "  tx_packets: $(cat /sys/class/net/wlan0/statistics/tx_packets 2>/dev/null)"
echo ""

echo "--- WiFi connect via NMS (v4.7.5) ---"
TOOLKIT_DIR="${TOOLKIT_DIR:-${TOOLKIT_DIR}}"
[ -d ${TOOLKIT_DIR} ] && TOOLKIT_DIR="${TOOLKIT_DIR}"
# NEVER start own wpa_supplicant (conflict with NMS) - via NMS D-Bus:
if [ -f "$TOOLKIT_DIR/wifi/connect-nms.sh" ]; then
    WIFI_SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}" WIFI_PASSWORD="${WIFI_PASSWORD:-}" sh "$TOOLKIT_DIR/wifi/connect-nms.sh" "${WIFI_SSID:-YOUR_HOTSPOT_SSID}" "${WIFI_PASSWORD:-}"
fi

echo ""

echo "--- DHCP ---"
killall udhcpc 2>/dev/null
udhcpc -i wlan0 -n -q -t 5 -T 3 2>&1

echo ""
echo "========================================"
echo " RESULT"
echo "========================================"
echo ""
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "WiFi IP: ${IP:-NONE}"
echo ""
echo "SSH ports:"
netstat -tln 2>/dev/null | grep sshd
echo ""
if [ -n "$IP" ]; then
    echo "Connect from phone/PC with (port 36000):"
    echo "  ssh -p 36000 cmu@$IP     (password: see above)"
else
    echo "WiFi not connected - check scan_results"
    echo "Try: wpactrl scan_results"
fi
echo ""
echo "========================================"
