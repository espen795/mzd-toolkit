#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/ap-mode.sh (v4.8.3)
# Put the CMU in WiFi AP mode via Mazda's own hostapd+udhcpd
# (inspired by /jci/scripts/jci-wifiap.sh in v74 firmware).
#
# WHY: NMS WIFI_SetMode(mode=2) gave NoReply (proven run r3
# 2026-11-03 11:40). hostapd works - Mazda uses it itself.
#
#: How it works:
#   - wlan0 krijgt statisch 192.168.53.1/24
#   - hostapd start AP met SSID "CMU-<MAC>" (channel 1, open of WPA)
#   - udhcpd geeft leases 192.168.53.20-254
#   - phone connects -> direct route to CMU (no hotspot isolation)
#
# Usage:  sh ap-mode.sh          -> AP on (default SSID CMU-<MAC>)
#           sh ap-mode.sh off      -> AP off, back to client mode
#           sh ap-mode.sh "SSID" "WPA password"  -> secured AP
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
sh "$(dirname "$0")/driver-info.sh" >/dev/null 2>&1

IFACE="wlan0"
AP_IP="192.168.53.1"
AP_MASK="255.255.255.0"
DHCP_START="192.168.53.20"
DHCP_END="192.168.53.254"
HOSTAPD_CONF="/tmp/mzd-hostapd.conf"
UDHCPD_CONF="/tmp/mzd-udhcpd.conf"

MAC=$(ifconfig $IFACE 2>/dev/null | grep "HWaddr" | awk '{print $5}' | tr -d ':')
SSID="${1:-CMU-$MAC}"
[ "$1" = "off" ] && SSID=""
PSK="${2:-}"

if [ "$1" = "off" ]; then
    echo "========================================"
    echo " MZD AP-mode OFF (v4.8.3)"
    echo "========================================"
    killall hostapd udhcpd 2>/dev/null
    ifconfig $IFACE down 2>/dev/null
    sleep 1
    ifconfig $IFACE up 2>/dev/null
    echo "AP stopped. Back to client: WiFi menu -> 2 (quick connect)"
    exit 0
fi

echo "========================================"
    echo " MZD AP-mode ON (v4.8.3)"
echo " SSID: $SSID"
echo " IP:   $AP_IP/$AP_MASK"
echo "========================================"
echo ""

# hostapd present?
if ! command -v hostapd >/dev/null 2>&1; then
    for p in /usr/sbin/hostapd /sbin/hostapd /jci/bin/hostapd; do
        [ -x "$p" ] && HOSTAPD="$p" && break
    done
fi
HOSTAPD="${HOSTAPD:-$(command -v hostapd 2>/dev/null)}"
if [ -z "$HOSTAPD" ]; then
    echo "ERROR: hostapd not found (look in /usr/sbin /sbin /jci/bin)"
    exit 1
fi
echo "hostapd: $HOSTAPD"

# Stop existing client connection (otherwise conflicts with wpa_supplicant)
# v4.7.5 rule: NEVER kill the NMS wpa_supplicant - only disconnect via NMS
if [ -S /tmp/dbus_service_socket ]; then
    IFCID=$(dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
        --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.GetInterfaceList 2>/dev/null \
        | grep -oE 'int32 [0-9]+' | awk '{print $2}' | tail -1)
    [ -n "$IFCID" ] && dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
        --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.Disconnect int32:$IFCID >/dev/null 2>&1
fi
killall udhcpc 2>/dev/null
sleep 1

# Configure interface
ifconfig $IFACE down 2>/dev/null
sleep 1
ifconfig $IFACE $AP_IP netmask $AP_MASK up 2>/dev/null && echo "  $IFACE = $AP_IP up"

# hostapd.conf
{
    echo "interface=$IFACE"
    echo "driver=nl80211"
    echo "channel=1"
    echo "hw_mode=g"
    echo "ssid=$SSID"
    if [ -n "$PSK" ]; then
        echo "wpa=2"
        echo "wpa_passphrase=$PSK"
        echo "wpa_key_mgmt=WPA-PSK"
        echo "rsn_pairwise=CCMP"
    fi
} > "$HOSTAPD_CONF"
echo "  hostapd.conf written ($([ -n "$PSK" ] && echo WPA2 || echo open))"

# udhcpd.conf
{
    echo "start $DHCP_START"
    echo "end   $DHCP_END"
    echo "interface $IFACE"
    echo "option subnet $AP_MASK"
    echo "opt router $AP_IP"
    echo "opt dns $AP_IP"
    echo "option lease 864000"
} > "$UDHCPD_CONF"

# Start hostapd (background)
"$HOSTAPD" -B "$HOSTAPD_CONF" 2>&1
sleep 2
if pidof hostapd >/dev/null 2>&1; then
    echo "  hostapd RUNNING (pid $(pidof hostapd))"
else
    echo "  WARNING: hostapd did not start - trying foreground debug:"
    "$HOSTAPD" "$HOSTAPD_CONF" 2>&1 | head -5 &
    sleep 3
    pidof hostapd >/dev/null 2>&1 && echo "  hostapd is running now" || echo "  hostapd fails - check dmesg"
fi

# Start udhcpd
if command -v udhcpd >/dev/null 2>&1 || [ -x /sbin/udhcpd ]; then
    udhcpd "$UDHCPD_CONF" 2>/dev/null || /sbin/udhcpd "$UDHCPD_CONF" 2>/dev/null
    echo "  udhcpd started (leases $DHCP_START-$DHCP_END)"
fi

sleep 1
echo ""
echo "========================================"
    echo " AP ACTIVE"
echo "========================================"
echo " SSID: $SSID"
    echo " CMU IP: $AP_IP"
    echo " Connect your phone to '$SSID'"
    echo " Then: ssh -p 36000 cmu@$AP_IP  (from phone)"
    echo " AP off: sh $0 off"
echo "========================================"
