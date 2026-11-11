#!/bin/sh
# MZD Toolkit - WiFi Debug v74
# Extensive diagnostics based on firmware v74 analysis
# Collects ALL WiFi info to USB log

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 item 5.3: log fw/driver version in every wifi run
# v4.8.1: log to $LOG_DIR (= $DATA_DIR/logs = mzd-data/logs on USB root)
LOG_DIR="${LOG_DIR:-$TOOLKIT_DIR/logs}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/wifi-debug-$TIMESTAMP.txt"

echo "========================================"
echo " WiFi Debug v74"
echo "========================================"
echo ""
echo "Log: $LOG_FILE"
echo ""

# Create log directory
mkdir -p "$LOG_DIR" 2>/dev/null

# Log functie
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log "=== MZD WiFi Debug v74 ==="
log "Date: $(date)"
log "Timestamp: $TIMESTAMP"
log ""

log "=== 1. Interface Status ==="
ifconfig -a 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 2. Wireless Status (wifi-compat; iwconfig/iwlist do NOT exist on MZD) ==="
wifi_status wlan0 2>&1 | tee -a "$LOG_FILE"
log ""
log "=== 2b. wl12xx deadlock check (M1b) ==="
wifi_deadlock_check 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 3. Kernel Modules (WiFi) ==="
cat /proc/modules 2>&1 | grep -E "rfkill|compat|cfg80211|mac80211|wl12xx|wlcore|ti" | tee -a "$LOG_FILE"
log "All modules:"
cat /proc/modules 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 4. wpa_supplicant Process ==="
ps 2>&1 | grep -E "wpa|dhcp|wifi" | tee -a "$LOG_FILE"
log ""

log "=== 5. wpa_supplicant Status ==="
wpactrl status 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 6. wpa_supplicant Scan (wifi_scan, run_with_timeout) ==="
run_with_timeout "wpactrl scan" 15 2>&1 | tee -a "$LOG_FILE"
sleep 3
run_with_timeout "wpactrl scan_results" 15 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 7. WiFi Firmware Files ==="
ls -la /lib/firmware/ti-connectivity/ 2>&1 | tee -a "$LOG_FILE"
log ""
log "NVS calibration:"
ls -la /lib/firmware/ti-connectivity/wl1271-nvs.bin 2>&1 | tee -a "$LOG_FILE"
if [ -L /lib/firmware/ti-connectivity/wl1271-nvs.bin ]; then
    target=$(readlink /lib/firmware/ti-connectivity/wl1271-nvs.bin)
    log "NVS symlink target: $target"
    log "Target exists: $([ -f "$target" ] && echo 'YES' || echo 'NO')"
    if [ -f "$target" ]; then
        log "NVS size: $(wc -c < "$target") bytes"
        log "NVS first bytes:"
        od -A x -t x1 "$target" 2>/dev/null | head -4 | tee -a "$LOG_FILE"
    fi
fi
log ""

log "=== 8. rfkill Status ==="
for r in /sys/class/rfkill/rfkill*; do
    if [ -d "$r" ]; then
        log "rfkill: $(cat $r/name 2>/dev/null) soft=$(cat $r/soft 2>/dev/null) hard=$(cat $r/hard 2>/dev/null)"
    fi
done 2>/dev/null
log ""

log "=== 9. Network Routes ==="
route -n 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 10. ARP Table ==="
cat /proc/net/arp 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 11. Wireless Stats ==="
for f in /sys/class/net/wlan0/statistics/*; do
    if [ -f "$f" ]; then
        log "$(basename $f): $(cat $f 2>/dev/null)"
    fi
done 2>/dev/null
log ""

log "=== 12. Kernel Messages (WiFi) ==="
dmesg 2>&1 | grep -i -E "wlan|wifi|wl12xx|wl1271|sdio|ti-connectivity|firmware|rfkill" | tee -a "$LOG_FILE"
log ""
log "=== Kernel Messages (USB) ==="
dmesg 2>&1 | grep -i -E "usb|sd[a-z]|mmc" | tail -10 | tee -a "$LOG_FILE"
log ""

log "=== 13. Config Files ==="
log "--- /etc/wpa_supplicant.conf ---"
# SECURITY (review M2): psk filteren uit logs
grep -v 'psk=' /etc/wpa_supplicant.conf 2>&1 | tee -a "$LOG_FILE"
log ""
log "--- /etc/wpa_supplicant.bak ---"
grep -v 'psk=' /etc/wpa_supplicant.bak 2>&1 | tee -a "$LOG_FILE"
log ""
log "--- /tmp/wpa_supplicant.conf ---"
grep -v 'psk=' /tmp/wpa_supplicant.conf 2>&1 | tee -a "$LOG_FILE"
log ""
log "--- /etc/resolv.conf ---"
cat /etc/resolv.conf 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 14. stage_wifi.sh ==="
cat /jci/scripts/stage_wifi.sh 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 15. IP Configuration ==="
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
log "IP address: ${IP:-NONE}"
log ""

log "=== 16. Ping Tests ==="
GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
log "Gateway: ${GW:-none}"
if [ -n "$GW" ]; then
    ping -c 3 -W 3 "$GW" 2>&1 | tee -a "$LOG_FILE"
fi
log ""
log "DNS (8.8.8.8):"
ping -c 2 -W 3 8.8.8.8 2>&1 | tee -a "$LOG_FILE"
log ""

log "=== 17. Available Commands ==="
log "WiFi: wifi_status/wifi_scan (wpactrl, /sys, ifconfig), wpa_supplicant, udhcpc"
log "ON MZD: iwconfig/iwlist NOT available - use wifi-compat.sh (v4.7.2 M1)"
log "Network: route, netstat, arp, ping, iptables"
log "System: ps, dmesg, lsmod, cat /proc/*"
log ""

log "=== Debug Complete ==="
log "End: $(date)"

echo ""
echo "========================================"
echo " Debug log saved"
echo "========================================"
echo ""
echo "Log file: $LOG_FILE"
echo "Size: $(wc -c < "$LOG_FILE") bytes"
echo "Lines: $(wc -l < "$LOG_FILE")"
echo ""
echo "Last 20 lines:"
tail -20 "$LOG_FILE"
