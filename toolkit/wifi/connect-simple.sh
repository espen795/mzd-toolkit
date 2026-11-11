#!/bin/sh
# ============================================================
# MZD WiFi CONNECT - simple & working (v4.1)
# Priority 1: get it WORKING, not security.
#
# Root cause from logs: wl12xx watchdog deadlock caused by power save.
# Fix: power save OFF + wpa_supplicant WITHOUT -D flag (default driver)
# ============================================================

SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="${WIFI_PASSWORD:-OPEN}"

echo "========================================"
echo " MZD WiFi Connect v4.1"
echo " Network: $SSID"
echo "========================================"

# --- Step 1: Power save OFF (KERNEL FIX for watchdog deadlock) ---
echo "[1/6] Power save OFF..."
# Via wpa_cli if wpa_supplicant is running
wpactrl set power_save off 2>/dev/null && echo "  power_save OFF via wpa_cli" || echo "  wpa_cli power_save failed (ok if wpa is not running)"
# Via /sys - ONLY existing paths (prevents "nonexistent directory" errors)
for f in /sys/class/net/wlan0/power/control /sys/class/net/wlan0/device/power/control; do
    [ -e "$f" ] && [ -w "$f" ] && echo "on" > "$f" 2>/dev/null && echo "  $f = on (powersave off)"
done
# Module params - ONLY if the path exists (wlcore/no_arp does NOT exist on v59!)
for p in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do
    [ -e "$p" ] && [ -w "$p" ] && echo "on" > "$p" 2>/dev/null && echo "  $p = on (powersave off)"
done
# no_arp only if path exists
for p in /sys/module/wlcore/parameters/no_arp /sys/module/wl12xx/parameters/no_arp; do
    [ -e "$p" ] && [ -w "$p" ] && echo "off" > "$p" 2>/dev/null
done

# --- Step 2: Interface reset ---
echo "[2/6] Interface down/up..."
ifconfig wlan0 down 2>/dev/null
sleep 2
ifconfig wlan0 up 2>/dev/null
sleep 2

# --- Step 3: Stop old processes ---
echo "[3/6] Stop old wpa_supplicant/udhcpc..."
# v4.7.5: NEVER killall wpa_supplicant - NMS (PID 2402+) owns it; killing breaks WiFi
# (only kill own instance if it is NOT from NMS - check cmdline)
for _wp in $(pidof wpa_supplicant 2>/dev/null); do
    case "$(cat /proc/$_wp/cmdline 2>/dev/null | tr '\0' ' ')" in
        */data/nms/*|*blm_nms*) ;;  # from NMS - do NOT kill
        *) kill "$_wp" 2>/dev/null ;;
    esac
done
killall udhcpc 2>/dev/null
sleep 1

# --- Step 4: wpa_supplicant config ---
echo "[4/6] Writing config..."
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "OPEN" ] || [ "$PASSWORD" = "open" ] || [ "$PASSWORD" = "***" ]; then
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n\nnetwork={\n    ssid="%s"\n    key_mgmt=NONE\n    scan_ssid=1\n    priority=10\n}\n' "$SSID" > /tmp/wpa.conf
    echo "  OPEN network: $SSID"
else
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nap_scan=1\n\nnetwork={\n    ssid="%s"\n    psk="%s"\n    key_mgmt=WPA-PSK\n    scan_ssid=1\n    priority=10\n}\n' "$SSID" "$PASSWORD" > /tmp/wpa.conf
    echo "  WPA network: $SSID"
fi
chmod 600 /tmp/wpa.conf 2>/dev/null

# --- Step 5: start wpa_supplicant WITHOUT -D (default driver works!) ---
echo "[5/6] starting wpa_supplicant (no -D flag)..."
wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf 2>&1
sleep 3
if ps 2>/dev/null | grep wpa_supplicant | grep -v grep > /dev/null; then
    echo "  wpa_supplicant RUNNING"
else
    echo "  wpa_supplicant did NOT start - trying with -D wext..."
    wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf -D wext 2>&1
    sleep 2
fi

# --- Wait for connection (max 20 sec) ---
echo "  Waiting for association (max 20s)..."
I=0
while [ $I -lt 20 ]; do
    check_stop 2>/dev/null && { echo "Stopped"; break; }
    STATE=$(wpactrl status 2>/dev/null | grep "^wpa_state=" | cut -d= -f2)
    if [ "$STATE" = "COMPLETED" ]; then
        echo "  CONNECTED! (after ${I}s)"
        break
    fi
    sleep 1
    I=$((I+1))
done

echo ""
echo "  wpa_cli status:"
wpactrl status 2>/dev/null | grep -E "wpa_state|ssid|bssid|ip_address" || echo "  (no status)"

# --- Step 6: DHCP ---
echo "[6/6] DHCP..."
killall udhcpc 2>/dev/null
udhcpc -i wlan0 -n -q -t 10 -T 3 2>&1

echo ""
echo "========================================"
echo " RESULT"
echo "========================================"
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -z "$IP" ]; then
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d: -f2)
fi
echo "IP: ${IP:-NO CONNECTION}"
echo ""
ifconfig wlan0 2>/dev/null | head -3
echo ""
if [ -n "$IP" ]; then
    echo "SSH: ssh -p 36000 cmu@$IP -i $TOOLKIT_DIR/ssh/id_mzd  (pubkey, port 36000)"
    ping -c 2 -W 3 8.8.8.8 2>&1 | tail -2
else
    echo "No IP - check dmesg for watchdog errors:"
    dmesg 2>/dev/null | grep -iE "wl12xx|watchdog|wlan" | tail -10
fi
echo "========================================"
