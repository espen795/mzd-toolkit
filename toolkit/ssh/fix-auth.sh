#!/bin/sh
# MZD Toolkit - Fix SSH Auth
# v4.7.5 M3: pubkey-only. Stock config (port 36000) has PasswordAuthentication no
# and password 'jci' NEVER works. Own sshd on port 22 with AuthorizedKeysFile
# in /tmp + /mnt/data_persist (writable), NEVER /config-mfg.

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

echo "========================================"
echo " SSH Auth Fix"
echo "========================================"
echo ""
echo "Problem: /etc/ssh/sshd_config has:"
echo "  PasswordAuthentication no"
echo "  AuthorizedKeysFile /config-mfg/authorized_keys  (read-only squashfs, NEVER modify - v4.7.5)"
echo ""
echo "Solution: own sshd config pubkey-only (deploy-key.sh sets the key)"
echo ""

# Create work directory
mkdir -p /tmp/sshd-fix

# Own config - port 36000 is THE port (design decision); password auth
# only if MZD_SSH_PASSWORD is in config/secrets.conf (test phase).
PWDAUTH=no
if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
    PWDAUTH=yes
    # v4.8.19: chpasswd (DES) instead of SHA-256 - v59 libcrypt 2011 has no $5$/$6$
    mount -o remount,rw / 2>/dev/null
    echo "cmu:$MZD_SSH_PASSWORD" | chpasswd 2>/dev/null
    unset _H MZD_SSH_PASSWORD
fi
cat > /tmp/sshd-fix/sshd_config << EOF
Port 36000
ListenAddress 0.0.0.0
PasswordAuthentication $PWDAUTH
# v4.8.19: PermitRootLogin yes (v59 sshd 5.9p1 does NOT know 'prohibit-password')
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/sshd-fix/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
# v4.8.19: NO UsePAM (v59 sshd 5.9p1 does not know it)
StrictModes no
PidFile /tmp/sshd-fix/sshd.pid
LogLevel DEBUG
# v4.8.19: only rsa+dsa host keys (v59 old build does not know ecdsa/ed25519)
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
EOF

echo "Config: /tmp/sshd-fix/sshd_config"
echo ""
cat /tmp/sshd-fix/sshd_config
echo ""

# v4.8.20 MAJOR FIX: deploy pubkey FIRST, then priv-sep user, then start sshd
# sshd priv-sep user (v59 sshd fails without)
grep -q "^sshd:" /etc/passwd 2>/dev/null || echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd 2>/dev/null
mkdir -p /var/empty /var/run/sshd 2>/dev/null
chmod 755 /var/empty /var/run/sshd 2>/dev/null

# Deploy pubkey to ALL paths the config reads
for AK_DST in /tmp/sshd-fix/authorized_keys /data_persist/dev/bin/authorized_keys /tmp/mzd-sshd/authorized_keys; do
    for AK_SRC in "$TOOLKIT_DIR/ssh/id_mzd.pub" /data_persist/mzd-toolkit/ssh/id_mzd.pub; do
        if [ -f "$AK_SRC" ]; then
            mkdir -p "$(dirname "$AK_DST")" 2>/dev/null
            cp "$AK_SRC" "$AK_DST" 2>/dev/null && chmod 600 "$AK_DST" 2>/dev/null && echo "key -> $AK_DST"
            break
        fi
    done
done

echo "--- Stop old sshd ---"
killall sshd 2>/dev/null
sleep 2

echo "--- Start sshd on port 36000 (pwd-auth=$PWDAUTH) ---"
/usr/sbin/sshd -f /tmp/sshd-fix/sshd_config 2>&1
sleep 2

echo ""
echo "--- Check ---"
ps 2>/dev/null | grep sshd | grep -v grep
netstat -tln 2>/dev/null | grep -E ":36000"

echo ""
echo "Log in (port 36000, v59 compat flags MANDATORY):"
echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@<ip> -i \$TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@<ip>            (password if set)"
