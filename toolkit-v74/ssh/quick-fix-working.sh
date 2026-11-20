#!/bin/sh
# ============================================================
# MZD SSH QUICK FIX (v4.7.6): port 36000 is THE port (design decision).
# Pwd-auth when MZD_SSH_PASSWORD is in config/secrets.conf (test phase, short
# pwd), otherwise pubkey-only. Kill stock sshd in pwd-mode (pubkey-only, ro).
# ============================================================

echo "========================================"
echo " MZD SSH Quick Fix v${TOOLKIT_VERSION:-4.8.3} (port 36000)"
echo "========================================"

# v4.7.6: load secrets.conf (this script does not source common.sh)
for _sc in "$(dirname "$0")/../config/secrets.conf" ${TOOLKIT_DIR}/config/secrets.conf ${TOOLKIT_DIR}/config/secrets.conf; do
    [ -f "$_sc" ] && . "$_sc" 2>/dev/null && break
done

# Stop old sshd
killall sshd 2>/dev/null
sleep 1

# v4.8.2 BUGFIX (logs 11h 2026-11-03, run r6 exit 1): v59 sshd faalt met
# "Privilege separation user sshd does not exist" if sshd is not in /etc/passwd.
# And "UsePAM" is not a valid option on this old sshd (sed-removed in v4.8.2).
if ! grep -q "^sshd:" /etc/passwd 2>/dev/null; then
    echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd 2>/dev/null \
        && echo "  priv-sep user 'sshd' added to /etc/passwd"
fi

# v4.7.6: password from secrets.conf -> pwd-auth; empty -> pubkey-only
mkdir -p /tmp/sshd
if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
    MZD_SSH_PWD_SET=1
    mount -o remount,rw / 2>/dev/null; echo "cmu:$MZD_SSH_PASSWORD" | chpasswd 2>/dev/null
    if [ -n "$_H" ]; then
        cp /etc/passwd /tmp/passwd.qfw.bak 2>/dev/null
        sed -i "s|^cmu:[^:]*:|cmu:$_H:|" /etc/passwd 2>/dev/null
    fi
    unset _H MZD_SSH_PASSWORD
    cat > /tmp/sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/sshd/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
EOF
else
    cat > /tmp/sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
# Mazda CMU has 'cmu' as uid 0 user - log in as cmu, not as root.
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/sshd/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
EOF
fi

echo "Start sshd on port 36000..."
# v4.8.2: DO show errors (was 2>&1 but config validation silently failed in FIX-ALL)
/usr/sbin/sshd -f /tmp/sshd/sshd_config 2>&1
sleep 2

# v4.8.2: LISTEN-check + explicit message when it failed
if netstat -tln 2>/dev/null | grep -q ':36000 '; then
    echo "  sshd LISTEN op 36000 OK"
else
    echo "  WARNING: sshd is NOT LISTENing on 36000 - config check:"
    /usr/sbin/sshd -t -f /tmp/sshd/sshd_config 2>&1 | head -5
fi

# Firewall: ONLY port 36000, NEVER -P INPUT ACCEPT
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null

# Pick up pubkey from USB (autorun also puts it in /data_persist/dev/bin/authorized_keys)
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
[ -d ${TOOLKIT_DIR} ] && TOOLKIT_DIR="${TOOLKIT_DIR}"
if [ -f "$TOOLKIT_DIR/ssh/id_mzd.pub" ]; then
    cp "$TOOLKIT_DIR/ssh/id_mzd.pub" /tmp/sshd/authorized_keys 2>/dev/null
    chmod 600 /tmp/sshd/authorized_keys 2>/dev/null
    echo "  pubkey set in /tmp/sshd/authorized_keys"
else
    echo "  no id_mzd.pub found - run ssh/deploy-key.sh and copy to USB"
fi

echo ""
echo "Ports:"
netstat -tln 2>/dev/null | grep sshd
echo ""
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d: -f2)
if [ -n "${MZD_SSH_PWD_SET:-}" ]; then
    echo "Connect with: ssh $MZD_SSH_OPTS -p 36000 cmu@$IP   (password from config/secrets.conf)"
else
    echo "Connect with: ssh $MZD_SSH_OPTS -p 36000 cmu@$IP -i $TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
fi
echo "========================================"
