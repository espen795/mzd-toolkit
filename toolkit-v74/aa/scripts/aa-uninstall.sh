#!/bin/sh
# aa-uninstall.sh — MZD AA bus-patch (v74), terugdraaien OP DE CMU. Versie 3 (2 doelen).
#   (zonder opties)  : DISABLE + DISABLE_AAPA zetten -> volgende boot stock usbmgr EN stock aapa
#                      (hook blijft, doet niets)
#   --restore-hook   : ook /jci/scripts/usb_drivers.sh exact stock maken (md5 a52bb423...)
#                      uit usb_drivers.sh.aabak, of (zonder geldige backup) door de 2 hookregels
#                      te verwijderen — alleen als het resultaat exact stock is.
#   --purge          : --restore-hook + /data_persist/dev/aa leegmaken (behalve logs + DISABLE*)
# Een actieve bind-mount kan niet live weg (usbmgr/aapa hebben de .so gemapt) -> reboot nodig.
# Vóór een firmware-update ALTIJD: --restore-hook + reboot (review m13).

AA=/data_persist/dev/aa
UD=/jci/scripts/usb_drivers.sh
DROPC=/proc/sys/vm/drop_caches
UD_STOCK_MD5=a52bb42330acedf809da1f02ab76b07d
TAG='MZD-AA-BUSPATCH'
HOOKID='/data_persist/dev/aa/aa-early.sh'

RW=0
cleanup() {
    rm -f "$UD.aanew" 2>/dev/null
    if [ $RW -eq 1 ]; then sync; mount -o remount,ro / 2>/dev/null || echo "LET OP: rootfs bleef rw (normaal tot reboot)"; fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

die() { echo "FOUT: $*" >&2; exit 1; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
dropcache() { sync; { echo 3 > "$DROPC"; } 2>/dev/null; }

case "$1" in ''|--restore-hook|--purge) ;; *) die "onbekende optie '$1' (geen, --restore-hook, --purge)";; esac

# review m7: resultaat controleren i.p.v. blind melden.
if [ -d "$AA" ]; then
    { echo "uninstall at $(date)" > "$AA/DISABLE"; } 2>/dev/null; sync
    if [ -s "$AA/DISABLE" ]; then echo "DISABLE gezet: volgende boot draait stock usbmgr + stock aapa."
    else echo "WAARSCHUWING: DISABLE kon NIET geschreven worden in $AA." >&2; fi
    { echo "uninstall at $(date)" > "$AA/DISABLE_AAPA"; } 2>/dev/null; sync
    if [ -s "$AA/DISABLE_AAPA" ]; then echo "DISABLE_AAPA gezet."
    else echo "WAARSCHUWING: DISABLE_AAPA kon NIET geschreven worden in $AA." >&2; fi
else
    echo "Geen $AA: de hook doet niets (aa-early.sh ontbreekt)."
fi

case "$1" in
    --restore-hook|--purge)
        if [ "$(md5 "$UD")" = "$UD_STOCK_MD5" ]; then
            echo "$UD is al stock ($UD_STOCK_MD5)."
        else
            if [ -f "$UD.aabak" ] && [ "$(md5 "$UD.aabak")" = "$UD_STOCK_MD5" ]; then
                src=backup
            else
                # review m6: geen (geldige) backup -> hookregels eruit filteren, alleen als exact stock.
                grep -v -F -e "$TAG" -e "$HOOKID" "$UD" > /tmp/aa-ud.$$ 2>/dev/null
                [ "$(md5 /tmp/aa-ud.$$)" = "$UD_STOCK_MD5" ] || { rm -f /tmp/aa-ud.$$; die "geen geldige backup en filteren geeft geen stock; NIETS gewijzigd (DISABLE staat wel)"; }
                src=filter
            fi
            mount -o remount,rw,sync / || die "remount rw mislukt; DISABLE staat wel"
            RW=1
            if [ $src = backup ]; then cp -p "$UD.aabak" "$UD.aanew" || die "kopie backup mislukt"
            else cp /tmp/aa-ud.$$ "$UD.aanew" && chmod 755 "$UD.aanew" || die "kopie mislukt"; rm -f /tmp/aa-ud.$$; fi
            [ "$(md5 "$UD.aanew")" = "$UD_STOCK_MD5" ] || die "tijdelijk bestand niet stock; origineel ongewijzigd"
            mv "$UD.aanew" "$UD" || die "terugzetten mislukt; origineel ongewijzigd"
            dropcache
            # review m8: harde eindcontrole.
            m=$(md5 "$UD")
            [ "$m" = "$UD_STOCK_MD5" ] || die "EINDCONTROLE FAALT: $UD md5 $m != $UD_STOCK_MD5 — NIET rebooten, handmatig herstellen"
            echo "usb_drivers.sh exact stock hersteld via $src (md5 $m teruggelezen)."
        fi
        ;;
esac

if [ "$1" = "--purge" ]; then
    rm -f "$AA/svcjciusbmgr.so.patched" "$AA/svcjciusbmgr.so.patched.md5" "$AA/MANIFEST.md5" "$AA/blmjciaapa.so.patched" \
          "$AA/aa-early.sh" "$AA/aa-guard.sh" "$AA/bootcount" "$AA/bootcount.tmp" "$AA/disabled" "$AA/aa.conf" \
          "$AA/proven" "$AA/proven.tmp"
    rm -rf "$AA/stage"
    sync
    echo "Bestanden verwijderd (logs + DISABLE/DISABLE_AAPA + aa-status/uninstall/install behouden)."
fi
echo "Reboot nodig om een eventueel actieve bind-mount kwijt te raken."
exit 0
