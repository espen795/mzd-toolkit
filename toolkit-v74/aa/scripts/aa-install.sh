#!/bin/sh
# aa-install.sh — MZD AA bus-patch (v74), installatie/upgrade OP DE CMU (via SSH). Versie 3.
# Twee situaties, automatisch herkend:
#  A) VERSE INSTALLATIE (hook nog niet in usb_drivers.sh) = FASE 1 (review M5): hook in
#     /jci/scripts/usb_drivers.sh + DISABLE + DISABLE_AAPA. Na reboot draait nog stock.
#     Activeren apart: `sh aa-status.sh arm` (usbmgr) en later `sh aa-status.sh arm-aapa`.
#  B) UPGRADE (hook staat er al, md5 exact = huidige hook): usb_drivers.sh en de rootfs worden
#     NIET aangeraakt (geen remount). De gewapend/DISABLE-stand van usbmgr blijft zoals hij is.
#     Het aapa-doel wordt (opnieuw) uitgezet met DISABLE_AAPA tot `arm-aapa`.
#     `aa-install.sh --keep-aapa` (alleen upgrade, kit 3.1): aapa-stand blijft zoals hij is — alleen
#     als de geïnstalleerde aa-early.sh al v3 is (aapa-ondersteuning) en de geïnstalleerde én nieuwe
#     aapa-payload exact de bekende patch zijn. Voor een kit-update zonder payloadwijziging.
#     Het proven-record (kit 3.1) wordt bij ELKE run (verse installatie, upgrade, ook --keep-aapa)
#     verwijderd, vóór er bestanden geplaatst worden (review4 L2): nieuwe scripts/firmware krijgen
#     eerst weer PROVEN_N strikt getelde, gezonde boots.
# Bestanden aanleveren (vanaf de beheerhost): bij voorkeur in $AA/stage/ (payloads + 5 scripts +
# MANIFEST.md5). Dan worden ze eerst daar tegen het manifest gecontroleerd en pas daarna per
# bestand atomisch (cp -> .aanew -> md5 -> mv) op hun plek gezet, aa-early.sh als laatste. Zo
# leest een nog draaiende aa-guard.sh (oude inode) nooit een half overschreven bestand.
# Zonder stage/: bestanden staan al in $AA (oude werkwijze).
# Controles: MANIFEST.md5 (alle bestanden), sh -n, md5 stock .so / patches / usb_drivers.sh,
# md5 van het NIEUWE usb_drivers.sh vóór én ná de mv (teruggelezen, cache geleegd).
# Mislukt de eindcontrole -> backup teruggezet + gecontroleerd. Rootfs gaat altijd terug naar ro (trap).
# De .so's op de rootfs worden NOOIT overschreven.
# Review 3: vóór het plaatsen een ondergrens vrije ruimte op $AA (m4); vóór de eindcontrole van $AA
# de page-cache legen, zodat van de flash wordt teruggelezen (m3); stage/ pas als allerlaatste
# weggooien vanuit een vooraf volledig ingelezen functie, zodat het script veilig vanuit stage/
# zelf kan draaien (m2).

AA=/data_persist/dev/aa
STAGE=$AA/stage
TARGET=/jci/usbmgr/svcjciusbmgr.so
TARGET_AAPA=/jci/aapa/blmjciaapa.so
UD=/jci/scripts/usb_drivers.sh
MOUNTS=/proc/mounts
DROPC=/proc/sys/vm/drop_caches
ORIG_MD5=413a2569b6528d11a00eb8773a60de80
PATCHED_MD5=b6aeec1653a26e36e4e1907832c7cbf3
AAPA_ORIG_MD5=486628ae7b5be7c80527968a0b85ae38
AAPA_PATCHED_MD5=a9c44143c0e89d66464269446a7726e0
UD_STOCK_MD5=a52bb42330acedf809da1f02ab76b07d
UD_PATCHED_MD5=cb2b34823582b55740c8134360c183c1
TAG='# MZD-AA-BUSPATCH'
TAGLINE="$TAG: aa-early.sh op achtergrond, max ~15 s gewacht (guarded, faalt open)"
HOOK='[ -f /data_persist/dev/aa/aa-early.sh ] && { /bin/sh /data_persist/dev/aa/aa-early.sh </dev/null >/dev/null 2>&1 & aa_p=$!; aa_i=0; while [ $aa_i -lt 15 ] && kill -0 $aa_p 2>/dev/null; do sleep 1; aa_i=$((aa_i + 1)); done; }'
# volgorde = plaatsingsvolgorde bij stage: payloads, dan guard/tools, aa-early.sh (ingang) als laatste
MINFREE_KB=4096   # m4: grootste bestand (1,7 MB) als .aanew + teller/logs, ruim
FILES="svcjciusbmgr.so.patched blmjciaapa.so.patched aa-guard.sh aa-status.sh aa-uninstall.sh aa-install.sh aa-early.sh"

RW=0
cleanup() {
    rm -f "$UD.aanew" "$UD.aachk" 2>/dev/null
    for f in $FILES MANIFEST.md5; do rm -f "$AA/$f.aanew" 2>/dev/null; done
    if [ $RW -eq 1 ]; then
        sync
        mount -o remount,ro / 2>/dev/null || echo "LET OP: rootfs bleef rw (normaal tot reboot)"
    fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

die() { echo "FOUT: $*" >&2; exit 1; }
KEEP_AAPA=0
case "$1" in ''|--keep-aapa) [ "$1" = --keep-aapa ] && KEEP_AAPA=1 ;; *) die "onbekende optie '$1' (geen of --keep-aapa)" ;; esac
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
dropcache() { sync; { echo 3 > "$DROPC"; } 2>/dev/null; }
# done_ok: stage/ weg en klaar. Een functie wordt in z'n geheel ingelezen vóór hij draait, dus ook
# als dit script zelf in stage/ staat leest de shell na de rm niets meer uit het (verwijderde) bestand.
done_ok() { [ -d "$STAGE" ] && { rm -rf "$STAGE"; sync; }; exit 0; }
# vrij_kb <dir>: beschikbare KB (busybox-df kan de device-naam op een eigen regel zetten:
# daarom van achteren tellen: ... Available Use% Mounted-on)
vrij_kb() { df -k "$1" 2>/dev/null | awk 'END { print $(NF-2) }'; }

# verify_dir <dir>: alle bestanden aanwezig, in het manifest van <dir>, md5 klopt, sh -n, payload-md5's
verify_dir() {
    [ -f "$1/MANIFEST.md5" ] || die "$1/MANIFEST.md5 ontbreekt (meesturen)"
    for f in $FILES; do
        [ -f "$1/$f" ] || die "$1/$f ontbreekt (eerst kopiëren)"
        want=$(awk -v f="$f" '$2 == f {print $1}' "$1/MANIFEST.md5")
        [ -n "$want" ] || die "$f staat niet in $1/MANIFEST.md5"
        [ "$(md5 "$1/$f")" = "$want" ] || die "md5 $1/$f klopt niet met MANIFEST.md5 (overdracht kapot?)"
    done
    for f in aa-early.sh aa-guard.sh aa-status.sh aa-uninstall.sh aa-install.sh; do
        sh -n "$1/$f" || die "syntaxfout $1/$f"
    done
    [ "$(md5 "$1/svcjciusbmgr.so.patched")" = "$PATCHED_MD5" ] || die "usbmgr-patch md5 klopt niet"
    [ "$(md5 "$1/blmjciaapa.so.patched")" = "$AAPA_PATCHED_MD5" ] || die "aapa-patch md5 klopt niet"
}

[ -d "$AA" ] || die "$AA ontbreekt"

# Modus bepalen VÓÓR er iets verandert.
if grep -q "$TAG" "$UD"; then
    # review m4: bestaande hook alleen accepteren als het hele bestand exact klopt.
    [ "$(md5 "$UD")" = "$UD_PATCHED_MD5" ] || die "$UD bevat de hook maar md5 $(md5 "$UD") != $UD_PATCHED_MD5; handmatig bekijken"
    MODE=upgrade
else
    [ "$(md5 "$UD")" = "$UD_STOCK_MD5" ] || die "$UD is niet stock (md5 $(md5 "$UD")); handmatig bekijken"
    [ "$(grep -c '^touch /var/run/usb_driver_ready$' "$UD")" = "1" ] || die "ankerregel niet precies 1x gevonden"
    MODE=fresh
fi
echo "Modus: $MODE"
if [ $KEEP_AAPA -eq 1 ]; then
    [ $MODE = upgrade ] || die "--keep-aapa alleen bij een upgrade (hook staat al)"
    grep -q '^TARGET_AAPA=' "$AA/aa-early.sh" 2>/dev/null || die "--keep-aapa: geïnstalleerde aa-early.sh is nog geen v3; gewone upgrade + arm-aapa"
    [ "$(md5 "$AA/blmjciaapa.so.patched")" = "$AAPA_PATCHED_MD5" ] || die "--keep-aapa: geïnstalleerde aapa-payload klopt niet; gewone upgrade + arm-aapa"
fi

# Stock-controle (doelen die nu gemount zijn overslaan: die tonen de patch).
if grep -q " $TARGET " "$MOUNTS"; then
    echo "LET OP: $TARGET is al bind-gemount (usbmgr-patch actief deze boot)."
else
    [ "$(md5 "$TARGET")" = "$ORIG_MD5" ] || die "stock usbmgr md5 klopt niet: $(md5 "$TARGET") (andere firmware?)"
fi
if grep -q " $TARGET_AAPA " "$MOUNTS"; then
    echo "LET OP: $TARGET_AAPA is al bind-gemount (aapa-patch actief deze boot)."
elif [ "$(md5 "$TARGET_AAPA")" != "$AAPA_ORIG_MD5" ]; then
    # Geen die: het usbmgr-doel moet blijven werken; aa-early.sh slaat aapa dan zelf over.
    echo "WAARSCHUWING: stock aapa md5 $(md5 "$TARGET_AAPA") != $AAPA_ORIG_MD5 -> aapa-doel wordt bij boot overgeslagen; NIET arm-aapa doen."
fi

# Eerst stage controleren, dan het aapa-doel uitzetten, dan pas bestanden plaatsen.
[ -d "$STAGE" ] && verify_dir "$STAGE"

# aapa-doel standaard UIT (ook bij upgrade/herinstallatie), vóór er een nieuwe aa-early.sh staat.
if [ $KEEP_AAPA -eq 1 ]; then
    echo "--keep-aapa: aapa-stand blijft: $( [ -e "$AA/DISABLE_AAPA" ] && echo 'UIT (DISABLE_AAPA)' || echo 'gewapend')"
else
    echo "install $(date): aapa-doel uit tot 'aa-status.sh arm-aapa'" > "$AA/DISABLE_AAPA"; sync
    [ -s "$AA/DISABLE_AAPA" ] || die "kon DISABLE_AAPA niet zetten in $AA (schrijfbaar?)"
fi

# review4 L2: proven-record altijd weg (fingerprint ziet scriptversie/rest van de firmware niet).
rm -f "$AA/proven" "$AA/proven.tmp" 2>/dev/null; sync
[ ! -e "$AA/proven" ] || die "kon $AA/proven niet verwijderen (schrijfbaar?)"
echo "proven-record: verwijderd (eerst weer strikt tellen tot de guard opnieuw genoeg gezonde boots ziet)."

if [ $MODE = fresh ]; then
    # Fase 1 = stock gedrag, vóór de rootfs wordt aangeraakt.
    if [ -e "$AA/DISABLE" ]; then
        echo "DISABLE stond al: blijft staan ($(head -n 1 "$AA/DISABLE" 2>/dev/null))."
    else
        echo "fase1: geïnstalleerd $(date), nog niet gewapend (aa-status.sh arm)" > "$AA/DISABLE"
    fi
    sync
    [ -e "$AA/DISABLE" ] || die "kon DISABLE niet zetten in $AA (schrijfbaar?)"
fi

if [ -d "$STAGE" ]; then
    vk=$(vrij_kb "$AA")
    case "$vk" in
        ''|*[!0-9]*) echo "WAARSCHUWING: vrije ruimte op $AA niet te bepalen ('$vk'); zelf 'df $AA' controleren" ;;
        *) [ "$vk" -ge "$MINFREE_KB" ] || die "te weinig vrije ruimte op $AA: ${vk} KB < ${MINFREE_KB} KB (niets geplaatst)" ;;
    esac
    for f in $FILES MANIFEST.md5; do
        cp "$STAGE/$f" "$AA/$f.aanew" 2>/dev/null || die "kopie $f uit stage mislukt (eerder geplaatste bestanden blijven; opnieuw draaien)"
        [ "$(md5 "$AA/$f.aanew")" = "$(md5 "$STAGE/$f")" ] || die "md5 $f.aanew klopt niet na kopie"
        mv "$AA/$f.aanew" "$AA/$f" || die "mv $f mislukt"
    done
    sync
    echo "Bestanden uit $STAGE geplaatst (per bestand atomisch, aa-early.sh laatst)."
fi
dropcache          # m3: eindcontrole van de flash, niet uit de page-cache
verify_dir "$AA"

case "$(head -n 1 "$AA/bootcount" 2>/dev/null)" in
    ''|*[!0-9]*) echo 0 > "$AA/bootcount"; sync ;;
esac

if [ $MODE = upgrade ]; then
    echo "Hook staat al correct in $UD (md5 $UD_PATCHED_MD5) — usb_drivers.sh en rootfs NIET aangeraakt."
    if [ $KEEP_AAPA -eq 1 ]; then
        echo "Upgrade klaar. usbmgr: $( [ -e "$AA/DISABLE" ] && echo 'DISABLE staat (stock)' || echo 'gewapend (blijft gewapend)'); aapa: $( [ -e "$AA/DISABLE_AAPA" ] && echo 'UIT (DISABLE_AAPA)' || echo 'gewapend (blijft gewapend)')."
        echo "Volgende stap: reboot ZONDER telefoon, >= 9 min wachten, 'sh $AA/aa-status.sh check' (guard.log: 'proven: gezonde boot 1')."
        done_ok
    fi
    echo "Upgrade klaar. usbmgr: $( [ -e "$AA/DISABLE" ] && echo 'DISABLE staat (stock)' || echo 'gewapend (blijft gewapend)'); aapa: UIT (DISABLE_AAPA)."
    echo "Volgende stap (review 3 H2): EERST een tussenboot met aapa UIT (contact uit/aan, 4 min, 'sh $AA/aa-status.sh check'),"
    echo "pas daarna 'sh $AA/aa-status.sh arm-aapa' + reboot ZONDER telefoon, >= 9 min wachten, 'sh $AA/aa-status.sh check'."
    done_ok
fi

mount -o remount,rw,sync / || die "remount rw mislukt"
RW=1
if [ ! -f "$UD.aabak" ]; then cp -p "$UD" "$UD.aabak" || die "backup mislukt"; sync; fi
[ "$(md5 "$UD.aabak")" = "$UD_STOCK_MD5" ] || die "backup $UD.aabak md5 klopt niet"

awk -v tag="$TAGLINE" -v hook="$HOOK" '
    /^touch \/var\/run\/usb_driver_ready$/ { print tag; print hook }
    { print }' "$UD.aabak" > "$UD.aanew" || die "awk mislukt"

sh -n "$UD.aanew" || die "nieuw usb_drivers.sh: syntaxfout"
old=$(wc -l < "$UD.aabak"); new=$(wc -l < "$UD.aanew")
[ "$new" -eq $((old + 2)) ] || die "regelaantal klopt niet ($old -> $new)"
grep -v -F -e "$TAGLINE" -e "$HOOK" "$UD.aanew" > "$UD.aachk"
cmp -s "$UD.aachk" "$UD.aabak" || die "onverwacht verschil buiten de 2 hookregels"
[ "$(md5 "$UD.aanew")" = "$UD_PATCHED_MD5" ] || die "md5 nieuw bestand $(md5 "$UD.aanew") != $UD_PATCHED_MD5"
chmod 755 "$UD.aanew"
mv "$UD.aanew" "$UD" || die "mv mislukt (origineel ongewijzigd)"
dropcache

# Eindcontrole op het echte bestand (review M3).
if [ "$(md5 "$UD")" != "$UD_PATCHED_MD5" ] || ! sh -n "$UD"; then
    echo "FOUT: eindcontrole $UD faalde (md5 $(md5 "$UD")) -> backup terugzetten" >&2
    cp -p "$UD.aabak" "$UD.aanew" && mv "$UD.aanew" "$UD"
    dropcache
    if [ "$(md5 "$UD")" = "$UD_STOCK_MD5" ]; then
        die "backup teruggezet, $UD is weer stock ($UD_STOCK_MD5). Niets geïnstalleerd."
    fi
    die "HERSTEL MISLUKT: $UD md5 $(md5 "$UD"). NIET rebooten; handmatig: cp $UD.aabak $UD"
fi
echo "Hook toegevoegd aan $UD (md5 $UD_PATCHED_MD5 teruggelezen; backup $UD.aabak)."
echo "Fase 1 klaar: hook staat, DISABLE + DISABLE_AAPA staan -> volgende boot draait STOCK."
echo "Volgende stap: contact uit/aan, dan 'sh $AA/aa-status.sh' (verwacht: 'DISABLE aanwezig' in early.log)."
echo "Pas daarna: 'sh $AA/aa-status.sh arm' + reboot zonder telefoon (fase 2)."
done_ok
