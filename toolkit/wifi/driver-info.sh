#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/driver-info.sh (v4.8.0, punt 5.3)
# Logs which WiFi driver/firmware version is NOW active - so we
# can validate whether the v74 patch (upgrade-firmware-v74.sh) succeeded.
# Called at the top by EVERY wifi/* script.
# Output: stdout + run-log (if trap_cleanup is active).
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null

FW_DIR="/lib/firmware/ti-connectivity"
FW_FILE="$FW_DIR/wl128x-fw-4-sr.bin"

echo "=== DRIVER INFO (v${TOOLKIT_VERSION:-4.8.3}) ==="
echo "kernel:      $(uname -r 2>/dev/null)"
echo "boot_id:     $(cat /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-8)"
echo "fw file:     $FW_FILE"
if [ -f "$FW_FILE" ]; then
    echo "fw sha256:   $(sha256sum "$FW_FILE" 2>/dev/null | awk '{print $1}')"
    echo "fw size:     $(ls -la "$FW_FILE" 2>/dev/null | awk '{print $5}') bytes"
else
    echo "fw file:     MISSING"
fi
echo "fw version (dmesg):"
dmesg 2>/dev/null | grep -E "firmware booted|wl12xx.*Rev|wl1271" | tail -5 | sed 's/^/  /'
echo "modinfo wl12xx:"
modinfo wl12xx 2>/dev/null | grep -E "^(version|firmware):" | sed 's/^/  /' || echo "  (modinfo not available)"
echo "module path: /lib/modules/$(uname -r 2>/dev/null)/kernel/drivers/net/wireless/ti/wl12xx"
echo "wpa_supplicant processes:"
ps 2>/dev/null | grep wpa_supplicant | grep -v grep | sed 's/^/  /' || echo "  (none)"
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    echo "  pid $_wp cmdline: $(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')"
done
echo "interface wlan0:"
ifconfig wlan0 2>/dev/null | head -3 | sed 's/^/  /' || echo "  wlan0 not found"
echo ""
# Verdict: v74 = FRev 7.3.10.0.142, v59 = Rev 7.3.10.10.136
_DMESG=$(dmesg 2>/dev/null | grep -E "firmware booted")
if echo "$_DMESG" | grep -q "7.3.10.0.142"; then
    echo "VERDICT: FW=v74 (FRev 7.3.10.0.142) - v74 patch ACTIVE"
elif echo "$_DMESG" | grep -q "7.3.10.10.136"; then
    echo "VERDICT: FW=v59 (Rev 7.3.10.10.136) - v74 patch NOT active (v59 fallback?)"
elif [ -n "$_DMESG" ]; then
    echo "VERDICT: fw booted found but version unknown:"
    echo "$_DMESG" | tail -2 | sed 's/^/  /'
else
    echo "VERDICT: no 'firmware booted' in dmesg (ringbuffer small / loglevel=3) - check fw sha256 above"
fi
echo "================================"
