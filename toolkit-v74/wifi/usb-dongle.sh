#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/usb-dongle.sh (v4.8.4)
# Loads a Ralink RT2800 USB WiFi dongle as wlan1, separate from the
# instabiele wl12xx/wlan0. Modules + firmware komen uit de v74
# rootfs (vermagic 3.0.35 ARMv7 = match met v59 CMU).
#
# IMPORTANT: NMS manages wlan0 - this dongle gets wlan1 and its
# OWN wpa_supplicant instance (never killall, see v4.7.5 M2).
# The Mazda GUI does NOT see wlan1 (NMS only knows wlan0).
#
# Exit codes: 0 = wlan1 has IP, 4 = dongle not detected,
#             5 = module load gefaald, 6 = connect gefaald.
# PsK via env MZD_PSK (never argv).
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TD="${TOOLKIT_DIR:-$(dirname "$0")/..}"
MODDIR="$TD/wifi/rt2800-modules"
FWDIR="$TD/wifi/rt2800-firmware"
IFC="wlan1"

echo "========================================"
echo " USB WiFi dongle (rt2800) -> $IFC (v4.8.4)"
echo "========================================"

# settings + secrets (zelfde patroon als quick-connect.sh)
for _sc in "${SETTINGS_DIR:-}/settings.conf" "$TD/config/settings.conf"; do
    [ -n "$_sc" ] && [ -f "$_sc" ] && . "$_sc" 2>/dev/null && break
done
for _sec in "${SETTINGS_DIR:-}/secrets.conf" "$TD/config/secrets.conf"; do
    [ -n "$_sec" ] && [ -f "$_sec" ] && . "$_sec" 2>/dev/null && break
done
SSID="${WIFI_SSID:-${1:-YOUR_HOTSPOT_SSID}}"
PASSWORD="${MZD_PSK:-${WIFI_PASSWORD:-${2:-}}}"

sh "$TD/wifi/driver-info.sh" 2>/dev/null

# --- 1. modules present? ---
for m in crc-ccitt.ko rt2x00lib.ko rt2x00usb.ko rt2800lib.ko rt2800usb.ko; do
    [ -f "$MODDIR/$m" ] || { echo "ERROR: module missing: $MODDIR/$m"; exit 5; }
done
[ -f "$FWDIR/rt2870.bin" ] || { echo "ERROR: firmware missing: $FWDIR/rt2870.bin"; exit 5; }

# --- 2. firmware path to toolkit dir (rootfs is ro) ---
# kernel 3.0: /sys/module/firmware_class/parameters/path
FWPATH=/sys/module/firmware_class/parameters/path
OLDFW=""
[ -f "$FWPATH" ] && OLDFW=$(cat "$FWPATH" 2>/dev/null)
echo "$FWDIR" > "$FWPATH" 2>/dev/null || echo "WARNING: could not set firmware path (may be normal if already set)"
echo "firmware path: $(cat "$FWPATH" 2>/dev/null)"

# --- 3. load modules in dep order (mac80211/cfg80211/rfkill already loaded by wl12xx) ---
for m in crc-ccitt rt2x00lib rt2x00usb rt2800lib rt2800usb; do
    if grep -q "^$m " /proc/modules 2>/dev/null; then
        echo "  $m: already loaded"
    else
        echo -n "  insmod $m... "
        if insmod "$MODDIR/$m.ko" 2>/dev/null; then echo "OK"; else echo "GEFAALD"; exit 5; fi
    fi
done

# --- 4. trigger dongle (if already plugged in before insmod: new_id bind) ---
# lees VID:PID van usb devices met Ralink vendor 148f
VIDPID=""
for d in /sys/bus/usb/devices/*/idVendor; do
    [ -f "$d" ] || continue
    v=$(cat "$d" 2>/dev/null); p=$(cat "$(dirname "$d")/idProduct" 2>/dev/null)
    [ "$v" = "148f" ] && VIDPID="$v $p"
done
if [ -n "$VIDPID" ] && [ -f /sys/bus/usb/drivers/rt2800usb/new_id ]; then
    echo "$VIDPID" > /sys/bus/usb/drivers/rt2800usb/new_id 2>/dev/null && echo "  new_id bound: $VIDPID"
fi
sleep 3

# --- 5. wlan1 present? ---
if ! ifconfig "$IFC" >/dev/null 2>&1; then
    echo "ERROR: $IFC not found - dongle not detected or other chipset"
    echo "check: ls /sys/bus/usb/devices/ en dmesg | tail -20"
    exit 4
fi
ifconfig "$IFC" up 2>/dev/null
echo "$IFC up: $(ifconfig "$IFC" 2>/dev/null | grep -m1 HWaddr)"

# --- 6. own wpa_supplicant on wlan1 (NMS instance on wlan0 untouched!) ---
CONF=/tmp/wpa-dongle.$$.conf
{
    echo "ctrl_interface=/var/run/wpa_supplicant-$IFC"
    echo "network={"
    echo "  ssid=\"$SSID\""
    if [ -n "$PASSWORD" ]; then
        echo "  psk=\"$PASSWORD\""
        echo "  key_mgmt=WPA-PSK"
    else
        echo "  key_mgmt=NONE"
    fi
    echo "}"
} > "$CONF"
chmod 600 "$CONF"

# kill ONLY an old dongle instance (never the NMS wpa_supplicant on wlan0)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        *"-i $IFC"*) kill "$_wp" 2>/dev/null ;;
    esac
done
sleep 1

wpa_supplicant -B -i "$IFC" -D nl80211 -c "$CONF" 2>&1
sleep 3

# wait for associate (max ~20s)
ST=""
i=0
while [ $i -lt 10 ]; do
    ST=$(wpa_cli -p "/var/run/wpa_supplicant-$IFC" -i "$IFC" status 2>/dev/null | grep -m1 "^wpa_state=" | cut -d= -f2)
    [ "$ST" = "COMPLETED" ] && break
    i=$((i+1)); sleep 2
done
echo "wpa_state=$ST"
if [ "$ST" != "COMPLETED" ]; then
    echo "CONNECT GEFAALD op $IFC (state=$ST)"
    rm -f "$CONF"
    exit 6
fi

# --- 7. DHCP op wlan1 ---
echo "udhcpc op $IFC..."
udhcpc -i "$IFC" -n -q -t 5 -T 3 2>&1 | tail -3
IP=$(ifconfig "$IFC" 2>/dev/null | grep -m1 "inet addr" | sed 's/.*inet addr:\([0-9.]*\).*/\1/')
if [ -z "$IP" ]; then
    echo "NO IP on $IFC"
    rm -f "$CONF"
    exit 6
fi
echo "OK: $IFC has IP $IP (SSID=$SSID)"
echo "SSH: ssh -p 36000 cmu@$IP -i <id_mzd>"
rm -f "$CONF"
exit 0
