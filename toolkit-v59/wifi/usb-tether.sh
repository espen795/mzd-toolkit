#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/usb-tether.sh (v4.8.6)
# USB tethering from an ANDROID phone to the CMU as usb0.
# Works because: CONFIG_USB_NET_CDCETHER=m + CONFIG_USB_NET_CDC_NCM=m
# + generic alias usb:v*p*d*ic02isc06ip00* (any vendor, incl. Android).
# RNDIS (old Android/Windows Phone) and iPhone ipheth do NOT work
# (not in CMU kernel config).
#
# Advantages vs wl12xx-wlan0: no chip-FW watchdog, no AP isolation
# (USB is a direct L3 link), phone charges at the same time.
#
# Modules come from the v74 rootfs (vermagic 3.0.35 ARMv7 = matches v59).
# usbnet is already loaded on v59 (asix), cdc_ether/cdc_ncm are
# insmod'ed here. NMS/wlan0 stay untouched.
#
# Exit-codes: 0 = usb0 has IP, 4 = no tether device found,
#             5 = module load failed, 6 = no IP via DHCP.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

TD="${TOOLKIT_DIR:-}"
# v4.8.8: fallback paths when TOOLKIT_DIR is empty (run manually from persist)
if [ -z "$TD" ] || [ ! -d "$TD/wifi/cdc-modules" ]; then
    for c in /data_persist/mzd-toolkit /mnt/data_persist/mzd-toolkit /tmp/mnt/data_persist/mzd-toolkit; do
        [ -d "$c/wifi/cdc-modules" ] && TD="$c" && break
    done
fi
[ -z "$TD" ] && TD="/data_persist/mzd-toolkit"
MODDIR="$TD/wifi/cdc-modules"
IFC="usb0"

echo "========================================"
echo " USB-tether (Android) -> $IFC (v4.8.6)"
echo "========================================"
sh "$TD/wifi/driver-info.sh" 2>/dev/null

# --- 1. modules present + hash check (v4.8.8: mismatch = WARNING, not blocking) ---
# Reason: on the CMU a FAT copy can differ subtly (LOST.DIR/bread errors in logs);
# the .ko either loads (vermagic check is done by the kernel) or not — a sha mismatch
# alone is no reason to refuse tethering.
for m in usbnet.ko cdc_ether.ko cdc_ncm.ko; do
    [ -f "$MODDIR/$m" ] || { echo "ERROR: $MODDIR/$m missing"; exit 5; }
done
GOT=$(sha256sum "$MODDIR/cdc_ether.ko" 2>/dev/null | awk '{print $1}')
if [ "$GOT" != "fe7a34af0480140446d88df20914344a9e668cda7d0ae60aec618f9d35ffef5b" ]; then
    echo "WARNING: cdc_ether.ko sha mismatch (got $GOT) - copy may be corrupt, trying anyway"
fi

# --- 2. load modules (usbnet is usually already loaded by asix) ---
for m in usbnet cdc_ether cdc_ncm; do
    if grep -q "^$m " /proc/modules 2>/dev/null; then
        echo "  $m: already loaded"
    else
        echo -n "  insmod $m... "
        insmod "$MODDIR/$m.ko" 2>/dev/null && echo OK || { echo "FAILED (can be normal if built-in)"; }
    fi
done

# --- 3. tether device detected? (interface class 02/06 -> usb0) ---
sleep 2
if ! ifconfig "$IFC" >/dev/null 2>&1; then
    # force bind via new_id if the phone came in as 02/06 or 02/0d before insmod
    for d in /sys/bus/usb/devices/*:*/bInterfaceClass /sys/bus/usb/devices/*/bInterfaceClass; do
        [ -f "$d" ] || continue
        c=$(cat "$d" 2>/dev/null); p=$(dirname "$d")
        sc=$(cat "$p/bInterfaceSubClass" 2>/dev/null)
        devname=$(basename "$p" | cut -d: -f1)
        devdir="$(dirname "$p")/$devname"
        [ -d "$devdir" ] || devdir="/sys/bus/usb/devices/$devname"
        if [ "$c" = "02" ] && { [ "$sc" = "06" ] || [ "$sc" = "0d" ]; }; then
            vid=$(cat "$devdir/idVendor" 2>/dev/null); pid=$(cat "$devdir/idProduct" 2>/dev/null)
            if [ -n "$vid" ] && [ -n "$pid" ]; then
                echo "  CDC device found: $vid:$pid (dev $devname) -> new_id bind"
                for drv in cdc_ether cdc_ncm; do
                    [ -f "/sys/bus/usb/drivers/$drv/new_id" ] && echo "$vid $pid" > "/sys/bus/usb/drivers/$drv/new_id" 2>/dev/null
                done
            fi
        fi
    done
    sleep 3
fi
if ! ifconfig "$IFC" >/dev/null 2>&1; then
    echo "ERROR: no $IFC — phone tethering ON? (Android: Settings > Network > Hotspot > USB tethering)"
    echo ""
    echo "--- USB DIAGNOSTICS ---"
    _found_any=0
    for dev in /sys/bus/usb/devices/*; do
        if [ -f "$dev/idVendor" ]; then
            v=$(cat "$dev/idVendor" 2>/dev/null); p=$(cat "$dev/idProduct" 2>/dev/null)
            case "$v:$p" in
                0000:*|1d6b:*) ;;
                *)
                    echo "  - USB dev $(basename "$dev"): VID=$v PID=$p"
                    _found_any=1
                    for ifc in /sys/bus/usb/devices/$(basename "$dev"):*/bInterfaceClass; do
                        [ -f "$ifc" ] || continue
                        ipath=$(dirname "$ifc")
                        iclass=$(cat "$ifc" 2>/dev/null)
                        isub=$(cat "$ipath/bInterfaceSubClass" 2>/dev/null)
                        echo "    interface $(basename "$ipath"): class=$iclass subclass=$isub"
                        if [ "$iclass" = "e0" ] && [ "$isub" = "01" ]; then
                            echo "    NOTE: Device is in RNDIS mode! CMU kernel only supports CDC-ECM/NCM."
                        fi
                    done
                    ;;
            esac
        fi
    done
    [ "$_found_any" = "0" ] && echo "  (No external USB devices seen — cable not connected or charge cable without data?)"
    echo ""
    echo "Last dmesg lines:"
    dmesg 2>/dev/null | tail -10
    exit 4
fi
ifconfig "$IFC" up 2>/dev/null
echo "$IFC up: $(ifconfig "$IFC" 2>/dev/null | grep -m1 HWaddr)"

# --- 4. DHCP on usb0 ---
echo "udhcpc on $IFC..."
udhcpc -i "$IFC" -n -q -t 5 -T 3 2>&1 | tail -3
IP=$(ifconfig "$IFC" 2>/dev/null | grep -m1 "inet addr" | sed 's/.*inet addr:\([0-9.]*\).*/\1/')
[ -z "$IP" ] && IP=$(ifconfig "$IFC" 2>/dev/null | grep -m1 "inet " | awk '{print $2}' | sed 's/addr://')
if [ -z "$IP" ]; then
    echo "NO IP on $IFC (tether DHCP failed)"
    exit 6
fi
GW=$(route -n 2>/dev/null | grep "$IFC" | grep -m1 UG | awk '{print $2}')
echo "OK: $IFC has IP $IP (phone tether active)"
[ -n "$GW" ] && echo " Phone IP (gateway): $GW"
echo " From phone (Termux): ssh -p 36000 cmu@$IP -i id_mzd"
echo " From CMU: internet via phone active — test: ping -c 1 8.8.8.8"
exit 0
