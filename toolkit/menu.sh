#!/bin/sh
# MZD Toolkit - Master Menu v4.8.1
# Structure: quick actions on top, then submenus. No asterisks.

# ============================================================
# SETUP - v4.8.1: source canonical lib + bootstrap_paths BEFORE anything
# ============================================================
SCRIPT_DIR=$(dirname "$0" 2>/dev/null)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="."

if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    . "$SCRIPT_DIR/lib/common.sh"
elif [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    . "$SCRIPT_DIR/../lib/common.sh"
elif [ -n "${TOOLKIT_DIR:-}" ] && [ -f "$TOOLKIT_DIR/lib/common.sh" ]; then
    . "$TOOLKIT_DIR/lib/common.sh"
else
    for _d in /mnt/data_persist/mzd-toolkit /data_persist/mzd-toolkit /tmp/mnt/data_persist/mzd-toolkit /mnt/data_persist/dev/bin; do
        if [ -f "$_d/lib/common.sh" ]; then
            . "$_d/lib/common.sh"
            break
        fi
    done
fi
if type bootstrap_paths >/dev/null 2>&1; then
    bootstrap_paths 2>/dev/null
fi
if type trap_cleanup >/dev/null 2>&1; then
    trap_cleanup 2>/dev/null
fi

_MLIB_DIR="${TOOLKIT_DIR:-$SCRIPT_DIR}/menu.lib"
[ -d "$_MLIB_DIR" ] || _MLIB_DIR="$SCRIPT_DIR/menu.lib"

if [ -f "$_MLIB_DIR/common.sh" ]; then
    . "$_MLIB_DIR/common.sh"
fi

# Minimal fallbacks if the lib could not be loaded
if ! type clear_screen >/dev/null 2>&1; then
    clear_screen() { echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; }
    clear() { clear_screen; }
    show_header() { clear_screen; echo "========================================"; echo "       MZD TOOLKIT v${TOOLKIT_VERSION:-4.8.10}"; echo "========================================"; echo ""; }
    pause() { echo ""; echo "Press Enter to continue..."; read dummy; }
    show_wifi_status() {
        IP=$(ifconfig wlan0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -z "$IP" ] && IP=$(ifconfig usb0 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -z "$IP" ] && IP=$(ifconfig wlan1 2>/dev/null | grep -m1 "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        [ -n "$IP" ] && echo "Network: CONNECTED - IP: $IP" || echo "Network: NOT CONNECTED"
    }
    show_ssh_status() { ps 2>/dev/null | grep sshd | grep -v grep >/dev/null && echo "SSH:  ACTIVE" || echo "SSH:  INACTIVE"; }
    read_choice() { echo -n "Choice: "; read choice; echo ""; }
    invalid_choice() { echo "Invalid choice. Try again."; sleep 2; }
    TOOLKIT_DIR="${TOOLKIT_DIR:-}"
    USB_MOUNT="${USB_MOUNT:-}"
fi

# ============================================================
# MAIN MENU v4.8.1 - quick actions first, then submenus
# ============================================================
main_menu() {
    if type usb_health_check >/dev/null 2>&1; then
        usb_health_check >/dev/null 2>&1
    fi
    while true; do
        show_header
        show_wifi_status
        show_ssh_status
        echo ""
        echo "--- QUICK ACTIONS ---"
        echo ""
        echo "  1. WiFi quick connect"
        echo "  2. SSH setup (port 36000)"
        echo "  3. All-in-one: WiFi + SSH + watchdog"
        echo "  4. Dump everything to USB"
        echo "  5. CAN/VIM dump to USB"
        echo ""
        echo "--- MENUS ---"
        echo ""
        echo "  6. WiFi"
        echo "  7. SSH"
        echo "  8. Network (USB-Ethernet)"
        echo "  9. Diagnostics & logs"
        echo " 10. VIM/CAN"
        echo " 11. System & security"
        echo " 12. Tools"
        echo ""
        echo "  0. Exit"
        echo ""
        read_choice

        case "$choice" in
            1)
                if ! "$TOOLKIT_DIR/wifi/quick-connect.sh"; then
                    echo "CONNECT FAILED - see $LOG_DIR/runs/"
                fi
                pause ;;
            2)
                "$TOOLKIT_DIR/ssh/quick-fix-working.sh"
                pause ;;
            3)
                if ! "$TOOLKIT_DIR/FIX-ALL.sh"; then
                    echo "FIX-ALL FAILED - see $LOG_DIR/runs/"
                fi
                pause ;;
            4)
                "$TOOLKIT_DIR/system/dump.sh"
                pause ;;
            5)
                "$TOOLKIT_DIR/tools/vim-dump-all.sh"
                pause ;;
            6) wifi_menu ;;
            7) ssh_menu ;;
            8) net_menu ;;
            9) diagnostics_menu ;;
            10) vim_menu ;;
            11) system_menu ;;
            12) tools_menu ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# WIFI MENU v4.8.1 - streamlined
# ============================================================
wifi_menu() {
    while true; do
        show_header
        show_wifi_status
        echo ""
        echo "--- WIFI ---"
        echo ""
        echo "  1. Status + scan + driver/fw version"
        echo "  2. Quick connect (SSID from settings.conf)"
        echo "  3. Interactive connect (scan -> pick AP -> psk)"
        echo "  4. WiFi off / reset + reconnect"
        echo "  5. Power save permanently off (via autorun)"
        echo "  6. AP mode on/off (phone straight to CMU, bypasses hotspot isolation)"
        echo "  7. USB WiFi dongle (rt2800 -> wlan1, separate from wlan0)"
        echo "  8. Swap wl12xx DRIVER to v74 build (chip firmware stays v59)"
        echo "  9. Rollback wl12xx driver to v59 (if problems)"
        echo " 10. USB tether from Android phone (usb0, no wl12xx)"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1)
                "$TOOLKIT_DIR/wifi/status.sh"
                echo ""
                "$TOOLKIT_DIR/wifi/driver-info.sh"
                echo ""
                echo "--- Scan (NMS D-Bus) ---"
                "$TOOLKIT_DIR/wifi/scan-v74.sh"
                pause
                ;;
            2)
                if ! "$TOOLKIT_DIR/wifi/quick-connect.sh"; then
                    echo "CONNECT FAILED - see $LOG_DIR/runs/"
                    pause
                    return
                fi
                pause ;;
            3)
                if ! "$TOOLKIT_DIR/wifi/connect-interactive.sh"; then
                    echo "CONNECT FAILED/CANCELLED"
                    pause
                    return
                fi
                pause ;;
            4)
                echo "Disabling WiFi..."
                "$TOOLKIT_DIR/wifi/disconnect.sh"
                echo ""
                echo "Reset + reconnect..."
                "$TOOLKIT_DIR/wifi/reset-wifi.sh" >/dev/null 2>&1
                if ! "$TOOLKIT_DIR/wifi/quick-connect.sh"; then
                    echo "RECONNECT FAILED - see $LOG_DIR/runs/"
                fi
                pause ;;
            5)
                "$TOOLKIT_DIR/wifi/fix-powersave-permanent.sh"
                pause ;;
            6)
                echo "Enable AP mode (CMU becomes its own WiFi AP)? (y/n, 'off' = off)"
                read apans
                case "$apans" in
                    off|OFF) "$TOOLKIT_DIR/wifi/ap-mode.sh" off ;;
                    y|Y|yes|YES|j|J|ja|JA|"") "$TOOLKIT_DIR/wifi/ap-mode.sh" ;;
                    *) echo "Not changed" ;;
                esac
                pause ;;
            7)
                if ! "$TOOLKIT_DIR/wifi/usb-dongle.sh"; then
                    echo "DONGLE CONNECT FAILED - see run-log in $LOG_DIR/runs/"
                fi
                pause ;;
            8)
                echo "WARNING: this replaces wl12xx.ko/wl12xx_sdio.ko with the v74 build."
                echo "Chip firmware (sr.bin) stays v59. Auto-rollback on boot-fail via autorun hook."
                echo "Confirm? (y/n)"
                read swans
                case "$swans" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/wifi/swap-driver-v74.sh" ;;
                    *) echo "Cancelled" ;;
                esac
                pause ;;
            9)
                echo "Rollback wl12xx driver to v59 backup? (y/n)"
                read rbans
                case "$rbans" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/wifi/rollback-driver-v59.sh" ;;
                    *) echo "Cancelled" ;;
                esac
                pause ;;
            10)
                if ! "$TOOLKIT_DIR/wifi/usb-tether.sh"; then
                    echo "TETHER FAILED - see run-log in $LOG_DIR/runs/"
                fi
                pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# SSH MENU
# ============================================================
ssh_menu() {
    while true; do
        show_header
        show_ssh_status
        IP=$(get_wifi_ip 2>/dev/null)
        echo "IP: ${IP:-not available}"
        echo ""
        echo "--- SSH ---"
        echo ""
        echo "  1. Quick setup (port 36000)"
        echo "  2. Start SSH (pubkey)"
        echo "  3. Stop SSH"
        echo "  4. Fix auth + deploy pubkey"
        echo "  5. Fix SSH pubkey (CRLF/perms) + restart"
        echo "  6. SSH with password (short, no cert)"
        echo "  7. Status + connect info"
        echo "  8. Test SSH connection"
        echo "  9. Install SSH permanently"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/ssh/quick-fix-working.sh"; pause ;;
            2) "$TOOLKIT_DIR/ssh/start.sh"; pause ;;
            3) "$TOOLKIT_DIR/ssh/stop.sh"; pause ;;
            4)
                "$TOOLKIT_DIR/ssh/fix-auth.sh"
                "$TOOLKIT_DIR/ssh/set-password.sh"
                pause
                ;;
            5) "$TOOLKIT_DIR/ssh/fix-ssh.sh"; pause ;;
            6)
                echo -n "Password (empty = 'mzd', 'off' = off): "
                read pw
                "$TOOLKIT_DIR/ssh/ssh-pwd.sh" "${pw:-mzd}"
                pause ;;
            7) "$TOOLKIT_DIR/ssh/connect-info.sh"; pause ;;
            8) "$TOOLKIT_DIR/ssh/test.sh"; pause ;;
            9) "$TOOLKIT_DIR/tools/install-ssh.sh"; pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# NETWORK (USB-Ethernet) MENU
# ============================================================
net_menu() {
    while true; do
        show_header
        show_wifi_status
        echo ""
        echo "--- NETWORK (USB-Ethernet) ---"
        echo ""
        echo "  1. eth up   (static IP 192.168.0.2/24)"
        echo "  2. eth down"
        echo "  3. eth status (ifconfig + route)"
        echo "  4. Set default gateway (for hop to home network)"
        echo "  5. Autostart eth1 + SSH pwd setup (v4.8.12)"
        echo "  6. Fix SSH pubkey + start sshd (port 36000)"
        echo "  7. Copy logs to USB"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/net/eth.sh" up; pause ;;
            2) "$TOOLKIT_DIR/net/eth.sh" down; pause ;;
            3) "$TOOLKIT_DIR/net/eth.sh" status; pause ;;
            4)
                echo -n "Gateway IP (empty = 192.168.0.1): "
                read gw
                "$TOOLKIT_DIR/net/eth.sh" gw "${gw:-192.168.0.1}"
                pause ;;
            5) "$TOOLKIT_DIR/tools/install-autostart.sh"; pause ;;
            6) "$TOOLKIT_DIR/ssh/fix-ssh.sh"; pause ;;
            7) "$TOOLKIT_DIR/wifi/copy-logs-usb.sh"; pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# DIAGNOSTICS & LOGS MENU
# ============================================================
diagnostics_menu() {
    while true; do
        show_header
        echo "--- DIAGNOSTICS & LOGS ---"
        echo ""
        echo "  1. Quick info"
        echo "  2. Network diagnostics"
        echo "  3. WiFi debug snapshot to USB"
        echo "  4. View logs (interactive)"
        echo "  5. Show run-logs on USB (latest runs)"
        echo "  6. dmesg / kernel messages"
        echo "  7. Processes"
        echo "  8. Storage / mounts"
        echo "  9. Hardware info"
        echo " 10. Serial/UART debug"
        echo " 11. Map OS to USB (os-map)"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/system/info.sh"; pause ;;
            2) "$TOOLKIT_DIR/system/network.sh"; pause ;;
            3) "$TOOLKIT_DIR/wifi/debug-v74.sh"; pause ;;
            4) "$TOOLKIT_DIR/tools/log-viewer.sh"; pause ;;
            5)
                echo "Latest run-logs in ${LOG_DIR:-/tmp/toolkit-logs}/runs/:"
                ls -t "${LOG_DIR:-/tmp/toolkit-logs}/runs/" 2>/dev/null | head -10
                echo ""
                echo -n "Open run dir (paste name, empty = no): "
                read runname
                if [ -n "$runname" ] && [ -f "${LOG_DIR:-/tmp/toolkit-logs}/runs/$runname/stdout.log" ]; then
                    tail -40 "${LOG_DIR:-/tmp/toolkit-logs}/runs/$runname/stdout.log"
                    echo ""
                    echo "--- exit.code: $(cat "${LOG_DIR:-/tmp/toolkit-logs}/runs/$runname/exit.code" 2>/dev/null) ---"
                fi
                pause
                ;;
            6) "$TOOLKIT_DIR/system/dmesg.sh"; pause ;;
            7) "$TOOLKIT_DIR/system/process.sh"; pause ;;
            8) "$TOOLKIT_DIR/system/storage.sh"; pause ;;
            9) "$TOOLKIT_DIR/system/hardware.sh"; pause ;;
            10) "$TOOLKIT_DIR/tools/serial-debug.sh"; pause ;;
            11) "$TOOLKIT_DIR/system/os-map.sh"; pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# SYSTEM & SECURITY MENU
# ============================================================
system_menu() {
    while true; do
        show_header
        echo "--- SYSTEM & SECURITY ---"
        echo ""
        echo "  1. Unlock OS (experimental)"
        echo "  2. Remount read-write"
        echo "  3. Fix startup warning"
        echo "  4. Start terminal (diag code 22, direct)"
        echo "  5. Close terminal / back to UI"
        echo "  6. Add terminal to settings menu (patch + reboot needed)"
        echo "  7. Reboot"
        echo "  8. Shutdown"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/system/unlock-os.sh"; pause ;;
            2) "$TOOLKIT_DIR/system/remount-rw.sh"; pause ;;
            3) "$TOOLKIT_DIR/tools/fix-warning.sh"; pause ;;
            4)
                # v4.8.3: direct via MMUI diag-code 22 - works WITHOUT GUI patch/reboot
                echo "Starting terminal via MMUI ReadDTC testId=22..."
                if [ -S /tmp/dbus_service_socket ]; then
                    dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
                        --dest=com.jci.testdiag /com/jci/testdiag com.jci.testdiag.ReadDTC int32:22 2>&1 | head -3
                    echo "  (if this does not work: check if /jci/scripts/run-terminal.sh exists)"
                    [ -f /jci/scripts/run-terminal.sh ] && sh /jci/scripts/run-terminal.sh
                else
                    echo "  /tmp/dbus_service_socket missing - fallback run-terminal.sh:"
                    [ -f /jci/scripts/run-terminal.sh ] && sh /jci/scripts/run-terminal.sh || echo "  run-terminal.sh not found"
                fi
                pause ;;
            5)
                echo "Stopping terminal, back to UI..."
                killall terminal 2>/dev/null
                pkill terminal 2>/dev/null
                sleep 1
                kill -9 $(pidof terminal 2>/dev/null) 2>/dev/null
                ivi-shell -f "Main" >/dev/null 2>&1
                echo "  Done"
                pause ;;
            6)
                echo "Current patch status syssettingsApp.js:"
                grep -c 'MZD-TERMINAL-MENU-PATCHED\|MZD-TERMINAL-CASE-PATCHED' /jci/gui/apps/syssettings/js/syssettingsApp.js 2>/dev/null | sed 's/^/  markers: /'
                "$TOOLKIT_DIR/tools/add-terminal-menu.sh"
                echo ""
                echo "NOTE: reboot the CMU (Mute+Navi 10s) to load the patched JS + i18n dict."
                echo "Without reboot the System tab may stay 'Loading'."
                echo "Without reboot item 4 (diag 22 direct) DOES work."
                pause ;;
            7) echo "Rebooting..."; reboot ;;
            8) echo "Shutting down..."; poweroff ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# TOOLS MENU v4.8.1 - stop/status here, watchdog/monitor at the end
# ============================================================
tools_menu() {
    while true; do
        show_header
        echo "--- TOOLS ---"
        echo ""
        echo "  1. Backup to USB"
        echo "  2. Fix USB read-write"
        echo "  3. Firmware info"
        echo "  4. GUI dump to USB"
        echo "  5. WiFi watchdog monitor (background, 2 hours)"
        echo "  6. System monitor (background, 5 min)"
        echo "  7. Cleanup /tmp + old logs"
        echo "  8. Show driver/fw version (validate v74 patch)"
        echo "  9. Upgrade WiFi firmware v74 (rollback available)"
        echo " 10. Rollback WiFi firmware to v59 (if watchdogs)"
        echo ""
        echo " 11. Status running processes"
        echo " 12. Stop everything (kill all running scripts)"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/tools/backup.sh"; pause ;;
            2) "$TOOLKIT_DIR/tools/fix-usb-rw.sh"; pause ;;
            3) "$TOOLKIT_DIR/tools/firmware-info.sh"; pause ;;
            4) "$TOOLKIT_DIR/tools/gui-dump.sh"; pause ;;
            5)
                "$TOOLKIT_DIR/wifi/fix-watchdog.sh" status
                echo ""
                echo "Start watchdog in background? (y/n)"
                read ans
                case "$ans" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/wifi/fix-watchdog.sh" monitor ;;
                    *) echo "Not started" ;;
                esac
                pause
                ;;
            6) "$TOOLKIT_DIR/tools/monitor.sh" bg; pause ;;
            7) "$TOOLKIT_DIR/tools/cleanup.sh"; pause ;;
            8) "$TOOLKIT_DIR/wifi/driver-info.sh"; pause ;;
            9) "$TOOLKIT_DIR/wifi/upgrade-firmware-v74.sh"; pause ;;
            10)
                echo "WARNING: this rolls the wl128x firmware back to v59 (Rev 7.3.10.10.136)."
                echo "Use this ONLY if v74 watchdog interrupts keep happening. Confirm? (y/n)"
                read rbans
                case "$rbans" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/wifi/rollback-firmware-v59.sh" ;;
                    *) echo "Cancelled" ;;
                esac
                pause ;;
            11) "$TOOLKIT_DIR/status.sh"; pause ;;
            12) "$TOOLKIT_DIR/stop-all.sh"; pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# VIM/CAN MENU
# ============================================================
vim_menu() {
    while true; do
        show_header
        echo "--- VIM / CAN BUS ---"
        echo ""
        echo "  NOTE: engine on for meaningful CAN/VIM data"
        echo ""
        echo "  1. Dump everything to USB (complete)"
        echo "  2. CAN/VIM snapshot (one-shot)"
        echo "  3. CAN monitor background (30 min)"
        echo "  4. CAN monitor stop / status"
        echo "  5. D-Bus signals capture (10 sec live)"
        echo "  6. D-Bus introspect all services"
        echo "  7. D-Bus introspect list (names only)"
        echo "  8. VIM deep dive"
        echo "  9. Vehicle data pull (speed/gear/DTC/VIN)"
        echo " 10. CAN bus info (basic)"
        echo ""
        echo "  0. Back"
        echo ""
        read_choice

        case "$choice" in
            1) "$TOOLKIT_DIR/tools/vim-dump-all.sh"; pause ;;
            2) "$TOOLKIT_DIR/tools/can-monitor.sh" once; pause ;;
            3)
                echo "Start CAN monitor in background (30 min)? (y/n)"
                read ans
                case "$ans" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/tools/can-monitor.sh" bg 30 ;;
                    *) echo "Not started" ;;
                esac
                pause
                ;;
            4)
                "$TOOLKIT_DIR/tools/can-monitor.sh" status
                echo ""
                echo "Stop? (y/n)"
                read ans2
                case "$ans2" in
                    y|Y|yes|YES|j|J|ja|JA) "$TOOLKIT_DIR/tools/can-monitor.sh" stop ;;
                    *) echo "Not stopped" ;;
                esac
                pause
                ;;
            5) "$TOOLKIT_DIR/tools/can-monitor.sh" signals 10; pause ;;
            6) "$TOOLKIT_DIR/tools/dbus-introspect.sh" all; pause ;;
            7) "$TOOLKIT_DIR/tools/dbus-introspect.sh" list; pause ;;
            8) "$TOOLKIT_DIR/tools/vim-deep-dive.sh"; pause ;;
            9) "$TOOLKIT_DIR/tools/vehicle-data.sh" once; pause ;;
            10) "$TOOLKIT_DIR/tools/can-bus.sh"; pause ;;
            0) return ;;
            *) invalid_choice ;;
        esac
    done
}

# ============================================================
# START
# ============================================================
main_menu
