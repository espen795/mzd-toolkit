#!/bin/sh
# MZD Toolkit - Install SSH Permanent
# Makes SSH persistent via data_persist and stage_wifi.sh hook

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TOOLKIT_DIR="${TOOLKIT_DIR:-}"
PERSIST="/mnt/data_persist/dev/bin"

echo "========================================"
echo " SSH Permanent Install"
echo "========================================"
echo ""

# Check root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: Must run as root!"
    exit 1
fi

echo "Step 1: Create directories..."
mkdir -p "$PERSIST"
mkdir -p /mnt/data_persist/aio/tweaks

echo "Step 2: Copy autorun script..."
cp "$TOOLKIT_DIR/ssh/autorun" "$PERSIST/autorun" 2>/dev/null
chmod +x "$PERSIST/autorun"

echo "Step 3: Copy SSH config..."
cp "$TOOLKIT_DIR/ssh/sshd_config" "$PERSIST/sshd_config" 2>/dev/null

echo "Step 4: Copy start scripts..."
cp "$TOOLKIT_DIR/ssh/start.sh" "$PERSIST/start-ssh.sh" 2>/dev/null
chmod +x "$PERSIST/start-ssh.sh"

echo "Step 5: Generate host key (if needed)..."
if [ ! -f "$PERSIST/ssh_host_rsa_key" ]; then
    ssh-keygen -t rsa -f "$PERSIST/ssh_host_rsa_key" -N "" -q
    echo "Host key gegenereerd"
else
    echo "Host key already exists"
fi

echo "Step 6: Patch stage_wifi.sh..."
STAGE_WIFI="/jci/scripts/stage_wifi.sh"

if [ -f "$STAGE_WIFI" ]; then
    # Backup
    cp "$STAGE_WIFI" /mnt/data_persist/stage_wifi.sh.bak 2>/dev/null

    # Check if already patched
    if grep -q "MZD-AIO Hook" "$STAGE_WIFI" 2>/dev/null; then
        echo "stage_wifi.sh is already patched"
    else
        # Try remount
        echo "Remount /jci as read-write..."
        mount -o remount,rw /jci 2>/dev/null

        # Patch via temporary file (BusyBox sed \n does not work - review M1)
        echo "Patch stage_wifi.sh..."
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/stage_wifi.$$")
        grep -v "^exit" "$STAGE_WIFI" > "$TMPF" 2>/dev/null
        echo "# MZD-AIO Hook" >> "$TMPF"
        echo "if [ -x /mnt/data_persist/dev/bin/autorun ]; then" >> "$TMPF"
        echo "    /mnt/data_persist/dev/bin/autorun &" >> "$TMPF"
        echo "fi" >> "$TMPF"
        echo "exit" >> "$TMPF"
        cp "$TMPF" "$STAGE_WIFI" 2>/dev/null
        rm -f "$TMPF"

        # Verify
        HOOK_LINE=$(grep -n "MZD-AIO Hook" "$STAGE_WIFI" 2>/dev/null | cut -d: -f1)
        EXIT_LINE=$(grep -n "^exit" "$STAGE_WIFI" 2>/dev/null | head -1 | cut -d: -f1)

        if [ -n "$HOOK_LINE" ] && [ -n "$EXIT_LINE" ]; then
            if [ "$HOOK_LINE" -lt "$EXIT_LINE" ]; then
                echo "OK: Hook correctly placed (line $HOOK_LINE before exit on line $EXIT_LINE)"
            else
                echo "WARNING: Hook possibly misplaced!"
            fi
        else
            echo "ERROR: Could not verify hook"
        fi
    fi
else
    echo "WARNING: stage_wifi.sh not found"
fi

echo "Step 7: Warning fix flags..."
echo "1" > /mnt/data_persist/aio/warning_ack 2>/dev/null
echo "1" > /mnt/data_persist/dev/no_warn 2>/dev/null

cat > /mnt/data_persist/aio/tweaks/no_warn.conf << 'EOF'
NO_STARTUP_WARNING=1
NO_DISCLAIMER=1
NO_MODIFIED_WARNING=1
EOF

echo "Step 8: jci-dialog wrapper..."
cat > "$PERSIST/jci-dialog" << 'EOF'
#!/bin/sh
for arg in "$@"; do
    if [ "$arg" = "--warning" ]; then
        exit 0
    fi
done
for path in /jci/bin/jci-dialog /usr/bin/jci-dialog; do
    if [ -x "$path" ]; then
        "$path" "$@"
        exit $?
    fi
done
exit 0
EOF
chmod +x "$PERSIST/jci-dialog"

echo "Step 9: Start SSH now..."
"$PERSIST/start-ssh.sh" 2>/dev/null || sh "$TOOLKIT_DIR/ssh/start.sh"

echo ""
echo "========================================"
echo " INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "Files in $PERSIST:"
ls -la "$PERSIST"
echo ""
echo "After reboot SSH starts automatically."
echo "Restart the car to test."
