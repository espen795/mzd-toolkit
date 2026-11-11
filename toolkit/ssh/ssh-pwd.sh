#!/bin/sh
# MZD Toolkit - ssh-pwd.sh (v4.8.16)
# SSH with password on port 36000. v59-proof: chpasswd (system crypt = DES).
# v4.8.16: chpasswd instead of manual sed - busybox cryptpw on v59 generates
#   inconsistencies; chpasswd uses libcrypt directly (same as login).
# v4.8.15: DES hash via busybox cryptpw (v59 libcrypt has no SHA $5$/$6$)
# v4.8.14: ensure_root_rw() + verify after passwd write
#
# Usage on the CMU:
#   sh /data_persist/mzd-toolkit/ssh/ssh-pwd.sh            -> password "mzd"
#   sh /data_persist/mzd-toolkit/ssh/ssh-pwd.sh mypass123  -> own password
#   sh /data_persist/mzd-toolkit/ssh/ssh-pwd.sh off        -> pubkey-only
#
# From PC:  ssh -p 36000 cmu@<ip>     (type password)

PWD="${1:-mzd}"

# Source lib for ensure_root_rw
_SCRIPT_DIR=$(dirname "$0" 2>/dev/null)
for _lib in "$_SCRIPT_DIR/../lib/common.sh" /data_persist/mzd-toolkit/lib/common.sh /mnt/data_persist/mzd-toolkit/lib/common.sh; do
    [ -f "$_lib" ] && . "$_lib" 2>/dev/null && break
done

# priv-sep user (v59 sshd fails without it)
grep -q "^sshd:" /etc/passwd 2>/dev/null || echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd 2>/dev/null

if [ "$PWD" = "off" ]; then
    PWDAUTH="no"
    echo "Password auth OFF (pubkey-only)"
else
    PWDAUTH="yes"
    # v4.8.16: chpasswd - sets hash via system crypt (DES on v59, guaranteed compatible)
    mount -o remount,rw / 2>/dev/null
    touch /etc/.rwtest_pwd 2>/dev/null && rm -f /etc/.rwtest_pwd || { echo "ERROR: / is read-only"; exit 1; }

    if echo "cmu:$PWD" | chpasswd 2>&1; then
        # Verify: hash in passwd must NOT contain $ (DES = 13 chars) or $1$ (MD5, also OK on v59?)
        H=$(grep "^cmu:" /etc/passwd 2>/dev/null | cut -d: -f2)
        echo "Hash set (len=${#H})"
        case "$H" in
            \$5\$*|\$6\$*) echo "WARNING: SHA hash detected - v59 sshd cannot verify this!";;
            \$*) echo "Hash type: \$1\$ (MD5) - test login";;
            *) echo "Hash type: DES (${#H} chars) - v59 native";;
        esac
    else
        # Fallback: manual with cryptpw
        echo "chpasswd failed, trying cryptpw..."
        H=$(busybox cryptpw "$PWD" 2>/dev/null)
        [ -z "$H" ] && H=$(openssl passwd -crypt "$PWD" 2>/dev/null)
        if [ -n "$H" ] && [ ${#H} -eq 13 ]; then
            sed -i "s|^cmu:[^:]*:|cmu:$H:|" /etc/passwd 2>&1
            grep -q "^cmu:$H:" /etc/passwd 2>/dev/null && echo "DES hash set via fallback" || echo "ERROR: sed failed"
        else
            echo "ERROR: no working hash generated (H=$H len=${#H})"
            exit 1
        fi
    fi
fi

# Own sshd config in /tmp (stock /etc/ssh is read-only squashfs overlay)
killall sshd 2>/dev/null
sleep 1
mkdir -p /tmp/mzd-pwd-sshd
chmod 700 /tmp/mzd-pwd-sshd
cat > /tmp/mzd-pwd-sshd/sshd_config << EOF
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication $PWDAUTH
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/mzd-pwd-sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
# v4.8.19: NO UsePAM - v59 sshd 5.9p1 (2011) does NOT know this option ("Unsupported option UsePAM")
PidFile /tmp/mzd-pwd-sshd/sshd.pid
LogLevel DEBUG3
# v4.8.16: only rsa+dsa host keys (v59 sshd has no ecdsa/ed25519 in old build)
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
EOF

# copy authorized_keys if it exists
[ -f /data_persist/dev/bin/authorized_keys ] && cp /data_persist/dev/bin/authorized_keys /tmp/mzd-pwd-sshd/authorized_keys 2>/dev/null && chmod 600 /tmp/mzd-pwd-sshd/authorized_keys

SSHD=""
for p in /usr/sbin/sshd /usr/lib/ssh/sshd /usr/lib/openssh/sshd /sbin/sshd; do
    [ -x "$p" ] && { SSHD="$p"; break; }
done
[ -z "$SSHD" ] && SSHD=$(find / -name sshd -type f 2>/dev/null | head -1)
[ -z "$SSHD" ] && { echo "ERROR: no sshd binary"; exit 1; }

# Start sshd with debug logging (for troubleshooting)
"$SSHD" -f /tmp/mzd-pwd-sshd/sshd_config 2>&1
sleep 2

if netstat -tln 2>/dev/null | grep -q ":36000"; then
    IP=$(ifconfig eth1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP" ] && IP=$(ifconfig eth0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "OK: sshd LISTEN on 36000, PasswordAuthentication=$PWDAUTH"
    echo "SSHD log: /tmp/mzd-pwd-sshd/sshd.log"
    echo "From PC (v59 compat - modern ssh refuses ssh-rsa without these flags):"
    echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-192.168.0.2}   (password: $PWD)"
    echo "Debug:  ssh -vvv $MZD_SSH_OPTS -p 36000 cmu@${IP:-192.168.0.2}"
else
    echo "ERROR: 36000 not LISTEN - config test:"
    "$SSHD" -t -f /tmp/mzd-pwd-sshd/sshd_config 2>&1
    echo "--- sshd.log ---"
    tail -20 /tmp/mzd-pwd-sshd/sshd.log 2>/dev/null
    exit 1
fi
