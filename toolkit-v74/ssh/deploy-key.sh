#!/bin/sh
# ============================================================
# MZD Toolkit - Deploy SSH pubkey (v4.7.5 M3, gate 0046b92)
# Generates/reuses ed25519 keypair in $TOOLKIT_DIR/ssh/id_mzd,
# copies .pub to USB (autorun puts it on the CMU in
# /mnt/data_persist/dev/bin/authorized_keys), print connect-info.
#
# NEVER touch /config-mfg: squashfs ro on mtdblock5, 128K, 100% full
# (bewezen in logs/from-mzd/dump-19700101-000231/03-storage.txt).
# ============================================================

# Source gedeelde library (met fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TOOLKIT_DIR="${TOOLKIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
KEY="$TOOLKIT_DIR/ssh/id_mzd"
detect_usb 2>/dev/null
USB_MOUNT="${USB_MOUNT:-${USB_MOUNT}}"
[ -d ${USB_MOUNT} ] && USB_MOUNT="${USB_MOUNT}"

# v4.8.16: RSA 2048 (v59 sshd 2016 does NOT know ed25519 — "unknown key type ssh-ed25519")
# ed25519 was only introduced in OpenSSH 6.5 (2014); v59 has an older build.
# RSA 2048 is universeel ondersteund. ssh-keygen -t rsa -b 2048.
if [ ! -f "$KEY" ]; then
    ssh-keygen -t rsa -b 2048 -f "$KEY" -N "" -q 2>/dev/null && echo "RSA-2048 keypair generated: $KEY" || { echo "ERROR: ssh-keygen failed"; exit 1; }
else
    # Check whether existing key is RSA (not ed25519)
    if head -1 "$KEY.pub" 2>/dev/null | grep -q "ssh-ed25519"; then
        echo "WARNING: existing key is ed25519 — v59 sshd does NOT support this"
        echo "Remove $KEY and $KEY.pub and run again for RSA"
        exit 1
    fi
    echo "Reusing existing keypair: $KEY ($(head -1 "$KEY.pub" | awk '{print $1}'))"
fi

# Copy .pub to USB (if USB detected) — otherwise it is already in data_persist
if [ -n "$USB_MOUNT" ] && [ -d "$USB_MOUNT" ]; then
    mkdir -p "$USB_MOUNT/mzd-toolkit/ssh" 2>/dev/null
    if cp "$KEY.pub" "$USB_MOUNT/mzd-toolkit/ssh/id_mzd.pub" 2>/dev/null; then
        echo "Pubkey copied to $USB_MOUNT/mzd-toolkit/ssh/id_mzd.pub"
    else
        echo "WARNING: could not copy .pub to USB ($USB_MOUNT)"
    fi
fi
# v4.8.16: write pubkey directly into authorized_keys paths (also works without USB/reboot)
for AK_DST in /data_persist/dev/bin/authorized_keys /mnt/data_persist/dev/bin/authorized_keys /tmp/mnt/data_persist/dev/bin/authorized_keys; do
    _dir=$(dirname "$AK_DST")
    if mkdir -p "$_dir" 2>/dev/null && touch "$_dir/.t$$" 2>/dev/null; then
        rm -f "$_dir/.t$$"
        mount -o remount,rw "$(dirname "$_dir")" 2>/dev/null
        cp "$KEY.pub" "$AK_DST" 2>/dev/null && chmod 600 "$AK_DST" 2>/dev/null && echo "authorized_keys set: $AK_DST"
        # also to /tmp/mzd-sshd for our own sshd
        mkdir -p /tmp/mzd-sshd 2>/dev/null
        cp "$KEY.pub" /tmp/mzd-sshd/authorized_keys 2>/dev/null && chmod 600 /tmp/mzd-sshd/authorized_keys 2>/dev/null
        break
    fi
done

IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d: -f2)

echo ""
echo "========================================"
echo " SSH pubkey deploy (v4.7.5 M3)"
echo "========================================"
echo "Connect from PC/phone with (port 36000 is THE port (design decision):"
echo "  v59 compat flags REQUIRED (modern ssh refuses ssh-rsa host key):"
echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-<IP>} -i $KEY   (pubkey)"
 echo "  ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-<IP>}            (password if set)"
echo "  MZD_SSH_OPTS=$MZD_SSH_OPTS"
echo "========================================"
