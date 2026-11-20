#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Quick System Info
# Shows basic system information on screen

echo "========================================"
echo " MZD System Info"
echo "========================================"
echo ""

echo "--- Identiteit ---"
echo "User:    $(whoami)"
echo "Host:    $(hostname)"
echo "Date:    $(date)"
echo "Uptime:  $(uptime 2>/dev/null || cat /proc/uptime)"
echo ""

echo "--- Firmware ---"
cat /jci/version.ini 2>/dev/null || echo "version.ini not found"
echo ""

echo "--- Kernel ---"
uname -a
echo ""

echo "--- Network ---"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "WiFi IP: ${IP:-not connected}"
MAC=$(ifconfig wlan0 2>/dev/null | grep "HWaddr" | awk "{print \$5}")
echo "WiFi MAC: ${MAC:-unknown}"
echo ""

echo "--- Geheugen ---"
cat /proc/meminfo 2>/dev/null | head -5
echo ""

echo "--- Storage ---"
df -h 2>/dev/null || df
echo ""

echo "--- USB Mounts ---"
ls -la /tmp/mnt/ 2>/dev/null || echo "No USB mounts"
echo ""

echo "--- SSH Status ---"
if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
    echo "SSH: ACTIVE"
else
    echo "SSH: INACTIVE"
fi
echo ""

echo "--- Last 5 processes ---"
ps 2>/dev/null | tail -5
