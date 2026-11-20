#!/bin/sh
# ============================================================
# MZD Toolkit - OS Map (read-only inventory -> USB)
# First calls system/dump.sh (OUTPUT_DIR) and only adds the
# delta: etc-listing, dbus-services, jci-tree, proc-cmdline.
# SECRET-MASKING: default-deny env, no /proc/*/cmdline,
# wpa_supplicant only ssid+md5. NEVER os_unlock/safe_write.
# Design: docs/designs/os-map-gui-dump-2026-11-01.md v2 (gate 29ed4dd)
# ============================================================

# Source gedeelde library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
require_root || exit 1

# Hard abort if no rw USB (no /tmp fallback - /tmp can be full/ro)
if ! detect_usb || ! ensure_usb_rw; then
    echo "ERROR: no writable USB found (check: ls /tmp/mnt). Abort."
    exit 1
fi
TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit"
log_to_usb "os-map.sh started (USB_MOUNT=$USB_MOUNT)"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${LOG_DIR:-$TOOLKIT_DIR/logs}/os-map-$TIMESTAMP-$$"
mkdir -p "$OUT_DIR" 2>/dev/null
if [ ! -d "$OUT_DIR" ]; then
    echo "ERROR: cannot create $OUT_DIR!"
    exit 1
fi
echo "Output dir: $OUT_DIR"

# --- Stap 1: volle dump via dump.sh in dezelfde dir ---
OUTPUT_DIR="$OUT_DIR/dump-$TIMESTAMP-$$" sh "$(dirname "$0")/dump.sh" > "$OUT_DIR/00-dump-console.log" 2>&1
echo "dump.sh done -> $OUT_DIR/dump-$TIMESTAMP-$$"
DUMP_OUT="$OUT_DIR/dump-$TIMESTAMP-$$"

# --- Stap 1b: SANITIZE dump-output (dump.sh dumpt raw psk/env/argv — lek!)
#   Design-regel "no secrets on USB" (gate 29ed4dd) — dump.sh zelf patchen = M5.
#   mask_lines: hele regel maskeren als key matcht; URL-creds maskeren.
mask_lines() {
    awk '{
        line=$0; eq=index(line,"=")
        if (eq>0) {
            key=tolower(substr(line,1,eq-1)); gsub(/[^a-z0-9_]/,"",key)
            if (key ~ /pass|pwd|secret|token|key|cred|auth|session|cookie|psk|bearer/) { print substr(line,1,eq) "***"; next }
        }
        if (line ~ /:\/\/[^\/]*:[^@]*@/) gsub(/:\/\/[^\/]*:[^@]*@/,"://***:***@",line)
        print line
    }' "$1" > "$1.tmp" 2>/dev/null && mv "$1.tmp" "$1"
}
if [ -d "$DUMP_OUT" ]; then
    for f in 04-processes.txt 06-configs.txt 09-ssh-remote.txt 10-environment.txt 11-wifi-debug.txt; do
        [ -f "$DUMP_OUT/$f" ] && mask_lines "$DUMP_OUT/$f" && echo "  sanitized: dump/$f"
    done
    # processes: NEVER argv ('ps aux' and /proc/*/cmdline contain argv with possible secrets)
    # -> only pid + /proc/<pid>/comm
    if [ -f "$DUMP_OUT/04-processes.txt" ]; then
        { echo "=== processes (pid + comm WITHOUT argv) ==="
          for p in /proc/[0-9]*; do
              [ -f "$p/comm" ] && echo "$(basename "$p") $(cat "$p/comm" 2>/dev/null)"
          done | sort -n
        } > "$DUMP_OUT/04-processes.txt.new" 2>/dev/null && mv "$DUMP_OUT/04-processes.txt.new" "$DUMP_OUT/04-processes.txt"
        echo "  sanitized: dump/04-processes.txt (argv removed)"
    fi
    log_to_usb "os-map: dump output sanitized (configs/env masked, processes without argv)"
fi

# --- Stap 2: delta (os-specifieke kennis) ---
write_file() {
    fname="$1"; shift
    target="$OUT_DIR/$fname"
    echo "Verzamelen: $fname"
    "$@" > "$target" 2>&1
    echo "  -> $fname ($(wc -c < "$target" 2>/dev/null || echo 0) bytes)"
}

# etc-listing: COMPLETE (no head-cap)
write_file "etc-listing.txt" sh -c 'find /etc -type f 2>/dev/null | sort'

# dbus services — exact pattern uit tools/dbus-introspect.sh:41
write_file "dbus-services.txt" sh -c \
    # v4.7.5 M1: JCI service bus only - NO --system (does not exist on MZD, gave empty dbus-services.txt)
    'jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -o "com\.jci\.[a-zA-Z0-9_.]*" | sort -u'

# jci-tree - BusyBox auto-detect for find -maxdepth
if find /jci -maxdepth 0 -type d >/dev/null 2>&1; then
    write_file "jci-tree.txt" sh -c \
        'for d in $(find /jci -maxdepth 2 -type d 2>/dev/null | sort); do echo "$(find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l) files  $d"; done'
else
    # Fallback: awk depth-filter (BusyBox without -maxdepth)
    write_file "jci-tree.txt" sh -c \
        'find /jci -type d 2>/dev/null | awk -F/ "NF<=4" | sort | while read d; do echo "$(find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l) files  $d"; done'
fi

# proc-cmdline + lsmod + proces-comm's.
# NO /proc/*/cmdline and NO 'ps aux' - BOTH contain argv (can leak tokens/passwords).
# Only /proc/<pid>/comm (process name, never argv).
{
    echo "=== /proc/cmdline ==="; cat /proc/cmdline 2>&1
    echo ""; echo "=== lsmod ==="; lsmod 2>&1
    echo ""; echo "=== processes (pid + comm WITHOUT argv) ==="
    for p in /proc/[0-9]*; do
        [ -f "$p/comm" ] && echo "$(basename "$p") $(cat "$p/comm" 2>/dev/null)"
    done | sort -n
} > "$OUT_DIR/proc-cmdline.txt" 2>&1
echo "  -> proc-cmdline.txt"

# mask_env() - BusyBox-safe awk masker (no GNU sed 'I' flag!):
#   - whitelist keys print as-is
#   - key matchend op pass|pwd|secret|token|key|cred|session|cookie|psk|bearer -> value = ***
#   - URL-style creds (proto://user:pass@host) -> gemaskeerd
mask_env() {
    awk '{
        line=$0; eq=index(line,"=")
        if (eq>0) {
            key=substr(line,1,eq-1)
            if (key=="PATH"||key=="HOME"||key=="SHELL"||key=="TERM"||key=="LANG"||key=="USER"||key=="PWD"||key=="HOSTNAME") { print line; next }
            kl=tolower(key); gsub(/[^a-z0-9_]/,"",kl)
            if (kl ~ /pass|pwd|secret|token|key|cred|auth|session|cookie|psk|bearer/) { print key "=***"; next }
        }
        if (line ~ /:\/\/[^\/]*:[^@]*@/) gsub(/:\/\/[^\/]*:[^@]*@/,"://***:***@",line)
        print line
    }'
}

# env - DEFAULT-DENY: whitelist + masked for the rest
{
    echo "=== env (whitelist) ==="
    env 2>/dev/null | grep -E '^(PATH|HOME|SHELL|TERM|LANG|USER|PWD|HOSTNAME)=' | sort
    echo ""
    echo "=== env (other, values masked) ==="
    env 2>/dev/null | mask_env | sort
} > "$OUT_DIR/env-filtered.txt" 2>&1
echo "  -> env-filtered.txt"

# wpa_supplicant: ONLY ssid + md5 - NEVER content
{
    echo "=== wpa_supplicant (ssid + md5 only) ==="
    if [ -f /etc/wpa_supplicant.conf ]; then
        echo "ssid: $(grep -E '^\s*ssid=' /etc/wpa_supplicant.conf 2>/dev/null | head -1 | sed 's/.*ssid=//; s/"//g')"
        echo "md5:  $(md5sum /etc/wpa_supplicant.conf 2>/dev/null | awk '{print $1}')"
    else
        echo "no /etc/wpa_supplicant.conf found"
    fi
    echo ""
    echo "=== sshd_config (md5 + head OK - no secret material) ==="
    if [ -f /etc/ssh/sshd_config ]; then
        md5sum /etc/ssh/sshd_config 2>/dev/null
        head -20 /etc/ssh/sshd_config 2>/dev/null
    else
        echo "no /etc/ssh/sshd_config"
    fi
} > "$OUT_DIR/configs-safe.txt" 2>&1
echo "  -> configs-safe.txt"

# SUMMARY
{
    echo "=== OS-MAP SUMMARY ==="
    echo "Datum: $(date)"
    echo "Firmware: $(cat /jci/version.ini 2>/dev/null | tr '\n' ' ')"
    echo "Hostname: $(hostname 2>/dev/null)"
    echo "uname: $(uname -a 2>/dev/null)"
    echo "Output: $OUT_DIR"
    echo ""
    echo "--- files in this directory ---"
    ls -la "$OUT_DIR"
} > "$OUT_DIR/SUMMARY.txt" 2>&1

# --- Verify-gate: secret-scan over ALLE output (design §5 — hit = fail) ---
SCAN_HITS=$(grep -riEl 'password|passwd|secret|token|api_key|private key|psk|bearer' "$OUT_DIR" 2>/dev/null | grep -v '\.md5$')
if [ -n "$SCAN_HITS" ]; then
    echo ""
    echo "⚠ SECRET-SCAN HIT in output — script faalt (gate):"
    echo "$SCAN_HITS"
    log_to_usb "os-map.sh SECRET-SCAN FAIL -> $OUT_DIR"
    exit 2
fi
echo "secret-scan OK (no hits)"

echo ""
echo "=== OS-MAP COMPLEET ==="
echo "Output: $OUT_DIR"
ls -la "$OUT_DIR"
sync 2>/dev/null
sleep 1
echo "USB can now be removed safely."
log_to_usb "os-map.sh compleet -> $OUT_DIR"
