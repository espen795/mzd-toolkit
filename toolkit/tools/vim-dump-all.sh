#!/bin/sh
# ============================================================
# MZD Toolkit - VIM Dump ALL v1.0
# Collects ALL vehicle/VIM/CAN data at once and writes to USB.
# FIRST does USB UNLOCK (ensure_usb_rw) - NEVER logs without USB.
#
# Bevat:
#   1. System info (firmware, uptime, mem, load)
#   2. VIM process analyse (vim_app, svcjcivbs, SPI interrupts)
#   3. CAN bus status (public/private via BCM)
#   4. ALLE BCM data (speed, gear, wheels, brake, ignition, BSM, PSM)
#   5. ALLE EEM data (fuel, trip, CO2)
#   6. ALLE VWM warnings/alerts
#   7. ALLE DIAG DTCs (CMU + AVC + permanent)
#   8. Power/ACC status
#   9. Vehicle info (VIN, type)
#  10. D-Bus service lijst (alle com.jci.*)
#  11. D-Bus introspectie ALLE services (methods + signals)
#  12. VIM deep dive (dmesg warnings, /jci/vim files, strings)
#  13. Korte D-Bus signal capture (5 sec)
#
# Usage:
#   sh vim-dump-all.sh              -> everything to USB (default)
#   sh vim-dump-all.sh screen       -> everything to screen + USB
#   sh vim-dump-all.sh no-unlock    -> without USB unlock attempt (only if already rw)
# ============================================================

# Source shared library - REQUIRED, with fallback
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

MODE="${1:-usb}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
TS_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================================
# 1. USB DETECT + UNLOCK - IMPORTANT: this must come FIRST
# ============================================================
echo "========================================"
echo " VIM Dump ALL v1.0"
echo "========================================"
echo ""

if ! detect_usb; then
    echo "ERROR: No USB detected (no /tmp/mnt/sd* or /mnt/sd*)"
    echo "Insert the USB stick and try again."
    log_to_usb "vim-dump-all: NO USB found - aborted"
    exit 1
fi
echo "USB mount found: $USB_MOUNT"

if [ "$MODE" != "no-unlock" ]; then
    echo "USB unlock (ensure_usb_rw)..."
    if ensure_usb_rw; then
        echo "USB is READ-WRITE: $USB_MOUNT"
    else
        echo "ERROR: USB unlock failed - cannot write to $USB_MOUNT"
        echo "Try manually: sh tools/fix-usb-rw.sh"
        log_to_usb "vim-dump-all: USB unlock FAILED on $USB_MOUNT - aborted"
        exit 1
    fi
else
    # Only check whether already rw
    if touch "$USB_MOUNT/.rwtest_vim" 2>/dev/null; then
        rm -f "$USB_MOUNT/.rwtest_vim"
        echo "USB is al READ-WRITE: $USB_MOUNT"
    else
        echo "ERROR: USB is read-only and no-unlock mode active"
        exit 1
    fi
fi

# ============================================================
# 2. CREATE LOG DIRECTORY ON USB
# ============================================================
LOGDIR="$USB_MOUNT/mzd-toolkit/logs"
DUMPDIR="$LOGDIR/vim-dump-$TIMESTAMP"
if ! mkdir -p "$DUMPDIR" 2>/dev/null; then
    echo "ERROR: cannot create $DUMPDIR"
    log_to_usb "vim-dump-all: mkdir FAILED $DUMPDIR"
    exit 1
fi
MAINLOG="$DUMPDIR/vim-dump-all.log"
echo "Dump directory: $DUMPDIR"
echo "Main log:       $MAINLOG"
echo ""

# Helper: write to main log AND screen
out() {
    echo "$1"
    echo "$1" >> "$MAINLOG" 2>/dev/null
}

# Helper: write only to main log
log() {
    echo "$1" >> "$MAINLOG" 2>/dev/null
}

# ============================================================
# D-BUS HELPER - v4.7.3: JCI service bus (/tmp/dbus_service_socket),
# NOT --system (does not exist on MZD -> empty logs, see ANALYSIS-2026-11-01)
# ============================================================
dbus_get() {
    DEST="$1"; PATH_="$2"; IFM="$3"; shift 3
    OUT=$(jci_dbus_send --print-reply --dest="$DEST" "$PATH_" "$IFM" "$@" 2>&1)
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERR($RC)"
    else
        R=$(echo "$OUT" | grep -E "^\s+(variant|.*\s)(boolean|int|uint|string|byte|array)" | head -5 | sed 's/^ *//' | tr '\n' '|')
        if [ -z "$R" ]; then
            R=$(echo "$OUT" | grep -v "^method\|^signal\|^\s*$" | head -5 | tr '\n' '|')
        fi
        echo "$R"
    fi
}

# ============================================================
# HEADER
# ============================================================
out ""
out "################################################"
out "#  MZD VIM DUMP ALL v1.0"
out "#  Datum:     $TS_HUMAN"
out "#  Timestamp: $TIMESTAMP"
out "#  USB:       $USB_MOUNT"
out "#  Dump dir:  $DUMPDIR"
out "################################################"
out ""

out "========================================"
out " [0/13] ENGINE/IGNITION CHECK"
out "========================================"
warn_engine | while read line; do out "$line"; done
out ""

# ============================================================
# SECTION 1: SYSTEM INFO
# ============================================================
out "========================================"
out " [1/13] SYSTEM INFO"
out "========================================"
out "Firmware:  $(grep -i '^Version=' /jci/version.ini 2>/dev/null | cut -d= -f2)"
out "Hostname:  $(hostname 2>/dev/null)"
out "Uptime:    $(uptime 2>/dev/null)"
out "Kernel:    $(uname -r 2>/dev/null)"
out "LoadAvg:   $(cat /proc/loadavg 2>/dev/null)"
out "MemFree:   $(grep MemFree /proc/meminfo 2>/dev/null)"
out "MemTotal:  $(grep MemTotal /proc/meminfo 2>/dev/null)"
IP=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
out "WiFi IP:   ${IP:-none}"
out "WiFi MAC:  $(ifconfig wlan0 2>/dev/null | grep -i hwaddr | awk '{print $5}')"
out ""

# ============================================================
# SECTION 2: VIM PROCESS ANALYSIS
# ============================================================
out "========================================"
out " [2/13] VIM PROCESS ANALYSE"
out "========================================"
for proc in vim_app svcjcivbs vim-ping svcjcieem svcjcivwm svcjcivdt; do
    pids=$(ps 2>/dev/null | grep "$proc" | grep -v grep | awk '{print $1}')
    if [ -n "$pids" ]; then
        for pid in $pids; do
            out "$proc (PID $pid):"
            out "  cmdline: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
            out "  state:   $(grep '^State' /proc/$pid/status 2>/dev/null | awk '{print $2, $3}')"
            out "  vmRSS:   $(grep '^VmRSS' /proc/$pid/status 2>/dev/null | awk '{print $2}') kB"
        done
    else
        out "$proc: NOT ACTIVE"
    fi
done
out ""
out "SPI interrupts: $(grep spi_imx /proc/interrupts 2>/dev/null | tr '\n' ' ')"
out "spidev module:  $(grep spidev /proc/modules 2>/dev/null)"
out "GpioChip:       $(grep GpioChip /proc/modules 2>/dev/null)"
out ""

# ============================================================
# SECTION 3: CAN BUS STATUS
# ============================================================
out "========================================"
out " [3/13] CAN BUS STATUS"
out "========================================"
out "PublicCAN:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPublicCanStatus)"
out "PrivateCAN: $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrivateCanStatus)"
out "SocketCAN:  $([ -d /proc/net/can ] && echo 'present' || echo 'not present (CAN via VIM/SPI)')"
out "CAN modules: $(grep -i -E '^can|flexcan|mscan' /proc/modules 2>/dev/null | tr '\n' ' ')"
out ""

# ============================================================
# SECTION 4: BCM - ALL DATA
# ============================================================
out "========================================"
out " [4/13] BCM (Body Control Module) - ALLE DATA"
out "========================================"
out "CarSpeed:    $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0)"
out "CarSpeedThr: $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeedThrshld uint32:0)"
out "GearPos:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetGearPos)"
out "WheelSpeed:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetWheelSpeed)"
out "TransmLever: $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetTransmChangeLeverPosition)"
out "Ignition:    $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus)"
out "BrakePedal:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBrkPedalDepressedStatus)"
out "PrkBrk:      $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrkBrkActv)"
out "FuelCutOff:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetFuelCutOffStatus)"
out "TransmType:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.getEngineTransmissionType)"
out "BSMInfo:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBSMInfo)"
out "PSMInfo:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPSMInfo)"
out "PASCD:       $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPASCD)"
out "NoSpdRestr:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetNoSpeedRestrict_TouchDisplay)"
out "VideoRestr:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetVideoRestrict)"
out ""

# ============================================================
# SECTION 5: EEM - FUEL/TRIP
# ============================================================
out "========================================"
out " [5/13] EEM (Energy Economy) - BRANDSTOF/TRIP"
out "========================================"
out "EquippedData:   $(dbus_get com.jci.eem /com/jci/eem com.jci.eem.GetEquippedData)"
out "FuelType:       $(dbus_get com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetFuelType)"
out ""

# ============================================================
# SECTION 6: VWM - WARNINGS
# ============================================================
out "========================================"
out " [6/13] VWM (Vehicle Warning Module)"
out "========================================"
out "ActiveAlerts: $(dbus_get com.jci.vwm /com/jci/vwm com.jci.vwm.getActiveAlertList uint32:0)"
out "VWMData:      $(dbus_get com.jci.vwm /com/jci/vwm com.jci.vwm.GetVWMData)"
out ""

# ============================================================
# SECTION 7: DIAG - DTCs
# ============================================================
out "========================================"
out " [7/13] DIAG - DTCs / FAULTS"
out "========================================"
out "CMUFaults:  $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.ReadCMUFaults_Request)"
out "AVCFaults:  $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.ReadAVCFaults_Request)"
out "PermDTCLog: $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.PermanentDTCLog_Request)"
out ""

# ============================================================
# SECTION 8: POWER/ACC
# ============================================================
out "========================================"
out " [8/13] POWER / ACC"
out "========================================"
out "ACCStatus:   $(dbus_get com.jci.cpp.power /com/jci/cpp/power com.jci.cpp.power.Interface.GetCurrentAccStatus)"
out "SysState:    $(dbus_get com.jci.blmsystem /com/jci/blmsystem com.jci.blmsystem.Interface.GetCurrentSystemState 2>/dev/null)"
out ""

# ============================================================
# SECTION 9: VEHICLE INFO
# ============================================================
out "========================================"
out " [9/13] VEHICLE INFO"
out "========================================"
out "VIN:         $(dbus_get com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetVINData)"
out "VehicleType: $(dbus_get com.jci.vbs.settings /com/jci/vbs/settings com.jci.vbs.settings.GetVehicleType)"
out ""

# ============================================================
# SECTION 10: D-BUS SERVICE LIST
# ============================================================
out "========================================"
out " [10/13] D-BUS SERVICES (com.jci.*)"
out "========================================"
jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
    | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u | while read svc; do out "  $svc"; done
out "  Total: $(jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u | wc -l) services"
out ""

# ============================================================
# SECTION 11: D-BUS INTROSPECTION ALL SERVICES -> separate file
# ============================================================
out "========================================"
out " [11/13] D-BUS INTROSPECTION (to separate file)"
out "========================================"
INTROSPECT_FILE="$DUMPDIR/dbus-introspect-all.txt"
{
    echo "# MZD D-Bus Introspectie - $TS_HUMAN"
    echo ""
} > "$INTROSPECT_FILE"

for svc in $(jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u); do
    objpath=$(echo "$svc" | sed 's/^com\.//; s/\./\//g')
    objpath="/$objpath"
    {
        echo ""
        echo "========================================"
        echo "SERVICE: $svc"
        echo "PATH:    $objpath"
        echo "========================================"
        jci_dbus_send --print-reply --dest="$svc" "$objpath" org.freedesktop.DBus.Introspectable.Introspect 2>&1
    } >> "$INTROSPECT_FILE" 2>&1
    out "  introspect: $svc"
done
out "Introspection saved to: dbus-introspect-all.txt ($(wc -c < "$INTROSPECT_FILE" 2>/dev/null) bytes)"
out ""

# ============================================================
# SECTION 12: VIM DEEP DIVE -> separate file
# ============================================================
out "========================================"
out " [12/13] VIM DEEP DIVE (to separate file)"
out "========================================"
DEEP_FILE="$DUMPDIR/vim-deep-dive.txt"
{
    echo "# MZD VIM Deep Dive - $TS_HUMAN"
    echo ""
    echo "--- dmesg VIM warnings (vimAttributeStore) ---"
    dmesg 2>/dev/null | grep "vimAttributeStore" | tail -20
    echo "  (totaal: $(dmesg 2>/dev/null | grep -c 'vimAttributeStore') warnings)"
    echo ""
    echo "--- dmesg CAN errors ---"
    dmesg 2>/dev/null | grep -i -E "can.*(error|fail|missing|bus.off)" | tail -15
    echo ""
    echo "--- /jci/vim/ files ---"
    ls -la /jci/vim/ 2>/dev/null
    echo ""
    echo "--- /jci/vbs/ files ---"
    ls -la /jci/vbs/ 2>/dev/null
    echo ""
    echo "--- /jci/vbs/modules/ CAN-related ---"
    ls -la /jci/vbs/modules/ 2>/dev/null | grep -E "can|bcm|eem|vwm|diag|vdt"
    echo ""
    echo "--- vim_app strings (CAN/VIM/SPI, first 40) ---"
    strings /jci/vim/vim_app 2>/dev/null | grep -i -E "can|vim|spi|VIMC_|0x[0-9a-fA-F]{3}" | head -40
    echo ""
    echo "--- vim-ping strings ---"
    strings /jci/vim/vim-ping 2>/dev/null | grep -i -E "can|vim|usage|VIMC_" | head -20
} > "$DEEP_FILE" 2>&1
out "Deep dive saved to: vim-deep-dive.txt ($(wc -c < "$DEEP_FILE" 2>/dev/null) bytes)"
out ""

# ============================================================
# SECTION 13: D-BUS SIGNAL CAPTURE (5 sec) -> separate file
# ============================================================
out "========================================"
out " [13/13] D-BUS SIGNAL CAPTURE (5 sec live)"
out "========================================"
SIG_FILE="$DUMPDIR/dbus-signals-5sec.txt"
{
    echo "# MZD D-Bus Signals - $TS_HUMAN (5 sec per source)"
    echo ""
    echo "--- com.jci.vbs.bcm ---"
    run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.vbs.bcm'\"" 5 2>/dev/null | head -40
    echo ""
    echo "--- com.jci.eem ---"
    run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.eem'\"" 5 2>/dev/null | head -20
    echo ""
    echo "--- com.jci.vwm ---"
    run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.vwm'\"" 5 2>/dev/null | head -20
} > "$SIG_FILE" 2>&1
out "Signals saved to: dbus-signals-5sec.txt ($(wc -c < "$SIG_FILE" 2>/dev/null) bytes)"
out ""

# ============================================================
# SUMMARY + SYNC
# ============================================================
out "========================================"
out " SUMMARY"
out "========================================"
out "Dump dir:  $DUMPDIR"
out "Files:"
ls -la "$DUMPDIR" 2>/dev/null | while read line; do out "  $line"; done
out ""
out "Total size: $(du -sh "$DUMPDIR" 2>/dev/null | awk '{print $1}')"
out "Done: $TS_HUMAN"
out "################################################"

# Sync to USB (important for flash drives!)
sync 2>/dev/null
sleep 1
sync 2>/dev/null

echo ""
echo "========================================"
echo " DONE - all data on USB"
echo "========================================"
echo "Dir:  $DUMPDIR"
echo "Main: $MAINLOG"
ls -la "$DUMPDIR" 2>/dev/null
echo ""
echo "Remove USB safely after 'sync'"

log_to_usb "vim-dump-all: DONE - dump in $DUMPDIR ($(du -sh "$DUMPDIR" 2>/dev/null | awk '{print $1}'))"
exit 0
