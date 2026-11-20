#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/rollback-driver-v59.sh (v4.8.5)
# Restores the original v59 wl12xx driver from the backup that
# swap-driver-v74.sh created ($BACKUP_DIR/wl12xx-v59/*.v59).
# Chip firmware is NOT touched (it is separate from the driver).
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

KREL=$(uname -r 2>/dev/null || echo "3.0.35")
CAND=""
for p in "/lib/modules/$KREL/kernel/drivers/net/wireless/ti/wl12xx" \
         "/lib/modules/$KREL/kernel/drivers/net/wireless/wl12xx"; do
    [ -f "$p/wl12xx.ko" ] && CAND="$p" && break
done
STATE_DIR="${STATE_DIR:-/tmp/toolkit-state}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/toolkit-backups}"
BK="$BACKUP_DIR/wl12xx-v59"
# fallback: USB backup
[ -f "$BK/wl12xx.ko.v59" ] || BK="${USB_MOUNT:-/tmp/mnt}/mzd-data/backups/wl12xx-v59"

echo "========================================"
echo " Rollback wl12xx driver -> v59 (v4.8.5)"
echo "========================================"

[ -f "$BK/wl12xx.ko.v59" ] || { echo "ERROR: no v59 backup in $BK"; ls -la "$BK" 2>/dev/null; exit 1; }
[ -n "$CAND" ] || { echo "ERROR: module dir not found"; exit 1; }

mount 2>/dev/null | grep -q " on / " && mount -o remount,rw / 2>/dev/null
mount 2>/dev/null | grep -q " on /lib " && mount -o remount,rw /lib 2>/dev/null
touch "$CAND/.rw-test" 2>/dev/null && rm -f "$CAND/.rw-test" || { echo "ERROR: $CAND read-only"; exit 1; }

rmmod wl12xx_sdio 2>/dev/null; rmmod wl12xx 2>/dev/null; sleep 2
grep -q "^wl12xx " /proc/modules 2>/dev/null && { echo "ERROR: wl12xx still loaded"; exit 2; }

cp "$BK/wl12xx.ko.v59" "$CAND/wl12xx.ko" && cp "$BK/wl12xx_sdio.ko.v59" "$CAND/wl12xx_sdio.ko" \
    || { echo "ERROR: restore copy failed"; exit 1; }
cmp -s "$BK/wl12xx.ko.v59" "$CAND/wl12xx.ko" || { echo "ERROR: cmp after restore"; exit 1; }

insmod "$CAND/wl12xx_sdio.ko" 2>/dev/null || { echo "ERROR: insmod v59 failed"; exit 3; }
sleep 3
ifconfig wlan0 up 2>/dev/null

if [ -S /tmp/dbus_service_socket ]; then
    dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
        --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_Recovery >/dev/null 2>&1
fi

mkdir -p "$STATE_DIR"; echo "v59" > "$STATE_DIR/driver-swap.state"
# neutralize autorun hook
PERSIST="/mnt/data_persist/dev/bin"
grep -v "# MZD-DRV-V74" "$PERSIST/autorun" 2>/dev/null > "$PERSIST/autorun.tmp" \
    && cp "$PERSIST/autorun.tmp" "$PERSIST/autorun" 2>/dev/null && rm -f "$PERSIST/autorun.tmp"

echo "v59 driver restored: $(stat -c%s "$CAND/wl12xx.ko") bytes (expected 190704)"
dmesg 2>/dev/null | grep -E "firmware booted|wl12xx" | tail -3
echo "DONE"
exit 0
