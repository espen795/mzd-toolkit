#!/bin/sh
# MZD Toolkit - setup-ssh.sh (v4.8.10)
# ONE command on the CMU: set authorized_keys + start sshd.
# Usage: put id_mzd.pub on the USB stick root, then on the CMU:
#   sh /tmp/mnt/sdb1/setup-ssh.sh
# (also works if the script is in mzd-toolkit/ssh)
D=""
for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
    if [ -d "$PP/dev/bin" ] || touch "$PP/.t$$" 2>/dev/null; then rm -f "$PP/.t$$"; D="$PP/dev/bin"; break; fi
done
[ -z "$D" ] && D="/data_persist/dev/bin"
mkdir -p "$D"

# find pubkey: stick root, ssh subdir, toolkit ssh dir, or current script dir
SELF_DIR=$(dirname "$0")
for src in /tmp/mnt/sdb1/id_mzd.pub /tmp/mnt/sda1/id_mzd.pub /mnt/sdb1/id_mzd.pub \
           /tmp/mnt/sdb1/ssh/id_mzd.pub /tmp/mnt/sda1/ssh/id_mzd.pub /mnt/sdb1/ssh/id_mzd.pub \
           /tmp/mnt/sd*/ssh/id_mzd.pub /mnt/sd*/ssh/id_mzd.pub \
           "$SELF_DIR/id_mzd.pub" "$SELF_DIR/../ssh/id_mzd.pub" \
           "$SELF_DIR/../../ssh/id_mzd.pub" id_mzd.pub ssh/id_mzd.pub; do
    if [ -f "$src" ]; then
        cp "$src" "$D/authorized_keys" && echo "pubkey uit $src -> $D/authorized_keys"
        break
    fi
done
if [ ! -s "$D/authorized_keys" ]; then
    echo "ERROR: no id_mzd.pub found. Put it on the USB stick root."
    exit 1
fi
chmod 600 "$D/authorized_keys"

# start sshd on 36000 (stock sshd is pubkey-only)
if ! netstat -tln 2>/dev/null | grep -q ":36000"; then
    TK=""
    for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
        [ -f "$PP/mzd-toolkit/ssh/start.sh" ] && TK="$PP/mzd-toolkit" && break
    done
    [ -z "$TK" ] && for d in /tmp/mnt/sd* /mnt/sd*; do
        [ -f "$d/mzd-toolkit/ssh/start.sh" ] && case "$d" in *nav*) ;; *) TK="$d/mzd-toolkit"; break ;; esac
    done
    if [ -n "$TK" ]; then
        sh "$TK/ssh/start.sh" >/dev/null 2>&1
    else
        # fallback: system sshd directly on 36000 with our config
        /usr/sbin/sshd -p 36000 -o AuthorizedKeysFile="$D/authorized_keys" 2>/dev/null
    fi
fi

netstat -tln 2>/dev/null | grep ":36000" && echo "OK: sshd listening on 36000" || echo "WARNING: 36000 not seen"
IP=$(ifconfig eth0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo ""
echo "Vanaf PC:  ssh -p 36000 cmu@${IP:-<IP>} -i id_mzd"
