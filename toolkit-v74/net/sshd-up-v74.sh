#!/bin/sh
# ============================================================
# MZD v74 - sshd-up-v74.sh  (RO-safe, point-to-point)
# Regains SSH on a v74 CMU after a firmware update, where the
# stock sshd (port 36000) only accepts the Mazda key from the
# read-only /config-mfg partition.
#
# Fixes the return-path problems seen on v74 (ARP works but the
# connection times out because no SYN-ACK reaches the laptop):
#   - clean /24 on the USB interface (no stale /32 leftovers)
#   - explicit host route back to the laptop (192.168.0.1)
#   - reverse-path filtering OFF (drops replies on a multi-homed host)
#   - firewall opened on the link (INPUT+OUTPUT) + ports
#   - our own sshd on 2222, keys in /tmp + /data_persist
# Prints a compact diag at the end (photograph it from the car).
# Everything runs from /tmp + /data_persist -> no rootfs write.
#   Run on the CMU (as root):  sh sshd-up-v74.sh
#
# KEY SETUP: put your RSA public key in /data_persist/dev/authorized_keys
# (or /data_persist/dev/bin/authorized_keys) before running, OR paste it
# into PUBKEY below. v74 ships OpenSSH 5.9 -> ed25519 is NOT supported,
# an RSA key is mandatory.
# ============================================================
AK=/tmp/ak; ETH_IP=192.168.0.2; LAP=192.168.0.1
mkdir -p "$AK"
# OpenSSH 5.9 on v74 has NO ed25519 -> use an RSA key.
# Replace this with your own RSA public key, or leave it and drop the key
# into /data_persist/dev/authorized_keys (picked up automatically below).
PUBKEY='<YOUR_RSA_PUBKEY>'

# --- bind dongle driver ------------------------------------
for m in usbnet asix ax88179_178a cdc_ether cdc_ncm rndis_host; do modprobe $m 2>/dev/null; done
for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] || continue
    v=$(cat "$dev/idVendor" 2>/dev/null); p=$(cat "$dev/idProduct" 2>/dev/null)
    case "$v" in ""|0000|1d6b) continue ;; esac
    for drv in asix ax88179_178a cdc_ether cdc_ncm; do
        [ -f "/sys/bus/usb/drivers/$drv/new_id" ] && echo "$v $p" > "/sys/bus/usb/drivers/$drv/new_id" 2>/dev/null
    done
done
sleep 2

# --- detect USB-net interface ------------------------------
IFC=""
for i in /sys/class/net/*; do
    [ -d "$i" ] || continue; n=${i##*/}
    case "$n" in lo|eth0|wlan0) continue ;; esac
    if readlink "$i/device" 2>/dev/null | grep -q usb; then IFC="$n"; break; fi
    [ -z "$IFC" ] && IFC="$n"
done
[ -z "$IFC" ] && IFC=eth1
echo "USB-net interface: $IFC"

# --- clean /24 on the interface ----------------------------
ip addr flush dev "$IFC" 2>/dev/null
ifconfig "$IFC" 0.0.0.0 2>/dev/null
ifconfig "$IFC" "$ETH_IP" netmask 255.255.255.0 up 2>/dev/null
sleep 1

# --- explicit host route back to the laptop ----------------
ip route add "$LAP"/32 dev "$IFC" 2>/dev/null || route add -host "$LAP" "$IFC" 2>/dev/null

# --- reverse-path filtering OFF (reply-drop fix) -----------
for f in /proc/sys/net/ipv4/conf/all/rp_filter "/proc/sys/net/ipv4/conf/$IFC/rp_filter" /proc/sys/net/ipv4/conf/default/rp_filter; do
    [ -w "$f" ] && echo 0 > "$f" 2>/dev/null
done

# --- open firewall on the link -----------------------------
iptables -I INPUT 1 -i "$IFC" -j ACCEPT 2>/dev/null
iptables -I OUTPUT 1 -o "$IFC" -j ACCEPT 2>/dev/null
iptables -I INPUT 1 -p tcp --dport 2222 -j ACCEPT 2>/dev/null
iptables -I INPUT 1 -p tcp --dport 36000 -j ACCEPT 2>/dev/null

# --- serial fallback: cmu/mzd (DES) instead of unknown $5$ --
# /etc/passwd is a symlink to the read-only /config-mfg/passwd (a $5$ SHA256
# hash we do not know) -> replace it with a real file carrying a DES hash of
# 'mzd' so 'cmu'/'mzd' works over serial. Idempotent.
if [ -L /etc/passwd ] || ! grep -q '^cmu:S6YIh05H4xJg\.:' /etc/passwd 2>/dev/null; then
    mount -o remount,rw,sync / 2>/dev/null
    cp /config-mfg/passwd /tmp/p.ensure 2>/dev/null
    sed -i 's|^cmu:[^:]*:|cmu:S6YIh05H4xJg.:|' /tmp/p.ensure 2>/dev/null
    chmod 644 /tmp/p.ensure 2>/dev/null
    [ -s /tmp/p.ensure ] && grep -q '^cmu:S6YIh05H4xJg' /tmp/p.ensure && mv -f /tmp/p.ensure /etc/passwd 2>/dev/null
fi

# --- keys ---------------------------------------------------
# Collect keys: PUBKEY above (if set) + anything already in /data_persist.
: > "$AK/keys"
case "$PUBKEY" in ssh-*) printf '%s\n' "$PUBKEY" >> "$AK/keys" ;; esac
for d in /data_persist/dev /data_persist/dev/bin; do
    mkdir -p "$d" 2>/dev/null; touch "$d/authorized_keys" 2>/dev/null
    case "$PUBKEY" in ssh-*)
        grep -qF "$PUBKEY" "$d/authorized_keys" 2>/dev/null || printf '%s\n' "$PUBKEY" >> "$d/authorized_keys" ;;
    esac
    cat "$d/authorized_keys" 2>/dev/null >> "$AK/keys"
    chmod 600 "$d/authorized_keys" 2>/dev/null
done
sort -u "$AK/keys" 2>/dev/null | grep -v '^$' > "$AK/keys.u" && mv "$AK/keys.u" "$AK/keys"
chmod 600 "$AK/keys"
if ! grep -q '^ssh-' "$AK/keys" 2>/dev/null; then
    echo "WARNING: no RSA public key found. Set PUBKEY in this script or put one in /data_persist/dev/authorized_keys" >&2
fi

# --- sshd on 2222 ------------------------------------------
HK=/etc/ssh/ssh_host_rsa_key
[ -f "$HK" ] || { ssh-keygen -t rsa -f "$AK/hk" -N '' >/dev/null 2>&1; HK="$AK/hk"; }
SSHD=""; for p in /usr/sbin/sshd /usr/lib/ssh/sshd /sbin/sshd; do [ -x "$p" ] && { SSHD="$p"; break; }; done
printf 'Port 2222\nHostKey %s\nAuthorizedKeysFile %s/keys\nPermitRootLogin yes\nPasswordAuthentication no\nPubkeyAuthentication yes\nUsePrivilegeSeparation no\nStrictModes no\nUseDNS no\nPidFile %s/s2222.pid\n' \
    "$HK" "$AK" "$AK" > "$AK/cfg2222"
pkill -f cfg2222 2>/dev/null; sleep 1
if [ -n "$SSHD" ] && "$SSHD" -f "$AK/cfg2222"; then echo SSHD2222_OK; else echo SSHD2222_FAIL; fi

# --- COMPACT DIAG (photograph this) ------------------------
echo "========== DIAG =========="
echo -n "IFC=$IFC  "; ifconfig "$IFC" 2>/dev/null | grep -i "inet addr"
echo -n "rp_filter(all)="; cat /proc/sys/net/ipv4/conf/all/rp_filter 2>/dev/null
echo "route:"; (ip route 2>/dev/null || route -n 2>/dev/null) | grep -iE "0\.0\.0|$IFC|default" | head -4
echo "iptables INPUT policy+top:"; iptables -nL INPUT 2>/dev/null | head -4
echo "listen:"; netstat -ltn 2>/dev/null | grep -E ":2222|:36000" || echo NONE
echo "=========================="
