#!/bin/sh
# MZD Toolkit - Start SSH  (v4.7.6: port 36000 is THE port (design decision)
# Start our OWN sshd as root on port 36000 with generated config in /tmp.
# In pwd-mode (MZD_SSH_PASSWORD in config/secrets.conf) killen we de stock sshd
# (pubkey-only, read-only config) and bind our own sshd on 36000 with
# PasswordAuthentication yes. Without secrets.conf: pubkey-only on 36000.
# NO iptables fix needed: firewall policy is already ACCEPT (proven in 08-firewall.txt).

# Source gedeelde library (met fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

echo "========================================"
echo " SSH Server Start (v4.7.2 M3)"
echo "========================================"
echo ""

# ============================================================
# M3 ordering fix: port-check BEFORE the early-exit (pubkey-mode only).
# If something is already LISTENing on 36000 (stock sshd), SSH is already available.
# ============================================================
port_listen() {
    netstat -tln 2>/dev/null | grep -E ':36000 ' && return 0
    # secondary: /proc/net/tcp (port 36000 = 8CA0) - POSIX awk only (F5: no strtonum, that is gawk-only)
    if [ -r /proc/net/tcp ]; then
        awk 'NR>1 { split($2,a,":"); h=a[2]; p=0; for(i=1;i<=length(h);i++){ c=substr(h,i,1); p=p*16 + (index("0123456789ABCDEF", toupper(c)) - 1) } if (p==36000 && $4=="0A") { found=1 } } END { exit !found }' /proc/net/tcp 2>/dev/null && return 0
    fi
    return 1
}

# v4.7.6 port 36000 is the primary port, optionally with password auth.
# Stock sshd op 36000 is pubkey-only (read-only config) — in pwd-mode killen we
# that and we bind OUR own sshd on 36000 with PasswordAuthentication yes.
if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
    echo "Pwd-mode (secrets.conf): kill stock sshd and start own sshd on 36000..."
    killall sshd 2>/dev/null
    sleep 1
elif port_listen; then
    # v4.8.11: stock sshd (pubkey-only via read-only /config-mfg) runs on 36000 after reboot.
    # If our key is not in there, we kill the stock sshd and start our own sshd.
    _stock_ok=0
    if [ -f /tmp/mzd-sshd/authorized_keys ]; then
        _stock_ok=1   # own sshd already running with our key
    elif [ -f /config-mfg/authorized_keys ] && grep -qF "$(cat "${TOOLKIT_DIR:-}/ssh/id_mzd.pub" 2>/dev/null)" /config-mfg/authorized_keys 2>/dev/null; then
        _stock_ok=1
    fi
    if [ "$_stock_ok" = "1" ]; then
        echo "SSH is already reachable (port 36000 is LISTEN, key OK):"
        netstat -tln 2>/dev/null | grep -E ':(22|36000) '
        IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -z "$IP" ] && IP=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -n "$IP" ] && echo "Connect with (v59 compat): ssh $MZD_SSH_OPTS -p 36000 cmu@$IP -i \$TOOLKIT_DIR/ssh/id_mzd"
        exit 0
    fi
    echo "Stock sshd on 36000 detected without our key - kill and start own sshd..."
    killall sshd 2>/dev/null
    sleep 1
fi

# If sshd is already running but NOT listening on 36000: report, do not silently exit
if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
    echo "NOTE: sshd is already running, but not on port 36000:"
    netstat -tln 2>/dev/null | grep sshd || true
    echo "Continuing with own sshd on port 36000..."
    echo ""
fi

# Look for sshd binary
SSHD=""
for path in /usr/sbin/sshd /usr/lib/ssh/sshd /usr/lib/openssh/sshd /sbin/sshd /usr/local/sbin/sshd; do
    if [ -x "$path" ]; then
        SSHD="$path"
        break
    fi
done

if [ -z "$SSHD" ]; then
    SSHD=$(find / -name sshd -type f 2>/dev/null | head -1)
fi

if [ -z "$SSHD" ]; then
    echo "ERROR: sshd binary not found!"
    echo ""
    echo "FALLBACK: use the already running sshd on port 36000 (CI-2955):"
    echo "  netstat -tln | grep 36000"
    echo "  ssh -p 36000 root@<IP>"
    echo "Search manually with: find / -name sshd 2>/dev/null"
    exit 1
fi

echo "Found: $SSHD"

# ============================================================
# M3: OWN sshd config + host keys in /tmp (no writes to persist needed)
# ============================================================
SSHD_TMP="/tmp/mzd-sshd"
mkdir -p "$SSHD_TMP"

CONFIG="$SSHD_TMP/sshd_config"
# v4.7.6 (design decision): port 36000 is THE port.
# If MZD_SSH_PASSWORD is set in config/secrets.conf -> password auth ON on
# port 36000 (own sshd, stock sshd gets killed). Otherwise pubkey-only on 36000.
# Password is NEVER in git - only in gitignored config/secrets.conf.
# v4.8.19: chpasswd (DES) - v59 libcrypt 2011 no SHA-256
# v4.8.20 BLOCKER FIX: save PWDAUTH BEFORE unset, and PermitRootLogin yes (cmu = uid 0!)
PWDAUTH="no"
if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
    PWDAUTH="yes"
    mount -o remount,rw / 2>/dev/null
    echo "cmu:$MZD_SSH_PASSWORD" | chpasswd 2>/dev/null && echo "  password for 'cmu' set via chpasswd (DES)"
    unset MZD_SSH_PASSWORD
fi
cat > "$CONFIG" << EOF
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication $PWDAUTH
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/mzd-sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/mzd-sshd/sshd.pid
HostKey /tmp/mzd-sshd/ssh_host_rsa_key
HostKey /tmp/mzd-sshd/ssh_host_dsa_key
EOF
# v4.8.2 BUGFIX (logs 11h 2026-11-03, run r6 exit 1): de v59 sshd (oud OpenSSH,
# kernel 3.0.35) does NOT know "UsePAM" option ("Unsupported option UsePAM") and
# fails if the priv-sep user "sshd" is not in /etc/passwd. Therefore:
#   - UsePAM line REMOVED from the config above
#   - add sshd user if absent (otherwise "Privilege separation user sshd does not exist")
if ! grep -q "^sshd:" /etc/passwd 2>/dev/null; then
    echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd 2>/dev/null \
        && echo "  priv-sep user 'sshd' added to /etc/passwd" \
        || echo "  WARNING: could not add sshd user (read-only /etc/passwd?)"
fi
# authorized_keys uit USB/autorun oppakken als die er is
# v4.8.16: also from data_persist (persist-install, no USB needed)
detect_usb 2>/dev/null
AK_SRC=""
for f in "${USB_MOUNT:-/nonexistent}/mzd-toolkit/ssh/id_mzd.pub" \
         /data_persist/mzd-toolkit/ssh/id_mzd.pub \
         /mnt/data_persist/mzd-toolkit/ssh/id_mzd.pub \
         /tmp/mnt/data_persist/mzd-toolkit/ssh/id_mzd.pub \
         /data_persist/dev/bin/authorized_keys; do
    [ -f "$f" ] && { AK_SRC="$f"; break; }
done
if [ -n "$AK_SRC" ]; then
    cp "$AK_SRC" "$SSHD_TMP/authorized_keys" 2>/dev/null && chmod 600 "$SSHD_TMP/authorized_keys" 2>/dev/null && echo "  authorized_keys uit $AK_SRC"
fi
# Set password on cmu (uid 0) when MZD_SSH_PASSWORD is set - /etc/passwd is rw on v59
if [ -n "${MZD_SSH_HASH:-}" ]; then
    MZD_SSH_PWD_SET=1
    cp /etc/passwd /tmp/passwd.mzd-sshd.bak 2>/dev/null
    sed -i "s|^cmu:[^:]*:|cmu:$MZD_SSH_HASH:|" /etc/passwd 2>/dev/null && echo "  password for 'cmu' set (from config/secrets.conf)" || echo "  WARNING: could not write /etc/passwd"
    unset MZD_SSH_HASH MZD_SSH_PASSWORD  # do not leave hash/pwd hanging in env
    echo "Config: $CONFIG (Port 36000, password auth ON - test phase)"
else
    echo "Config: $CONFIG (Port 36000, pubkey-only)"
fi

# v4.8.20: ALWAYS copy system host keys from /etc/ssh (stable host identity after reboot!)
# v4.8.16: ONLY rsa + dsa (v59 sshd does not know ed25519/ecdsa host keys)
# NEVER generate new keys in /tmp - the client would then see a different host key each time.
for t in rsa dsa; do
    K="$SSHD_TMP/ssh_host_${t}_key"
    if [ -f "/etc/ssh/ssh_host_${t}_key" ]; then
        cp "/etc/ssh/ssh_host_${t}_key" "$K" 2>/dev/null
        [ -f "/etc/ssh/ssh_host_${t}_key.pub" ] && cp "/etc/ssh/ssh_host_${t}_key.pub" "$K.pub" 2>/dev/null
    elif [ ! -f "$K" ]; then
        # only if /etc/ssh key is missing: generate in /tmp (once, then copy to persist)
        ssh-keygen -t "$t" -f "$K" -N "" -q 2>/dev/null || rm -f "$K"
    fi
done
# v4.8.20: NO ssh-keygen -A - tries to modify read-only /etc/ssh.
# Config gebruikt al expliciete HostKey paden (/tmp/mzd-sshd/ssh_host_*_key).

# Valideer config
if ! "$SSHD" -t -f "$CONFIG" 2>/dev/null; then
    echo "ERROR: generated config is not valid:"
    "$SSHD" -t -f "$CONFIG" 2>&1 || true
    echo ""
    echo "FALLBACK: sshd already runs on port 36000 (CI-2955, proven in logs 2026-11-01):"
    echo "  netstat -tln | grep -E ':(22|36000) '"
    echo "  ssh -p 36000 root@<IP>"
    exit 1
fi

# Start own sshd (as root)
# v4.8.2: do NOT suppress errors anymore (2>/dev/null removed) - in logs at 11h the
# start failed silently, making FIX-ALL think sshd was running while it was not.
echo "Start own sshd on port 36000..."
"$SSHD" -f "$CONFIG" 2>&1
sleep 2

# ============================================================
# M3: LISTEN-check via netstat (bewezen in 02-network.txt)
# ============================================================
if netstat -tln 2>/dev/null | grep -E ':36000 '; then
    echo ""
    echo "SUCCESS: SSH server running on port 36000!"
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    if [ -n "$IP" ]; then
        if [ -n "${MZD_SSH_PWD_SET:-}" ]; then
            echo "Connect with: ssh -p 36000 cmu@$IP   (password from config/secrets.conf)"
        else
            echo "Connect with: ssh -p 36000 cmu@$IP -i \$TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
        fi
    fi
    # NO iptables: firewall policy is already ACCEPT (08-firewall.txt, logs 2026-11-01)
    exit 0
fi

echo ""
echo "ERROR: no sshd LISTEN on 36000. Debug output:"
"$SSHD" -t -f "$CONFIG" 2>&1 || true
"$SSHD" -f "$CONFIG" -d 2>&1 &
DBGPID=$!
sleep 3
kill $DBGPID 2>/dev/null
echo ""
echo "FALLBACK (proven working in MZD logs 2026-11-01, dump 06-configs.txt / 02-network.txt):"
echo "  the system sshd runs on port 36000 (CI-2955), PID 1430:"
echo "  netstat -tln | grep 36000   ->  0.0.0.0:36000 LISTEN"
echo "  ssh -p 36000 cmu@<IP> -i \$TOOLKIT_DIR/ssh/id_mzd   (pubkey via /data_persist/dev/bin/authorized_keys)"
exit 1
