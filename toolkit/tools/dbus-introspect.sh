#!/bin/sh
# ============================================================
# MZD Toolkit - D-Bus Introspection v1.0
# Fetches ALL methods + signals of every com.jci.* D-Bus service
# Output to USB log. Essential to see WHICH data is available.
#
# Usage:
#   sh dbus-introspect.sh              -> all services, to USB
#   sh dbus-introspect.sh bcm          -> only com.jci.vbs.bcm
#   sh dbus-introspect.sh vwm diag     -> several specific services
#   sh dbus-introspect.sh list         -> show only all service names
# ============================================================

# Source shared library
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

# ============================================================
# USB LOG SETUP
# ============================================================
setup_log() {
    LOGFILE="/tmp/dbus-introspect.log"
    detect_usb || true
    if [ -n "$USB_MOUNT" ] && ensure_usb_rw; then
        LOGDIR="$USB_MOUNT/mzd-toolkit/logs"
        mkdir -p "$LOGDIR" 2>/dev/null
        if [ -d "$LOGDIR" ]; then
            LOGFILE="$LOGDIR/dbus-introspect-$(date +%Y%m%d-%H%M%S).log"
        fi
    fi
    echo "$LOGFILE"
}

LOGFILE=$(setup_log)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# v4.7.3: engine/ignition check during vehicle D-Bus introspection
warn_engine

# ============================================================
# DBUS HELPERS - v4.7.3: JCI service bus (/tmp/dbus_service_socket)
# ============================================================
list_all_services() {
    jci_dbus_send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
        | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u
}

# Introspect a service: methods + signals
# introspect_service <service_name> <object_path>
introspect_service() {
    SVC="$1"
    OBJPATH="$2"
    {
        echo ""
        echo "========================================"
        echo " SERVICE: $SVC"
        echo " PATH:    $OBJPATH"
        echo "========================================"
        jci_dbus_send --print-reply --dest="$SVC" "$OBJPATH" org.freedesktop.DBus.Introspectable.Introspect 2>&1
    }
}

# ============================================================
# MAIN
# ============================================================
MODE="${1:-all}"

{
    echo ""
    echo "################################################"
    echo "#  MZD D-Bus Introspection Report"
    echo "#  Datum: $TIMESTAMP"
    echo "#  Log:   $LOGFILE"
    echo "################################################"
} >> "$LOGFILE"

case "$MODE" in
    list)
        echo "All com.jci.* D-Bus services:"
        list_all_services | tee -a "$LOGFILE"
        echo ""
        echo "Total: $(list_all_services | wc -l) services"
        echo "Log: $LOGFILE"
        exit 0
        ;;
esac

# Determine which services to introspect
if [ "$MODE" = "all" ]; then
    SERVICES=$(list_all_services)
else
    # Specific services from args
    SERVICES=""
    for arg in "$@"; do
        case "$arg" in
            bcm)  SERVICES="$SERVICES com.jci.vbs.bcm" ;;
            eem)  SERVICES="$SERVICES com.jci.vbs.eem com.jci.eem" ;;
            vwm)  SERVICES="$SERVICES com.jci.vbs.vwm com.jci.vwm" ;;
            diag) SERVICES="$SERVICES com.jci.vbs.diag" ;;
            vdt)  SERVICES="$SERVICES com.jci.vbs.vdt com.jci.vdt" ;;
            navi) SERVICES="$SERVICES com.jci.vbs.navi" ;;
            settings) SERVICES="$SERVICES com.jci.vbs.settings com.jci.settings" ;;
            power) SERVICES="$SERVICES com.jci.cpp.power" ;;
            *)    SERVICES="$SERVICES com.jci.$arg" ;;
        esac
    done
fi

echo "Introspecting $(echo $SERVICES | wc -w) services to $LOGFILE"
echo ""

for svc in $SERVICES; do
    # Derive object path from service name: com.jci.vbs.bcm -> /com/jci/vbs/bcm
    objpath=$(echo "$svc" | sed 's/^com\.//; s/\./\//g')
    objpath="/$objpath"
    # Fix: com.jci.eem -> /com/jci/eem (al correct), com.jci.cpp.power -> /com/jci/cpp/power
    echo "Introspecting $svc ($objpath)..."
    introspect_service "$svc" "$objpath" >> "$LOGFILE" 2>&1

    # Also try alternate paths
    alt1=$(echo "$svc" | sed 's/\./\//g')
    if [ "$alt1" != "$objpath" ]; then
        introspect_service "$svc" "/$alt1" >> "$LOGFILE" 2>&1
    fi
done

# Summary: count methods and signals per service
{
    echo ""
    echo "################################################"
    echo "#  SUMMARY"
    echo "################################################"
    for svc in $SERVICES; do
        objpath=$(echo "$svc" | sed 's/^com\.//; s/\./\//g')
        objpath="/$objpath"
        methods=$(jci_dbus_send --print-reply --dest="$svc" "$objpath" org.freedesktop.DBus.Introspectable.Introspect 2>/dev/null | grep -c "method name=")
        signals=$(jci_dbus_send --print-reply --dest="$svc" "$objpath" org.freedesktop.DBus.Introspectable.Introspect 2>/dev/null | grep -c "signal name=")
        echo "$svc: $methods methods, $signals signals"
    done
    echo ""
    echo "Report complete: $TIMESTAMP"
} >> "$LOGFILE"

echo ""
echo "Done! Log: $LOGFILE"
echo ""
echo "=== Summary ==="
tail -30 "$LOGFILE" 2>/dev/null
log_to_usb "dbus-introspect: report to $LOGFILE ($(echo $SERVICES | wc -w) services)"
exit 0
