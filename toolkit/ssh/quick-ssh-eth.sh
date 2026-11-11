#!/bin/sh
# ============================================================
# MZD Toolkit - quick-ssh-eth.sh (v2)
# 1. Makes all required partitions READ-WRITE (unlock)
# 2. Fix privilege separation directories (/var/empty AND /var/run/sshd)
# 3. Password for user 'cmu' (no certificates/keys required)
# 4. Start sshd on port 36000 with PasswordAuthentication YES
# 5. Brings ONLY eth1 up on 192.168.0.2 (STAYS AWAY FROM eth0!)
# ============================================================

PWD="${1:-mzd}"
IP="192.168.0.2"
MASK="255.255.255.0"

echo "=== [1/5] Unlock OS (remount rw) ==="
mount -o remount,rw / 2>/dev/null
mount -o remount,rw /lib 2>/dev/null
mount -o remount,rw /data_persist 2>/dev/null
mount -o remount,rw /mnt/data_persist 2>/dev/null
mount -o remount,rw /tmp/mnt/data_persist 2>/dev/null

echo "=== [2/5] sshd privilege separation configureren ==="
# Add priv-sep user 'sshd' to /etc/passwd if missing
if ! grep -q "^sshd:" /etc/passwd 2>/dev/null; then
    echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd
    echo "  sshd user added to /etc/passwd"
else
    echo "  sshd user already present"
fi

# Create both privilege separation directories (depends on OpenSSH build)
mkdir -p /var/empty
chown root:root /var/empty 2>/dev/null
chmod 755 /var/empty

mkdir -p /var/run/sshd
chown root:root /var/run/sshd 2>/dev/null
chmod 755 /var/run/sshd

echo "=== [3/5] Set password for 'cmu' ($PWD) ==="
H=""
# Fallback to DES crypt via busybox if sha256 fails
[ -z "$H" ] && type busybox >/dev/null 2>&1 && H=$(busybox cryptpw "$PWD" 2>/dev/null)

if [ -n "$H" ]; then
    cp /etc/passwd /tmp/passwd.bak 2>/dev/null
    sed -i "s|^cmu:[^:]*:|cmu:$H:|" /etc/passwd 2>/dev/null
    echo "  password set successfully"
else
    echo "  WARNING: no hash tool found"
fi

echo "=== [4/5] start sshd on port 36000 ==="
killall sshd 2>/dev/null
sleep 1

mkdir -p /tmp/mzd-pwd-sshd
chmod 700 /tmp/mzd-pwd-sshd

cat > /tmp/mzd-pwd-sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords yes
StrictModes no
PidFile /tmp/mzd-pwd-sshd/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
EOF

SSHD=""
for p in /usr/sbin/sshd /usr/lib/ssh/sshd /usr/lib/openssh/sshd /sbin/sshd; do
    [ -x "$p" ] && { SSHD="$p"; break; }
done
[ -z "$SSHD" ] && SSHD=$(find / -name sshd -type f 2>/dev/null | head -1)

if [ -x "$SSHD" ]; then
    "$SSHD" -f /tmp/mzd-pwd-sshd/sshd_config 2>&1
    sleep 1
    if netstat -tln 2>/dev/null | grep -q ":36000"; then
        echo "  sshd running on port 36000 (PasswordAuthentication=yes)"
    else
        echo "  WARNING: sshd debug output:"
        "$SSHD" -t -f /tmp/mzd-pwd-sshd/sshd_config 2>&1
    fi
else
    echo "  ERROR: sshd binary not found!"
fi

echo "=== [5/5] Bring Ethernet interface eth1 up (eth0 stays untouched) ==="
# Bind USB dongle drivers if eth1 is not yet in /sys/class/net
if [ ! -d "/sys/class/net/eth1" ]; then
    echo "  eth1 not visible yet, forcing USB driver bind..."
    for dev in /sys/bus/usb/devices/*; do
        [ -f "$dev/idVendor" ] || continue
        v=$(cat "$dev/idVendor" 2>/dev/null); p=$(cat "$dev/idProduct" 2>/dev/null)
        case "$v" in ""|0000|1d6b) continue ;; esac
        for drv in asix cdc_ether cdc_ncm; do
            f="/sys/bus/usb/drivers/$drv/new_id"
            [ -f "$f" ] && echo "$v $p" > "$f" 2>/dev/null
        done
    done
    sleep 2
fi

if [ -d "/sys/class/net/eth1" ]; then
    ifconfig eth1 "$IP" netmask "$MASK" up 2>/dev/null
    echo "  eth1 UP met IP $IP netmask $MASK"
else
    # Try direct ifconfig eth1 anyway
    ifconfig eth1 "$IP" netmask "$MASK" up 2>/dev/null
    if ifconfig eth1 2>/dev/null | grep -q "inet addr"; then
        echo "  eth1 geforceerd UP met IP $IP"
    else
        echo "  ERROR: eth1 does not exist! Current interfaces:"
        ifconfig -a 2>/dev/null
    fi
fi

echo ""
echo "============================================================"
echo "DONE! You can now log in via eth1:"
echo "  ssh -p 36000 cmu@$IP"
echo "  Password: $PWD"
echo "============================================================"
