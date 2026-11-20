#!/bin/sh
# ============================================================
# MZD Toolkit - Fix Startup Warning / Disclaimer  (v4.7.4)
# ============================================================
# v4.7.4 fix: "remaining = 0" still shows 1 frame (setTimeout(0)).
# Real fix: patch _displayedDisclaimer() so it sends "Timeout"
# to MMUI DIRECTLY -> disclaimer never visible.
#
# v59 GUI (dump 2026-11-01-1518) regelnummers:
#   systemApp.js:2146 _displayedDisclaimer = function()
#   2153: this._disclaimerTime.remaining = 0;   (was 3500)
#   2165: setTimeout(this._disclaimerTimedout..., remaining)
#
# Patch strategy (idempotent, works on v59 and v74):
#   1. Replace the WHOLE _displayedDisclaimer body with:
#      framework.sendEventToMmui("system", "DisposeIntroVideo");
#      framework.sendEventToMmui(this.uiaId, "Timeout");
#   2. same for _disclaimerTimedout (defensive)
# ============================================================

# ---- Source shared library ----
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null

if ! command -v log_to_usb >/dev/null 2>&1; then
    log_to_usb() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /tmp/toolkit.log 2>/dev/null; echo "$1"; }
fi
if ! command -v os_unlock >/dev/null 2>&1; then
    os_unlock() {
        for _p in / /jci /etc /usr /var /mnt/data_persist /data_persist /opt /home; do
            [ -d "$_p" ] || continue
            mount 2>/dev/null | grep -q " on $_p " && mount -o remount,rw "$_p" 2>/dev/null
        done
        sync 2>/dev/null
        return 0
    }
fi
if command -v trap_cleanup >/dev/null 2>&1; then trap_cleanup; fi

log_to_usb "fix-warning.sh v4.7.4 started"

echo "========================================"
echo " Startup Warning/Disclaimer Fix v4.7.4"
echo "========================================"
echo ""

# Step 1: os_unlock
echo "Step 1: os_unlock (remount rw)..."
os_unlock
mount 2>/dev/null | grep -q " on /jci " && mount -o remount,rw /jci 2>/dev/null
if touch /jci/.rwtest 2>/dev/null; then
    rm -f /jci/.rwtest
    echo "  /jci writable OK"
else
    echo "  ERROR: /jci not writable"
    log_to_usb "v4.7.4: /jci NOT writable"
    exit 1
fi
echo ""

# Step 2: patch systemApp.js - disclaimer FULLY gone
# v59/v74: replace _displayedDisclaimer function with direct Timeout
SYSAPP="/jci/gui/apps/system/js/systemApp.js"
echo "Step 2: patch $SYSAPP disclaimer function (v4.7.4)..."

if [ -f "$SYSAPP" ]; then
    # Backup
    if [ ! -f "$SYSAPP.org" ]; then
        cp -a "$SYSAPP" "$SYSAPP.org" 2>/dev/null && log_to_usb "v4.7.4: backup $SYSAPP.org"
    fi

    PATCHED=0

    # 2a. replace _displayedDisclaimer: send Timeout directly
    if ! grep -q 'MZD-DISCLAIMER-V474' "$SYSAPP" 2>/dev/null; then
        if grep -q 'systemApp.prototype._displayedDisclaimer = function' "$SYSAPP" 2>/dev/null; then
            TMPF=$(mktemp 2>/dev/null || echo "/tmp/sysapp.$$")
            awk '
                /^systemApp\.prototype\._displayedDisclaimer = function/ {
                    print "// MZD-DISCLAIMER-V474 - disclaimer fully disabled"
                    print "systemApp.prototype._displayedDisclaimer = function()"
                    print "{"
                    print "    framework.sendEventToMmui(\"system\", \"DisposeIntroVideo\");"
                    print "    framework.sendEventToMmui(this.uiaId, \"Timeout\");"
                    print "};"
                    skip = 1
                    next
                }
                skip == 1 {
                    # skip until function end "};" on its own line
                    if ($0 ~ /^};/) { skip = 0 }
                    next
                }
                { print }
            ' "$SYSAPP" > "$TMPF" 2>/dev/null
            if [ -s "$TMPF" ] && grep -q 'MZD-DISCLAIMER-V474' "$TMPF"; then
                cp "$TMPF" "$SYSAPP" 2>/dev/null && PATCHED=$((PATCHED+1)) && echo "  _displayedDisclaimer replaced -> direct Timeout"
            fi
            rm -f "$TMPF"
        fi
    else
        echo "  _displayedDisclaimer already patched (v4.7.4 marker present)"
    fi

    # 2b. also replace _disclaimerTimedout (defensive - if it is ever called)
    if ! grep -q 'MZD-TIMEOUT-V474' "$SYSAPP" 2>/dev/null; then
        if grep -q 'systemApp.prototype._disclaimerTimedout = function' "$SYSAPP" 2>/dev/null; then
            TMPF=$(mktemp 2>/dev/null || echo "/tmp/sysapp2.$$")
            awk '
                /^systemApp\.prototype\._disclaimerTimedout = function/ {
                    print "// MZD-TIMEOUT-V474"
                    print "systemApp.prototype._disclaimerTimedout = function()"
                    print "{"
                    print "    this._disclaimerTime.timeoutId = null;"
                    print "    this._disclaimerTime.reset = true;"
                    print "    framework.sendEventToMmui(this.uiaId, \"Timeout\");"
                    print "};"
                    skip = 1
                    next
                }
                skip == 1 {
                    if ($0 ~ /^};/) { skip = 0 }
                    next
                }
                { print }
            ' "$SYSAPP" > "$TMPF" 2>/dev/null
            if [ -s "$TMPF" ] && grep -q 'MZD-TIMEOUT-V474' "$TMPF"; then
                cp "$TMPF" "$SYSAPP" 2>/dev/null && PATCHED=$((PATCHED+1)) && echo "  _disclaimerTimedout replaced"
            fi
            rm -f "$TMPF"
        fi
    fi

    # 2c. Fallback: if awk did not work, 3500 -> -1 (negative = direct Timeout in original code)
    if [ "$PATCHED" -eq 0 ]; then
        if grep -q 'remaining = 3500' "$SYSAPP" 2>/dev/null; then
            sed -i 's/this\._disclaimerTime\.remaining = 3500;/this._disclaimerTime.remaining = -1;/g' "$SYSAPP" 2>/dev/null
            echo "  fallback: remaining 3500 -> -1 (direct Timeout via < 0 check)"
            log_to_usb "v4.7.4: fallback sed 3500->-1"
        fi
    fi

    if [ "$PATCHED" -gt 0 ]; then
        echo "  OK: disclaimer FULLY disabled ($PATCHED functions replaced)"
        log_to_usb "v4.7.4: systemApp.js disclaimer OFF ($PATCHED patches)"
    fi
    sync 2>/dev/null
else
    echo "  $SYSAPP not found"
    log_to_usb "v4.7.4: systemApp.js not found"
fi
echo ""

# Step 3: jci-dialog wrapper (defensive, for --warning dialogs)
PERSIST=/data_persist
[ -d "$PERSIST" ] || PERSIST=/mnt/data_persist
mkdir -p "$PERSIST/dev/bin" 2>/dev/null
cat > "$PERSIST/dev/bin/jci-dialog" << 'WRAPEOF'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        --warning|--error) exit 0 ;;
    esac
done
ORIG=/jci/tools/jci-dialog
[ -x "$ORIG" ] || ORIG=/jci/bin/jci-dialog
if [ -x "$ORIG" ]; then exec "$ORIG" "$@"; fi
exit 0
WRAPEOF
chmod 755 "$PERSIST/dev/bin/jci-dialog" 2>/dev/null
echo "Step 3: jci-dialog wrapper placed"
echo ""

# Step 4: flag files (AIO-compat)
mkdir -p "$PERSIST/aio/tweaks" 2>/dev/null
echo "1" > "$PERSIST/aio/warning_ack" 2>/dev/null
printf 'NO_STARTUP_WARNING=1\nNO_DISCLAIMER=1\nNO_MODIFIED_WARNING=1\nSKIP_FIRST_RUN=1\n' > "$PERSIST/aio/tweaks/no_warn.conf" 2>/dev/null
echo "1" > "$PERSIST/dev/no_warn" 2>/dev/null
touch "$PERSIST/dev/disclaimer_ack" 2>/dev/null
echo "Step 4: flag files set"
echo ""

# Step 5: autorun hook in stage_1.sh AND stage_wifi.sh (both idempotent)
# v4.8.3: stage_wifi.sh was EMPTY in dump 11:40 - hook doubled in both scripts.
for STAGE in /jci/scripts/stage_1.sh /jci/scripts/stage_wifi.sh; do
    if [ -f "$STAGE" ] && ! grep -q 'data_persist/dev/bin/autorun' "$STAGE" 2>/dev/null; then
        [ ! -f "$STAGE.org" ] && cp -a "$STAGE" "$STAGE.org" 2>/dev/null
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/stage_hook.$$")
        {
            echo "# MZD-AUTORUN HOOK"
            echo "if [ -x /data_persist/dev/bin/autorun ]; then /data_persist/dev/bin/autorun & fi"
            cat "$STAGE" 2>/dev/null
        } > "$TMPF"
        cp "$TMPF" "$STAGE" 2>/dev/null && echo "Step 5: autorun hook in $STAGE" || echo "Step 5: hook FAILED in $STAGE"
        rm -f "$TMPF"
    fi
done

# Step 6: autorun - ONLY append, NEVER overwrite!
# v4.8.3 BUGFIX: old version wrote a bare PATH-only autorun here, which made
# the install.sh autorun (WiFi+SSH+failsafe) disappear and stage_wifi.sh stay empty.
# Now: create if absent; only add PATH if that line is missing.
mkdir -p "$PERSIST/dev/bin" 2>/dev/null
AUTORUN="$PERSIST/dev/bin/autorun"
if [ ! -f "$AUTORUN" ]; then
    cat > "$AUTORUN" << 'AUTORUNEOF'
#!/bin/sh
export PATH="/data_persist/dev/bin:/data_persist/dev/sbin:$PATH"
export LD_LIBRARY_PATH="/data_persist/dev/lib:$LD_LIBRARY_PATH"
# warning flags at boot
echo "1" > /mnt/data_persist/aio/warning_ack 2>/dev/null
AUTORUNEOF
    chmod 755 "$AUTORUN" 2>/dev/null
    echo "Step 6: autorun created (new)"
elif ! grep -q 'warning_ack' "$AUTORUN" 2>/dev/null; then
    cp "$AUTORUN" "$AUTORUN.bak-warn" 2>/dev/null
    TMPF=$(mktemp 2>/dev/null || echo "/tmp/autorun.warn.$$")
    {
        echo 'echo "1" > /mnt/data_persist/aio/warning_ack 2>/dev/null'
        cat "$AUTORUN"
    } > "$TMPF"
    cp "$TMPF" "$AUTORUN" 2>/dev/null && chmod 755 "$AUTORUN" 2>/dev/null
    rm -f "$TMPF"
    echo "Step 6: warning_ack line added to existing autorun (rest kept)"
else
    echo "Step 6: autorun already contains warning_ack - nothing changed"
fi

sync 2>/dev/null
echo ""
echo "========================================"
echo " WARNING FIX v4.7.4 COMPLETE"
echo "========================================"
echo "Restart CMU (NAV+MUTE 10s) to test."
echo "Disclaimer should now NEVER appear."
log_to_usb "fix-warning.sh v4.7.4 DONE"
