#!/bin/sh
# ============================================================
# MZD Toolkit - install-autostart.sh
# Purpose: installs autostart-eth1-ssh.sh in /data_persist/dev/bin/autorun
# so that at EVERY boot of the CMU:
#   1. The Realtek RTL8152 dongle is bound directly to cdc_ether
#   2. eth1 is automatically configured on 192.168.0.2
#   3. sshd automatically starts on port 36000 with password 'mzd'
# ============================================================

echo "=== MZD Autostart Installer ==="

mount -o remount,rw / 2>/dev/null
mount -o remount,rw /data_persist 2>/dev/null
mount -o remount,rw /mnt/data_persist 2>/dev/null

TARGET_DIR="/data_persist/dev/bin"
[ ! -d "$TARGET_DIR" ] && TARGET_DIR="/mnt/data_persist/dev/bin"
mkdir -p "$TARGET_DIR"

SELF_DIR=$(dirname "$0")
SCRIPT_SRC=""

for cand in "$SELF_DIR/autostart-eth1-ssh.sh" \
            "$SELF_DIR/../net/autostart-eth1-ssh.sh" \
            "/tmp/mnt/sd*/autostart-eth1-ssh.sh" \
            "/tmp/mnt/sd*/mzd-toolkit/net/autostart-eth1-ssh.sh" \
            "/data_persist/mzd-toolkit/net/autostart-eth1-ssh.sh"; do
    if [ -f "$cand" ]; then
        SCRIPT_SRC="$cand"
        break
    fi
done

if [ -z "$SCRIPT_SRC" ]; then
    echo "ERROR: autostart-eth1-ssh.sh not found!"
    exit 1
fi

echo "Source file: $SCRIPT_SRC"
cp "$SCRIPT_SRC" "$TARGET_DIR/autostart-eth1-ssh.sh"
chmod 755 "$TARGET_DIR/autostart-eth1-ssh.sh"

AUTORUN="$TARGET_DIR/autorun"
touch "$AUTORUN"

# Add trigger to autorun if not already present
if ! grep -q "autostart-eth1-ssh.sh" "$AUTORUN" 2>/dev/null; then
    echo "" >> "$AUTORUN"
    echo "# === MZD Autostart ETH1 & SSH (Realtek RTL8152 + Port 36000 PWD) ===" >> "$AUTORUN"
    echo "sh $TARGET_DIR/autostart-eth1-ssh.sh > /tmp/mzd-autostart-eth1.log 2>&1 &" >> "$AUTORUN"
    chmod 755 "$AUTORUN"
    echo "SUCCESS: Autostart added to $AUTORUN"
else
    echo "Autostart line was already present in $AUTORUN"
fi

# Also run it once right now
echo "Running autostart directly..."
sh "$TARGET_DIR/autostart-eth1-ssh.sh"

echo ""
echo "DONE! At every restart of the CMU, eth1 and SSH start automatically."
