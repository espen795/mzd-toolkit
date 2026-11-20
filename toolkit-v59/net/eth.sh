#!/bin/sh
# MZD Toolkit - net/eth.sh (v4.8.11)
# USB-Ethernet helper. No special characters needed, only:
#   sh /data_persist/mzd-toolkit/net/eth.sh up
#   sh /data_persist/mzd-toolkit/net/eth.sh down
#   sh /data_persist/mzd-toolkit/net/eth.sh status
#   sh /data_persist/mzd-toolkit/net/eth.sh gw
#
# Auto-detects the USB net interface (eth0/wlan0/lo are NEVER picked),
# and binds the dongle via new_id to asix/cdc_ether/cdc_ncm if needed.

IP="${MZD_ETH_IP:-192.168.0.2}"
MASK="255.255.255.0"
GW="${MZD_ETH_GW:-192.168.0.1}"

# pick_ifc - find first USB net interface in /sys/class/net (exclude eth0/wlan0/lo)
pick_ifc() {
    _first=""
    for i in /sys/class/net/*; do
        [ -d "$i" ] || continue
        n=${i##*/}
        case "$n" in lo|eth0|wlan0) continue ;; esac
        [ -z "$_first" ] && _first="$n"
        if readlink "$i/device" 2>/dev/null | grep -q usb; then echo "$n"; return 0; fi
    done
    [ -n "$_first" ] && { echo "$_first"; return 0; }
    return 1
}

# bind_usb - force driver bind via new_id for all USB devices
bind_usb() {
    for dev in /sys/bus/usb/devices/*; do
        [ -f "$dev/idVendor" ] || continue
        v=$(cat "$dev/idVendor" 2>/dev/null)
        p=$(cat "$dev/idProduct" 2>/dev/null)
        case "$v" in ""|0000|1d6b) continue ;; esac
        echo "bind $v:$p"
        for drv in asix cdc_ether cdc_ncm; do
            f="/sys/bus/usb/drivers/$drv/new_id"
            [ -f "$f" ] && echo "$v $p" > "$f" 2>/dev/null
        done
    done
    sleep 2
}

cmd="$1"
[ -z "$cmd" ] && cmd=status

case "$cmd" in
    up|bind)
        IFC=$(pick_ifc)
        if [ -z "$IFC" ]; then
            echo "No USB net interface found - forcing driver bind..."
            bind_usb
            sleep 1
            IFC=$(pick_ifc)
        fi
        if [ -z "$IFC" ]; then
            echo "ERROR: dongle provides no interface. Check: dmesg | tail -10"
            exit 1
        fi
        echo "Interface: $IFC"
        ifconfig "$IFC" "$IP" netmask "$MASK" up
        echo "$IFC up with $IP netmask $MASK"
        ;;
    down)
        IFC=$(pick_ifc)
        [ -z "$IFC" ] && { echo "no USB interface"; exit 1; }
        ifconfig "$IFC" down
        echo "$IFC down"
        ;;
    gw)
        IFC=$(pick_ifc)
        if [ -n "$IFC" ]; then
            route add default gw "$GW" "$IFC" 2>/dev/null || route add default gw "$GW"
        else
            route add default gw "$GW" 2>/dev/null
        fi
        echo "default gw -> $GW"
        route -n 2>/dev/null
        ;;
    status)
        echo "=== USB net interfaces ==="
        for i in /sys/class/net/*; do
            [ -d "$i" ] || continue
            n=${i##*/}
            case "$n" in lo|eth0|wlan0) continue ;; esac
            echo "-- $n --"
            ifconfig "$n" 2>/dev/null
        done
        echo "=== all interfaces ==="
        ifconfig -a 2>/dev/null
        echo "=== route ==="
        route -n 2>/dev/null
        ;;
    *)
        echo "Usage: eth.sh up|down|gw|status|bind"
        ;;
esac
