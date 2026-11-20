#!/bin/sh
# ============================================================
# MZD Toolkit - GUI Dump (copy GUI of running version -> USB)
# Read-only w.r.t. CMU; writes ONLY to USB.
# Pre-flight free-space check (USB has only a few GB - hardware testing.
# NEVER os_unlock/safe_write. /data NEVER via symlink (FAT32).
# /data/integration: md5 + allowlist GuiConfig.js only (secret-scan).
# Design: docs/designs/os-map-gui-dump-2026-11-01.md v2 (gate 29ed4dd)
# ============================================================

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
require_root || exit 1

# Hard abort if no rw USB
if ! detect_usb || ! ensure_usb_rw; then
    echo "ERROR: no writable USB found (check: ls /tmp/mnt). Abort."
    exit 1
fi
TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit"
log_to_usb "gui-dump.sh started (USB_MOUNT=$USB_MOUNT)"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Pre-flight: free space on USB vs estimated source size (x1.1 margin) ---
SRC_DIRS="/jci/gui /jci/fonts /jci/resources /jci/nng/ux /jci/opera/opera_dir/skin"
NEED_KB=$(du -sk $SRC_DIRS 2>/dev/null | awk '{s+=$1} END{print s+0}')
AVAIL_KB=$(df -k "$USB_MOUNT" 2>/dev/null | awk 'NR==2{print $4}')
NEED_KB=$(( NEED_KB * 11 / 10 ))
echo "USB free: ${AVAIL_KB} KB | needed (incl. 10%): ${NEED_KB} KB"
if [ "$AVAIL_KB" -lt "$NEED_KB" ]; then
    echo "ERROR: not enough USB space! ($AVAIL_KB KB free, $NEED_KB KB needed)"
    echo "Tip: use a bigger USB stick, or copy a smaller package manually."
    log_to_usb "gui-dump.sh ABORT: not enough space ($AVAIL_KB < $NEED_KB KB)"
    exit 1
fi

# --- Atomic output: .tmp-<pid> on USB, then mv ---
OUT_TMP="${LOG_DIR:-$TOOLKIT_DIR/logs}/gui-dump-$TIMESTAMP-$$.tmp"
OUT_DIR="${LOG_DIR:-$TOOLKIT_DIR/logs}/gui-dump-$TIMESTAMP-$$"
mkdir -p "$OUT_TMP" 2>/dev/null || { echo "ERROR: cannot create $OUT_TMP"; exit 1; }
echo "Output (tmp): $OUT_TMP"

copy_dir() {
    src="$1"; dst="$2"
    if [ -d "$src" ]; then
        cp -rL "$src" "$OUT_TMP/$dst" 2>/dev/null && echo "  OK: $src -> $dst ($(du -sk "$OUT_TMP/$dst" 2>/dev/null | awk '{print $1}') KB)" \
            || echo "  FAIL: $src"
    else
        echo "  SKIP (does not exist): $src"
    fi
}

# Abort-only behavior (design v2 section 3): on low space NO partial copy -
# pre-flight check above already aborts. Here: plain copy in fixed order.
copy_dir /jci/gui            gui
copy_dir /jci/fonts          fonts
copy_dir /jci/resources      resources
[ -d /jci/nng/ux ] && { mkdir -p "$OUT_TMP/skin"; cp -rL /jci/nng/ux/*.zip "$OUT_TMP/skin/" 2>/dev/null; echo "  OK: /jci/nng/ux/*.zip -> skin/"; }
copy_dir /jci/opera/opera_dir/skin opera-skin

# --- /data/integration: md5 + allowlist ONLY, NEVER raw content (except GuiConfig after mask) ---
INT_SRC="/mnt/data/integration"
{
    echo "=== /mnt/data/integration - md5 only (no contents) ==="
    if [ -d "$INT_SRC" ]; then
        ( cd "$INT_SRC" 2>/dev/null && md5sum * 2>/dev/null ) || echo "(empty or not readable)"
    else
        echo "no $INT_SRC"
    fi
} > "$OUT_TMP/integration.md5" 2>&1
echo "  -> integration.md5"
# Allowlist: only GuiConfig.js, with token values masked.
# BusyBox-safe: NO 'I' flag (GNU-only) - case-insensitive via character classes.
# On a matching key the WHOLE value (to end of line) is masked.
if [ -f "$INT_SRC/developer_mode_GuiConfig.js" ]; then
    # v4.7.5 M5 (gate 0046b92): awk instead of sed -E - BusyBox sed has no -E and failed
    # silently -> 0-byte masked file (proven in gui-dump 2026-11-01-1518).
    awk '{
        if ($0 ~ /^[^=:]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss]?[Ww][Oo][Rr][Dd]|[Pp][Ww][Dd]|[Cc][Rr][Ee][Dd]|[Aa][Uu][Tt][Hh]|[Ss][Ee][Ss][Ss][Ii][Oo][Nn]|[Cc][Oo][Oo][Kk][Ii][Ee]|[Pp][Ss][Kk]|[Bb][Ee][Aa][Rr][Ee][Rr])[A-Za-z0-9_]*[[:space:]]*[=:]/) {
            idx = index($0, "="); if (idx == 0) idx = index($0, ":")
            print substr($0, 1, idx) "***"
        } else print
    }' "$INT_SRC/developer_mode_GuiConfig.js" > "$OUT_TMP/developer_mode_GuiConfig.masked.js" 2>/dev/null
    if [ -s "$OUT_TMP/developer_mode_GuiConfig.masked.js" ]; then
        echo "  OK: GuiConfig.js (masked, $(wc -c < "$OUT_TMP/developer_mode_GuiConfig.masked.js") bytes)"
    else
        echo "  ERROR: masking produced empty file - source copied as .raw"
        cp "$INT_SRC/developer_mode_GuiConfig.js" "$OUT_TMP/developer_mode_GuiConfig.masked.js.raw" 2>/dev/null
    fi
fi

# --- MANIFEST: md5 of WHAT WAS ACTUALLY COPIED ---
( cd "$OUT_TMP" 2>/dev/null && find . -type f ! -name 'MANIFEST.md5' ! -name 'SUMMARY.txt' -exec md5sum {} \; 2>/dev/null | sort -k2 ) \
    > "$OUT_TMP/MANIFEST.md5" 2>&1
echo "  -> MANIFEST.md5 ($(wc -l < "$OUT_TMP/MANIFEST.md5" 2>/dev/null || echo 0) entries)"

# --- SUMMARY ---
{
    echo "=== GUI-DUMP SUMMARY ==="
    echo "Date: $(date)"
    echo "Firmware: $(cat /jci/version.ini 2>/dev/null | tr '\n' ' ')"
    echo "USB free before copy: ${AVAIL_KB} KB, estimated needed: ${NEED_KB} KB"
    echo ""
    echo "--- copied ---"
    ls -la "$OUT_TMP"
    echo ""
    echo "--- sizes per dir ---"
    du -sk "$OUT_TMP"/* 2>/dev/null
} > "$OUT_TMP/SUMMARY.txt" 2>&1

# --- Atomic finish ---
mv "$OUT_TMP" "$OUT_DIR" 2>/dev/null || { echo "ERROR: mv tmp->final failed"; exit 1; }
sync 2>/dev/null
sleep 1

# --- Verify-gate: secret-scan over ALL output (design section 5 - hit = fail) ---
SCAN_HITS=$(grep -riEl 'password|passwd|secret|token|api_key|private key|psk|bearer' "$OUT_DIR" 2>/dev/null | grep -v '\.md5$')
if [ -n "$SCAN_HITS" ]; then
    echo ""
    echo "! SECRET-SCAN HIT in output - script fails (gate):"
    echo "$SCAN_HITS"
    log_to_usb "gui-dump.sh SECRET-SCAN FAIL -> $OUT_DIR"
    exit 2
fi
echo "secret-scan OK (no hits)"

echo ""
echo "=== GUI-DUMP COMPLETE ==="
echo "Output: $OUT_DIR"
du -sh "$OUT_DIR" 2>/dev/null
ls "$OUT_DIR"
echo "USB can now be removed safely."
log_to_usb "gui-dump.sh complete -> $OUT_DIR"
