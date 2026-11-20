#!/bin/sh
# ============================================================
# MZD Toolkit - WiFi Connect via NMS D-Bus (v4.7.4)
# ============================================================
# ROOT CAUSE v4.7.3 failed: the CMU itself already runs wpa_supplicant:
#   wpa_supplicant -c /data/nms/wpa_supplicant-wlan0.conf -i wlan0 -D nl80211
# (beheerd door NMS/blm_nms_svc, PID 2402 in dump-19700101-000231).
# A second wpa_supplicant on wlan0 gives "Operation not supported"
# on all wext ioctls and an empty scan -> DISCONNECTED.
#
# SOLUTION: do NOT start our own wpa_supplicant. Drive via Mazda's
# own NMS D-Bus service:
#   com.jci.blm_nms @ /com/jci/blm_nms  op  unix:path=/tmp/dbus_service_socket
#
# Workflow (uit blm_nms.so introspectie):
#   1. GetInterfaceList           -> ifcId van wlan0
#   2. GetInterfaceParams(ifcId)  -> name="wlan0" bevestigen
#   3. WIFI_SetMode(ifcId, 1)     -> CLIENT mode (0=DISABLED, 1=CLIENT, 2=AP)
#   4. WIFI_StartScan(ifcId, 10)  -> scan; wait for WIFI_ScanResultsReady signal
#   5. WIFI_GetScanResults(ifcId) -> lijst met ssid/bssid/signal
#   6. WIFI_AddNetwork(ifcId, (ssid, bssid, secType, hidden, pass))
#      -> returns networkId; secType: 0=NONE, 2=WEP, 4=WPA, 8=WPA2
#   7. WIFI_SelectNetwork(ifcId, networkId)
#   8. Connect(ifcId)             -> reqId; resultaat via ConnectResult signal
#   9. NMS does DHCP itself (internal udhcpc) -> check GetInterfaceParams for IP
#
# dbus-send struct syntax: struct:string:"ssid",string:"",int32:0,boolean:false,string:""
# ============================================================

# Source gedeelde library (met fallback)
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

# v4.8.0 (item 5.3): log driver/firmware version in every run - validates whether the v74 patch is active
sh "$(dirname "$0")/driver-info.sh" 2>/dev/null
log_to_category "connect-nms START ssid=${1:-${WIFI_SSID:-}} (psk not logged)" 2>/dev/null

# v4.8.0: psk via env MZD_PSK wins over argv - NEVER psk in /proc/<pid>/cmdline
SSID="${WIFI_SSID:-${1:-YOUR_HOTSPOT_SSID}}"
PASSWORD="${MZD_PSK:-${WIFI_PASSWORD:-${2:-}}}"
# secType: 0=NONE(open), 8=WPA2, 12=WPA+WPA2
# v4.7.6 (design decision): open connect is de default-werkwijze —
# WIFI_PASSWORD empty/OPEN/*** => SECTYPE=0 (open network, no password).
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "OPEN" ] || [ "$PASSWORD" = "open" ] || [ "$PASSWORD" = "***" ]; then
    SECTYPE=0
    PASSWORD=""
else
    SECTYPE=12   # WPA|WPA2
fi

BUS="unix:path=/tmp/dbus_service_socket"
NMS="com.jci.blm_nms"
NMSPATH="/com/jci/blm_nms"

# dbus-send wrapper op de JCI service bus.
# v4.7.5 M1 (gate 0046b92): NO --system fallback (MZD has no system bus).
# BUT retry 3x with 2s - /tmp is tmpfs, socket can briefly disappear on dbus-daemon restart.
# v4.8.1: --reply-timeout=8000 (8s max per call) - without this dbus-send blocks
# ~25s bij NoReply (bewezen in run-logs 2026-11-03: WIFI_SetMode gaf NoReply).
dbsend() {
    _i=0
    while [ $_i -lt 3 ]; do
        if [ -S /tmp/dbus_service_socket ]; then
            dbus-send --address="$BUS" --print-reply --reply-timeout=8000 "$@" 2>&1
            return $?
        fi
        _i=$((_i+1))
        [ $_i -lt 3 ] && sleep 2
    done
    echo "ERROR: /tmp/dbus_service_socket missing after 3 attempts - no --system fallback (does not exist on MZD)" 2>&1
    return 1
}

log() { echo "$*"; }

echo "========================================"
echo " MZD WiFi Connect via NMS D-Bus (v4.7.4)"
echo " SSID: $SSID (secType=$SECTYPE)"
echo "========================================"
echo ""

# --- Stap 0: check of NMS service er is ---
echo "[0/8] NMS service check..."
NAMES=$(dbsend --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -o 'com\.jci\.[a-zA-Z0-9_.]*' | sort -u)
echo "$NAMES" | grep -q "blm_nms" && echo "  com.jci.blm_nms PRESENT" || echo "  WARNING: com.jci.blm_nms not in ListNames"
echo "$NAMES" | grep -q "com.jci.nms" && echo "  com.jci.nms PRESENT" || true
echo ""

# --- Stap 1: interface list -> ifcId van wlan0 ---
echo "[1/8] GetInterfaceList..."
IFLIST=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.GetInterfaceList 2>&1)
echo "$IFLIST" | head -10
# Parse ifcId's uit array (ai)
IFCIDS=$(echo "$IFLIST" | grep -oE 'int32 [0-9]+' | awk '{print $2}')
echo "  Found ifcIds: $IFCIDS"

# Look for the ifcId whose name=wlan0
IFCID=""
for id in $IFCIDS; do
    PARAMS=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.GetInterfaceParams int32:$id 2>&1)
    NAME=$(echo "$PARAMS" | grep -A2 'string' | grep -oE '"[a-z0-9]+"' | tr -d '"' | head -5 | tr '\n' ' ')
    if echo "$PARAMS" | grep -q '"wlan0"'; then
        IFCID=$id
        echo "  wlan0 = ifcId $id"
        break
    fi
done
if [ -z "$IFCID" ]; then
    # Fallback: take the highest ifcId (wlan0 is usually after lo/eth0)
    IFCID=$(echo "$IFCIDS" | sort -n | tail -1)
    echo "  wlan0 not found via name, fallback ifcId=$IFCID"
fi
[ -z "$IFCID" ] && { echo "ERROR: no ifcId found"; log_to_category "connect-nms FAIL exit1 no ifcId"; exit 1; }
echo ""

# --- Stap 2: power save UIT (voorkomt wl12xx watchdog) ---
echo "[2/8] Power save UIT..."
for p in /sys/class/net/wlan0/power/control /sys/class/net/wlan0/device/power/control; do
    [ -e "$p" ] && [ -w "$p" ] && echo "on" > "$p" 2>/dev/null && echo "  $p = on"
done
# v4.8.1 BUGFIX (bugfix): module param ps must be OFF, not ON.
# "on" zet driver power-save juist AAN = wl12xx ELP watchdog trigger (3-min drop).
for p in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do
    [ -e "$p" ] && [ -w "$p" ] && echo "off" > "$p" 2>/dev/null && echo "  $p = off (powersave UIT)"
done
# rfkill unblock
for r in /sys/class/rfkill/rfkill*/soft; do
    [ -e "$r" ] && [ -w "$r" ] && echo 0 > "$r" 2>/dev/null
done
# interface up
ifconfig wlan0 up 2>/dev/null && echo "  wlan0 UP"
echo ""

# --- Stap 3: WIFI_SetMode CLIENT ---
echo "[3/8] WIFI_SetMode(ifcId=$IFCID, mode=1=CLIENT)..."
dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_SetMode int32:$IFCID int32:1 | head -5
MODE=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_GetMode int32:$IFCID 2>&1 | grep -oE 'int32 [0-9]+' | tail -1)
echo "  Current mode: $MODE (1=CLIENT)"
echo ""

# --- Step 4: start scan ---
echo "[4/8] WIFI_StartScan(ifcId=$IFCID, refresh=10)..."
dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_StartScan int32:$IFCID int32:10 | head -5
echo "  Waiting for scan results (5s)..."
sleep 5

# --- Step 5: fetch scan results ---
echo "[5/8] WIFI_GetScanResults..."
SCAN=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_GetScanResults int32:$IFCID 2>&1)
echo "$SCAN" | grep -oE 'string "[^"]*"' | head -20
BSSID=$(echo "$SCAN" | grep -B1 -A1 "$SSID" | grep -oE 'string "[0-9a-f:]{17}"' | head -1 | tr -d 'string "' | tr -d '"')
echo "  BSSID of $SSID: ${BSSID:-not found}"
echo ""

# --- Step 6: add network (or update if it exists) ---
echo "[6/8] WIFI_AddNetwork(ifcId=$IFCID, ssid=$SSID)..."
# First check whether already configured
EXISTING=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_GetConfiguredNetworks int32:$IFCID 2>&1)
NETID=$(echo "$EXISTING" | grep -B2 "$SSID" | grep -oE 'uint32 [0-9]+' | head -1 | awk '{print $2}')
if [ -z "$NETID" ]; then
    # Add new network: struct (ssid, bssid, secType, hidden, pass)
    ADD=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_AddNetwork int32:$IFCID \
        struct:string:"$SSID",string:"${BSSID:-}",int32:$SECTYPE,boolean:false,string:"$PASSWORD" 2>&1)
    echo "$ADD" | head -5
    NETID=$(echo "$ADD" | grep -oE 'uint32 [0-9]+' | tail -1 | awk '{print $2}')
    echo "  Nieuw networkId: $NETID"
else
    echo "  Network already exists, networkId=$NETID"
    # Update password if needed
    if [ -n "$PASSWORD" ] && [ "$SECTYPE" != "0" ]; then
        dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_UpdateNetworkPass int32:$IFCID uint32:$NETID string:"$PASSWORD" 2>&1 | head -3
    fi
fi
[ -z "$NETID" ] && { echo "ERROR: no networkId"; log_to_category "connect-nms FAIL exit3 no networkId"; exit 3; }
echo ""

# --- Step 7: select network + connect ---
# v4.8.0 FIX (proven on hardware): WIFI_EnableNetwork exists
# NOT on the v59 NMS -> org.freedesktop.DBus.Error.UnknownMethod. Only
# SelectNetwork + Connect aanroepen (correcte sequence).
echo "[7/8] WIFI_SelectNetwork(ifcId=$IFCID, netId=$NETID) + Connect..."
dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_SelectNetwork int32:$IFCID int32:$NETID | head -3
echo "  Connect(ifcId=$IFCID)..."
CONN=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.Connect int32:$IFCID 2>&1)
echo "$CONN" | head -5
REQID=$(echo "$CONN" | grep -oE 'int32 [0-9]+' | tail -1 | awk '{print $2}')
echo "  reqId: $REQID - waiting for ConnectResult signal / interface params (max 30s)..."
echo ""

# --- Step 8: wait for IP ---
# v4.8.1: wall-clock deadline (30s real) instead of iteration counter - each iteration could
# met dbus NoReply ~25s duren, dus "30 iteraties" was in de praktijk ~13 minuten.
echo "[8/8] Waiting for connection + IP (max 30s)..."
_DEADLINE=$(( $(date +%s 2>/dev/null || echo 0) + 30 ))
while [ "$(date +%s 2>/dev/null || echo 0)" -lt "$_DEADLINE" ]; do
    PARAMS=$(dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.GetInterfaceParams int32:$IFCID 2>&1)
    IP=$(echo "$PARAMS" | grep -oE 'string "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | tr -d 'string "' | tr -d '"')
    STATE=$(echo "$PARAMS" | grep -oE 'int32 [0-9]+' | tail -1 | awk '{print $2}')
    if [ -n "$IP" ] && [ "$IP" != "0.0.0.0" ]; then
        echo "  IP GEKREGEN: $IP"
        break
    fi
    sleep 1
done

# Fallback: manual DHCP if NMS did not do it
# v4.8.3: udhcpc safer - -n (exit on no lease), shorter timeouts, and NO
# killall (leave NMS's own udhcpc alive). Evidence 11:40: "Sending discover..." x2
# dan "No lease, failing" — v74 fw watchdog blokkeert DHCP-antwort.
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
if [ -z "$IP" ]; then
    echo "  No IP via NMS - udhcpc fallback (max 3 attempts)..."
    _i=0
    while [ $_i -lt 3 ] && [ -z "$IP" ]; do
        udhcpc -i wlan0 -n -q -t 3 -T 2 >/dev/null 2>&1
        IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
        _i=$((_i+1))
        [ -z "$IP" ] && [ $_i -lt 3 ] && sleep 2
    done
    [ -n "$IP" ] && echo "  udhcpc fallback OK: $IP (attempt $_i)"
fi

# v4.8.2: route-check + default-gateway fallback.
# Evidence run r23 (2026-11-03 11h): got IP but ping 8.8.8.8 -> "Network is unreachable"
# (no default route; udhcpc gave in r4 "route: SIOCDELRT: No such process").
if [ -n "$IP" ] && ! route -n 2>/dev/null | grep -q "^0.0.0.0"; then
    echo "  No default route - adding via gateway..."
    GW=$(cat /proc/net/arp 2>/dev/null | awk 'NR>1 && $3!="00:00:00:00:00:00" {print $1}' | head -1)
    [ -z "$GW" ] && GW="${IP%.*}.1"
    route add default gw "$GW" wlan0 2>/dev/null && echo "  default gw = $GW" || echo "  route add gefaald (gw=$GW)"
fi

echo ""
echo "========================================"
echo " RESULTAAT"
echo "========================================"
echo "IP: ${IP:-NO CONNECTION}"
ifconfig wlan0 2>/dev/null | head -4
echo ""
# Status via NMS
dbsend --dest="$NMS" "$NMSPATH" com.jci.blm_nms.WIFI_GetConnectionInfo int32:$IFCID 2>&1 | head -10
echo ""
# v4.8.0 exit-code contract (item 5.2): 0 = got IP, 4 = connect failed (no IP), 5 = udhcpc fallback failed
if [ -n "$IP" ]; then
    if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
        echo "SSH: ssh -p 36000 cmu@$IP   (password from secrets.conf)"
    else
        echo "SSH: ssh -p 36000 cmu@$IP -i \$TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
    fi
    ping -c 2 -W 3 8.8.8.8 2>&1 | tail -2
    log_to_category "connect-nms OK ip=$IP ssid=$SSID"
    exit 0
else
    echo "No IP - debug:"
    echo "  dmesg | grep -iE 'wl12xx|watchdog|wlan' | tail -10"
    dmesg 2>/dev/null | grep -iE "wl12xx|watchdog|wlan" | tail -10
    wifi_deadlock_check 2>/dev/null | tail -5
    # v4.8.3: bij terugkerende watchdog/TX-flush errors is v74 fw de oorzaak
    # (bewezen 11:40: 11x watchdog + 92x "Unable to flush TX buffers" -> No lease)
    _wd=$(dmesg 2>/dev/null | grep -c "watchdog interrupt")
    _tx=$(dmesg 2>/dev/null | grep -c "Unable to flush")
    if [ "${_wd:-0}" -gt 2 ] || [ "${_tx:-0}" -gt 5 ]; then
        echo ""
        echo "  >>> wl12xx instability detected (watchdog=$_wd, TX-flush=$_tx) <<<"
        echo "  >>> v74 firmware (FRev .142) is hier de vermoedelijke oorzaak. <<<"
        echo "  >>> Solution: Tools menu -> 10 (rollback firmware v59) <<<"
    fi
    log_to_category "connect-nms FAIL exit4 no IP ssid=$SSID"
    exit 4
fi
echo "========================================"
echo "========================================"
