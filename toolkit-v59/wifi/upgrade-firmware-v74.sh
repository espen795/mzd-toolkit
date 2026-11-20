#!/bin/sh
# ============================================================
# MZD Toolkit - upgrade-firmware-v74.sh
# Upgrade WL1271 station-role firmware from v59 to v74 build
#
# v59 runs:   Rev 7.3.10.10.136  (wl128x-fw-4-sr.bin)
# v74 has:    FRev 7.3.10.0.142   (wl128x-fw-4-sr.bin - NEWER)
#
# WARNING: wl1271-nvs.bin is BOARD-SPECIFIC (calibration data)
# and must NEVER be overwritten! Only the fw-4-sr.bin is
# replaced.
#
# Source: v74 extract in ${TOOLKIT_DIR}/../mazda-firmware-analysis/
#         or copy manually to USB:
#   ${TOOLKIT_DIR}/wifi/v74-firmware/wl128x-fw-4-sr.bin
#
# Works on: Mazda CMU v59, BusyBox sh
# ============================================================

# Source shared library (with fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

FW_DIR="/lib/firmware/ti-connectivity"
SRC_DIR="${TOOLKIT_DIR}/wifi/v74-firmware"
[ ! -d "$SRC_DIR" ] && SRC_DIR="${TOOLKIT_DIR}/wifi/v74-firmware"
NEW_FW="$SRC_DIR/wl128x-fw-4-sr.bin"
LOG="/tmp/mnt/data_persist/mzd-toolkit-logs/upgrade-fw-$(date +%s).log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

log() { echo "$*" | tee -a "$LOG" 2>/dev/null; echo "$*"; }

log "========================================"
log " MZD upgrade-firmware-v74.sh - $(date)"
log "========================================"

# --- Check current firmware version ---
log ""
log "[1/6] Checking current firmware version..."
dmesg 2>/dev/null | grep "firmware booted" | tail -1 | tee -a "$LOG"

# --- Check source file ---
log ""
log "[2/6] Source firmware file: $NEW_FW"
if [ ! -f "$NEW_FW" ]; then
    log "ERROR: $NEW_FW not found!"
    log "First copy wl128x-fw-4-sr.bin from the v74 extract to:"
    log "  $SRC_DIR/wl128x-fw-4-sr.bin"
    log "(v74 extract: mazda-firmware-analysis/extracted/v74_extracted/rootfs/extracted_rootfs/lib/firmware/ti-connectivity/wl128x-fw-4-sr.bin)"
    exit 1
fi
log "  Source found: $(ls -la "$NEW_FW" | awk '{print $5}') bytes"

# M4 (review): log SHA256 checksum of source file + verify against known-good
SRC_SHA=$(sha256sum "$NEW_FW" 2>/dev/null | awk '{print $1}')
log "  SHA256 source: ${SRC_SHA:-unknown}"
# Known-good hash for v74 FRev 7.3.10.0.142 (fill in after first deploy!)
KNOWN_GOOD_SHA="${MZD_FW_SHA256:-b1981c5f9448a71ff9854b1057efb86eae56749cb69195a3506c6e74f7c00fa6}"
if [ -n "$KNOWN_GOOD_SHA" ]; then
    if [ "$SRC_SHA" = "$KNOWN_GOOD_SHA" ]; then
        log "  -> checksum OK (matches known-good)"
    else
        log "  -> ERROR: checksum mismatch! Source corrupt?"
        log "  Expected: $KNOWN_GOOD_SHA"
        log "  Found: $SRC_SHA"
        exit 1
    fi
else
    log "  -> WARNING: no known-good hash - source hash above is now the reference"
fi

# Check version in source
log "  Version in source file:"
strings "$NEW_FW" 2>/dev/null | grep -i "FRev" | head -1 | tee -a "$LOG"

# --- Backup current firmware ---
log ""
log "[3/6] Backing up current firmware..."
if [ -f "$FW_DIR/wl128x-fw-4-sr.bin" ]; then
    cp "$FW_DIR/wl128x-fw-4-sr.bin" "$FW_DIR/wl128x-fw-4-sr.bin.v59-backup-$(date +%s)" 2>/dev/null && \
        log "  -> backup made: wl128x-fw-4-sr.bin.v59-backup-*" || \
        log "  -> backup FAILED (read-only fs?) - check mount"
else
    log "  -> no existing sr.bin found"
fi

# IMPORTANT: do NOT touch NVS calibration!
if [ -L "$FW_DIR/wl1271-nvs.bin" ]; then
    log "  NVS symlink: $(readlink $FW_DIR/wl1271-nvs.bin) - LEFT UNTOUCHED"
elif [ -f "$FW_DIR/wl1271-nvs.bin" ]; then
    log "  NVS file present - LEFT UNTOUCHED (board calibration!)"
fi

# --- Copy new firmware ---
log ""
log "[4/6] Installing new firmware..."
# Try rw remount if needed
mount -o remount,rw / 2>/dev/null
mount -o remount,rw /lib/firmware 2>/dev/null
if cp "$NEW_FW" "$FW_DIR/wl128x-fw-4-sr.bin" 2>/dev/null; then
    log "  -> wl128x-fw-4-sr.bin vervangen door v74 build (FRev 7.3.10.0.142)"
else
    log "  -> direct copy failed, trying via /tmp..."
    cp "$NEW_FW" /tmp/wl128x-fw-4-sr.bin.new 2>/dev/null && \
        cat /tmp/wl128x-fw-4-sr.bin.new > "$FW_DIR/wl128x-fw-4-sr.bin" 2>/dev/null && \
        log "  -> installed via cat redirect" || \
        log "  -> ERROR: could not write firmware (fs read-only?)"
fi

# M4 (review): verify the copy is byte-identical (cmp)
if cmp -s "$NEW_FW" "$FW_DIR/wl128x-fw-4-sr.bin" 2>/dev/null; then
    log "  -> VERIFICATION OK: copied firmware is byte-identical to source (cmp)"
else
    log "  -> WARNING: cmp shows difference after copy - file possibly corrupt!"
fi

# --- Restart WiFi to load new firmware ---
# v4.7.5 M4 (gate 0046b92): NEVER killall wpa_supplicant - it belongs to NMS
# (PID 2402/3432, -c /data/nms/wpa_supplicant-wlan0.conf). Killing breaks NMS and WiFi.
log ""
log "[5/6] Restarting WiFi (module reload; NMS wpa_supplicant keeps running)..."
# Only kill udhcpc if it belongs to the toolkit, NEVER NMS's
for _up in $(pidof udhcpc 2>/dev/null); do
    case "$(cat /proc/$_up/cmdline 2>/dev/null | tr '\0' ' ')" in
        *mzd-toolkit*|*/tmp/*) kill "$_up" 2>/dev/null && log "  toolkit-udhcpc $_up killed" ;;
        *) log "  udhcpc $_up belongs to NMS - NOT killing" ;;
    esac
done
sleep 1
ifconfig wlan0 down 2>/dev/null
sleep 2

# Module path dynamic (v4.7.5), fallback hardcoded 3.0.35
MODBASE="/lib/modules/$(uname -r 2>/dev/null || echo 3.0.35)/kernel/drivers/net/wireless/ti/wl12xx"
[ -d "$MODBASE" ] || MODBASE="/lib/modules/3.0.35/kernel/drivers/net/wireless/wl12xx"
# Module reload (correct order: sdio off first, then core)
rmmod wl12xx_sdio 2>/dev/null
rmmod wl12xx 2>/dev/null
sleep 2
insmod "$MODBASE/wl12xx.ko" 2>/dev/null || modprobe wl12xx 2>/dev/null
insmod "$MODBASE/wl12xx_sdio.ko" 2>/dev/null || modprobe wl12xx_sdio 2>/dev/null
sleep 3
ifconfig wlan0 up 2>/dev/null
sleep 2

# v4.7.5: explicit NMS re-init - wpa_supplicant does not restart by itself after rmmod/insmod
log "  NMS re-init via D-Bus WIFI_Recovery..."
if [ -S /tmp/dbus_service_socket ]; then
    dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_Recovery 2>&1 | head -3 | tee -a "$LOG"
fi
sleep 2
if ! pgrep -f "wpa_supplicant.*wlan0" > /dev/null 2>&1; then
    log "  wpa_supplicant NOT alive after reload - NMS mode-toggle (0 then 1)..."
    if [ -S /tmp/dbus_service_socket ]; then
        IFCID=$(dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.GetInterfaceList 2>/dev/null | grep -oE 'int32 [0-9]+' | awk '{print $2}' | tail -1)
        if [ -n "$IFCID" ]; then
            dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_SetMode int32:$IFCID int32:0 > /dev/null 2>&1
            sleep 1
            dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_SetMode int32:$IFCID int32:1 > /dev/null 2>&1
        fi
    fi
fi

# Boot-fail detection (v4.7.5): no "firmware booted" in recent dmesg -> auto-restore backup
if ! dmesg 2>/dev/null | tail -50 | grep -q "firmware booted"; then
    for BK in "$FW_DIR"/wl128x-fw-4-sr.bin.v59-backup-*; do
        [ -f "$BK" ] || continue
        log "  BOOT-FAIL: no 'firmware booted' after insmod - auto-restore $BK"
        cp "$BK" "$FW_DIR/wl128x-fw-4-sr.bin" 2>/dev/null
        rmmod wl12xx_sdio 2>/dev/null; rmmod wl12xx 2>/dev/null; sleep 2
        insmod "$MODBASE/wl12xx.ko" 2>/dev/null; insmod "$MODBASE/wl12xx_sdio.ko" 2>/dev/null
        ifconfig wlan0 up 2>/dev/null
        break
    done
fi

log ""
log "[6/6] Verification - new firmware version:"
dmesg 2>/dev/null | grep -E "firmware booted|wl12xx.*Rev" | tail -3 | tee -a "$LOG"

# v4.7.5: do NOT start our own wpa_supplicant - reconnect via NMS (connect-nms.sh)
TR="${TOOLKIT_ROOT:-${TOOLKIT_DIR}}"
[ -d ${TOOLKIT_DIR} ] && TR="${TOOLKIT_DIR}"
if [ -n "${WIFI_SSID:-}" ] && [ -f "$TR/wifi/connect-nms.sh" ]; then
    log "  Reconnect via NMS: $WIFI_SSID"
    WIFI_SSID="$WIFI_SSID" WIFI_PASSWORD="${WIFI_PASSWORD:-}" sh "$TR/wifi/connect-nms.sh" "$WIFI_SSID" "${WIFI_PASSWORD:-}" >> "$LOG" 2>&1
fi
if command -v wpactrl > /dev/null 2>&1; then
    wpactrl set power_save off 2>/dev/null
fi

# NOTE (v4.7.5 gate R3): this is a 24-48h A/B measurement, not a direct pass/fail -
# watchdogs only trigger 58-290s after associate (proven wifi-debug-002743.txt)
log "  watchdog count now: $(dmesg 2>/dev/null | grep -c 'watchdog interrupt')  (measure again after 24-48h!)"
if command -v wifi_deadlock_check > /dev/null 2>&1; then
    wifi_deadlock_check >> "$LOG" 2>&1 && log "  deadlock check: clean" || log "  deadlock check: SIGNATURE FOUND (see log)"
fi

log ""
log "========================================"
log " Firmware upgrade completed"
log " New version should be: FRev 7.3.10.0.142"
log " Watchdog test: dmesg | grep watchdog"
log " Log: $LOG"
log "========================================"
