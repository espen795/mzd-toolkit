#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/fix-powersave-permanent.sh (v4.8.1)
# Zet wl12xx power save PERMANENT uit via de autorun-hook:
#   - runtime: /sys/module/*/parameters/ps = off (nu direct)
#   - boot:    hook in stage_wifi.sh / autorun voert hetzelfde uit
# WAAROM: ps=on triggert wl12xx ELP-sleep watchdog interrupts
# (bewezen: UI-wifi valt na ~3 min weg, dmesg "watchdog interrupt").
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1

echo "========================================"
echo " Power save permanent UIT (v4.8.1)"
echo "========================================"
echo ""

# --- 1. Runtime: direct alle ps-paden uit ---
echo "[1/3] Runtime power save UIT..."
for p in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do
    if [ -e "$p" ] && [ -w "$p" ]; then
        echo "off" > "$p" 2>/dev/null && echo "  $p = off"
    fi
done
for p in /sys/class/net/wlan0/power/control /sys/class/net/wlan0/device/power/control; do
    [ -e "$p" ] && [ -w "$p" ] && echo "on" > "$p" 2>/dev/null && echo "  $p = on (runtime PM uit)"
done
wpactrl set power_save off 2>/dev/null && echo "  wpa_cli power_save off"
echo ""

# --- 2. Boot-permanent: hook in autorun ---
echo "[2/3] Installing autorun hook (survives reboot)..."
PERSIST="/mnt/data_persist/dev/bin"
AUTORUN="$PERSIST/autorun"
HOOK_MARKER="# MZD-PS-OFF"

if [ -f "$AUTORUN" ]; then
    if grep -q "$HOOK_MARKER" "$AUTORUN" 2>/dev/null; then
        echo "  Hook zit er al in (autorun)"
    else
        cp "$AUTORUN" "$AUTORUN.bak-ps-$(date +%s 2>/dev/null || echo 0)" 2>/dev/null
        # Insert hook before the closing lines; busybox-proof with temp file
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/autorun-hook.$$")
        {
            echo "$HOOK_MARKER"
            echo "for _ps in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do"
            echo "  [ -e \"\$_ps\" ] && [ -w \"\$_ps\" ] && echo off > \"\$_ps\" 2>/dev/null"
            echo "done"
            cat "$AUTORUN" 2>/dev/null
        } > "$TMPF"
        if cp "$TMPF" "$AUTORUN" 2>/dev/null; then
            rm -f "$TMPF"
            chmod +x "$AUTORUN" 2>/dev/null
            echo "  Hook added to $AUTORUN"
        else
            rm -f "$TMPF"
            echo "  Could NOT write autorun (read-only?) - only runtime applied"
        fi
    fi
else
    echo "  No autorun found on $PERSIST - only runtime applied"
    echo "  (draai install.sh om autorun aan te maken)"
fi
echo ""

# --- 3. Verificatie ---
echo "[3/3] Verificatie..."
for p in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do
    [ -e "$p" ] && echo "  $p = $(cat "$p" 2>/dev/null)"
done
wpactrl get power_save 2>/dev/null | sed 's/^/  wpa_cli power_save: /'
echo ""
echo "Done. On next boot ps is automatically off via the autorun hook."
echo "========================================"
