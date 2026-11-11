#!/bin/sh
# ============================================================
# MZD Toolkit - Install Terminal Menu (Permanent via autorun)
# ============================================================
# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

# Makes the UI Terminal fix permanent at every boot:
#  1. verify/create the /data symlink
#  2. set developer_mode flags in /data/integration/
#  3. copy developer_mode_GuiConfig.js to /data/integration/
#
# Installation: copy this script to /mnt/data_persist/dev/bin/autorun
# (or add a line to an existing autorun script)
# stage_1.sh calls autorun at every boot (v74: stage_wifi.sh is empty - see WARNING-FIX-V2.md par.5).
# ============================================================

echo "========================================"
echo " MZD Terminal Menu - Permanent Install"
echo "========================================"
echo ""

# Check root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must run as root!"
    exit 1
fi

PERSIST="/mnt/data_persist/dev/bin"
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
# ------------------------------------------------------------
# Step 1: Make sure directories exist
# ------------------------------------------------------------
echo "Step 1: Creating directories..."
mkdir -p "$PERSIST"
mkdir -p /mnt/data_persist/aio 2>/dev/null

# ------------------------------------------------------------
# Step 2: Create the terminal-setup script in data_persist
# (this runs at every boot via autorun)
# ------------------------------------------------------------
echo "Step 2: Creating terminal setup script in $PERSIST..."
cat > "$PERSIST/terminal-setup.sh" << 'SETUPEOF'
#!/bin/sh
# MZD Terminal Setup - runs at every boot via autorun
# Sets developer mode flags in /data/integration/ (where the GUI reads them)

LOG=/tmp/mzd-terminal-setup.log
echo "Terminal setup started: $(date)" > "$LOG"

# Wait until /mnt/data is mounted (can take a while after boot)
for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -d /mnt/data ] || [ -d /mnt/data_persist ]; then
        break
    fi
    sleep 2
done

# Make sure the /data symlink exists (GUI reads /data/integration/)
if [ ! -e /data ]; then
    if [ -d /mnt/data ]; then
        ln -sf /mnt/data /data 2>>"$LOG"
        echo "/data -> /mnt/data symlink created" >> "$LOG"
    elif [ -d /mnt/data_persist ]; then
        ln -sf /mnt/data_persist /data 2>>"$LOG"
        echo "/data -> /mnt/data_persist symlink created" >> "$LOG"
    fi
fi

# Determine integration dir (via /data as the GUI reads it)
if [ -d /data ]; then
    INTEG="/data/integration"
elif [ -d /mnt/data ]; then
    INTEG="/mnt/data/integration"
else
    INTEG="/mnt/data_persist/integration"
fi

mkdir -p "$INTEG"
echo "Integration dir: $INTEG" >> "$LOG"

# Set developer mode flags
touch "$INTEG/developer_mode_on_flag"
touch "$INTEG/eth0_on_flag"
echo "Flags set: developer_mode_on_flag, eth0_on_flag" >> "$LOG"

# Copy GuiConfig (only if source exists)
if [ -f /jci/gui/common/js/developer_mode_GuiConfig.js ]; then
    cp -f /jci/gui/common/js/developer_mode_GuiConfig.js "$INTEG/developer_mode_GuiConfig.js"
    echo "developer_mode_GuiConfig.js copied" >> "$LOG"
else
    echo "WARNING: developer_mode_GuiConfig.js source not found" >> "$LOG"
fi

# Use official developer_mode.sh if available (does the same but more official)
if [ -f /jci/scripts/developer_mode.sh ]; then
    sh /jci/scripts/developer_mode.sh on >> "$LOG" 2>&1
    echo "developer_mode.sh on executed" >> "$LOG"
fi

sync
echo "Terminal setup complete: $(date)" >> "$LOG"
SETUPEOF
chmod +x "$PERSIST/terminal-setup.sh"
echo "  terminal-setup.sh created"

# ------------------------------------------------------------
# Step 3: Update autorun to start terminal-setup.sh
# ------------------------------------------------------------
echo "Step 3: Updating autorun..."

AUTORUN="$PERSIST/autorun"

if [ -f "$AUTORUN" ]; then
    # Backup
    cp "$AUTORUN" "$AUTORUN.bak.$(date +%s)" 2>/dev/null

    # Check if terminal-setup is already in autorun
    if grep -q "terminal-setup.sh" "$AUTORUN" 2>/dev/null; then
        echo "  terminal-setup.sh already in autorun"
    else
        # Add before the exit (or at the end)
        if grep -q "^exit" "$AUTORUN"; then
            # BusyBox sed \n does not work (review M1) - use temp file
            TMPF=$(mktemp 2>/dev/null || echo "/tmp/autorun.$$")
            grep -v "^exit" "$AUTORUN" > "$TMPF" 2>/dev/null
            echo "# MZD Terminal Setup" >> "$TMPF"
            echo "if [ -x $PERSIST/terminal-setup.sh ]; then" >> "$TMPF"
            echo "    sh $PERSIST/terminal-setup.sh &" >> "$TMPF"
            echo "fi" >> "$TMPF"
            echo "exit" >> "$TMPF"
            cp "$TMPF" "$AUTORUN" 2>/dev/null
            rm -f "$TMPF"
        else
            echo "" >> "$AUTORUN"
            echo "# MZD Terminal Setup" >> "$AUTORUN"
            echo "if [ -x $PERSIST/terminal-setup.sh ]; then" >> "$AUTORUN"
            echo "    sh $PERSIST/terminal-setup.sh &" >> "$AUTORUN"
            echo "fi" >> "$AUTORUN"
        fi
        echo "  terminal-setup.sh added to autorun"
    fi
else
    # Create new autorun
    cat > "$AUTORUN" << 'AUTORUNEOF'
#!/bin/sh
# MZD Toolkit Autorun + Terminal Setup
sleep 15
LOG=/tmp/mzd-autorun.log
echo "Autorun started: $(date)" > "$LOG"
export PATH=/mnt/data_persist/dev/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# Warning fix
echo "1" > /mnt/data_persist/aio/warning_ack 2>/dev/null

# Terminal setup (developer mode flags in /data/integration/)
if [ -x /mnt/data_persist/dev/bin/terminal-setup.sh ]; then
    sh /mnt/data_persist/dev/bin/terminal-setup.sh >> "$LOG" 2>&1 &
fi

# WiFi connect (if toolkit is on USB)
if [ -f ${TOOLKIT_DIR}/wifi/connect.sh ]; then
    sh ${TOOLKIT_DIR}/wifi/connect.sh >> "$LOG" 2>&1
fi

sleep 5

# SSH start
if [ -f /mnt/data_persist/dev/bin/start-ssh.sh ]; then
    sh /mnt/data_persist/dev/bin/start-ssh.sh >> "$LOG" 2>&1
fi

# Firewall
iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
# SECURITY (review 2026-10-30): NO default ACCEPT anymore

echo "Autorun complete: $(date)" >> "$LOG"
AUTORUNEOF
    chmod +x "$AUTORUN"
    echo "  New autorun created with terminal-setup"
fi

# ------------------------------------------------------------
# Step 4: Make sure stage_1.sh calls the autorun (v74: stage_wifi.sh is empty!)
#         See WARNING-FIX-V2.md par.5 - review M3
# ------------------------------------------------------------
echo "Step 4: Checking stage_1.sh hook..."
STAGE_1="/jci/scripts/stage_1.sh"

if [ -f "$STAGE_1" ]; then
    if grep -q "autorun" "$STAGE_1" 2>/dev/null; then
        echo "  stage_1.sh already has an autorun hook"
    else
        cp "$STAGE_1" "$STAGE_1.org" 2>/dev/null
        mount -o remount,rw /jci 2>/dev/null
        # BusyBox sed \n does not work (review M1) - temp file
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/stage_1.$$")
        grep -v "^exit" "$STAGE_1" > "$TMPF" 2>/dev/null
        echo "# MZD-AIO Hook" >> "$TMPF"
        echo "if [ -x /mnt/data_persist/dev/bin/autorun ]; then" >> "$TMPF"
        echo "    /mnt/data_persist/dev/bin/autorun &" >> "$TMPF"
        echo "fi" >> "$TMPF"
        echo "exit" >> "$TMPF"
        cp "$TMPF" "$STAGE_1" 2>/dev/null
        rm -f "$TMPF"
        mount -o remount,ro /jci 2>/dev/null
        echo "  stage_1.sh patched with autorun hook (backup: stage_1.sh.org)"
    fi
else
    echo "  WARNING: $STAGE_1 not found"
fi

# ------------------------------------------------------------
# Step 5: Apply now directly (without reboot)
# ------------------------------------------------------------
echo "Step 5: Running terminal setup NOW directly..."
if [ -x "$PERSIST/terminal-setup.sh" ]; then
    sh "$PERSIST/terminal-setup.sh"
    echo "  terminal-setup.sh executed"
    echo "  Log: /tmp/mzd-terminal-setup.log"
    cat /tmp/mzd-terminal-setup.log 2>/dev/null
fi

echo ""
echo "========================================"
echo " INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "Installed:"
    echo "  - $PERSIST/terminal-setup.sh  (runs at every boot)"
    echo "  - $PERSIST/autorun            (modified)"
echo ""
echo "REBOOT NOW: hold Mute + Navi for 10 seconds"
    echo "After reboot 'Terminal' appears in the Settings menu!"
echo ""
echo "Start terminal directly (without reboot):"
echo "  sh $TOOLKIT_DIR/tools/ui.sh terminal"
echo ""
