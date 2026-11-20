#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1   # v4.8.0 point 5.3: log fw/driver version in every wifi run
# MZD Toolkit - Check WiFi Firmware
# Checks whether all required firmware files are present

echo "========================================"
echo " WiFi Firmware Check"
echo "========================================"
echo ""
echo "WiFi Chip: TI WL1271/WL1283"
echo "Firmware location: /lib/firmware/ti-connectivity/"
echo ""

FW_DIR="/lib/firmware/ti-connectivity"

echo "--- Firmware directory ---"
ls -la "$FW_DIR" 2>&1
echo ""

echo "--- Required firmware files ---"
FILES="wl128x-fw-4-sr.bin wl1271-nvs.bin wl127x-fw-4-sr.bin wl127x-nvs.bin"

for fw in $FILES; do
    echo -n "Check $fw... "
    if [ -f "$FW_DIR/$fw" ]; then
        size=$(wc -c < "$FW_DIR/$fw")
        echo "OK ($size bytes)"
    elif [ -L "$FW_DIR/$fw" ]; then
        target=$(readlink "$FW_DIR/$fw")
        if [ -f "$target" ]; then
            size=$(wc -c < "$target")
            echo "OK (symlink -> $target, $size bytes)"
        else
            echo "SYMLINK BUT TARGET MISSING -> $target"
        fi
    else
        echo "MISSING!"
    fi
done

echo ""
echo "--- NVS Calibration file (CRITICAL!) ---"
NVS="$FW_DIR/wl1271-nvs.bin"
if [ -L "$NVS" ]; then
    target=$(readlink "$NVS")
    echo "NVS is symlink to: $target"
    if [ -f "$target" ]; then
        echo "NVS calibration data PRESENT ($(wc -c < "$target") bytes)"
        echo ""
        echo "First 64 bytes (hex):"
        od -A x -t x1 "$target" 2>/dev/null | head -4
    else
        echo "NVS calibration data MISSING!"
        echo ""
        echo "PROBLEM: Without NVS file WiFi does not work properly!"
        echo ""
        echo "Look for NVS file elsewhere:"
        find / -name "wl1271-nvs*" -o -name "wl12xx-nvs*" -o -name "*-nvs.bin" 2>/dev/null | head -10
        echo ""
        echo "Or generate with:"
        echo "  wl1271-nvs-tool (if available)"
        echo "  or copy from a working system"
    fi
elif [ -f "$NVS" ]; then
    echo "NVS file present ($(wc -c < "$NVS") bytes)"
else
    echo "NVS file MISSING!"
fi

echo ""
echo "--- WiFi firmware in kernel log ---"
dmesg 2>/dev/null | grep -i -E "wl12xx|wl1271|ti-connectivity|firmware|wlcore" | head -20
echo ""

echo "--- Module firmware requests ---"
dmesg 2>/dev/null | grep -i "firmware" | tail -10
echo ""

echo "--- Check /lib/firmware algemeen ---"
ls -la /lib/firmware/ 2>&1 | head -20
echo ""

echo "--- Alternative firmware locations ---"
for dir in /lib/firmware /system/etc/firmware /vendor/firmware /data/misc/wifi; do
    if [ -d "$dir" ]; then
        echo "$dir:"
        ls "$dir" 2>/dev/null | grep -i -E "wl|ti|wireless" | head -5
    fi
done
