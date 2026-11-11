#!/bin/sh
# ============================================================
# MZD FIX-ALL v4.8.0 - WiFi via NMS + SSH on port 36000
# Priority 1: WORKING. No security theater.
#
# Order is critical:
# 1. Power save OFF (prevents wl12xx watchdog deadlock)
# 2. WiFi connect via NMS D-Bus (open/WPA per settings.conf)
# 3. SSH on PORT 36000 (2026-11-10 17:31): own sshd - password-auth if
#    MZD_SSH_PASSWORD in config/secrets.conf, else pubkey-only
# 4. Verify everything
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
[ -n "${SETTINGS_DIR:-}" ] && [ -f "$SETTINGS_DIR/settings.conf" ] && . "$SETTINGS_DIR/settings.conf"
[ -f "$TOOLKIT_DIR/config/settings.conf" ] && . "$TOOLKIT_DIR/config/settings.conf"
SSID="${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
PASSWORD="${WIFI_PASSWORD:-OPEN}"

echo "========================================"
echo " MZD FIX-ALL v${TOOLKIT_VERSION:-4.8.3} - all in one"
echo " SSID: $SSID"
echo "========================================"
echo ""

# ============================================
# STEP 1: WL12XX POWER SAVE OFF (core fix!)
# ============================================
echo "=== [1/5] Power save OFF (prevents watchdog crash) ==="
# v4.8.1 BUGFIX (2026-11-03): module param ps must be OFF.
# "on" turns driver power-save ON = wl12xx ELP watchdog = ~3min drop.
# Module parameter (works even if interface is down) - ONLY if path exists!
for p in /sys/module/wl12xx/parameters/ps /sys/module/wlcore/parameters/ps; do
    if [ -e "$p" ] && [ -w "$p" ]; then
        echo "off" > "$p" 2>/dev/null && echo "  $p = off (powersave OFF)"
    fi
done
# wlcore no_arp does NOT exist on v59 kernel 3.0.35 - check first
for p in /sys/module/wlcore/parameters/no_arp /sys/module/wl12xx/parameters/no_arp; do
    [ -e "$p" ] && [ -w "$p" ] && echo "off" > "$p" 2>/dev/null
done
# Via /sys power management - only existing paths
for f in /sys/class/net/wlan0/power/control /sys/class/net/wlan0/device/power/control /sys/bus/sdio/devices/*/power/control; do
    [ -e "$f" ] && [ -w "$f" ] && echo "on" > "$f" 2>/dev/null && echo "  $f = on"
done
# rfkill unblock
for r in /sys/class/rfkill/rfkill*/soft; do
    [ -e "$r" ] && [ -w "$r" ] && echo 0 > "$r" 2>/dev/null
done
echo ""

# ============================================
# STEP 2: WIFI CONNECT
# ============================================
echo "=== [2/5] WiFi connect to $SSID (via NMS D-Bus) ==="
# v4.7.4: DO NOT start own wpa_supplicant! The CMU already runs
#   wpa_supplicant -c /data/nms/wpa_supplicant-wlan0.conf -i wlan0 -D nl80211
# (managed by NMS). A second instance gives "Operation not supported"
# on all wext ioctls and empty scan. Control via com.jci.blm_nms D-Bus.
ifconfig wlan0 up 2>/dev/null
# v4.7.5 M6: kill udhcpc ONLY if it is from the toolkit - NMS runs its own udhcpc
for _up in $(pidof udhcpc 2>/dev/null); do
    case "$(cat /proc/$_up/cmdline 2>/dev/null | tr '\0' ' ')" in
        *mzd-toolkit*|*/tmp/*) kill "$_up" 2>/dev/null && echo "  toolkit-udhcpc $_up killed" ;;
        *) echo "  udhcpc $_up is from NMS - NOT killing" ;;
    esac
done
TOOLKIT_DIR="${TOOLKIT_DIR:-}"
# v4.7.5 M6: NO own wpa_supplicant fallback anymore - the CMU already runs
# wpa_supplicant via NMS; a second instance conflicts ("Operation not supported").
# v4.8.0 fail-fast (point 5.2): connect fails -> exit 1, NO follow-up steps
if [ -f "$TOOLKIT_DIR/wifi/connect-nms.sh" ]; then
    MZD_PSK="$PASSWORD" WIFI_SSID="$SSID" sh "$TOOLKIT_DIR/wifi/connect-nms.sh" "$SSID"
    _wifi_rc=$?
else
    echo "  WARNING: connect-nms.sh not found in $TOOLKIT_DIR - WiFi via GUI/NMS"
    _wifi_rc=1
fi
IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d: -f2)
# v4.8.20 BLOCKER FIX: fallback to eth1 (USB-ethernet 192.168.0.2) if wlan0 has no IP
[ -z "$IP" ] && IP=$(ifconfig eth1 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
[ -z "$IP" ] && IP=$(ifconfig eth0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
echo "  IP: ${IP:-NONE}"
if [ -z "$IP" ]; then
    echo "=== WiFi CONNECT FAILED (exit $_wifi_rc) - SSH/watchdog steps skipped (fail-fast v4.8.0) ==="
    log_to_category "FIX-ALL FAIL exit1 wifi connect failed ssid=$SSID" 2>/dev/null
    exit 1
fi
echo ""

# ============================================
# STEP 3: SSH pubkey-only (port 22 own sshd or 36000 stock)
# ============================================
echo "=== [3/5] Starting SSH on port 36000 ==="
# v4.7.6 (2026-11-10 17:31): port 36000 is THE port. If MZD_SSH_PASSWORD is in
# config/secrets.conf -> own sshd on 36000 with PASSWORDAUTH (short pwd),
# stock sshd is killed (that one is pubkey-only, read-only config). Else own
# sshd on 36000 pubkey-only.
SSH_PWD_SET=0
if [ -n "${MZD_SSH_PASSWORD:-}" ]; then
    SSH_PWD_SET=1
    # v4.8.19: chpasswd (DES) - v59 libcrypt 2011 no SHA-256 $5$/$6$
    mount -o remount,rw / 2>/dev/null
    echo "cmu:$MZD_SSH_PASSWORD" | chpasswd 2>/dev/null && echo "  password for 'cmu' set via chpasswd (DES)"
    unset MZD_SSH_PASSWORD
fi
if netstat -tln 2>/dev/null | grep -q ':36000 ' && [ "$SSH_PWD_SET" = "0" ]; then
    echo "  sshd already LISTENING on 36000 - pubkey login:"
    IP0=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP0" ] && IP0=$(ifconfig eth1 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "    ssh $MZD_SSH_OPTS -p 36000 cmu@${IP0:-<IP>} -i $TOOLKIT_DIR/ssh/id_mzd"
else
    # Own sshd on 36000 - password-auth if secrets.conf sets it, else pubkey-only
    killall sshd 2>/dev/null
    sleep 1
    # v4.8.2 BUGFIX (logs 11h 2026-11-03, run r6 exit 1): v59 sshd fails with
    # "Privilege separation user sshd does not exist" if sshd not in /etc/passwd.
    if ! grep -q "^sshd:" /etc/passwd 2>/dev/null; then
        echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> /etc/passwd 2>/dev/null \
            && echo "  priv-sep user 'sshd' added to /etc/passwd"
    fi
    mkdir -p /tmp/mzd-sshd
    if [ "$SSH_PWD_SET" = "1" ]; then
        cat > /tmp/mzd-sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/mzd-sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/mzd-sshd/sshd.pid
HostKey /tmp/mzd-sshd/ssh_host_rsa_key
EOF
    else
        cat > /tmp/mzd-sshd/sshd_config << 'EOF'
Port 36000
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /tmp/mzd-sshd/authorized_keys /data_persist/dev/bin/authorized_keys
PermitEmptyPasswords no
StrictModes no
PidFile /tmp/mzd-sshd/sshd.pid
HostKey /tmp/mzd-sshd/ssh_host_rsa_key
EOF
    fi
    for t in rsa dsa; do
        [ -f "/tmp/mzd-sshd/ssh_host_${t}_key" ] || ssh-keygen -t "$t" -f "/tmp/mzd-sshd/ssh_host_${t}_key" -N "" -q 2>/dev/null
    done
    [ -f "$TOOLKIT_DIR/ssh/id_mzd.pub" ] && cp "$TOOLKIT_DIR/ssh/id_mzd.pub" /tmp/mzd-sshd/authorized_keys 2>/dev/null && chmod 600 /tmp/mzd-sshd/authorized_keys
    # v4.8.2: show errors - at 11h the start failed silently (2>/dev/null)
    /usr/sbin/sshd -f /tmp/mzd-sshd/sshd_config 2>&1 || sshd -f /tmp/mzd-sshd/sshd_config 2>&1
    sleep 2
    # Firewall: ONLY port 36000 rule - NEVER -P INPUT ACCEPT (v59 policy is already ACCEPT)
    iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
    if netstat -tln 2>/dev/null | grep -E ':36000 '; then
        echo "  own sshd LISTENING on 36000"
    else
        echo "  WARNING: no sshd LISTENING on 36000 after start - check output above"
    fi
    IP0=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    [ -z "$IP0" ] && IP0=$(ifconfig eth1 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    if [ "$SSH_PWD_SET" = "1" ] && [ -n "$IP0" ]; then
        echo "    ssh $MZD_SSH_OPTS -p 36000 cmu@$IP0   (password from config/secrets.conf)"
    elif [ -n "$IP0" ]; then
        echo "    ssh $MZD_SSH_OPTS -p 36000 cmu@$IP0 -i $TOOLKIT_DIR/ssh/id_mzd"
    fi
fi
echo ""

# v4.8.2: route-check + default gateway fallback (run r23 11h: IP but "Network is unreachable",
# run r4 saw "route: SIOCDELRT: No such process" with udhcpc - udhcpc's route-add sometimes fails)
echo "=== Route check ==="
if ! route -n 2>/dev/null | grep -q "^0.0.0.0"; then
    GW=$(dbsend --dest="com.jci.blm_nms" /com/jci/blm_nms com.jci.blm_nms.GetInterfaceParams int32:100 2>/dev/null | grep -oE 'string "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | tr -d 'string "' | tr -d '"')
    # gateway is usually .1 or the DHCP server; try from udhcpc lease / arp
    [ -z "$GW" ] && GW=$(cat /proc/net/arp 2>/dev/null | awk 'NR>1 && $3!="00:00:00:00:00:00" {print $1}' | head -1)
    [ -z "$GW" ] && GW="192.168.0.1"
    route add default gw "$GW" wlan0 2>/dev/null && echo "  default route added via $GW" || echo "  default route failed (gw=$GW)"
fi
route -n 2>/dev/null | grep "^0.0.0.0" | sed 's/^/  /'
echo ""

# ============================================
# STEP 4: WATCHDOG MONITOR (auto-recovery)
# ============================================
echo "=== [4/5] Starting watchdog monitor ==="
cat > /tmp/mzd-watchdog.sh << 'WDEOF'
#!/bin/sh
# v4.7.5 M6 watchdog: wpactrl (runtime ctrl-socket detect) + NMS WIFI_Recovery fallback
STOP_DIR="/tmp/toolkit-stop"
PID_DIR="/tmp/toolkit-pids"
mkdir -p "$PID_DIR"
echo "mzd-watchdog" > "$PID_DIR/$$"
trap '_rc=$?; rm -f "$PID_DIR/$$"; exit "$_rc"' INT TERM EXIT
WD_ITER=0
WD_MAX=2880
while [ "$WD_ITER" -lt "$WD_MAX" ]; do
    if [ -f "$STOP_DIR/STOP" ] || [ -f ${TOOLKIT_DIR}/STOP ] || [ -f ${TOOLKIT_DIR}/STOP ]; then
        echo "$(date) STOP file found - watchdog stops" >> /tmp/watchdog.log
        rm -f "$PID_DIR/$$"
        exit 0
    fi
    WD_ITER=$((WD_ITER + 1))
    sleep 30
    TOOLKIT_DIR="${TOOLKIT_DIR:-}"
    [ -d ${TOOLKIT_DIR} ] && TOOLKIT_DIR="${TOOLKIT_DIR}"
    . "$TOOLKIT_DIR/lib/wifi-compat.sh" 2>/dev/null
    STATE=$(wpactrl status 2>/dev/null | grep "^wpa_state=" | cut -d= -f2)
    if [ "$STATE" != "COMPLETED" ]; then
        echo "$(date) WiFi down ($STATE) - reassociate via wpactrl..." >> /tmp/watchdog.log
        wpactrl reassociate 2>/dev/null
        wpactrl set power_save off 2>/dev/null
        # if wpactrl fails -> NMS WIFI_Recovery via JCI service bus (NO --system)
        if [ -S /tmp/dbus_service_socket ]; then
            dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_Recovery > /dev/null 2>&1
        fi
        sleep 30
        IPN=$(ifconfig wlan0 2>/dev/null | grep -c "inet addr")
        [ "$IPN" = "0" ] && udhcpc -i wlan0 -n -q -t 3 -T 2 2>/dev/null
    fi
    WD=$(dmesg 2>/dev/null | grep -c "watchdog interrupt")
    echo "$(date) iter=$WD_ITER wpa_state=$STATE watchdog_count=$WD" >> /tmp/watchdog.log
    # wl12xx deadlock signature -> log + message (no auto-recovery, brick-risk)
    if command -v wifi_deadlock_check > /dev/null 2>&1; then
        wifi_deadlock_check >> /tmp/watchdog.log 2>&1
    fi
done
echo "$(date) watchdog max iterations reached - stopping" >> /tmp/watchdog.log
rm -f "$PID_DIR/$$"
WDEOF
chmod +x /tmp/mzd-watchdog.sh
# Start in background, log to USB if available
if [ -d ${USB_MOUNT} ]; then
    nohup /tmp/mzd-watchdog.sh >> ${TOOLKIT_DIR}/logs/watchdog.log 2>&1 &
else
    nohup /tmp/mzd-watchdog.sh >> /tmp/watchdog.log 2>&1 &
fi
echo "  PID: $(pidof mzd-watchdog 2>/dev/null || pgrep -f mzd-watchdog | head -1)"
echo ""

# ============================================
# STEP 5: RESULT
# ============================================
echo "=== [5/5] RESULT ==="
echo "========================================"
echo "WiFi IP:  ${IP:-NONE}"
if [ "${SSH_PWD_SET:-0}" = "1" ]; then
    echo "SSH:      ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-?}   (password from config/secrets.conf)"
else
    echo "SSH:      ssh $MZD_SSH_OPTS -p 36000 cmu@${IP:-?} -i $TOOLKIT_DIR/ssh/id_mzd   (pubkey)"
fi
echo "Watchdog: running (check /tmp/watchdog.log)"
echo "========================================"
if [ -n "$IP" ]; then
    ping -c 2 -W 3 8.8.8.8 2>&1 | tail -2
fi
# Show last watchdog errors if any
echo ""
echo "Last wl12xx errors (if any):"
dmesg 2>/dev/null | grep -iE "wl12xx.*(watchdog|ERROR)" | tail -5 || echo "  no errors"
