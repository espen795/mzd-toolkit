#!/bin/sh
# ============================================================
# MZD Toolkit - autostart-eth1-ssh.sh
# Purpose: automatic at boot (and directly runnable by hand):
#   1. Partition unlock (rw)
#   2. Privilege separation (/var/empty, /var/run/sshd, user sshd)
#   3. Enable password auth for 'cmu' (no certificates/keys!)
#   4. Start SSH daemon on port 36000
#   5. Realtek RTL8152 (0bda:8152) koppelen aan cdc_ether
#   6. eth1 configureren op 192.168.0.2 (blijft 100% van eth0 af!)
# ============================================================

PWD_DEFAULT="mzd"
CMU_IP="192.168.0.2"
CMU_NETMASK="255.255.255.0"

echo "[MZD-AUTO] 1. Unlock filesystems..."
mount -o remount,rw / 2>/dev/null
mount -o remount,rw /lib 2>/dev/null
mount -o remount,rw /data_persist 2>/dev/null
mount -o remount,rw /mnt/data_persist 2>/dev/null
mount -o remount,rw /tmp/mnt/data_persist 2>/dev/null

echo "[MZD-AUTO] 2. Configureer SSH privilege separation..."
if ! grep -q "^sshd:" /etc/passwd 2>/dev/null; then
    echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd
fi
mkdir -p /var/empty /var/run/sshd
chown root:root /var/empty /var/run/sshd 2>/dev/null
chmod 755 /var/empty /var/run/sshd

echo "[MZD-AUTO] 3. Set password for 'cmu' (chpasswd = system crypt)..."
# v4.8.16: chpasswd instead of manual cryptpw - uses libcrypt directly (DES on v59)
mount -o remount,rw / 2>/dev/null
if echo "cmu:$PWD_DEFAULT" | chpasswd 2>&1; then
    H=$(grep "^cmu:" /etc/passwd 2>/dev/null | cut -d: -f2)
    case "$H" in
        \$5\$*|\$6\$*) echo "[MZD-AUTO] WARNING: SHA hash - v59 sshd may fail";;
        *) echo "[MZD-AUTO] cmu password set via chpasswd (hash len=${#H})";;
    esac
else
    echo "[MZD-AUTO] chpasswd failed, fallback to cryptpw..."
    H=$(busybox cryptpw "$PWD_DEFAULT" 2>/dev/null)
    [ -n "$H" ] && [ ${#H} -eq 13 ] && sed -i "s|^cmu:[^:]*:|cmu:$H:|" /etc/passwd 2>/dev/null
fi

echo "[MZD-AUTO] 4. Start SSH daemon (Port 36000, PasswordAuthentication=yes)..."
killall sshd 2>/dev/null
sleep 1
mkdir -p /tmp/mzd-pwd-sshd
chmod 700 /tmp/mzd-pwd-sshd
# v4.8.16: sshd met PasswordAuthentication yes + debug log
cat > /tmp/mzd-pwd-sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/mzd-pwd-sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
# v4.8.19: NO UsePAM - v59 sshd 5.9p1 does not know this option
PidFile /tmp/mzd-pwd-sshd/sshd.pid
LogLevel DEBUG3
# v4.8.16: only rsa+dsa (v59 sshd old build does not know ecdsa/ed25519)
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
EOF

SSHD=""
for p in /usr/sbin/sshd /usr/lib/ssh/sshd /sbin/sshd; do
    [ -x "$p" ] && { SSHD="$p"; break; }
done
[ -z "$SSHD" ] && SSHD=$(which sshd 2>/dev/null)

if [ -x "$SSHD" ]; then
    "$SSHD" -f /tmp/mzd-pwd-sshd/sshd_config 2>&1
    echo "[MZD-AUTO] sshd started with pwd-auth, log: /tmp/mzd-pwd-sshd/sshd.log"
fi

echo "[MZD-AUTO] 5. Load USB-Ethernet drivers (asix AX88772 detected in dmesg)..."
# v4.8.15: the dongle is an ASIX AX88772 (dongle MAC redacted), NOT RTL8152!
# asix module is already loaded (see lsmod: asix Live). Only configure eth1.
# Forceer asix new_id bind als fallback
if [ -f /sys/bus/usb/drivers/asix/new_id ]; then
    echo "0b95 772a" > /sys/bus/usb/drivers/asix/new_id 2>/dev/null
fi
# RTL8152 bind as backup (for when another dongle)
if [ -f /sys/bus/usb/drivers/cdc_ether/new_id ]; then
    echo "0bda 8152" > /sys/bus/usb/drivers/cdc_ether/new_id 2>/dev/null
fi

# Give the USB bus a moment to register the interface
sleep 3

echo "[MZD-AUTO] 6. Configure eth1 (eth0 stays untouched!)..."
# v4.8.15: actively wait for eth1 (max 10s) - dongle can take a moment to register
_i=0
while [ $_i -lt 10 ] && [ ! -d "/sys/class/net/eth1" ]; do
    sleep 1; _i=$((_i+1))
done
if [ -d "/sys/class/net/eth1" ]; then
    ifconfig eth1 "$CMU_IP" netmask "$CMU_NETMASK" up 2>&1
    if ifconfig eth1 2>/dev/null | grep -q "inet addr"; then
        echo "[MZD-AUTO] SUCCESS: eth1 is UP on $CMU_IP"
    else
        echo "[MZD-AUTO] WARNING: eth1 exists but got no IP"
    fi
else
    echo "[MZD-AUTO] WARNING: eth1 still not seen after 10s (check dongle/cable)"
fi

echo "[MZD-AUTO] Status:"
netstat -tln 2>/dev/null | grep ":36000" && echo "  - SSHD: Active on port 36000 (Password: $PWD_DEFAULT)"
ifconfig eth1 2>/dev/null | grep -E "inet addr|HWaddr"
