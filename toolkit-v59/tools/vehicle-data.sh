#!/bin/sh
# ============================================================
# vehicle-data-pull.sh - Mazda MZD Vehicle Data Puller
# ============================================================
# Pulls current vehicle data via D-Bus, shows on screen and logs to USB.
#
# Firmware: v74.00.324A (also works on v59 with SSH/diag)
# Requires: root access (autorun/SSH), dbus-send present
#
# Usage:
#   sh /tmp/mnt/sdX1/vehicle-data-pull.sh              # one-shot
#   sh /tmp/mnt/sdX1/vehicle-data-pull.sh watch        # every 5 sec (Ctrl-C stop, max 60 iter)
#   sh /tmp/mnt/sdX1/vehicle-data-pull.sh watch 60     # 60 iterations (~5 min) then stop
#
# Output:
#   - Screen: jci-dialog with summary
#   - /tmp/vehicle-data.log
#   - USB: <usb>/logs/vehicle-data-YYYYMMDD-HHMMSS.log
# ============================================================

# Source shared library (only if not already loaded)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup

LOGFILE="/tmp/vehicle-data.log"
TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S'; }

# ============================================================
# USB DETECT + RW REMOUNT - now via common.sh (detect_usb/ensure_usb_rw)
# ============================================================
find_usb() { detect_usb; }
make_usb_rw() { ensure_usb_rw; }

# ============================================================
# LOGGING - to /tmp AND USB
# ============================================================
USB_LOGFILE=""
setup_logging() {
    find_usb || true
    if [ -n "$USB_MOUNT" ]; then
        if make_usb_rw; then
            USB_LOG_DIR="$USB_MOUNT/logs"
            mkdir -p "$USB_LOG_DIR" 2>/dev/null
            if [ -d "$USB_LOG_DIR" ]; then
                USB_LOGFILE="$USB_LOG_DIR/vehicle-data-$(date +%Y%m%d-%H%M%S).log"
            fi
        fi
    fi
    # start log
    echo "========================================" > "$LOGFILE"
    echo "Vehicle Data Pull - $(TIMESTAMP)" >> "$LOGFILE"
    echo "========================================" >> "$LOGFILE"
    if [ -n "$USB_LOGFILE" ]; then
        echo "========================================" > "$USB_LOGFILE"
        echo "Vehicle Data Pull - $(TIMESTAMP)" >> "$USB_LOGFILE"
        echo "USB: $USB_MOUNT -> $USB_LOGFILE" >> "$USB_LOGFILE"
        echo "========================================" >> "$USB_LOGFILE"
    fi
}

log() {
    msg="[$(TIMESTAMP)] $1"
    echo "$msg" >> "$LOGFILE"
    echo "$msg"
    if [ -n "$USB_LOGFILE" ]; then
        echo "$msg" >> "$USB_LOGFILE"
    fi
}

log_raw() {
    echo "$1" >> "$LOGFILE"
    echo "$1"
    if [ -n "$USB_LOGFILE" ]; then
        echo "$1" >> "$USB_LOGFILE"
    fi
}

# ============================================================
# D-BUS HELPERS - v4.7.3: JCI service bus (/tmp/dbus_service_socket)
# ============================================================
# dbus_call <dest> <path> <interface.method> [args...]
# Return only the "return" value line (compact)
dbus_call() {
    DEST="$1"; PATH_="$2"; IFM="$3"; shift 3
    OUT=$(jci_dbus_send --print-reply --dest="$DEST" "$PATH_" "$IFM" "$@" 2>&1)
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERR($RC): $(echo "$OUT" | head -1)"
    else
        # Parse the first variant/value line
        echo "$OUT" | grep -E "^\s+(variant|.*\s)(boolean|int|uint|string|byte)" | head -3 | sed 's/^ *//' | tr '\n' ' '
        # If no match, show first data line
        if [ -z "$(echo "$OUT" | grep -E "^\s+(variant|.*\s)(boolean|int|uint|string|byte)")" ]; then
            echo "$OUT" | grep -v "^method\|^signal\|^\s*$" | head -3 | tr '\n' ' '
        fi
    fi
}

# ============================================================
# DATA PULL - all key vehicle signals
# ============================================================
pull_data() {
    log_raw ""
    log_raw "=== VEHICLE DATA PULL $(TIMESTAMP) ==="

    # --- Basic info ---
    log_raw "--- System ---"
    log_raw "Firmware:  $(grep -i '^Version=' /jci/version.ini 2>/dev/null | cut -d= -f2)"
    log_raw "Hostname:  $(hostname 2>/dev/null)"
    log_raw "Uptime:    $(uptime 2>/dev/null)"
    IP=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d: -f2 | head -1)
    log_raw "WiFi IP:   ${IP:-none}"

    # --- BCM: snelheid, versnelling, wielen, rem, contact ---
    log_raw ""
    log_raw "--- BCM (Body Control Module) ---"
    log_raw "CarSpeed:       $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0)"
    log_raw "GearPos:        $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetGearPos)"
    log_raw "WheelSpeed:     $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetWheelSpeed)"
    log_raw "Ignition:       $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus)"
    log_raw "BrakePedal:     $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetBrkPedalDepressedStatus)"
    log_raw "PrkBrk:         $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrkBrkActv)"
    log_raw "PublicCAN:      $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPublicCanStatus)"
    log_raw "PrivateCAN:     $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetPrivateCanStatus)"
    log_raw "FuelCutOff:     $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetFuelCutOffStatus)"
    log_raw "TransmType:     $(dbus_call com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.getEngineTransmissionType)"

    # --- EEM: fuel consumption, trip ---
    log_raw ""
    log_raw "--- EEM (Energy Economy) ---"
    log_raw "EquippedData:   $(dbus_call com.jci.eem /com/jci/eem com.jci.eem.GetEquippedData)"
    log_raw "FuelType:       $(dbus_call com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetFuelType)"

    # --- VWM: warnings ---
    log_raw ""
    log_raw "--- VWM (Warnings) ---"
    log_raw "ActiveAlerts:   $(dbus_call com.jci.vwm /com/jci/vwm com.jci.vwm.getActiveAlertList uint32:0)"
    log_raw "VWMData:        $(dbus_call com.jci.vwm /com/jci/vwm com.jci.vwm.GetVWMData)"

    # --- DIAG: DTCs ---
    log_raw ""
    log_raw "--- DIAG (DTCs) ---"
    log_raw "CMUFaults:      $(dbus_call com.jci.vbs.diag /com/jci/vbs/diag com.jci.vbs.diag.ReadCMUFaults_Request)"

    # --- Power/ACC ---
    log_raw ""
    log_raw "--- Power/ACC ---"
    log_raw "ACCStatus:      $(dbus_call com.jci.cpp.power /com/jci/cpp/power com.jci.cpp.power.Interface.GetCurrentAccStatus)"

    # --- Settings: belangrijke vehicle settings ---
    log_raw ""
    log_raw "--- Settings ---"
    log_raw "VehicleType:    $(dbus_call com.jci.vbs.settings /com/jci/vbs/settings com.jci.vbs.settings.GetVehicleType)"
    log_raw "VIN:            $(dbus_call com.jci.vbs.navi /com/jci/vbs/navi com.jci.vbs.navi.GetVINData)"

    # --- Available D-Bus services (overview) ---
    log_raw ""
    log_raw "--- D-Bus services (com.jci.*) ---"
    jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
        | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u | while read svc; do
            log_raw "  $svc"
        done

    log_raw ""
    log_raw "=== END PULL $(TIMESTAMP) ==="
    log_raw ""
}

# ============================================================
# SCREEN OUTPUT - jci-dialog with summary
# ============================================================
show_on_screen() {
    # Build short summary (max ~15 lines for Mazda screen)
    SUMMARY=$(tail -60 "$LOGFILE" 2>/dev/null | grep -E "CarSpeed|GearPos|Ignition|PublicCAN|PrivateCAN|ActiveAlerts|ACCStatus|FuelType|WiFi IP|Firmware" | head -12)
    if [ -z "$SUMMARY" ]; then
        SUMMARY="See log: $LOGFILE"
    fi
    if [ -n "$USB_LOGFILE" ]; then
        SUMMARY="$SUMMARY\n\nLog: $USB_LOGFILE"
    fi
    /jci/scripts/jci-dialog --info --title="Vehicle Data $(date '+%H:%M:%S')" --text="$SUMMARY" --ok 2>/dev/null
}

# ============================================================
# MAIN
# ============================================================
MODE="${1:-once}"
COUNT="${2:-0}"

setup_logging

# v4.7.3: engine/ignition check - debug logging without ignition is pointless
warn_engine

log "========================================"
log "  VEHICLE DATA PULLER v1.0"
log "  Mode: $MODE"
log "========================================"
if [ -n "$USB_LOGFILE" ]; then
    log "USB log: $USB_LOGFILE"
else
    log "WARN: No writable USB - only /tmp log"
fi
log "Local log: $LOGFILE"

if [ "$MODE" = "watch" ]; then
    # NON-BLOCKING: watch mode starts in background, CLI returns immediately
    # Max 30 iterations x 5s = 2.5 minutes
    VDPID="/tmp/toolkit-pids/vehicle-data.pid"
    mkdir -p "$(dirname "$VDPID")"
    cat > /tmp/vehicle-data-watch.sh << 'VEOF'
#!/bin/sh
LOGFILE="/tmp/vehicle-data.log"
echo $$ > "__VDPID__"
I=0
MAX=30
while [ "$I" -lt "$MAX" ]; do
    [ -f /tmp/toolkit-stop/STOP ] && break
    I=$((I+1))
    echo "=== pull $I/$MAX $(date) ===" >> "$LOGFILE"
    # Call parent script again in once mode for each pull
    sh "$0" once >> "$LOGFILE" 2>&1
    sleep 5
done
rm -f "__VDPID__"
VEOF
    sed -i "s|__VDPID__|$VDPID|g" /tmp/vehicle-data-watch.sh
    chmod +x /tmp/vehicle-data-watch.sh
    nohup /tmp/vehicle-data-watch.sh > /dev/null 2>&1 &
    echo $! > "$VDPID"
    echo "Vehicle data watch started in background (PID $(cat "$VDPID"))"
    echo "Max 30 pulls (2.5 min). Log: $LOGFILE"
    echo "Stop: sh stop-all.sh"
    exit 0
else
    pull_data
    show_on_screen
    log "Done. Log: $LOGFILE"
    [ -n "$USB_LOGFILE" ] && log "USB log: $USB_LOGFILE"
    sync 2>/dev/null
fi

log_to_usb "vehicle-data.sh done (mode=$MODE)"
exit 0
