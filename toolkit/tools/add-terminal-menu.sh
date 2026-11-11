#!/bin/sh
# ============================================================
# MZD Toolkit - Add Terminal Menu Item to Settings > System tab
# ============================================================
# Patches /jci/gui/apps/syssettings/js/syssettingsApp.js so a
# "Terminal" item appears in Settings > System tab.
# Clicking the item writes a trigger file; our autorun
# watchdog then runs /jci/scripts/run-terminal.sh (SYSTEM_TERMINAL=22).
#
# Mechanisme (v74 source analyse):
#   - SystemTab list is built dynamically in _createDisplayList
#     (line ~5265-5375): items are set index by index.
#   - After "About" (index 7) there is room - we push an extra item.
#   - In _menuItemSelectCallback we add case "SelectTerminal"
#     which writes a trigger file: /tmp/mzd-terminal-trigger
#   - Our autorun watchdog (terminal-menu-watchdog.sh) checks this
#     file and runs: sh /jci/scripts/systemHooks.sh 22
#
# Requires: os_unlock (remount rw of /jci)
# ============================================================

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

log_to_usb "add-terminal-menu.sh started"

echo "========================================"
echo " Adding Terminal Menu Item (v1)"
echo "========================================"
echo ""

# Step 1: os_unlock for /jci
echo "Step 1: os_unlock..."
os_unlock
if mount 2>/dev/null | grep -q " on /jci "; then
    mount -o remount,rw /jci 2>/dev/null
fi
if touch /jci/.rwtest 2>/dev/null; then
    rm -f /jci/.rwtest
    echo "  /jci is writable"
else
    echo "  ERROR: /jci not writable - cannot patch"
    log_to_usb "add-terminal-menu: /jci NOT writable"
    exit 1
fi
echo ""

# Step 2: patch syssettingsApp.js
SYSAPP="/jci/gui/apps/syssettings/js/syssettingsApp.js"
echo "Step 2: patching $SYSAPP..."

if [ ! -f "$SYSAPP" ]; then
    echo "  ERROR: $SYSAPP not found"
    log_to_usb "add-terminal-menu: syssettingsApp.js not found"
    exit 1
fi

# Backup
if [ ! -f "$SYSAPP.org" ]; then
    cp -a "$SYSAPP" "$SYSAPP.org" 2>/dev/null && log_to_usb "add-terminal-menu: backup $SYSAPP.org" || log_to_usb "add-terminal-menu: backup FAILED"
fi

PATCHED=0

# 2a. Add Terminal item AFTER the About item in SystemTab list builder
#     v59/v74 GUI source (line ~4892):
#       this._SystemTabCtxtDataList.items[systemTabIndex] = { appData : 'SelectAbout', text1Id : 'About', ... };
#       this._SystemTabHelperArray["about"].index = systemTabIndex;
#     After that: itemCount = systemTabIndex + 1.
#     v4.8.2: also helper-array entry + i18n dict (WITHOUT dict entry the
#     System tab stays "Loading" forever — proven photo hardware testing).
#     v4.8.13 FIX: also patch the static _SystemTabHelperArray definition (line ~315-351)
#     with a "terminal" entry — otherwise this._SystemTabHelperArray["terminal"]
#     is undefined in _EnableDisableControlItems and the tab stays "Loading".
if ! grep -q 'MZD-TERMINAL-MENU-PATCHED' "$SYSAPP" 2>/dev/null; then
    if grep -q "appData : 'SelectAbout', text1Id : 'About'" "$SYSAPP" 2>/dev/null; then
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/sysset.$$")
        awk '
            /appData : .SelectAbout., text1Id : .About./ {
                print
                getline; print   # helper array line ("about".index)
                print "                // MZD-TERMINAL-MENU-PATCHED"
                print "                systemTabIndex++;"
                print "                this._SystemTabCtxtDataList.items[systemTabIndex] = { appData : '\''SelectTerminal'\'', text1Id : '\''Terminal'\'', itemStyle : '\''style01'\'', hasCaret : false };"
                print "                this._SystemTabHelperArray[\"terminal\"] = { index : systemTabIndex };"
                patched = 1
                next
            }
            /"about" : *$/ {
                # statische helper-array def: voeg terminal entry toe na about block
                print
                getline; print  # {
                getline; print  # "index" : 7,
                getline; print  # }  (without comma after it)
                print "        ,"
                print "        \"terminal\" :"
                print "        {"
                print "            \"index\" : 8,"
                print "        }"
                stat_done = 1
                next
            }
            { print }
            END { if (patched) exit 0; else exit 1 }
        ' "$SYSAPP" > "$TMPF" 2>/dev/null
        if [ -s "$TMPF" ] && grep -q 'MZD-TERMINAL-MENU-PATCHED' "$TMPF" 2>/dev/null; then
            cp "$TMPF" "$SYSAPP" 2>/dev/null && PATCHED=$((PATCHED+1))
            log_to_usb "add-terminal-menu: Terminal item added to SystemTab + static helper array"
        fi
        rm -f "$TMPF"
    fi
fi

# 2a-bis. v4.8.2: i18n dict entries — WITHOUT "Terminal" string in the active dict
# the list-control renders the tab as empty/"Loading" (proven photo 2026-11-03 11:15).
# Patch ALL syssettingsAppDict_*.js with a "Terminal" entry (idempotent).
DICT_DIR="/jci/gui/resources/js/syssettings"
if [ -d "$DICT_DIR" ]; then
    for DICT in "$DICT_DIR"/syssettingsAppDict_*.js; do
        [ -f "$DICT" ] || continue
        if ! grep -q '"Terminal"' "$DICT" 2>/dev/null; then
            # insert after the "About" line (exists in every dict)
            if grep -q '"About"' "$DICT" 2>/dev/null; then
                DTMP=$(mktemp 2>/dev/null || echo "/tmp/dict.$$")
                awk '/"About"/ && !done { print; print "\t\"Terminal\" : \"Terminal\","; done=1; next } { print }' "$DICT" > "$DTMP" 2>/dev/null
                if [ -s "$DTMP" ]; then
                    cp "$DTMP" "$DICT" 2>/dev/null && log_to_usb "add-terminal-menu: Terminal string added to $(basename "$DICT")"
                fi
                rm -f "$DTMP"
            fi
        fi
    done
    echo "  i18n dicts patched in $DICT_DIR"
fi

# 2b. Add case "SelectTerminal" in _menuItemSelectCallback
#     v4.8.14 FIX (hardware testing): uiaId MUST be "diag", not this.uiaId!
#     sendEventToMmui(uiaId, ...) routes via MMUI to the service with that uiaId.
#     ReadDTC is handled by svcjcitestdiag (com.jci.testdiag) which is loaded
#     with uiaId="diag" (diagApp.js line 333 uses this.uiaId="diag").
#     With this.uiaId="syssettings" MMUI routes ReadDTC to a non-existent
#     "syssettings" testdiag service -> event is silently dropped.
#     Original v59 GUI dump line 2044: case "SelectVersion": -> sendEventToMmui SelectVersion
#     We add OUR case after it which calls MMUI with testId=22 (SYSTEM_TERMINAL).
#     MMUI translates ReadDTC/DiagCode events to: /jci/scripts/startSystemScripts.sh 22
#     (proven in diagApp.js: sendEventToMmui(uiaId,"ReadDTC",{payload:{testId:22}})
#     and svcjcitestdiag.so: "/jci/scripts/startSystemScripts.sh %d")
#     startSystemScripts.sh -> systemHooks.sh 22 -> run-terminal.sh
if ! grep -q 'MZD-TERMINAL-CASE-PATCHED' "$SYSAPP" 2>/dev/null; then
    if grep -q 'case "SelectVersion":' "$SYSAPP" 2>/dev/null; then
        TMPF=$(mktemp 2>/dev/null || echo "/tmp/sysset2.$$")
        awk '
            /case "SelectVersion":/ {
                print
                getline; print  # framework.sendEventToMmui line
                getline; print  # break;
                # Add our case — v4.8.14: uiaId="diag" (NOT this.uiaId!)
                print "        // MZD-TERMINAL-CASE-PATCHED"
                print "        case \"SelectTerminal\":"
                print "            /* v4.8.14: uiaId=\"diag\" — ReadDTC is handled by svcjcitestdiag (uiaId=diag),"
                print "               NOT by syssettings. With this.uiaId the call silently fails. */"
                print "            framework.sendEventToMmui(\"diag\", \"ReadDTC\", { payload : { testId : 22 } });"
                print "            break;"
                next
            }
            { print }
        ' "$SYSAPP" > "$TMPF" 2>/dev/null
        if [ -s "$TMPF" ] && grep -q 'MZD-TERMINAL-CASE-PATCHED' "$TMPF" 2>/dev/null; then
            # v4.8.14: verify the patch really uses "diag" (guard against old this.uiaId patch)
            if grep -q 'sendEventToMmui("diag", "ReadDTC"' "$TMPF" 2>/dev/null; then
                cp "$TMPF" "$SYSAPP" 2>/dev/null && PATCHED=$((PATCHED+1))
                log_to_usb "add-terminal-menu: SelectTerminal case added (uiaId=diag, v4.8.14 fix)"
            else
                log_to_usb "add-terminal-menu: WARNING - patched case does not use uiaId=diag!"
                echo "  WARNING: patch did not generate a uiaId=diag call - check awk output"
            fi
        fi
        rm -f "$TMPF"
    fi
fi

# 2c. NO systemHooks.sh patch or watchdog needed:
#     the JS case "SelectTerminal" sends ReadDTC testId=22 directly to MMUI,
#     and MMUI itself calls /jci/scripts/startSystemScripts.sh 22
#     (startSystemScripts.sh -> systemHooks.sh SYSTEM_TERMINAL=22 -> run-terminal.sh)
#     See diagApp.js + svcjcitestdiag.so in firmware analysis.

# Step 3: (reserved) - no extra files needed
PERSIST=/data_persist
[ -d "$PERSIST" ] || PERSIST=/mnt/data_persist
mkdir -p "$PERSIST/dev/bin"
echo "  (no watchdog needed - MMUI handles testId=22 directly)"

sync 2>/dev/null
echo ""
echo "========================================"
echo " TERMINAL MENU INSTALLATION COMPLETE"
echo "========================================"
echo "Patches applied: $PATCHED"
echo ""
echo "HOW IT WORKS:"
echo "  1. Reboot the CMU (Mute+Navi 10s) so patched JS + dict are loaded"
echo "     WITHOUT reboot the System tab stays 'Loading' forever (dict string"
echo "     'Terminal' is only loaded at boot)."
echo "  2. Go to Settings > System tab"
echo "  3. Klik op 'Terminal' (onderaan, na About)"
echo "  4. Terminal verschijnt in fullscreen"
echo ""
echo "  Test directly without reboot (via MMUI diag-code):"
echo "    dbus-send --address=unix:path=/tmp/dbus_service_socket --print-reply \\"
echo "      --dest=com.jci.testdiag /com/jci/testdiag com.jci.testdiag.ReadDTC int32:22"
echo ""
log_to_usb "add-terminal-menu.sh DONE ($PATCHED patches)"
