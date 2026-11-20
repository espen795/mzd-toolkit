#!/bin/sh
# MZD Toolkit - fix-ssh.sh (v4.8.10)
# Pubkey fix + sshd restart with StrictModes no.
# Run op de CMU:  sh /tmp/mnt/sdb1/fix-ssh.sh
# Looks for id_mzd.pub on the stick (root of mzd-toolkit/ssh), sanitized CRLF,
# puts it in /tmp/mzd-sshd/authorized_keys AND /data_persist/dev/bin/authorized_keys,
# fixes permissions (stock sshd refuses group-writable paths), restarts sshd.

PUB=""
# v4.8.16: also look in data_persist toolkit (persist-install mode, no USB stick needed)
for d in /data_persist/mzd-toolkit/ssh /mnt/data_persist/mzd-toolkit/ssh /tmp/mnt/data_persist/mzd-toolkit/ssh; do
    [ -f "$d/id_mzd.pub" ] && { PUB="$d/id_mzd.pub"; break; }
done
# Fallback: USB stick paths
if [ -z "$PUB" ]; then
    for d in /tmp/mnt/sdb1 /tmp/mnt/sda1 /tmp/mnt/sdc1 /mnt/sdb1 /mnt/sda1 /tmp/mnt/sd* /mnt/sd*; do
        [ -d "$d" ] || continue
        case "$d" in *nav*) continue ;; esac
        for f in "$d/id_mzd.pub" "$d/ssh/id_mzd.pub" "$d/mzd-toolkit/ssh/id_mzd.pub"; do
            if [ -f "$f" ]; then PUB="$f"; break 2; fi
        done
    done
fi
# Last resort: generate key directly on the CMU if ssh-keygen works
if [ -z "$PUB" ]; then
    echo "No id_mzd.pub found - trying to generate key on the CMU..."
    GEN_DIR="/data_persist/mzd-toolkit/ssh"
    mkdir -p "$GEN_DIR" 2>/dev/null
    mount -o remount,rw /data_persist 2>/dev/null
    if ssh-keygen -t rsa -b 2048 -f "$GEN_DIR/id_mzd" -N "" -q 2>/dev/null; then
        PUB="$GEN_DIR/id_mzd.pub"
        echo "RSA key generated: $PUB"
    else
        echo "ERROR: id_mzd.pub not found AND ssh-keygen failed on CMU"
        echo "Generate on your PC: ssh-keygen -t rsa -b 2048 -f id_mzd -N ''"
        echo "Copy id_mzd.pub to the USB stick root or mzd-toolkit/ssh/"
        ls /tmp/mnt/ 2>/dev/null
        exit 1
    fi
fi
echo "pubkey found: $PUB"

# sanitize: remove Windows CRLF
tr -d '\r' < "$PUB" > /tmp/ak.pub
# v4.8.16: accept ssh-rsa (v59 sshd does not know ed25519). ed25519 is refused.
if grep -q "ssh-ed25519" /tmp/ak.pub; then
    echo "ERROR: key is ed25519 - v59 sshd (2016) does NOT support this. Generate RSA:"
    echo "  ssh-keygen -t rsa -b 2048 -f id_mzd -N ''"
    exit 1
fi
grep -q "ssh-rsa" /tmp/ak.pub || { echo "ERROR: no ssh-rsa key in $PUB:"; cat "$PUB"; exit 1; }

# 1. /tmp/mzd-sshd (eerste AuthorizedKeysFile in stock config)
mkdir -p /tmp/mzd-sshd
cp /tmp/ak.pub /tmp/mzd-sshd/authorized_keys
chmod 700 /tmp/mzd-sshd
chmod 600 /tmp/mzd-sshd/authorized_keys

# 2. data_persist path + permissions fix (777 dirs fail StrictModes)
for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
    if [ -d "$PP" ] && touch "$PP/.t$$" 2>/dev/null; then
        rm -f "$PP/.t$$"
        D="$PP/dev/bin"
        mkdir -p "$D"
        cp /tmp/ak.pub "$D/authorized_keys"
        chmod 600 "$D/authorized_keys"
        chmod 755 "$PP/dev" "$D" 2>/dev/null
        echo "authorized_keys set in $D"
        break
    fi
done

echo "--- authorized_keys contents ---"
cat /tmp/mzd-sshd/authorized_keys
echo "-------------------------------"

# 3. restart sshd with own config (StrictModes no)
killall sshd 2>/dev/null
sleep 1
TK=""
for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
    [ -f "$PP/mzd-toolkit/ssh/start.sh" ] && TK="$PP/mzd-toolkit" && break
done
[ -z "$TK" ] && for d in /tmp/mnt/sd* /mnt/sd*; do
    [ -f "$d/mzd-toolkit/ssh/start.sh" ] && case "$d" in *nav*) ;; *) TK="$d/mzd-toolkit"; break ;; esac
done
if [ -n "$TK" ]; then
    sh "$TK/ssh/start.sh" 2>&1 | tail -8
else
    echo "ERROR: toolkit start.sh not found"
    exit 1
fi

echo ""
netstat -tln 2>/dev/null | grep ":36000" && echo "OK: port 36000 LISTEN" || echo "ERROR: 36000 not LISTEN"
IP=$(ifconfig eth0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "From PC (v59 compat flags REQUIRED - otherwise 'no matching host key type'):"
echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-192.168.0.2} -i id_mzd"
echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-192.168.0.2}    (password)"
