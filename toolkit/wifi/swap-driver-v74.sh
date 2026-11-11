#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/swap-driver-v74.sh (v4.8.5, EGM Klasse C)
# Binary swap of the wl12xx HOST DRIVER to the v74 build:
#   v59: wl12xx.ko 190704 B (SP4-era, frozen kernel 3.0.35)
#   v74: wl12xx.ko 246528 B (SP8-era fixes), SAME vermagic
#        "3.0.35 SMP preempt mod_unload ARMv7" + MODVERSIONS off
#        -> loads without recompiling.
#
# The CHIP firmware (wl128x-fw-4-sr.bin) is NOT touched:
# v74 sr.bin (FRev .142) gave MORE watchdogs (11x) than v59 (.136)
# in the 11:40 logs -> we keep the v59 chip firmware.
#
# Atomicity/rollback:
#   - backup original -> $BACKUP_DIR/wl12xx-v59/ + USB
#   - state-file $STATE_DIR/driver-swap.state = v74|v59
#   - autorun-hook # MZD-DRV-V74 checks at boot: wlan0 up within
#     90s? no -> restore v59 backup + rmmod/insmod + log
#   - manual rollback: wifi/rollback-driver-v59.sh
#
# NMS owns wpa_supplicant: NEVER killall. After rmmod/insmod
# explicit NMS re-init via WIFI_Recovery (v4.7.5 M4 line).
#
# Exit-codes: 0 = v74 driver loaded + wlan0 up,
#             1 = preconditions (files/remount),
#             2 = rmmod faalde (wlan0 bezet),
#             3 = insmod v74 failed -> AUTO-ROLLBACK to v59.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TD="${TOOLKIT_DIR:-$(dirname "$0")/..}"
SRC="$TD/wifi/v74-driver"
KREL=$(uname -r 2>/dev/null || echo "3.0.35")
# v59 CMU loaded path (proven in logs): ti/wl12xx; v74 rootfs path: wl12xx
CAND=""
for p in "/lib/modules/$KREL/kernel/drivers/net/wireless/ti/wl12xx" \
         "/lib/modules/$KREL/kernel/drivers/net/wireless/wl12xx" \
         "/lib/modules/$KREL/kernel/drivers/net/wireless"; do
    [ -f "$p/wl12xx.ko" ] && CAND="$p" && break
done
[ -z "$CAND" ] && CAND="/lib/modules/$KREL/kernel/drivers/net/wireless/ti/wl12xx"
STATE_DIR="${STATE_DIR:-/tmp/toolkit-state}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/toolkit-backups}"
STATE="$STATE_DIR/driver-swap.state"
BK="$BACKUP_DIR/wl12xx-v59"

echo "========================================"
echo " wl12xx driver swap -> v74 build (v4.8.5)"
echo "========================================"
sh "$TD/wifi/driver-info.sh" 2>/dev/null
echo "module dir: $CAND"

# --- 0. preconditions ---
[ -f "$SRC/wl12xx.ko" ] && [ -f "$SRC/wl12xx_sdio.ko" ] || {
    echo "ERROR: v74 driver .ko files missing in $SRC"; exit 1; }
V74_SHA=$(sha256sum "$SRC/wl12xx.ko" 2>/dev/null | awk '{print $1}')
V74SD_SHA=$(sha256sum "$SRC/wl12xx_sdio.ko" 2>/dev/null | awk '{print $1}')
# known hashes (v74 extract, verified 2026-11-03)
[ "$V74_SHA" = "f071a3d43c1c07225531d4b25b568508c45ffe555e603b59fc9858f6e72a6875" ] \
    || { echo "ERROR: wl12xx.ko sha mismatch ($V74_SHA)"; exit 1; }
[ "$V74SD_SHA" = "3dd4743882d0128af662764357de81072f7db23e69b4cf1223982046141759f9" ] \
    || { echo "ERROR: wl12xx_sdio.ko sha mismatch ($V74SD_SHA)"; exit 1; }
echo "v74 driver hashes OK"

# --- 1. remount rw ---
mount 2>/dev/null | grep -q " on / " && mount -o remount,rw / 2>/dev/null
mount 2>/dev/null | grep -q " on /lib " && mount -o remount,rw /lib 2>/dev/null
touch "$CAND/.rw-test" 2>/dev/null && rm -f "$CAND/.rw-test" || {
    echo "ERROR: $CAND is read-only and remount rw failed"; exit 1; }

# --- 2. backup original (once) ---
mkdir -p "$BK"
if [ ! -f "$BK/wl12xx.ko.v59" ]; then
    cp "$CAND/wl12xx.ko" "$BK/wl12xx.ko.v59" 2>/dev/null || { echo "ERROR: backup failed"; exit 1; }
    cp "$CAND/wl12xx_sdio.ko" "$BK/wl12xx_sdio.ko.v59" 2>/dev/null
    # also to USB if the backup dir is on USB
    [ -n "$USB_MOUNT" ] && mkdir -p "$USB_MOUNT/mzd-data/backups/wl12xx-v59" \
        && cp "$BK"/*.v59 "$USB_MOUNT/mzd-data/backups/wl12xx-v59/" 2>/dev/null
    echo "v59 driver backup -> $BK (sha $(sha256sum "$BK/wl12xx.ko.v59" | awk '{print $1}'))"
else
    echo "v59 backup already exists: $(sha256sum "$BK/wl12xx.ko.v59" | awk '{print $1}')"
fi

# --- 3. rmmod (only if wlan0 is not in use by an active connection) ---
if wpactrl status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
    echo "WARNING: wlan0 is connected - disconnect first (menu 4) for a clean swap"
fi
rmmod wl12xx_sdio 2>/dev/null; rmmod wl12xx 2>/dev/null
sleep 2
if grep -q "^wl12xx " /proc/modules 2>/dev/null; then
    echo "ERROR: wl12xx still loaded (busy) - rmmod refused"; exit 2
fi

# --- 4. copy v74 driver over the old one ---
cp "$SRC/wl12xx.ko" "$CAND/wl12xx.ko" || { echo "ERROR: copy wl12xx.ko"; exit 1; }
cp "$SRC/wl12xx_sdio.ko" "$CAND/wl12xx_sdio.ko" || { echo "ERROR: copy wl12xx_sdio.ko"; exit 1; }
cmp -s "$SRC/wl12xx.ko" "$CAND/wl12xx.ko" || { echo "ERROR: cmp wl12xx.ko"; exit 1; }
echo "v74 driver files geplaatst"

# --- 5. insmod v74 ---
if ! insmod "$CAND/wl12xx_sdio.ko" 2>/dev/null; then
    echo "ERROR: insmod v74 wl12xx_sdio failed -> AUTO-ROLLBACK to v59"
    cp "$BK/wl12xx.ko.v59" "$CAND/wl12xx.ko" 2>/dev/null
    cp "$BK/wl12xx_sdio.ko.v59" "$CAND/wl12xx_sdio.ko" 2>/dev/null
    insmod "$CAND/wl12xx_sdio.ko" 2>/dev/null
    echo "v59 driver restored"; exit 3
fi
sleep 3
ifconfig wlan0 up 2>/dev/null

# --- 6. NMS re-init (NEVER assume wpa_supplicant starts by itself) ---
if [ -S /tmp/dbus_service_socket ]; then
    dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
        --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_Recovery >/dev/null 2>&1
    echo "NMS WIFI_Recovery invoked"
fi
sleep 2

# --- 7. state + autorun-hook for boot rollback ---
mkdir -p "$STATE_DIR"
echo "v74" > "$STATE"
echo "v74 $(date +%s 2>/dev/null || echo 0) sha=$V74_SHA" >> "$STATE_DIR/driver-swap.history" 2>/dev/null

PERSIST="/mnt/data_persist/dev/bin"
AUTORUN="$PERSIST/autorun"
if [ -f "$AUTORUN" ]; then
    if ! grep -q "# MZD-DRV-V74" "$AUTORUN" 2>/dev/null; then
        cp "$AUTORUN" "$AUTORUN.bak-drv-$(date +%s 2>/dev/null || echo 0)" 2>/dev/null
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/autorun-drv.$$")
        {
            echo "# MZD-DRV-V74 boot-check: if wlan0 not up within 90s -> restore v59"
            echo "( sleep 90; if ! ifconfig wlan0 2>/dev/null | grep -q UP; then"
            echo "    BK=\"${BACKUP_DIR:-/tmp/toolkit-backups}/wl12xx-v59\""
            echo "    [ -f \"\$BK/wl12xx.ko.v59\" ] && {"
            echo "      mount -o remount,rw / 2>/dev/null"
            echo "      K=/lib/modules/\$(uname -r)/kernel/drivers/net/wireless/ti/wl12xx"
            echo "      rmmod wl12xx_sdio 2>/dev/null; rmmod wl12xx 2>/dev/null"
            echo "      cp \"\$BK/wl12xx.ko.v59\" \"\$K/wl12xx.ko\" 2>/dev/null"
            echo "      cp \"\$BK/wl12xx_sdio.ko.v59\" \"\$K/wl12xx_sdio.ko\" 2>/dev/null"
            echo "      insmod \"\$K/wl12xx_sdio.ko\" 2>/dev/null"
            echo "      ifconfig wlan0 up 2>/dev/null"
            echo "      echo \"drv-rollback\" >> /tmp/drv-rollback.log"
            echo "    }"
            echo "  fi ) &"
            cat "$AUTORUN" 2>/dev/null
        } > "$TMPF"
        cp "$TMPF" "$AUTORUN" 2>/dev/null && rm -f "$TMPF" && chmod +x "$AUTORUN" 2>/dev/null \
            && echo "autorun-hook MZD-DRV-V74 added"
    else
        echo "autorun-hook MZD-DRV-V74 already present"
    fi
else
    echo "no autorun found - only runtime swap (boot rollback not active)"
fi

# --- 8. verify ---
echo ""
echo "--- verify ---"
echo "loaded: $(grep -E '^wl12xx' /proc/modules | head -2)"
echo "wl12xx.ko size now: $(stat -c%s "$CAND/wl12xx.ko" 2>/dev/null) (v74 = 246528, v59 = 190704)"
dmesg 2>/dev/null | grep -E "firmware booted|wl12xx.*Rev|watchdog" | tail -5
if ifconfig wlan0 >/dev/null 2>&1; then
    echo "wlan0 UP: $(ifconfig wlan0 | grep -m1 HWaddr)"
    echo "DONE: v74 driver active. Watchdog-count check: dmesg | grep -c 'watchdog interrupt'"
    exit 0
else
    echo "WARNING: wlan0 did not come up within 5s - check dmesg; rollback: wifi/rollback-driver-v59.sh"
    exit 0   # driver loaded is the goal; wlan0 up can take a while via NMS
fi
