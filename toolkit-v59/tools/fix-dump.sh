#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Fix Dump (alternative version)
# Writes dump files step by step, even if /tmp is full
# Uses USB directly, not /tmp

TOOLKIT_DIR="${TOOLKIT_DIR:-}"
LOG_DIR="${LOG_DIR:-$TOOLKIT_DIR/logs}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_DIR="$LOG_DIR/dump-$TIMESTAMP"

echo "========================================"
echo " MZD Dump v2 (USB direct)"
echo "========================================"
echo ""

# Check USB
if [ ! -d "$LOG_DIR" ]; then
    echo "ERROR: $LOG_DIR does not exist!"
    echo "Check USB mount:"
    ls -la /tmp/mnt/
    exit 1
fi

# Force USB rw
for dev in /tmp/mnt/sd*; do
    if [ -d "$dev" ]; then
        if ! touch "$dev/.rw_test" 2>/dev/null; then
            echo "USB $dev is read-only, fixing..."
            umount "$dev" 2>/dev/null
            sleep 1
            REAL_DEV="/dev/$(basename $dev)"
            mount -o rw "$REAL_DEV" "$dev" 2>/dev/null
            sleep 1
        fi
        rm -f "$dev/.rw_test" 2>/dev/null
    fi
done

# Create dump directory
mkdir -p "$DUMP_DIR" 2>/dev/null
if [ ! -d "$DUMP_DIR" ]; then
    echo "ERROR: cannot create $DUMP_DIR!"
    exit 1
fi

echo "Dump directory: $DUMP_DIR"
echo ""

# Function to write command output to file
run_cmd() {
    local fname="$1"
    local cmd="$2"
    echo -n "  $fname... "
    eval "$cmd" > "$DUMP_DIR/$fname" 2>&1
    local size=$(wc -c < "$DUMP_DIR/$fname" 2>/dev/null || echo 0)
    echo "($size bytes)"
}

echo "Collecting info..."
echo ""

# Basic info
run_cmd "01-basic.txt" "echo 'User: '$(whoami); echo 'Host: '$(hostname); echo 'Date: '$(date); echo 'Uname: '$(uname -a); echo 'Firmware:'; cat /jci/version.ini 2>&1"

# Network
# v4.7.2 M1: iwconfig removed (does NOT exist on MZD); wifi_status via wifi-compat
run_cmd "02-network.txt" "ifconfig -a; echo '---'; wifi_status wlan0; echo '---'; route -n; echo '---'; netstat -tln; echo '---'; cat /proc/net/arp"

# Storage
run_cmd "03-storage.txt" "df -h; echo '---'; mount; echo '---'; ls -la /tmp/mnt/; for d in /tmp/mnt/*; do echo \"Mount: \$d\"; touch \"\$d/.test\" 2>/dev/null && echo 'RW' && rm \"\$d/.test\" || echo 'RO'; ls -la \"\$d\" | head -10; done"

# Processes
run_cmd "04-processes.txt" "ps; echo '---'; ps aux 2>&1"

# Configs
run_cmd "05-configs.txt" "cat /etc/wpa_supplicant.conf 2>&1; echo '---'; cat /etc/resolv.conf 2>&1; echo '---'; cat /jci/scripts/stage_wifi.sh 2>&1; echo '---'; ls -la /etc/ssh/ 2>&1"

# Logs
run_cmd "06-logs.txt" "dmesg 2>&1 | tail -100; echo '---WIFI---'; dmesg 2>&1 | grep -i wlan; echo '---USB---'; dmesg 2>&1 | grep -i usb"

# Hardware
run_cmd "07-hardware.txt" "cat /proc/cpuinfo; echo '---'; cat /proc/meminfo; echo '---'; cat /proc/modules"

# Firewall
run_cmd "08-firewall.txt" "iptables -L -n 2>&1; echo '---'; iptables -L -n -v 2>&1"

# WiFi debug
# v4.7.2 M1+M1b: iwconfig vervangen door wifi_status + deadlock check
run_cmd "09-wifi.txt" "wifi_status wlan0 2>&1; echo '---'; wifi_deadlock_check; echo '---'; ifconfig wlan0 2>&1"

# Environment
run_cmd "10-env.txt" "env; echo '---'; echo PATH=\$PATH; echo '---'; ls /bin /sbin /usr/bin 2>&1 | head -50"

# SSH status
run_cmd "11-ssh.txt" "ps | grep ssh; echo '---'; netstat -tln | grep 22; echo '---'; ls -la /mnt/data_persist/dev/bin/ 2>&1"

# Copy specific files (if they exist)
echo ""
echo "Copying specific files..."
for f in /etc/wpa_supplicant.conf /etc/resolv.conf /jci/scripts/stage_wifi.sh /jci/version.ini /tmp/wpa_supplicant.conf /tmp/wpa.conf; do
    if [ -f "$f" ]; then
        safe_name=$(echo "$f" | tr "/" "_")
        cp "$f" "$DUMP_DIR/file$safe_name" 2>/dev/null && echo "  -> file$safe_name"
    fi
done

# Create archive (v4.7.2 M4/R8: TAR.GZ primary - MZD busybox has tar but no zip)
cd "$LOG_DIR" || exit 1
echo ""
echo "Creating TAR.GZ archive (primary)..."
if command -v tar > /dev/null 2>&1; then
    tar -czf "mzd-dump-$TIMESTAMP.tar.gz" "dump-$TIMESTAMP" 2>&1
    echo "TAR.GZ created: mzd-dump-$TIMESTAMP.tar.gz"
elif command -v zip > /dev/null 2>&1; then
    zip -r "mzd-dump-$TIMESTAMP.zip" "dump-$TIMESTAMP" 2>&1
    echo "ZIP created (PC only): mzd-dump-$TIMESTAMP.zip"
else
    echo "No tar/zip available, files are in:"
    echo "  $DUMP_DIR"
fi

echo ""
echo "========================================"
echo " DUMP COMPLETE"
echo "========================================"
echo ""
ls -la "$DUMP_DIR"
echo ""
ls -la "$LOG_DIR"/mzd-dump-*.zip "$LOG_DIR"/mzd-dump-*.tar.gz 2>/dev/null || true
