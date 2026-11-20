#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# ============================================================
# MZD Toolkit - UI Terminal Fix v2
# ============================================================
# Gebaseerd op v74 firmware analyse (cmu150 v74 rootfs):
#   - jci/scripts/developer_mode.sh  -> writes to /data/integration/
#   - jci/scripts/systemHooks.sh     -> SYSTEM_TERMINAL=22 -> run-terminal.sh
#   - jci/scripts/run-terminal.sh    -> /usr/bin/terminal -f + ivi-shell
#   - jci/gui/index.html             -> laadt ../../data/integration/developer_mode_GuiConfig.js
#
# KEY FIX v2: In v74 /data is a symlink to /mnt/data.
# The GUI reads /data/integration/ (NOT /mnt/data_persist/integration/).
# In v59 (59.00.502) we must write to /data/integration/,
# or create the /data symlink if it is missing.
#
# v1 BUG: flags were put in /mnt/data_persist/integration/ -> GUI did not see them!
# ============================================================

echo "========================================"
echo " MZD UI Terminal Fix v2"
echo "========================================"
echo ""

cmd="${1:-help}"

# ------------------------------------------------------------
# Helper: determine the right integration path
# Priority: /data/integration (v74 style) > /mnt/data/integration > fallback
# ------------------------------------------------------------
get_integration_dir() {
    # If /data is a symlink to /mnt/data (v74/v59), use /data/integration
    if [ -L /data ] || [ -d /data ]; then
        echo "/data/integration"
    elif [ -d /mnt/data ]; then
        echo "/mnt/data/integration"
    else
        # Fallback: create /data symlink to /mnt/data_persist
        # (so the GUI can find the path ../../data/integration/)
        echo "/mnt/data_persist/integration"
    fi
}

# ------------------------------------------------------------
# Helper: make sure /data exists (symlink to /mnt/data or /mnt/data_persist)
# ------------------------------------------------------------
ensure_data_symlink() {
    if [ ! -e /data ]; then
        if [ -d /mnt/data ]; then
            ln -sf /mnt/data /data 2>/dev/null && echo "  /data symlink created -> /mnt/data"
        elif [ -d /mnt/data_persist ]; then
            ln -sf /mnt/data_persist /data 2>/dev/null && echo "  /data symlink created -> /mnt/data_persist"
        fi
    fi
}

case "$cmd" in
    dev|developer|dev-on)
        echo "--- Developer Mode ON (v2) ---"
        ensure_data_symlink
        INTEG=$(get_integration_dir)
        echo "  Integration dir: $INTEG"

        # Method 1: use official developer_mode.sh if it exists (v74 style)
        if [ -f /jci/scripts/developer_mode.sh ]; then
            echo "  Using /jci/scripts/developer_mode.sh on"
            sh /jci/scripts/developer_mode.sh on
        else
            # Method 2: manual (v59 fallback) - IMPORTANT: to /data/integration!
            echo "  developer_mode.sh not found, setting flags manually in $INTEG"
            mkdir -p "$INTEG"
            touch "$INTEG/developer_mode_on_flag"
            touch "$INTEG/eth0_on_flag"
            # Copy GuiConfig so index.html loads it
            if [ -f /jci/gui/common/js/developer_mode_GuiConfig.js ]; then
                cp /jci/gui/common/js/developer_mode_GuiConfig.js "$INTEG/developer_mode_GuiConfig.js"
                echo "  developer_mode_GuiConfig.js copied to $INTEG"
            else
                echo "  WARNING: developer_mode_GuiConfig.js not found in /jci/gui/common/js/"
            fi
            sync
        fi

        # Verification
        echo ""
        echo "  Verification:"
        ls -la "$INTEG/" 2>/dev/null || echo "    $INTEG does not exist!"
        # Also check via /data path (as the GUI reads it)
        if [ -f /data/integration/developer_mode_on_flag ]; then
            echo "  OK: /data/integration/developer_mode_on_flag exists"
        else
            echo "  NOTE: /data/integration/developer_mode_on_flag NOT found"
            echo "  Check if /data symlink is correct: ls -la /data"
        fi
        if [ -f /data/integration/developer_mode_GuiConfig.js ]; then
            echo "  OK: /data/integration/developer_mode_GuiConfig.js exists"
        fi
        echo ""
        echo "  >>> REBOOT THE CMU NOW (Mute + Navi 10 seconds) <<<"
        echo "  After reboot 'Terminal' appears in Settings menu (if the GUI supports it)"
        ;;

    dev-off|developer-off)
        echo "--- Developer Mode OFF (v2) ---"
        if [ -f /jci/scripts/developer_mode.sh ]; then
            sh /jci/scripts/developer_mode.sh off
        fi
        # Also remove manually from both locations (to be sure)
        rm -f /data/integration/developer_mode_on_flag 2>/dev/null
        rm -f /data/integration/eth0_on_flag 2>/dev/null
        rm -f /data/integration/developer_mode_GuiConfig.js 2>/dev/null
        rm -f /mnt/data/integration/developer_mode_on_flag 2>/dev/null
        rm -f /mnt/data_persist/integration/developer_mode_on_flag 2>/dev/null
        rm -f /mnt/data_persist/integration/developer_mode_GuiConfig.js 2>/dev/null
        sync
        echo "  Developer mode OFF (all flags removed)"
        echo "  >>> REBOOT THE CMU NOW (Mute + Navi 10 seconds) <<<"
        ;;

    terminal|term)
        echo "--- Start Terminal fullscreen (v2) ---"
        # Method 1: systemHooks.sh event 22 (v74 officially)
        if [ -f /jci/scripts/systemHooks.sh ]; then
            echo "  Call systemHooks.sh with event 22 (SYSTEM_TERMINAL)"
            sh /jci/scripts/systemHooks.sh 22
        elif [ -f /jci/scripts/run-terminal.sh ]; then
            echo "  systemHooks.sh not found, using run-terminal.sh directly"
            sh /jci/scripts/run-terminal.sh
        else
            # Method 3: manual (v59 fallback)
            echo "  run-terminal.sh not found, starting terminal manually..."
            export XDG_RUNTIME_DIR=/tmp
            export XDG_CONFIG_HOME=/tmp/root/
            export SHELL=/bin/sh
            mkdir -p /tmp/root/
            echo "" > /tmp/root/weston.ini 2>/dev/null
            modprobe usbhid 2>/dev/null
            /usr/bin/terminal -f > /dev/null 2>&1 &
            sleep 1
            ivi-shell -f "Wayland Terminal" > /dev/null 2>&1
            ivi-shell -z "Wayland Terminal":10000 > /dev/null 2>&1 &
            ivi-shell -a "Wayland Terminal":255 > /dev/null 2>&1 &
        fi
        echo "  Terminal started"
        ;;

    event-terminal|event22)
        echo "--- Send SYSTEM_TERMINAL event (22) via systemHooks.sh ---"
        if [ -f /jci/scripts/systemHooks.sh ]; then
            sh /jci/scripts/systemHooks.sh 22
            echo "  Event 22 sent"
        else
            echo "  systemHooks.sh not found! Use 'ui.sh terminal'"
        fi
        ;;

    run-terminal)
        echo "--- Start run-terminal.sh directly ---"
        if [ -f /jci/scripts/run-terminal.sh ]; then
            sh /jci/scripts/run-terminal.sh
            echo "  run-terminal.sh executed"
        else
            echo "  /jci/scripts/run-terminal.sh not found!"
            sh "$0" terminal
        fi
        ;;

    exit|close|back|ui)
        echo "--- Close terminal, back to normal UI ---"
        killall terminal 2>/dev/null
        pkill terminal 2>/dev/null
        sleep 1
        if ps 2>/dev/null | grep -v grep | grep -q terminal; then
            echo "  Terminal still running - force kill..."
            kill -9 $(pidof terminal) 2>/dev/null
        fi
        ivi-shell -f "Main" > /dev/null 2>&1 || true
        echo "  Terminal stopped"
        ;;

    status)
        echo "--- UI Terminal Status (v2) ---"
        echo ""
        echo "Filesystem check:"
        ls -la /data 2>/dev/null || echo "  /data does NOT exist (symlink missing!)"
        echo ""
        echo "Integration dir via /data:"
        ls -la /data/integration/ 2>/dev/null || echo "  /data/integration/ does not exist"
        echo ""
        echo "Integration dir via /mnt/data:"
        ls -la /mnt/data/integration/ 2>/dev/null || echo "  /mnt/data/integration/ does not exist"
        echo ""
        echo "Integration dir via /mnt/data_persist (v1 bug location):"
        ls -la /mnt/data_persist/integration/ 2>/dev/null || echo "  /mnt/data_persist/integration/ does not exist"
        echo ""
        echo "Developer mode flag check (GUI reads /data/integration/):"
        if [ -f /data/integration/developer_mode_on_flag ]; then
            echo "  ON - /data/integration/developer_mode_on_flag exists"
        else
            echo "  OFF - flag not found in /data/integration/"
        fi
        if [ -f /data/integration/developer_mode_GuiConfig.js ]; then
            echo "  GuiConfig ON - /data/integration/developer_mode_GuiConfig.js exists"
        else
            echo "  GuiConfig OFF - not found"
        fi
        echo ""
        echo "Scripts:"
        ls -la /jci/scripts/developer_mode.sh 2>/dev/null || echo "  developer_mode.sh NOT found"
        ls -la /jci/scripts/systemHooks.sh 2>/dev/null || echo "  systemHooks.sh NOT found"
        ls -la /jci/scripts/run-terminal.sh 2>/dev/null || echo "  run-terminal.sh NOT found"
        ls -la /jci/gui/common/js/developer_mode_GuiConfig.js 2>/dev/null || echo "  developer_mode_GuiConfig.js NOT found"
        ls -la /usr/bin/terminal 2>/dev/null || echo "  /usr/bin/terminal NOT found"
        echo ""
        echo "Terminal process:"
        ps 2>/dev/null | grep -v grep | grep terminal || echo "  not active"
        ;;

    fix|install)
        echo "--- Apply full UI Terminal Fix ---"
        sh "$0" dev
        echo ""
        echo "Next steps:"
        echo "  1. Reboot CMU: hold Mute + Navi 10 seconds"
        echo "  2. After reboot: Settings menu -> 'Terminal' button should appear"
        echo "  3. If the button is NOT there: use 'sh ui.sh terminal' to start directly"
        echo "  4. Make permanent with: sh install-terminal-menu.sh"
        ;;

    menu)
        echo "--- Explanation: Terminal button in settings menu ---"
        echo ""
        echo "How it works (v74 mechanism, also valid for v59):"
        echo "  1. /jci/gui/index.html optionally loads:"
        echo "     ../../data/integration/developer_mode_GuiConfig.js"
        echo "     (= /data/integration/developer_mode_GuiConfig.js)"
        echo "  2. If that file exists, it calls guiConfig._setDeveloperMode(true)"
        echo "  3. This enables debug features in the GUI"
        echo "  4. The Terminal button itself is triggered via systemHooks.sh event 22"
        echo ""
        echo "CRITICAL: /data must be a symlink to /mnt/data (or /mnt/data_persist)"
        echo "Otherwise the GUI can NEVER find the file, no matter where you put it!"
        echo ""
        echo "Quick flow:"
        echo "  sh ui.sh dev          # developer mode on (sets flags in /data/integration/)"
        echo "  # Reboot: Mute+Navi 10s"
        echo "  sh ui.sh terminal     # start terminal directly (event 22)"
        echo "  sh ui.sh exit         # back to UI"
        ;;

    *)
        echo "Usage: ui.sh <command>"
        echo ""
        echo "Commands:"
        echo "  dev / dev-on     - Developer mode ON (flags in /data/integration/) + GuiConfig"
        echo "  dev-off          - Developer mode OFF (remove all flags)"
        echo "  terminal         - Start fullscreen terminal (via systemHooks event 22)"
        echo "  event-terminal   - Only send event 22 to systemHooks.sh"
        echo "  run-terminal     - Execute run-terminal.sh directly"
        echo "  exit / back      - Close terminal, back to normal UI"
        echo "  status           - Show filesystem status + flags + scripts"
        echo "  fix / install    - Developer mode on + explanation of next steps"
        echo "  menu             - Explanation of how the Terminal button works"
        echo ""
        echo "After 'dev' ALWAYS reboot: Mute + Navi 10 seconds!"
        ;;
esac
