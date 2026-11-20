#!/bin/sh
# ============================================================
# MZD Toolkit - VIM Deep Dive v1.0
# In-depth analysis of the VIM (Vehicle Interface Module):
# - Process details (vim_app, svcjcivbs)
# - SPI traffic analyse
# - CAN-related kernel modules and interrupts
# - /jci/vim/ and /jci/vbs/ file overview
# - dmesg VIM/CAN errors
# - D-Bus service health check
# Output to USB log.
#
# Usage:
#   sh vim-deep-dive.sh           -> full analysis to USB
#   sh vim-deep-dive.sh screen    -> screen only (short version)
# ============================================================

# Source shared library
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

MODE="${1:-usb}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================================
# USB LOG SETUP
# ============================================================
setup_log() {
    LOGFILE="/tmp/vim-deep-dive.log"
    detect_usb || true
    if [ -n "$USB_MOUNT" ] && ensure_usb_rw; then
        LOGDIR="$USB_MOUNT/mzd-toolkit/logs"
        mkdir -p "$LOGDIR" 2>/dev/null
        if [ -d "$LOGDIR" ]; then
            LOGFILE="$LOGDIR/vim-deep-dive-$(date +%Y%m%d-%H%M%S).log"
        fi
    fi
    echo "$LOGFILE"
}

LOGFILE=$(setup_log)

# v4.7.3: engine/ignition check - without ignition the CAN/VIM debug data is empty
warn_engine

# Helper: log to both USB and screen (if screen mode)
out() {
    echo "$1"
    [ "$MODE" != "screen" ] && echo "$1" >> "$LOGFILE" 2>/dev/null
}

out ""
out "################################################"
out "#  MZD VIM Deep Dive Report"
out "#  Datum: $TIMESTAMP"
out "#  Log:   $LOGFILE"
out "################################################"
out ""

# ============================================================
# 1. VIM PROCESS ANALYSIS
# ============================================================
out "========================================"
out " 1. VIM PROCESS ANALYSIS"
out "========================================"
out ""

for proc in vim_app svcjcivbs vim-ping; do
    pids=$(ps 2>/dev/null | grep "$proc" | grep -v grep | awk '{print $1}')
    if [ -n "$pids" ]; then
        for pid in $pids; do
            out "--- $proc (PID $pid) ---"
            out "  cmdline:  $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
            out "  state:    $(grep '^State' /proc/$pid/status 2>/dev/null)"
            out "  ppid:     $(grep '^PPid' /proc/$pid/status 2>/dev/null)"
            out "  threads:  $(grep '^Threads' /proc/$pid/status 2>/dev/null)"
            out "  vmRSS:    $(grep '^VmRSS' /proc/$pid/status 2>/dev/null)"
            out "  cpu time: $(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null) jiffies"
            # open files relevant to VIM
            out "  open FDs (SPI/CAN/dev):"
            ls -la /proc/$pid/fd/ 2>/dev/null | grep -E "spi|can|dev|vim" | head -10 | sed 's/^/    /' | while read line; do out "$line"; done
            out ""
        done
    else
        out "--- $proc: NOT ACTIVE ---"
        out ""
    fi
done

# ============================================================
# 2. SPI ANALYSIS (VIM communicates via SPI)
# ============================================================
out "========================================"
out " 2. SPI ANALYSIS"
out "========================================"
out ""
out "--- SPI kernel modules ---"
grep -i spi /proc/modules 2>/dev/null | while read line; do out "  $line"; done
out ""
out "--- SPI interrupts ---"
grep spi /proc/interrupts 2>/dev/null | while read line; do out "  $line"; done
out ""
out "--- SPI devices in sysfs ---"
ls -la /sys/bus/spi/devices/ 2>/dev/null | while read line; do out "  $line"; done
[ ! -d /sys/bus/spi/devices/ ] && out "  (no /sys/bus/spi/devices/)"
out ""
out "--- spidev character devices ---"
ls -la /dev/spidev* 2>/dev/null | while read line; do out "  $line"; done
[ ! -e /dev/spidev0.0 ] && out "  (no /dev/spidev* devices)"
out ""
out "--- SPI dmesg messages ---"
dmesg 2>/dev/null | grep -i spi | tail -20 | while read line; do out "  $line"; done
out ""

# ============================================================
# 3. CAN-RELATED KERNEL INFO
# ============================================================
out "========================================"
out " 3. CAN-RELATED KERNEL INFO"
out "========================================"
out ""
out "--- CAN modules in kernel ---"
grep -i -E "^can|flexcan|mscan|can_" /proc/modules 2>/dev/null | while read line; do out "  $line"; done
[ -z "$(grep -i -E '^can|flexcan|mscan' /proc/modules 2>/dev/null)" ] && out "  (no CAN kernel modules - expected: CAN goes via VIM/SPI, not SocketCAN)"
out ""
out "--- /proc/net/can (SocketCAN) ---"
[ -d /proc/net/can ] && cat /proc/net/can/* 2>/dev/null | while read line; do out "  $line"; done || out "  (no /proc/net/can - no SocketCAN)"
out ""
out "--- CAN errors in dmesg ---"
dmesg 2>/dev/null | grep -i -E "can.*(error|fail|missing|bus.off|warning)" | tail -15 | while read line; do out "  $line"; done
out ""

# ============================================================
# 4. VIM ATTRIBUTE / GPIO WARNINGS
# ============================================================
out "========================================"
out " 4. VIM GPIO ATTRIBUTE WARNINGS"
out "========================================"
out ""
out "--- vimAttributeStore warnings (count + laatste 10) ---"
VC=$(dmesg 2>/dev/null | grep -c "vimAttributeStore")
out "  Total: $VC warnings"
dmesg 2>/dev/null | grep "vimAttributeStore" | tail -10 | while read line; do out "  $line"; done
out ""
out "--- GpioChip module info ---"
grep GpioChip /proc/modules 2>/dev/null | while read line; do out "  $line"; done
out ""

# ============================================================
# 5. /jci/vim/ AND /jci/vbs/ FILES
# ============================================================
out "========================================"
out " 5. VIM/VBS FILES"
out "========================================"
out ""
out "--- /jci/vim/ ---"
ls -la /jci/vim/ 2>/dev/null | while read line; do out "  $line"; done
[ ! -d /jci/vim/ ] && out "  (no /jci/vim/)"
out ""
out "--- /jci/vbs/ ---"
ls -la /jci/vbs/ 2>/dev/null | while read line; do out "  $line"; done
out ""
out "--- /jci/vbs/modules/ (CAN-related) ---"
ls -la /jci/vbs/modules/ 2>/dev/null | grep -E "can|bcm|eem|vwm|diag|vdt|navi|settings" | while read line; do out "  $line"; done
out ""
out "--- /jci/lib/ VIM libraries ---"
ls -la /jci/lib/ 2>/dev/null | grep -i -E "vim|can|vbs" | while read line; do out "  $line"; done
out ""
out "--- Test CAN plugin ---"
ls -la /jci/testapp/plugins/ 2>/dev/null | grep -i can | while read line; do out "  $line"; done
out ""

# ============================================================
# 6. D-BUS SERVICE HEALTH - v4.7.3: JCI service bus (no --system)
# ============================================================
out "========================================"
out " 6. D-BUS SERVICE HEALTH"
out "========================================"
out ""
out "--- Alle com.jci.* services ---"
jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
    | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u | while read svc; do out "  $svc"; done
out ""

# Ping each service with a simple call
out "--- Service ping (GetCarSpeed as test) ---"
for svc in com.jci.vbs.bcm com.jci.vbs.eem com.jci.vbs.vwm com.jci.vbs.diag; do
    objpath=$(echo "$svc" | sed 's/^com\.//; s/\./\//g')
    objpath="/$objpath"
    rc=$(jci_dbus_send --print-reply --dest="$svc" "$objpath" org.freedesktop.DBus.Peer.Ping 2>&1 | grep -c "return")
    if [ "$rc" -gt 0 ]; then
        out "  $svc: OK (reageert)"
    else
        out "  $svc: NOT RESPONDING"
    fi
done
out ""

# ============================================================
# 7. VBS CONFIG
# ============================================================
out "========================================"
out " 7. VBS CONFIG"
out "========================================"
out ""
[ -f /jci/vbs/vbs.conf ] && { out "--- /jci/vbs/vbs.conf ---"; cat /jci/vbs/vbs.conf 2>/dev/null | while read line; do out "  $line"; done; } || out "  (no vbs.conf)"
out ""

# ============================================================
# 8. VIM BINARIES - strings analysis (limited)
# ============================================================
out "========================================"
out " 8. VIM BINARY INFO"
out "========================================"
out ""
if [ -f /jci/vim/vim_app ]; then
    out "--- vim_app: file info ---"
    file /jci/vim/vim_app 2>/dev/null | while read line; do out "  $line"; done
    out "--- vim_app: size ---"
    ls -la /jci/vim/vim_app | awk '{print "  " $5 " bytes"}' | while read line; do out "$line"; done
    out "--- vim_app: CAN/VIM related strings (first 30) ---"
    strings /jci/vim/vim_app 2>/dev/null | grep -i -E "can|vim|spi|VIMC_|0x[0-9a-fA-F]{3}" | head -30 | while read line; do out "  $line"; done
fi
out ""
if [ -f /jci/vim/vim-ping ]; then
    out "--- vim-ping: strings ---"
    strings /jci/vim/vim-ping 2>/dev/null | grep -i -E "can|vim|usage|VIMC_" | head -20 | while read line; do out "  $line"; done
fi
out ""

# ============================================================
# 9. SUMMARY
# ============================================================
out "========================================"
out " 9. SUMMARY"
out "========================================"
out ""
VIM_PID=$(ps 2>/dev/null | grep vim_app | grep -v grep | awk '{print $1}' | head -1)
VBS_PID=$(ps 2>/dev/null | grep svcjcivbs | grep -v grep | awk '{print $1}' | head -1)
SPI_COUNT=$(grep -c spi /proc/interrupts 2>/dev/null)
GPIO_WARN=$(dmesg 2>/dev/null | grep -c "vimAttributeStore")
DBUS_COUNT=$(jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u | wc -l)

out "  Engine/ignition:  $(engine_on && echo 'ON (live CAN data)' || echo 'OFF - start engine for debug logging')"
out "  vim_app active:     ${VIM_PID:-NO}"
out "  VBS service active: ${VBS_PID:-NO}"
out "  SPI interrupts:     $SPI_COUNT"
out "  GPIO warnings:      $GPIO_WARN"
out "  D-Bus services:     $DBUS_COUNT"
out "  SocketCAN:          $([ -d /proc/net/can ] && echo 'YES' || echo 'NO (via VIM/SPI)')"
out "  CAN raw access:     via VIM chip (SPI), not via /dev/can*"
out ""
out "  Report complete: $TIMESTAMP"
out "  Log file: $LOGFILE"
out "################################################"

log_to_usb "vim-deep-dive: report to $LOGFILE (vim_app=${VIM_PID:-no}, vbs=${VBS_PID:-no}, dbus=$DBUS_COUNT)"

if [ "$MODE" = "screen" ]; then
    echo ""
    echo "Full log: $LOGFILE"
fi

exit 0
