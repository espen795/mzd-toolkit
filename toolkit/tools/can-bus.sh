#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - CAN Bus Tools
# Mazda uses the CAN bus for internal communication

echo "========================================"
echo " CAN Bus Tools"
echo "========================================"
echo ""

echo "--- CAN interfaces ---"
ls -la /sys/class/net/can* 2>/dev/null || echo "No CAN interfaces"
ip link show 2>/dev/null | grep -i can || echo "ip link: no CAN"
echo ""

echo "--- CAN modules loaded? ---"
cat /proc/modules 2>/dev/null | grep -i -E "can|flexcan|mscan" || echo "No CAN modules"
echo ""

echo "--- CAN tools available? ---"
which candump 2>/dev/null && echo "candump: YES" || echo "candump: NO"
which cansend 2>/dev/null && echo "cansend: YES" || echo "cansend: NO"
which canconfig 2>/dev/null && echo "canconfig: YES" || echo "canconfig: NO"
echo ""

echo "--- CAN in kernel messages ---"
dmesg 2>/dev/null | grep -i -E "can|flexcan|mscan|can0|can1" | head -20
echo ""

echo "--- SocketCAN test ---"
# Check whether we can create CAN sockets
if [ -d /proc/net/can ]; then
    echo "SocketCAN stats:"
    cat /proc/net/can/* 2>/dev/null
else
    echo "No /proc/net/can"
fi
echo ""

echo "--- Mazda CAN bus info ---"
echo "Mazda MZD uses the CAN bus for:"
echo "  - Infotainment communication"
echo "  - Vehicle diagnostics (OBD-II)"
echo "  - Internal module communication"
echo ""
echo "Without CAN tools you can only read via:"
echo "  cat /proc/net/can/statistics"
echo "  cat /sys/class/net/can*/statistics/*"
