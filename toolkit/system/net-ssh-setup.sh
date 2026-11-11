#!/bin/sh
# ============================================================
# MZD Toolkit - system/net-ssh-setup.sh (v4.8.7)
# ONE script from /tmp (or persist) that fixes internet + SSH:
#   1. USB tether (Android) as usb0  - most stable, no wl12xx
#   2. fallback: wlan0 via NMS connect (wl12xx)
#   3. Start SSH daemon on port 36000 (own sshd, pubkey-only)
#      + iptables ACCEPT - interface-independent (usb0 and wlan0)
#   4. print connect-info (IP + ssh command)
#
# Runs on the CMU (busybox) OR on a Debian host (for testing).
# No toolkit dependencies - standalone, runnable from /tmp:
#   curl ... > /tmp/net-ssh-setup.sh && sh /tmp/net-ssh-setup.sh
#
# Exit: 0 = internet + sshd active, 1 = no internet, 2 = sshd fail.
# ============================================================
set -u
LOG="${MZD_SETUP_LOG:-/tmp/net-ssh-setup.log}"
log() { echo "$*" | tee -a "$LOG" 2>/dev/null; }
: > "$LOG" 2>/dev/null

log "========================================"
log " net-ssh-setup $(date 2>/dev/null) (v4.8.7)"
log "========================================"

HAVE_INET=0

# ---------- 1. USB-tether (Android CDC) ----------
tether() {
    log "[1] USB tether probe (usb0)..."
    # modules from toolkit if present, else from system
    TD="${TOOLKIT_DIR:-/mnt/data_persist/mzd-toolkit}"
    for m in usbnet cdc_ether cdc_ncm; do
        grep -q "^$m " /proc/modules 2>/dev/null || insmod "$TD/wifi/cdc-modules/$m.ko" 2>/dev/null || modprobe "$m" 2>/dev/null
    done
    sleep 2
    if ifconfig usb0 >/dev/null 2>&1; then
        ifconfig usb0 up 2>/dev/null
        udhcpc -i usb0 -n -q -t 5 -T 3 >>"$LOG" 2>&1
        IP=$(ifconfig usb0 2>/dev/null | grep -m1 -oE "inet (addr:)?[0-9.]+" | grep -oE "[0-9.]+$")
        if [ -n "$IP" ]; then
            log "  usb0 IP: $IP"
            ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && { log "  internet OK via tether"; HAVE_INET=1; IFACE=usb0; IP_OUT="$IP"; return 0; }
            log "  usb0 has IP but no internet (tether without data?)"
            HAVE_INET=1; IFACE=usb0; IP_OUT="$IP"; return 0
        fi
    fi
    # new_id bind if device class is 02/06 but no interface yet
    for d in /sys/bus/usb/devices/*/bInterfaceClass; do
        [ -f "$d" ] || continue
        c=$(cat "$d" 2>/dev/null); p=$(dirname "$d"); sc=$(cat "$p/bInterfaceSubClass" 2>/dev/null)
        if [ "$c" = "02" ] && { [ "$sc" = "06" ] || [ "$sc" = "0d" ]; }; then
            vid=$(cat "$p/../idVendor" 2>/dev/null); pid=$(cat "$p/../idProduct" 2>/dev/null)
            log "  CDC device $vid:$pid -> bind"
            for drv in cdc_ether cdc_ncm; do
                [ -w "/sys/bus/usb/drivers/$drv/new_id" ] && echo "$vid $pid" > "/sys/bus/usb/drivers/$drv/new_id" 2>/dev/null
            done
            sleep 3
            ifconfig usb0 up 2>/dev/null
            udhcpc -i usb0 -n -q -t 5 -T 3 >>"$LOG" 2>&1
            IP=$(ifconfig usb0 2>/dev/null | grep -m1 -oE "inet (addr:)?[0-9.]+" | grep -oE "[0-9.]+$")
            [ -n "$IP" ] && { log "  usb0 IP after bind: $IP"; HAVE_INET=1; IFACE=usb0; IP_OUT="$IP"; return 0; }
        fi
    done
    log "  no usb0 (tether ON on phone?)"
    return 1
}

# ---------- 2. wlan0 fallback via NMS ----------
wlan() {
    log "[2] wlan0 fallback (NMS connect)..."
    ifconfig wlan0 up 2>/dev/null
    if [ -S /tmp/dbus_service_socket ]; then
        IFCID=$(dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
            --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.GetInterfaceList 2>/dev/null \
            | grep -oE 'int32 [0-9]+' | awk '{print $2}' | tail -1)
        [ -n "$IFCID" ] && dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --reply-timeout=8000 \
            --dest=com.jci.blm_nms /com/jci/blm_nms com.jci.blm_nms.WIFI_Recovery >/dev/null 2>&1
    fi
    SSID="${MZD_SSID:-${WIFI_SSID:-YOUR_HOTSPOT_SSID}}"
    PSK="${MZD_PSK:-}"
    if [ -n "$PSK" ] && command -v wpa_cli >/dev/null 2>&1; then
        wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 add_network >>"$LOG" 2>&1
        wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 set_network 0 ssid "\"$SSID\"" >>"$LOG" 2>&1
        wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 set_network 0 psk "\"$PSK\"" >>"$LOG" 2>&1
        wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 enable_network 0 >>"$LOG" 2>&1
        wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0 select_network 0 >>"$LOG" 2>&1
    fi
    i=0; IP=""
    while [ $i -lt 15 ]; do
        udhcpc -i wlan0 -n -q -t 2 -T 2 >>"$LOG" 2>&1
        IP=$(ifconfig wlan0 2>/dev/null | grep -m1 -oE "inet (addr:)?[0-9.]+" | grep -oE "[0-9.]+$")
        [ -n "$IP" ] && break
        i=$((i+1)); sleep 2
    done
    if [ -n "$IP" ]; then
        log "  wlan0 IP: $IP"
        HAVE_INET=1; IFACE=wlan0; IP_OUT="$IP"; return 0
    fi
    log "  wlan0 no IP"
    return 1
}

# ---------- 3. SSH daemon ----------
start_ssh() {
    log "[3] SSH daemon (port 36000)..."
    # firewall: interface-independent
    iptables -I INPUT -p tcp --dport 36000 -j ACCEPT 2>/dev/null
    # own sshd if present (toolkit), else system sshd
    TD="${TOOLKIT_DIR:-/mnt/data_persist/mzd-toolkit}"
    if [ -x "$TD/ssh/start.sh" ]; then
        sh "$TD/ssh/start.sh" >>"$LOG" 2>&1
    elif command -v sshd >/dev/null 2>&1; then
        mkdir -p /run/sshd 2>/dev/null
        /usr/sbin/sshd -p 36000 2>>"$LOG" || sshd -p 36000 2>>"$LOG"
    fi
    sleep 1
    if netstat -tln 2>/dev/null | grep -q ":36000 " || ss -tln 2>/dev/null | grep -q ":36000 "; then
        log "  sshd LISTENING on 36000"
        return 0
    fi
    log "  WARNING: no LISTEN on 36000 (see $LOG)"
    return 1
}

# ---------- run ----------
tether || wlan || true
SSH_OK=0
start_ssh && SSH_OK=1

log ""
log "========================================"
if [ "$HAVE_INET" = "1" ]; then
    log " INTERNET: YES via $IFACE ($IP_OUT)"
else
    log " INTERNET: NO - no tether and wlan0 failed"
fi
if [ "$SSH_OK" = "1" ]; then
    log " SSH: ssh $MZD_SSH_OPTS -p 36000 cmu@${IP_OUT:-<IP>} -i id_mzd   (pubkey)"
else
    log " SSH: NOT active"
fi
log "========================================"
if [ "$HAVE_INET" = "1" ] && [ "$SSH_OK" = "1" ]; then exit 0; fi
if [ "$HAVE_INET" = "1" ]; then exit 2; fi
if [ "$SSH_OK" = "1" ]; then exit 0; fi
exit 1
