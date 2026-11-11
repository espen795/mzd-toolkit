#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Access Point Mode
# Turns the Mazda into a WiFi Access Point

echo "========================================"
echo " MZD Access Point Mode"
echo "========================================"
echo ""
echo "This turns the Mazda into a WiFi hotspot."
echo "Other devices can connect to the Mazda."
echo ""
echo "WARNING: WiFi client mode will be disabled!"
echo ""
echo -n "Continue? (y/n): "
read confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && [ "$confirm" != "yes" ] && [ "$confirm" != "YES" ] && [ "$confirm" != "j" ] && [ "$confirm" != "J" ] && [ "$confirm" != "ja" ] && [ "$confirm" != "JA" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "--- Step 1: Check hostapd ---"
if which hostapd > /dev/null 2>&1; then
    echo "hostapd found: $(which hostapd)"
else
    echo "hostapd NOT found"
    echo ""
    echo "Alternative: use WiFi tethering via Mazda settings"
    echo "or install hostapd (difficult on a read-only system)"
    exit 1
fi

echo ""
echo "--- Step 2: Configuration ---"
AP_SSID="Mazda-MZD"
AP_PASS="mazda1234"
AP_CHANNEL=6

echo "SSID: $AP_SSID"
echo "Password: $AP_PASS"
echo "Channel: $AP_CHANNEL"
echo ""

echo "--- Step 3: Write hostapd config ---"
cat > /tmp/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=$AP_SSID
channel=$AP_CHANNEL
hw_mode=g
wpa=2
wpa_passphrase=$AP_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
EOF

echo "Config: /tmp/hostapd.conf"
cat /tmp/hostapd.conf
echo ""

echo "--- Step 4: Set IP address ---"
ifconfig wlan0 192.168.1.1 netmask 255.255.255.0 up
sleep 2
ifconfig wlan0

echo ""
echo "--- Step 5: Start DHCP server ---"
# Check for dnsmasq or udhcpd
if which dnsmasq > /dev/null 2>&1; then
    echo "Starting dnsmasq..."
    dnsmasq -i wlan0 --dhcp-range=192.168.1.100,192.168.1.200 --dhcp-option=3,192.168.1.1 -d
elif which udhcpd > /dev/null 2>&1; then
    echo "udhcpd config..."
    cat > /tmp/udhcpd.conf << EOF
start 192.168.1.100
end 192.168.1.200
interface wlan0
option subnet 255.255.255.0
option router 192.168.1.1
option dns 8.8.8.8
EOF
    udhcpd /tmp/udhcpd.conf
else
    echo "No DHCP server found (dnsmasq/udhcpd)"
    echo "Clients must set a static IP in 192.168.1.x"
fi

echo ""
echo "--- Step 6: Start hostapd ---"
hostapd /tmp/hostapd.conf &
HOSTAPD_PID=$!
sleep 3

echo ""
echo "========================================"
echo " Access Point ACTIVE"
echo "========================================"
echo ""
echo "SSID: $AP_SSID"
echo "Password: $AP_PASS"
echo "Gateway: 192.168.1.1"
echo ""
echo "Connect from phone/laptop with:"
echo "  WiFi: $AP_SSID"
echo "  Pass: $AP_PASS"
echo ""
echo "hostapd PID: $HOSTAPD_PID"
echo ""
echo "Stop with: killall hostapd"
echo "Restore WiFi client with: sh ${TOOLKIT_DIR}/wifi/connect.sh"
