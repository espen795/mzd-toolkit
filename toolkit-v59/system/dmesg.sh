#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Kernel Messages (dmesg)
# Shows kernel messages

echo "========================================"
echo " Kernel Messages (dmesg)"
echo "========================================"
echo ""

echo "--- All messages (last 100) ---"
dmesg 2>/dev/null | tail -100

echo ""
echo "--- WiFi/Broadcom ---"
dmesg 2>/dev/null | grep -i -E "wlan|wifi|sdio|bcmdhd|brcm|802.11"

echo ""
echo "--- USB ---"
dmesg 2>/dev/null | grep -i -E "usb|sd[a-z]|mass storage"

echo ""
echo "--- Network ---"
dmesg 2>/dev/null | grep -i -E "eth|net|dhcp|link"

echo ""
echo "--- Errors/Warnings ---"
dmesg 2>/dev/null | grep -i -E "error|fail|warn|timeout"

echo ""
echo "--- Everything to file ---"
dmesg > /tmp/mzd-dmesg-full.txt 2>&1
echo "Full dmesg: /tmp/mzd-dmesg-full.txt"
if [ -d ${TOOLKIT_DIR}/logs ]; then
    cp /tmp/mzd-dmesg-full.txt ${TOOLKIT_DIR}/logs/dmesg-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null
    echo "Copied to USB: logs/dmesg-*.txt"
fi
