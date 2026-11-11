#!/bin/sh
# MZD Toolkit - Install Script
# Copies everything to the right places and makes it permanent
# Runs on the Mazda (as root)

# Source shared library (with fallback) - v4.8.0: own dir first
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/lib/common.sh" 2>/dev/null
if [ "${TOOLKIT_LIB_LOADED:-0}" != "1" ]; then
    for _d in /tmp/mnt/sd* /mnt/sd*; do
        [ -f "$_d/mzd-toolkit/lib/common.sh" ] && case "$_d" in *nav*) ;; *) . "$_d/mzd-toolkit/lib/common.sh" && break ;; esac
    done
fi
bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

echo "========================================"
echo " MZD Toolkit v${TOOLKIT_VERSION:-4.8.6} Install"
echo "========================================"
echo ""

# Check root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must run as root!"
    echo "Start the car with your root exploit first."
    exit 1
fi

# Find toolkit directory - v4.8.0: runtime detection, sd_nav excluded,
# prefer mount WITH mzd-toolkit/menu.sh
TOOLKIT=""
for dev in /tmp/mnt/sd* /mnt/sd*; do
    [ -d "$dev" ] || continue
    case "$dev" in *nav*) continue ;; esac
    if [ -f "$dev/mzd-toolkit/menu.sh" ]; then TOOLKIT="$dev/mzd-toolkit"; break; fi
done
if [ -z "$TOOLKIT" ]; then
    for dev in /tmp/mnt/sd* /mnt/sd*; do
        if [ -f "$dev/mzd-toolkit/menu.sh" ]; then TOOLKIT="$dev/mzd-toolkit"; break; fi
        if [ -f "$dev/menu.sh" ]; then TOOLKIT="$dev"; break; fi
    done
fi

if [ -z "$TOOLKIT" ]; then
    echo "ERROR: mzd-toolkit not found on USB!"
    echo "Searching in /tmp/mnt:"
    ls /tmp/mnt/
    exit 1
fi

echo "Toolkit found: $TOOLKIT"
echo ""

# Detect persist root - choose /data_persist as primary default
PERSIST_ROOT=""
for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
    if [ -d "$PP" ] && touch "$PP/.rwtest-$$" 2>/dev/null; then rm -f "$PP/.rwtest-$$"; PERSIST_ROOT="$PP"; break; fi
done
[ -z "$PERSIST_ROOT" ] && PERSIST_ROOT="/data_persist"
PERSIST="$PERSIST_ROOT/dev/bin"
PERSIST_TK="$PERSIST_ROOT/mzd-toolkit"
echo "Persist root detected: $PERSIST_ROOT"

echo "Step 1: Creating directories..."
mkdir -p "$PERSIST"
mkdir -p "$PERSIST_ROOT/aio/tweaks"
mkdir -p "$PERSIST_ROOT/jci"

echo "Step 2: Copying scripts to data_persist..."
cp "$TOOLKIT/menu.sh" "$PERSIST/menu.sh" 2>/dev/null
# v4.8.7 PERSIST-INSTALL: WHOLE toolkit to /data_persist/mzd-toolkit
# (1.7 MB) so everything works WITHOUT USB stick -> ports free for
# phone (tether) + keyboard + hub. Space check first.
if [ -f "$TOOLKIT/menu.sh" ]; then
    mount -o remount,rw "$PERSIST_ROOT" 2>/dev/null
    NEED_KB=$(du -sk "$TOOLKIT" 2>/dev/null | awk '{print $1}'); NEED_KB=${NEED_KB:-2048}
    AVAIL_KB=$(df -k "$PERSIST_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt $((NEED_KB * 12 / 10)) ]; then
        echo "  WARNING: not enough space on "$PERSIST_ROOT" ($AVAIL_KB KB free, $NEED_KB KB needed) - persist-install skipped"
    else
        rm -rf "$PERSIST_TK.tmp.$$" 2>/dev/null
        mkdir -p "$PERSIST_TK.tmp.$$" 2>/dev/null
        cp -r "$TOOLKIT/." "$PERSIST_TK.tmp.$$/" 2>/dev/null
        # Do NOT copy secrets to persist (only .example); real secrets stay on USB mzd-data
        rm -f "$PERSIST_TK.tmp.$$/config/secrets.conf" "$PERSIST_TK.tmp.$$/ssh/id_mzd" "$PERSIST_TK.tmp.$$/ssh/id_mzd.pub" 2>/dev/null
        if [ -f "$PERSIST_TK.tmp.$$/menu.sh" ]; then
            rm -rf "$PERSIST_TK.old" 2>/dev/null
            [ -d "$PERSIST_TK" ] && mv "$PERSIST_TK" "$PERSIST_TK.old" 2>/dev/null
            mv "$PERSIST_TK.tmp.$$" "$PERSIST_TK" 2>/dev/null
            if [ -d "$PERSIST_TK" ]; then
                SIZE=$(du -sh "$PERSIST_TK" 2>/dev/null | awk '{print $1}')
                echo "  persist-install OK: $PERSIST_TK ($SIZE)"
                # v4.8.8: exec-bits on ALL scripts in the persist copy (else "not found" with ./menu.sh)
                find "$PERSIST_TK" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
                chmod +x "$PERSIST_TK/menu.sh" "$PERSIST_TK/autorun" 2>/dev/null
                # v4.8.8: deterministically re-copy driver/module dirs (sha-check in scripts fails otherwise)
                for d in wifi/v74-driver wifi/cdc-modules wifi/rt2800-modules wifi/rt2800-firmware; do
                    [ -d "$TOOLKIT/$d" ] && { rm -rf "$PERSIST_TK/$d" 2>/dev/null; cp -r "$TOOLKIT/$d" "$PERSIST_TK/$d" 2>/dev/null; }
                done
            else
                rm -rf "$PERSIST_TK.tmp.$$" 2>/dev/null
                [ -d "$PERSIST_TK.old" ] && mv "$PERSIST_TK.old" "$PERSIST_TK" 2>/dev/null
                echo "  WARNING: persist-install failed, old version restored"
            fi
        else
            rm -rf "$PERSIST_TK.tmp.$$" 2>/dev/null
            echo "  WARNING: copy to persist failed - USB mode remains"
        fi
    fi
    # mzd-data on persist for logs/config/state when USB is removed
    mkdir -p "$PERSIST_ROOT/mzd-data/config" "$PERSIST_ROOT/mzd-data/state" "$PERSIST_ROOT/mzd-data/logs/runs" "$PERSIST_ROOT/mzd-data/backups" 2>/dev/null
    # settings/secrets: if they only exist on USB -> copy to persist config (else menu misses them without USB)
    [ -n "${USB_MOUNT:-}" ] && [ -f "$USB_MOUNT/mzd-data/config/settings.conf" ] && [ ! -f "$PERSIST_ROOT/mzd-data/config/settings.conf" ] && cp "$USB_MOUNT/mzd-data/config/settings.conf" "$PERSIST_ROOT/mzd-data/config/settings.conf" 2>/dev/null
    [ -n "${USB_MOUNT:-}" ] && [ -f "$USB_MOUNT/mzd-data/config/secrets.conf" ] && [ ! -f "$PERSIST_ROOT/mzd-data/config/secrets.conf" ] && cp "$USB_MOUNT/mzd-data/config/secrets.conf" "$PERSIST_ROOT/mzd-data/config/secrets.conf" 2>/dev/null && chmod 600 "$PERSIST_ROOT/mzd-data/config/secrets.conf" 2>/dev/null
fi
# M3 (v4.7.2): copy the WHOLE lib/ dir (incl. wifi-compat.sh) to $PERSIST/lib/
# v4.8.0: do NOT copy menu.lib anymore - menu.lib/common.sh is a thin shim
# that sources lib/common.sh; only lib/ is needed in $PERSIST.
mkdir -p "$PERSIST/lib"
cp -r "$TOOLKIT/lib/." "$PERSIST/lib/" 2>/dev/null && echo "  lib/ copied to $PERSIST/lib/" || echo "  WARNING: lib/ could not be copied"
# v4.8.0: initialize mzd-data on USB root (logs/config/state/backups/runs)
# so data survives a delete of mzd-toolkit/ (reviewer point #1)
if [ -n "${USB_MOUNT:-}" ] && [ -d "$USB_MOUNT" ]; then
    mkdir -p "$USB_MOUNT/mzd-data/config" "$USB_MOUNT/mzd-data/state" "$USB_MOUNT/mzd-data/logs" "$USB_MOUNT/mzd-data/backups" "$USB_MOUNT/mzd-data/logs/runs" 2>/dev/null \
        && echo "  mzd-data/ created on $USB_MOUNT"
    # seed settings/secrets to mzd-data/config if they are in toolkit
    [ -f "$TOOLKIT/config/settings.conf" ] && [ ! -f "$USB_MOUNT/mzd-data/config/settings.conf" ] && cp "$TOOLKIT/config/settings.conf" "$USB_MOUNT/mzd-data/config/settings.conf" 2>/dev/null
    [ -f "$TOOLKIT/config/secrets.conf" ] && [ ! -f "$USB_MOUNT/mzd-data/config/secrets.conf" ] && cp "$TOOLKIT/config/secrets.conf" "$USB_MOUNT/mzd-data/config/secrets.conf" 2>/dev/null && chmod 600 "$USB_MOUNT/mzd-data/config/secrets.conf" 2>/dev/null
    # run.env cache
    cat > "$USB_MOUNT/mzd-data/config/run.env" 2>/dev/null <<EOF
USB_MOUNT="$USB_MOUNT"
TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit"
DATA_DIR="$USB_MOUNT/mzd-data"
BOOT8="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-8)"
EOF
fi
# F1 (v4.7.2 verify): USB health pre-flight at install
if [ -f "$PERSIST/lib/common.sh" ]; then
    . "$PERSIST/lib/common.sh" 2>/dev/null
    if type usb_health_check >/dev/null 2>&1; then usb_health_check || true; fi
fi
cp "$TOOLKIT/ssh/autorun" "$PERSIST/autorun" 2>/dev/null
# v4.8.20 BLOCKER FIX: start-ssh.sh as flat copy in $PERSIST cannot find ../lib/common.sh
# (lib is in $PERSIST/lib/, not $PERSIST/../lib/). Fix: patched copy with explicit path.
cat > "$PERSIST/start-ssh.sh" << 'STARTEOF'
#!/bin/sh
# v4.8.20: explicit lib paths for flat persist copy
for _lib in /data_persist/dev/bin/lib/common.sh /data_persist/dev/lib/common.sh; do
    [ -f "$_lib" ] && . "$_lib" 2>/dev/null && break
done
SCRIPT_DIR=$(dirname "$0")
for _src in "$SCRIPT_DIR/../mzd-toolkit/ssh/start.sh" /data_persist/mzd-toolkit/ssh/start.sh; do
    [ -f "$_src" ] && exec sh "$_src" "$@"
done
echo "ERROR: start.sh not found" >&2
exit 1
STARTEOF
chmod +x "$PERSIST/start-ssh.sh" 2>/dev/null
cp "$TOOLKIT/ssh/sshd_config" "$PERSIST/sshd_config" 2>/dev/null
cp "$TOOLKIT/ssh/stop.sh" "$PERSIST/stop-ssh.sh" 2>/dev/null
cp "$TOOLKIT/ssh/status.sh" "$PERSIST/ssh-status.sh" 2>/dev/null
cp "$TOOLKIT/ssh/test.sh" "$PERSIST/ssh-test.sh" 2>/dev/null

echo "Step 3: Copying WiFi scripts..."
cp "$TOOLKIT/wifi/connect.sh" "$PERSIST/wifi-connect.sh" 2>/dev/null
cp "$TOOLKIT/wifi/fix.sh" "$PERSIST/wifi-fix.sh" 2>/dev/null
cp "$TOOLKIT/wifi/status.sh" "$PERSIST/wifi-status.sh" 2>/dev/null
cp "$TOOLKIT/wifi/scan.sh" "$PERSIST/wifi-scan.sh" 2>/dev/null
cp "$TOOLKIT/wifi/disconnect.sh" "$PERSIST/wifi-disconnect.sh" 2>/dev/null

echo "Step 4: Copying system scripts..."
cp "$TOOLKIT/system/dump.sh" "$PERSIST/system-dump.sh" 2>/dev/null
cp "$TOOLKIT/system/info.sh" "$PERSIST/system-info.sh" 2>/dev/null
cp "$TOOLKIT/system/network.sh" "$PERSIST/network-diag.sh" 2>/dev/null
cp "$TOOLKIT/system/storage.sh" "$PERSIST/storage-info.sh" 2>/dev/null
cp "$TOOLKIT/system/process.sh" "$PERSIST/process-info.sh" 2>/dev/null
cp "$TOOLKIT/system/logs.sh" "$PERSIST/collect-logs.sh" 2>/dev/null
cp "$TOOLKIT/system/dmesg.sh" "$PERSIST/dmesg.sh" 2>/dev/null
cp "$TOOLKIT/system/hardware.sh" "$PERSIST/hardware-info.sh" 2>/dev/null

echo "Step 5: Copying net & tools scripts..."
cp "$TOOLKIT/net/autostart-eth1-ssh.sh" "$PERSIST/autostart-eth1-ssh.sh" 2>/dev/null
cp "$TOOLKIT/tools/install-autostart.sh" "$PERSIST/install-autostart.sh" 2>/dev/null
cp "$TOOLKIT/tools/install-ssh.sh" "$PERSIST/install-ssh.sh" 2>/dev/null
cp "$TOOLKIT/tools/fix-warning.sh" "$PERSIST/fix-warning.sh" 2>/dev/null
cp "$TOOLKIT/tools/backup.sh" "$PERSIST/backup.sh" 2>/dev/null
cp "$TOOLKIT/tools/cleanup.sh" "$PERSIST/cleanup.sh" 2>/dev/null
cp "$TOOLKIT/tools/vehicle-data.sh" "$PERSIST/vehicle-data.sh" 2>/dev/null

echo "Step 6: Making executable..."
chmod +x "$PERSIST"/*.sh 2>/dev/null
chmod +x "$PERSIST"/autorun 2>/dev/null

echo "Step 7: Generating host key..."
if [ ! -f "$PERSIST/ssh_host_rsa_key" ]; then
    ssh-keygen -t rsa -f "$PERSIST/ssh_host_rsa_key" -N "" -q
    echo "  Host key created"
else
    echo "  Host key already exists"
fi

echo "Step 8: Patching stage_wifi.sh + stage_1.sh - autorun hook, idempotent..."
# v4.8.3: hook in BOTH scripts (stage_wifi.sh was empty in 11:40 dump due to
# overwrite by fix-warning.sh); backup .org per script.
for STAGE_SCRIPT in /jci/scripts/stage_wifi.sh /jci/scripts/stage_1.sh; do
    if [ -f "$STAGE_SCRIPT" ]; then
        if grep -q "data_persist/dev/bin/autorun" "$STAGE_SCRIPT" 2>/dev/null; then
            echo "  $STAGE_SCRIPT: already hooked"
        else
            cp "$STAGE_SCRIPT" "$STAGE_SCRIPT.org" 2>/dev/null
            mount -o remount,rw /jci 2>/dev/null
            TMPF=$(mktemp 2>/dev/null || echo "/tmp/stage_hook.$$")
            {
                echo "# MZD-AUTORUN HOOK"
                echo "if [ -x \"$PERSIST_ROOT/dev/bin/autorun\" ]; then"
                echo "    \"$PERSIST_ROOT/dev/bin/autorun\" &"
                echo "fi"
                cat "$STAGE_SCRIPT" 2>/dev/null
            } > "$TMPF"
            if cp "$TMPF" "$STAGE_SCRIPT" 2>/dev/null; then
                rm -f "$TMPF"
                echo "  $STAGE_SCRIPT: hook added"
            else
                rm -f "$TMPF"
                echo "  $STAGE_SCRIPT: could not patch - read-only?"
            fi
        fi
    else
        echo "  $STAGE_SCRIPT not found"
    fi
done

echo "Step 9: Applying warning fix..."
echo "1" > "$PERSIST_ROOT/aio/warning_ack" 2>/dev/null
echo "1" > "$PERSIST/no_warn" 2>/dev/null

cat > "$PERSIST_ROOT/aio/tweaks/no_warn.conf" << 'EOF'
NO_STARTUP_WARNING=1
NO_DISCLAIMER=1
NO_MODIFIED_WARNING=1
EOF

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

echo "Step 10: Starting WiFi and SSH..."
# ============================================================
# M6 (v4.7.2, gate a1b9ce9): brick-risk guard.
# Backup original autorun BEFORE we overwrite it, and write a
# wrapper with fail-counter in /tmp: if toolkit start fails 3x in
# a row, autorun.orig is restored (fail-safe).
# ============================================================
if [ -f "$PERSIST/autorun" ] && [ ! -f "$PERSIST/autorun.orig" ]; then
    cp "$PERSIST/autorun" "$PERSIST/autorun.orig" 2>/dev/null && echo "  Original autorun backed up to autorun.orig"
fi
# Update autorun: v4.8.8 copies the CURRENT ssh/autorun (PERSIST-first, v4.8.7+).
# The old inline heredoc (v4.7.2) overwrote the new autorun -> boot started
# the old USB-based version. Never write inline again.
cp "$TOOLKIT/ssh/autorun" "$PERSIST/autorun" 2>/dev/null && echo "  autorun (v4.8.8 PERSIST-first) copied" || echo "  WARNING: autorun copy failed"
chmod +x "$PERSIST/autorun" 2>/dev/null

# Start now

# Start now
sh "$PERSIST/wifi-connect.sh" 2>/dev/null || echo "WiFi connect script not started"
sleep 5
sh "$PERSIST/start-ssh.sh" 2>/dev/null || echo "SSH start script not started"

echo ""
echo "========================================"
echo " INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "Installed in: $PERSIST"
echo ""
ls -la "$PERSIST"
echo ""
echo "Shortcuts:"
echo "  Menu:      sh $PERSIST/menu.sh"
echo "  WiFi:      sh $PERSIST/wifi-connect.sh"
echo "  SSH start: sh $PERSIST/start-ssh.sh"
echo "  SSH test:  sh $PERSIST/ssh-test.sh"
echo "  System:    sh $PERSIST/system-info.sh"
echo "  Dump:      sh $PERSIST/system-dump.sh"
echo ""
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -n "$IP" ]; then
    echo "IP address: $IP"
    echo "SSH port 36000: ssh -p 36000 cmu@$IP -i $PERSIST/../mzd-toolkit/ssh/id_mzd  - pubkey"
    echo "                   or with password from config/secrets.conf"
else
    echo "WiFi not connected - run wifi/connect-nms.sh"
fi
echo ""
echo "Restart the car to test the permanent installation."
