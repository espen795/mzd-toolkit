#!/bin/sh
# MZD Toolkit - Menu Library (v4.8.0 thin shim)
# Contains ONLY UI helpers. All path/logic functions live in lib/common.sh.
# Sourced by menu.sh - do NOT run standalone.
#
# menu.sh sets _MLIB_DIR="$(dirname "$0")/menu.lib" BEFORE sourcing this file.

# Source the canonical lib (lib/common.sh) - do NOT set path vars here
if [ "${TOOLKIT_LIB_LOADED:-0}" != "1" ]; then
    if [ -n "${_MLIB_DIR:-}" ] && [ -f "$_MLIB_DIR/../lib/common.sh" ]; then
        . "$_MLIB_DIR/../lib/common.sh"
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
    elif [ -f "$(dirname "$0")/../lib/common.sh" ]; then
        . "$(dirname "$0")/../lib/common.sh"
    elif [ -n "${TOOLKIT_DIR:-}" ] && [ -f "$TOOLKIT_DIR/lib/common.sh" ]; then
        . "$TOOLKIT_DIR/lib/common.sh"
    fi
fi

# ============================================================
# UI HELPERS
# ============================================================

# Clear screen (portable: blank lines instead of terminal escape codes)
clear_screen() {
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
}

# compatibility alias (old menu.sh used 'clear')
clear() {
    clear_screen
}

# Standard header for all menus
show_header() {
    clear_screen
    echo "========================================"
    echo "       MZD TOOLKIT v${TOOLKIT_VERSION:-4.8.10}"
    echo "========================================"
    echo ""
}

# Wait for Enter (after running an action)
pause() {
    echo ""
    echo "Press Enter to continue..."
    read dummy
}

# ============================================================
# STATUS FUNCTIONS
# ============================================================

# WiFi / network status line (wlan0, usb0 tether or wlan1 dongle)
show_wifi_status() {
    IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet " | awk '{print $2}' | sed 's/addr://')
    if [ -n "$IP" ]; then
        echo "WiFi:     CONNECTED (wlan0) - IP: $IP"
        return
    fi
    IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet " | awk '{print $2}' | sed 's/addr://')
    if [ -n "$IP" ]; then
        echo "Network:  CONNECTED (usb0 tether) - IP: $IP"
        return
    fi
    IP=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP" ] && IP=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet " | awk '{print $2}' | sed 's/addr://')
    if [ -n "$IP" ]; then
        echo "WiFi:     CONNECTED (wlan1 dongle) - IP: $IP"
        return
    fi
    echo "Network:  NOT CONNECTED"
}

# SSH status line: active/inactive + port if detected
show_ssh_status() {
    if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
        # try to detect port from config
        PORT=$(grep -i "^Port " /tmp/sshd/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
        if [ -n "$PORT" ]; then
            echo "SSH:      ACTIVE (port $PORT)"
        else
            echo "SSH:      ACTIVE (port 36000)"
        fi
    else
        echo "SSH:      INACTIVE"
    fi
}

# Show both status lines (for main menu)
show_status() {
    show_wifi_status
    show_ssh_status
}

# Current IP (wlan0, usb0 or wlan1) - for display in submenus
get_wifi_ip() {
    _ip=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$_ip" ] && _ip=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$_ip" ] && _ip=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "$_ip"
}

# ============================================================
# MENU HELPERS
# ============================================================

# Read a menu choice from the user
# usage: read_choice
read_choice() {
    echo -n "Choice: "
    read choice
    echo ""
}

# Invalid choice message
invalid_choice() {
    echo "Invalid choice. Try again."
    sleep 2
}
