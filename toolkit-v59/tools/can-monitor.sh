#!/bin/sh
# ============================================================
# MZD Toolkit - CAN/VIM Monitor v1.0
# Continuous monitoring of all vehicle D-Bus signals + VIM status
# Logs to USB with timestamps. NON-BLOCKING in bg mode.
#
# Usage:
#   sh can-monitor.sh once              -> one-time snapshot
#   sh can-monitor.sh bg                -> background, max 30 min
#   sh can-monitor.sh bg 120            -> background, max 120 min
#   sh can-monitor.sh stop              -> stop running monitor
#   sh can-monitor.sh status            -> show status
# ============================================================

# Source shared library
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

PIDFILE="/tmp/toolkit-pids/can-monitor.pid"
ACTION="${1:-once}"
MAXMIN="${2:-30}"

# ============================================================
# USB LOG SETUP - logs to USB if available, else /tmp
# ============================================================
setup_log() {
    LOGFILE="/tmp/can-monitor.log"
    detect_usb || true
    if [ -n "$USB_MOUNT" ] && ensure_usb_rw; then
        LOGDIR="$USB_MOUNT/mzd-toolkit/logs"
        mkdir -p "$LOGDIR" 2>/dev/null
        if [ -d "$LOGDIR" ]; then
            LOGFILE="$LOGDIR/can-monitor-$(date +%Y%m%d-%H%M%S).log"
        fi
    fi
    echo "$LOGFILE"
}

LOGFILE=$(setup_log)

# ============================================================
# D-BUS HELPERS - v4.7.3: JCI service bus (/tmp/dbus_service_socket),
# NOT --system (does not exist on MZD -> empty logs, see ANALYSIS-2026-11-01)
# ============================================================
dbus_get() {
    # dbus_get <dest> <path> <interface.method> [args...]
    DEST="$1"; PATH_="$2"; IFM="$3"; shift 3
    OUT=$(jci_dbus_send --print-reply --dest="$DEST" "$PATH_" "$IFM" "$@" 2>&1)
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERR"
    else
        echo "$OUT" | grep -E "^\s+(variant|.*\s)(boolean|int|uint|string|byte|array)" | head -5 | sed 's/^ *//' | tr '\n' '|'
        # fallback: first data line
        if [ -z "$(echo "$OUT" | grep -E '^\s+(variant|.*\s)(boolean|int|uint|string|byte|array)')" ]; then
            echo "$OUT" | grep -v "^method\|^signal\|^\s*$" | head -5 | tr '\n' '|'
        fi
    fi
}

# ============================================================
# SNAPSHOT - all vehicle data in 1x
# ============================================================
take_snapshot() {
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "========================================"
        echo " CAN/VIM SNAPSHOT - $TS"
        echo "========================================"

        # --- VIM/SPI Status ---
        echo ""
        echo "--- VIM / SPI Status ---"
        echo "vim_app process: $(ps 2>/dev/null | grep vim_app | grep -v grep | head -1)"
        echo "VBS process:     $(ps 2>/dev/null | grep svcjcivbs | grep -v grep | head -1)"
        echo "SPI interrupts:  $(grep spi_imx /proc/interrupts 2>/dev/null | tr '\n' ' ')"
        echo "spidev module:   $(grep spidev /proc/modules 2>/dev/null)"
        echo "GpioChip module: $(grep GpioChip /proc/modules 2>/dev/null)"

        # --- CAN Status via BCM ---
        echo ""
        echo "--- CAN Bus Status (BCM) ---"
        echo "PublicCAN:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPublicCanStatus)"
        echo "PrivateCAN: $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrivateCanStatus)"

        # --- BCM: speed, acceleration, wheels ---
        echo ""
        echo "--- BCM (Body Control Module) ---"
        echo "CarSpeed:    $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0)"
        echo "GearPos:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetGearPos)"
        echo "WheelSpeed:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetWheelSpeed)"
        echo "Ignition:    $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus)"
        echo "BrakePedal:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBrkPedalDepressedStatus)"
        echo "PrkBrk:      $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrkBrkActv)"
        echo "FuelCutOff:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetFuelCutOffStatus)"
        echo "TransmType:  $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.getEngineTransmissionType)"
        echo "BSMInfo:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBSMInfo)"
        echo "PSMInfo:     $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPSMInfo)"

        # --- EEM: fuel, trip ---
        echo ""
        echo "--- EEM (Energy Economy) ---"
        echo "EquippedData: $(dbus_get com.jci.eem /com/jci/eem com.jci.eem.GetEquippedData)"
        echo "FuelType:     $(dbus_get com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetFuelType)"

        # --- VWM: warnings ---
        echo ""
        echo "--- VWM (Warnings) ---"
        echo "ActiveAlerts: $(dbus_get com.jci.vwm /com/jci/vwm com.jci.vwm.getActiveAlertList uint32:0)"
        echo "VWMData:      $(dbus_get com.jci.vwm /com/jci/vwm com.jci.vwm.GetVWMData)"

        # --- DIAG: DTCs ---
        echo ""
        echo "--- DIAG (DTCs / Faults) ---"
        echo "CMUFaults:  $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.ReadCMUFaults_Request)"
        echo "AVCFaults:  $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.ReadAVCFaults_Request)"
        echo "PermDTCLog: $(dbus_get com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.PermanentDTCLog_Request)"

        # --- Power/ACC ---
        echo ""
        echo "--- Power ---"
        echo "ACCStatus: $(dbus_get com.jci.cpp.power /com/jci/cpp/power com.jci.cpp.power.Interface.GetCurrentAccStatus)"

        # --- Vehicle Info ---
        echo ""
        echo "--- Vehicle Info ---"
        echo "VIN:         $(dbus_get com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetVINData)"
        echo "VehicleType: $(dbus_get com.jci.vbs.settings /com/jci/vbs/settings com.jci.vbs.settings.GetVehicleType)"

        # --- System ---
        echo ""
        echo "--- System ---"
        echo "Firmware: $(grep -i '^Version=' /jci/version.ini 2>/dev/null | cut -d= -f2)"
        echo "Uptime:   $(uptime 2>/dev/null)"
        IP=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
        echo "WiFi IP:  ${IP:-none}"
        echo "LoadAvg:  $(cat /proc/loadavg 2>/dev/null)"
        echo "MemFree:  $(grep MemFree /proc/meminfo 2>/dev/null)"

        # --- Alle actieve com.jci D-Bus services ---
        echo ""
        echo "--- D-Bus Services (com.jci.*) ---"
        dbus-send --address="$JCI_SERVICE_BUS_ADDR" --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
            | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u

        echo ""
        echo "========================================"
        echo " END SNAPSHOT - $TS"
        echo "========================================"
    }
}

# ============================================================
# VIM DEEP DIVE - extra VIM/SPI/CAN info
# ============================================================
vim_deep_dive() {
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "========================================"
        echo " VIM DEEP DIVE - $TS"
        echo "========================================"

        echo ""
        echo "--- VIM Process Details ---"
        for pid in $(ps 2>/dev/null | grep -E "vim_app|vim-ping" | grep -v grep | awk '{print $1}'); do
            echo "PID $pid:"
            cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' '; echo ""
            echo "  State: $(grep State /proc/$pid/status 2>/dev/null)"
            echo "  CPU:   $(grep VmRSS /proc/$pid/status 2>/dev/null)"
        done

        echo ""
        echo "--- VBS Process Details ---"
        for pid in $(ps 2>/dev/null | grep svcjcivbs | grep -v grep | awk '{print $1}'); do
            echo "PID $pid: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
            echo "  State: $(grep State /proc/$pid/status 2>/dev/null)"
        done

        echo ""
        echo "--- CAN-related kernel modules ---"
        grep -i -E "can|vim|vbs|spidev|gpio" /proc/modules 2>/dev/null

        echo ""
        echo "--- SPI devices ---"
        ls -la /dev/spidev* 2>/dev/null || echo "No /dev/spidev* devices"
        ls /sys/bus/spi/devices/ 2>/dev/null || echo "No SPI devices in sysfs"

        echo ""
        echo "--- VIM-related files in /jci ---"
        ls -la /jci/vim/ 2>/dev/null || echo "No /jci/vim/"
        ls -la /jci/vbs/ 2>/dev/null | head -20 || echo "No /jci/vbs/"

        echo ""
        echo "--- VIM attribute warnings from dmesg ---"
        dmesg 2>/dev/null | grep -i "vimAttribute\|GpioChip.*vim" | tail -10

        echo ""
        echo "--- CAN bus errors from dmesg ---"
        dmesg 2>/dev/null | grep -i -E "can.*error|can.*fail|can.*missing|bus.*off" | tail -10

        echo ""
        echo "--- VBS modules loaded ---"
        ls /jci/vbs/modules/ 2>/dev/null | grep -E "can|bcm|eem|vwm|diag|vdt" || echo "No modules dir"

        echo ""
        echo "========================================"
        echo " END VIM DEEP DIVE"
        echo "========================================"
    }
}

# ============================================================
# DBUS SIGNAL MONITOR - captures real-time signals (short duration)
# ============================================================
dbus_signal_capture() {
    DURATION="${1:-10}"
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "========================================"
        echo " DBUS SIGNALS CAPTURE ($DURATION sec) - $TS"
        echo "========================================"
        echo ""
        echo "--- com.jci.vbs.bcm signals ---"
        run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.vbs.bcm'\"" "$DURATION" 2>/dev/null | head -50
        echo ""
        echo "--- com.jci.eem signals ---"
        run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.eem'\"" "$DURATION" 2>/dev/null | head -30
        echo ""
        echo "--- com.jci.vwm signals ---"
        run_with_timeout "jci_dbus_monitor \"type='signal',sender='com.jci.vwm'\"" "$DURATION" 2>/dev/null | head -30
        echo ""
        echo "========================================"
        echo " END DBUS CAPTURE"
        echo "========================================"
    }
}

# ============================================================
# MAIN - command dispatch
# ============================================================
case "$ACTION" in
    stop)
        if [ -f "$PIDFILE" ]; then
            pid=$(cat "$PIDFILE" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
                sleep 1
                kill -9 "$pid" 2>/dev/null
                echo "CAN monitor $pid stopped"
                log_to_usb "can-monitor: stopped (PID $pid)"
            else
                echo "CAN monitor $pid was not running"
            fi
            rm -f "$PIDFILE"
        else
            echo "No CAN monitor active"
        fi
        exit 0
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "CAN monitor ACTIVE (PID $(cat "$PIDFILE"))"
            echo "Log: $LOGFILE"
            echo "Last 10 lines:"
            tail -10 "$LOGFILE" 2>/dev/null
        else
            echo "CAN monitor NOT active"
            echo "Last log: $LOGFILE"
        fi
        exit 0
        ;;
    once)
        warn_engine
        echo "CAN/VIM Snapshot to: $LOGFILE"
        take_snapshot >> "$LOGFILE" 2>&1
        vim_deep_dive >> "$LOGFILE" 2>&1
        # Also show on screen
        take_snapshot 2>&1 | head -80
        echo ""
        echo "Full log: $LOGFILE"
        log_to_usb "can-monitor: once snapshot to $LOGFILE"
        exit 0
        ;;
    signals)
        DUR="${2:-10}"
        warn_engine
        echo "D-Bus signal capture ($DUR sec) to: $LOGFILE"
        dbus_signal_capture "$DUR" >> "$LOGFILE" 2>&1
        dbus_signal_capture "$DUR" 2>&1 | head -60
        echo "Full log: $LOGFILE"
        log_to_usb "can-monitor: signals capture ($DUR sec)"
        exit 0
        ;;
    bg|"")
        # Check if already active
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "CAN monitor already running (PID $(cat "$PIDFILE")) - log: $LOGFILE"
            echo "Stop: sh can-monitor.sh stop"
            exit 0
        fi
        warn_engine
        ;;
esac

# ============================================================
# BACKGROUND MONITOR - loop with snapshots every 30 sec
# ============================================================
MAXITER=$((MAXMIN * 2))   # every 30 sec, so 2x per minute
mkdir -p "$(dirname "$PIDFILE")"

cat > /tmp/can-monitor-loop.sh << 'LOOPEOF'
#!/bin/sh
PIDFILE="/tmp/toolkit-pids/can-monitor.pid"
LOGFILE="__LOGFILE__"
MAXITER=__MAXITER__
echo $$ > "$PIDFILE"
echo "" >> "$LOGFILE"
echo "=== CAN Monitor started $(date) (max ${MAXITER} iterations x 30s) ===" >> "$LOGFILE"

# Redefine functions in the loop shell (common.sh NOT sourced here)
setup_log() { echo "$LOGFILE"; }

# v4.7.5 M1 (gate 0046b92): NO --system fallback - MZD only has the JCI service bus
jci_dbus_send() {
    if [ -S /tmp/dbus_service_socket ]; then
        dbus-send --address="unix:path=/tmp/dbus_service_socket" "$@"
    else
        echo "ERROR: /tmp/dbus_service_socket missing - no system bus on MZD" >&2
        return 1
    fi
}

warn_engine() {
    _o=$(jci_dbus_send --print-reply --dest=com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus 2>/dev/null)
    echo "$_o" | grep -q "byte 1" && echo "Engine/ignition: ON - CAN live" || echo "WARNING: engine/ignition OFF - CAN data empty/static (turn engine ON)"
    return 0
}

dbus_get() {
    DEST="$1"; PATH_="$2"; IFM="$3"; shift 3
    OUT=$(jci_dbus_send --print-reply --dest="$DEST" "$PATH_" "$IFM" "$@" 2>&1)
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERR"
    else
        echo "$OUT" | grep -E "^\s+(variant|.*\s)(boolean|int|uint|string|byte|array)" | head -3 | sed 's/^ *//' | tr '\n' '|'
        [ -z "$(echo "$OUT" | grep -E '^\s+(variant|.*\s)(boolean|int|uint|string|byte|array)')" ] && \
            echo "$OUT" | grep -v "^method\|^signal\|^\s*$" | head -3 | tr '\n' '|'
    fi
}

I=0
warn_engine >> "$LOGFILE" 2>&1
while [ "$I" -lt "$MAXITER" ]; do
    [ -f /tmp/toolkit-stop/STOP ] && { echo "$(date) STOP - can-monitor ends" >> "$LOGFILE"; break; }
    I=$((I+1))
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "--- [$TS] iter $I/$MAXITER ---"
        echo "Ignition:     $(jci_dbus_send --print-reply --dest=com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus 2>/dev/null | grep -oE 'byte [0-9]+|boolean (true|false)' | head -1)"
        # Only the key values in the loop (compact)
        echo "CAN pub/priv: $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPublicCanStatus) / $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrivateCanStatus)"
        echo "Speed/Gear:   $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0) / $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetGearPos)"
        echo "Wheels:       $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetWheelSpeed)"
        echo "Ign/Brake:    $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus) / $(dbus_get com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBrkPedalDepressedStatus)"
        echo "ACC:          $(dbus_get com.jci.cpp.power /com/jci/cpp/power com.jci.cpp.power.Interface.GetCurrentAccStatus)"
        echo "Alerts:       $(dbus_get com.jci.vwm /com/jci/vwm com.jci.vwm.getActiveAlertList uint32:0)"
        echo "vim_app:      $(ps 2>/dev/null | grep vim_app | grep -v grep | awk '{print $1}' | head -1)"
        echo "Load/Mem:     $(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3) / $(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2}')kB"
    } >> "$LOGFILE" 2>&1
    sleep 30
done
echo "" >> "$LOGFILE"
echo "=== CAN Monitor done $(date) after $I iterations ===" >> "$LOGFILE"
rm -f "$PIDFILE"
LOOPEOF

sed -i "s|__LOGFILE__|$LOGFILE|g; s|__MAXITER__|$MAXITER|g" /tmp/can-monitor-loop.sh
chmod +x /tmp/can-monitor-loop.sh

nohup /tmp/can-monitor-loop.sh > /dev/null 2>&1 &
echo $! > "$PIDFILE"

echo "CAN Monitor started in background (PID $(cat "$PIDFILE"))"
echo "Log: $LOGFILE"
echo "Max $MAXMIN minutes ($MAXITER iterations x 30s)"
echo "Stop: sh can-monitor.sh stop  OF  sh stop-all.sh"
echo "Status: sh can-monitor.sh status"
log_to_usb "can-monitor: bg started (PID $(cat "$PIDFILE"), max ${MAXMIN}min, log=$LOGFILE)"
exit 0
