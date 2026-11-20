#!/bin/sh
# MZD Toolkit - Copy Logs to USB (SIMPLE)
# Copy ALL logs to USB in one go - for quick debug

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
detect_usb || true
if [ -z "$USB_MOUNT" ] || [ ! -d "$USB_MOUNT" ]; then
    for dev in /tmp/mnt/sdb1 /tmp/mnt/sda1 /tmp/mnt/sdc1 /tmp/mnt/sdd1 /mnt/sdb1 /mnt/sda1 /tmp/mnt/sd* /mnt/sd*; do
        [ -d "$dev" ] || continue
        case "$dev" in *nav*) continue ;; esac
        mount -o remount,rw "$dev" 2>/dev/null
        if touch "$dev/.rwtest-$$" 2>/dev/null; then
            rm -f "$dev/.rwtest-$$"
            USB_MOUNT="$dev"
            break
        fi
    done
fi
[ -n "$USB_MOUNT" ] || { echo "ERROR: no writable USB drive found in /tmp/mnt/ or /mnt/ (stick plugged in?)"; ls -la /tmp/mnt/ 2>/dev/null; exit 1; }
ensure_usb_rw || log_to_usb "copy-logs-usb.sh: USB not rw after fix attempt"
USB="$USB_MOUNT"
log_to_usb "copy-logs-usb.sh started (USB=$USB)"

echo "========================================"
echo " Copy Logs to USB"
echo "========================================"
echo ""

LOGDIR="$USB/mzd-logs-$(date +%Y%m%d-%H%M%S)"

echo "USB: $USB"
echo "Log dir: $LOGDIR"
echo ""

# Check USB
if [ ! -d "$USB" ]; then
    echo "ERROR: $USB not found!"
    ls /tmp/mnt/
    exit 1
fi

# Force USB rw (via common.sh)
ensure_usb_rw || echo "WARNING: USB could not be made rw"

mkdir -p "$LOGDIR"
echo "Directory created: $LOGDIR"
echo ""

echo "Copying logs..."

# dmesg
dmesg > "$LOGDIR/dmesg.txt" 2>&1
echo "  dmesg.txt ($(wc -c < "$LOGDIR/dmesg.txt") bytes)"

# dmesg WiFi only
dmesg 2>/dev/null | grep -i -E "wlan|wifi|wl12xx|sdio" > "$LOGDIR/dmesg-wifi.txt"
echo "  dmesg-wifi.txt ($(wc -c < "$LOGDIR/dmesg-wifi.txt") bytes)"

# /tmp logs
for f in /tmp/*.log; do
    if [ -f "$f" ]; then
        cp "$f" "$LOGDIR/" 2>/dev/null
        echo "  $(basename $f)"
    fi
done

# v4.8.8/4.8.9: persist logs + runs copied to USB as well
for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
    if [ -d "$PP/mzd-data/logs" ]; then
        echo "  persist logs from $PP/mzd-data/logs -> persist-logs/"
        mkdir -p "$LOGDIR/persist-logs"
        cp -r "$PP/mzd-data/logs/." "$LOGDIR/persist-logs/" 2>/dev/null
        [ -f /tmp/mzd-autorun.log ] && cp /tmp/mzd-autorun.log "$LOGDIR/autorun.log" 2>/dev/null && echo "  autorun.log"
        break
    fi
done

# Configs
for f in /etc/wpa_supplicant.conf /etc/wpa_supplicant.bak /etc/resolv.conf /jci/scripts/stage_wifi.sh; do
    if [ -f "$f" ]; then
        cp "$f" "$LOGDIR/$(basename $f)" 2>/dev/null
        echo "  config: $(basename $f)"
    fi
done

# Network info
ifconfig -a > "$LOGDIR/ifconfig.txt" 2>&1
echo "  ifconfig.txt"

# v4.7.2 M1: iwconfig does NOT exist on MZD - use wifi_status (wpactrl + /sys + ifconfig)
wifi_status wlan0 > "$LOGDIR/wifi-status-compat.txt" 2>&1
echo "  wifi-status-compat.txt"
wifi_deadlock_check > "$LOGDIR/wl12xx-deadlock-check.txt" 2>&1 || true  # M1b
echo "  wl12xx-deadlock-check.txt"

route -n > "$LOGDIR/route.txt" 2>&1
echo "  route.txt"

netstat -tln > "$LOGDIR/netstat.txt" 2>&1
echo "  netstat.txt"

wpactrl status > "$LOGDIR/wpa-status.txt" 2>&1
echo "  wpa-status.txt"

wpactrl scan_results > "$LOGDIR/wpa-scan.txt" 2>&1
echo "  wpa-scan.txt"

ps > "$LOGDIR/ps.txt" 2>&1
echo "  ps.txt"

cat /proc/modules > "$LOGDIR/modules.txt" 2>&1
echo "  modules.txt"

ls -la /lib/firmware/ti-connectivity/ > "$LOGDIR/firmware.txt" 2>&1
echo "  firmware.txt"

# Create archive (v4.7.2 M4/R8: TAR.GZ primary - MZD busybox has tar but no zip)
cd "$USB" || exit 1
echo ""
echo "Creating TAR.GZ..."
if command -v tar > /dev/null 2>&1; then
    tar -czf "mzd-logs-$(date +%Y%m%d-%H%M%S).tar.gz" "$(basename $LOGDIR)" 2>&1
    echo "TAR.GZ: $USB/mzd-logs-*.tar.gz"
elif command -v zip > /dev/null 2>&1; then
    zip -r "mzd-logs-$(date +%Y%m%d-%H%M%S).zip" "$(basename $LOGDIR)" 2>&1
    echo "ZIP (PC only): $USB/mzd-logs-*.zip"
fi

echo ""
echo "========================================"
echo " Done!"
echo "========================================"
echo "Logs in: $LOGDIR"
ls -la "$LOGDIR"
