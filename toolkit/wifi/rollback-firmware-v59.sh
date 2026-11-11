#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/rollback-firmware-v59.sh (v4.8.2)
# Restores the original v59 wl128x firmware (Rev 7.3.10.10.136) from the
# backup that upgrade-firmware-v74.sh made (*.v59-backup-*).
#
# WHEN: if the v74 patch (FRev 7.3.10.0.142) keeps giving wl12xx watchdog interrupts
# (proven 2026-11-03 11h: 5x "watchdog interrupt" in FIX-ALL r14,
# despite ps=off). v59 was more stable w.r.t. ELP-sleep.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

FW_DIR="/lib/firmware/ti-connectivity"
FW="$FW_DIR/wl128x-fw-4-sr.bin"

echo "========================================"
echo " Rollback WiFi firmware to v59 (v4.8.2)"
echo "========================================"
echo ""

BK=$(ls -t "$FW_DIR"/wl128x-fw-4-sr.bin.v59-backup-* 2>/dev/null | head -1)
if [ -z "$BK" ]; then
    echo "ERROR: no v59 backup found in $FW_DIR (wl128x-fw-4-sr.bin.v59-backup-*)"
    ls -la "$FW_DIR"/wl128x-fw-4-sr.bin* 2>/dev/null
    exit 1
fi
echo "Backup found: $BK"
echo "Current fw: $(sha256sum "$FW" 2>/dev/null | awk '{print $1}')"
echo "Backup fw: $(sha256sum "$BK" 2>/dev/null | awk '{print $1}')"
echo ""

# /lib/firmware is read-only? -> remount rw
mount 2>/dev/null | grep -q " on /lib " && mount -o remount,rw /lib 2>/dev/null
mount 2>/dev/null | grep -q " on / " && mount -o remount,rw / 2>/dev/null

cp "$BK" "$FW" 2>/dev/null && echo "v59 firmware restored" || { echo "ERROR: could not overwrite $FW (read-only?)"; exit 1; }

# reload driver
rmmod wl12xx_sdio wl12xx 2>/dev/null
sleep 2
insmod /lib/modules/$(uname -r 2>/dev/null)/kernel/drivers/net/wireless/ti/wl12xx/wl12xx_sdio.ko 2>/dev/null || modprobe wl12xx_sdio 2>/dev/null
sleep 3
ifconfig wlan0 up 2>/dev/null

echo ""
echo "dmesg after reload (expect Rev 7.3.10.10.136):"
dmesg 2>/dev/null | grep -E "firmware booted|wl12xx.*Rev" | tail -3
echo ""
echo "Done. Check watchdog-count: dmesg | grep -c 'watchdog interrupt'"
echo "========================================"
