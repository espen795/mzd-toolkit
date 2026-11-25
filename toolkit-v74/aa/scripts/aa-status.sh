#!/bin/sh
# aa-status.sh — MZD AA bus-patch (v74), status + fasebeheer OP DE CMU. Versie 3 (2 doelen).
#   sh aa-status.sh            : status (alleen lezen)
#   sh aa-status.sh check      : na-boot-controle (alleen lezen): bind-mount, usbmgr, sshd/eth1,
#                                sd_nav + navigatie (review M4), dmesg reset/sda, ruimte/dumps (m11)
#   sh aa-status.sh arm        : SCHRIJFT — fase 2: DISABLE + disabled weg, bootcount=0.
#                                Weigert als de hook niet exact klopt of nog nooit een boot heeft gedaan
#                                (fase 1 niet afgerond); `arm --force` slaat alleen die laatste check over.
#   sh aa-status.sh disarm     : SCHRIJFT — DISABLE zetten (teruggelezen) + proven-record weg (review4 L2).
#                                Volgende boot stock.
#   sh aa-status.sh rearm      : SCHRIJFT — alleen crash-guard-marker 'disabled' + bootcount wissen
#                                (na analyse van een crash). DISABLE blijft zoals hij is. Alias: --rearm
#   sh aa-status.sh arm-aapa   : SCHRIJFT — aapa-doel aan: DISABLE_AAPA weg (teruggecontroleerd).
#                                Weigert zonder hook v2, zonder aa-early v3, bij foute payload-md5,
#                                als stock blmjciaapa.so niet klopt, als bootcount != 0 of 'disabled'
#                                staat (guard deze boot niet gezond), of als een bestand in $AA niet
#                                klopt met $AA/MANIFEST.md5 (review3 m5). Raakt usbmgr/teller niet aan.
#   sh aa-status.sh disarm-aapa: SCHRIJFT — DISABLE_AAPA zetten (teruggelezen) + proven-record weg (review4 L2).
#                                usbmgr blijft zoals hij is.
#   sh aa-status.sh unprove    : SCHRIJFT — proven-record weg (kit 3.1): weer strikt tellen tot de guard
#                                opnieuw PROVEN_N gezonde boots voor de combinatie heeft gezien.
# Proven mode (kit 3.1): na PROVEN_N (aa.conf, standaard 5) gezonde boots voor exact dezelfde
# doelcombinatie (stock+patch-md5) telt aa-early de boot niet meer mee (korte ritten). Elke
# 'niet gezond' van de guard trekt proven in. disarm/disarm-aapa en aa-install verwijderen het record
# (review4 L2); arm/rearm/arm-aapa zetten het NIET terug: na opnieuw wapenen wordt het opnieuw opgebouwd.
# DISABLE = alles uit (beide doelen); DISABLE_AAPA = alleen aapa uit; 'disabled' (guard) = alles uit.

AA=/data_persist/dev/aa
TARGET=/jci/usbmgr/svcjciusbmgr.so
TARGET_AAPA=/jci/aapa/blmjciaapa.so
UD=/jci/scripts/usb_drivers.sh
MOUNTS=/proc/mounts
ORIG_MD5=413a2569b6528d11a00eb8773a60de80
PATCHED_MD5=b6aeec1653a26e36e4e1907832c7cbf3
AAPA_ORIG_MD5=486628ae7b5be7c80527968a0b85ae38
AAPA_PATCHED_MD5=a9c44143c0e89d66464269446a7726e0
UD_PATCHED_MD5=cb2b34823582b55740c8134360c183c1

die() { echo "FOUT: $*" >&2; exit 1; }
isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
# --- proven-record (kit 3.1). Identiek in aa-early.sh, aa-guard.sh en aa-status.sh. ---
# $AA/proven (max 1 KB):  short=<n>                (boots op rij zonder guard-oordeel in proven mode)
#                         rec=<aantal> <fingerprint>  (gezonde boots per doelcombinatie, max 1 per fp)
# fingerprint = per GEMOUNT doel "<naam>:<stock-md5>:<patch-md5>", met '+' aan elkaar (usbmgr eerst).
# Elke afwijking in het bestand = ongeldig = niet proven (P_RECS leeg).
PF=$AA/proven
NL='
'
nz() { v=$1; while :; do case "$v" in 0?*) v=${v#0} ;; *) break ;; esac; done; echo "$v"; }
fp_of() {   # fp_of <usbmgr 0/1> <aapa 0/1>
    f=
    [ "$1" = 1 ] && f="usbmgr:$ORIG_MD5:$PATCHED_MD5"
    [ "$2" = 1 ] && f="${f:+$f+}aapa:$AAPA_ORIG_MD5:$AAPA_PATCHED_MD5"
    echo "$f"
}
_rp() {
    [ -f "$PF" ] || return 1
    sz=$(wc -c < "$PF" 2>/dev/null | tr -d ' ')
    isnum "$sz" && [ "$sz" -le 1024 ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            short=*) v=${line#short=}; isnum "$v" && [ ${#v} -le 4 ] || return 1; P_SHORT=$(nz "$v") ;;
            rec=*)   r=${line#rec=}; c=${r%% *}; f=${r#* }
                     [ "$f" != "$r" ] && isnum "$c" && [ ${#c} -le 4 ] || return 1
                     case "$f" in ''|*[!a-z0-9:+]*) return 1 ;; esac
                     P_RECS="$P_RECS$(nz "$c") $f$NL" ;;
            '') ;;
            *) return 1 ;;
        esac
        line=
    done 2>/dev/null < "$PF"
    [ -n "$P_SHORT" ]
}
read_proven() { P_SHORT=; P_RECS=; _rp && return 0; P_SHORT=; P_RECS=; return 1; }
get_cnt() { c=$(printf '%s' "$P_RECS" | awk -v f="$1" '$2 == f { print $1; exit }'); echo "${c:-0}"; }
# write_proven <short> [<fp> <aantal>]: atomisch (tmp + mv + sync) en TERUGGELEZEN; andere records blijven
write_proven() {
    { echo "short=$1"
      printf '%s' "$P_RECS" | awk -v f="$2" 'NF == 2 && $2 != f { print "rec=" $1 " " $2 }'
      if [ -n "$2" ]; then echo "rec=$3 $2"; fi
    } 2>/dev/null > "$PF.tmp" && mv "$PF.tmp" "$PF" 2>/dev/null && sync || return 1
    w_s=$1; w_f=$2; w_c=$3
    read_proven && [ "$P_SHORT" = "$w_s" ] || return 1
    [ -z "$w_f" ] || [ "$(get_cnt "$w_f")" = "$w_c" ]
}
revoke_proven() { rm -f "$PF" "$PF.tmp" 2>/dev/null; sync; P_SHORT=; P_RECS=; [ ! -e "$PF" ]; }
# --- einde proven-record ---
setcount0() {
    echo 0 > "$AA/bootcount.tmp" && mv "$AA/bootcount.tmp" "$AA/bootcount" && sync \
        && [ "$(head -n 1 "$AA/bootcount" 2>/dev/null)" = "0" ]
}

case "$1" in
    arm)
        [ "$(md5 "$UD")" = "$UD_PATCHED_MD5" ] || die "hook niet (correct) geïnstalleerd: md5 $(md5 "$UD"); eerst aa-install.sh"
        [ "$(md5 "$AA/svcjciusbmgr.so.patched")" = "$PATCHED_MD5" ] || die "payload md5 klopt niet"
        for f in aa-early.sh aa-guard.sh; do sh -n "$AA/$f" || die "$f ontbreekt/syntaxfout"; done
        if [ "$2" != "--force" ] && ! grep -q "aa-early v[23] start" "$AA/early.log" 2>/dev/null; then
            die "early.log toont nog geen boot met de hook (fase 1: eerst contact uit/aan + controleren). 'arm --force' om te negeren."
        fi
        setcount0 || die "bootcount niet schrijfbaar/teruglezbaar -> NIET gewapend"
        rm -f "$AA/DISABLE" "$AA/disabled"; sync
        [ ! -e "$AA/DISABLE" ] && [ ! -e "$AA/disabled" ] || die "kon DISABLE/disabled niet verwijderen"
        echo "GEWAPEND. Volgende boot: bind-mount gepatchte usbmgr. Reboot ZONDER telefoon (fase 2), daarna 'sh $0 check'."
        [ -e "$AA/DISABLE_AAPA" ] && echo "aapa-doel blijft UIT (DISABLE_AAPA); apart: 'sh $0 arm-aapa'."
        exit 0 ;;
    arm-aapa)
        [ "$(md5 "$UD")" = "$UD_PATCHED_MD5" ] || die "hook niet (correct) geïnstalleerd: md5 $(md5 "$UD"); eerst aa-install.sh"
        [ "$(md5 "$AA/blmjciaapa.so.patched")" = "$AAPA_PATCHED_MD5" ] || die "aapa-payload md5 klopt niet (eerst upgrade via aa-install.sh)"
        for f in aa-early.sh aa-guard.sh; do sh -n "$AA/$f" || die "$f ontbreekt/syntaxfout"; done
        grep -q '^TARGET_AAPA=' "$AA/aa-early.sh" && grep -q '^AAPAPROC=' "$AA/aa-guard.sh" \
            || die "aa-early.sh/aa-guard.sh zijn nog geen v3 (geen aapa-ondersteuning); eerst aa-install.sh (upgrade)"
        # review3 m5: alle kitbestanden tegen het manifest
        [ -f "$AA/MANIFEST.md5" ] || die "$AA/MANIFEST.md5 ontbreekt"
        for f in svcjciusbmgr.so.patched blmjciaapa.so.patched aa-early.sh aa-guard.sh aa-install.sh aa-status.sh aa-uninstall.sh; do
            want=$(awk -v f="$f" '$2 == f {print $1}' "$AA/MANIFEST.md5")
            [ -n "$want" ] && [ "$(md5 "$AA/$f")" = "$want" ] || die "$AA/$f klopt niet met MANIFEST.md5 -> eerst (opnieuw) aa-install.sh"
        done
        # review3 m5: alleen wapenen na een boot waarin de guard 'gezond' gaf (teller 0, geen 'disabled')
        [ "$(head -n 1 "$AA/bootcount" 2>/dev/null)" = "0" ] \
            || die "bootcount is '$(head -n 1 "$AA/bootcount" 2>/dev/null)', niet 0: guard gaf deze boot (nog) geen 'gezond' (uptime > 4 min? guard.log bekijken)"
        [ ! -e "$AA/disabled" ] || die "crash-guard-marker 'disabled' staat ($(cat "$AA/disabled" 2>/dev/null)); eerst analyseren + 'rearm'"
        if ! grep -q " $TARGET_AAPA " "$MOUNTS"; then
            [ "$(md5 "$TARGET_AAPA")" = "$AAPA_ORIG_MD5" ] || die "stock $TARGET_AAPA md5 $(md5 "$TARGET_AAPA") != $AAPA_ORIG_MD5 (andere firmware?)"
        fi
        rm -f "$AA/DISABLE_AAPA"; sync
        [ ! -e "$AA/DISABLE_AAPA" ] || die "kon DISABLE_AAPA niet verwijderen"
        echo "aapa-doel GEWAPEND. Volgende boot: bind-mount gepatchte blmjciaapa.so (naast usbmgr)."
        [ -e "$AA/DISABLE" ] && echo "LET OP: DISABLE staat -> bij boot blijven BEIDE doelen stock ('sh $0 arm' voor usbmgr)."
        echo "Reboot ZONDER telefoon, >= 9 min wachten (guard-beoordeling aapa op AAPA_GRACE 420 s + 60 s bevestiging),"
        echo "dan 'sh $0 check'. Telefoon pas daarna, bemand; bij een onverwachte reboot EERST de telefoon lostrekken, dan 'sh $0 disarm-aapa'."
        exit 0 ;;
    disarm-aapa)
        echo "disarm-aapa at $(date)" > "$AA/DISABLE_AAPA"; sync
        [ -s "$AA/DISABLE_AAPA" ] || die "DISABLE_AAPA kon niet geschreven worden!"
        echo "DISABLE_AAPA gezet. Volgende boot: stock aapa (usbmgr ongewijzigd)."
        # review4 L2: na disarm geen oud vertrouwen meenemen (arm-aapa bouwt proven opnieuw op)
        if [ -e "$PF" ] || [ -e "$PF.tmp" ]; then
            revoke_proven && echo "proven-record verwijderd (na opnieuw wapenen eerst weer strikt tellen)." \
                || echo "LET OP: proven-record kon niet verwijderd worden ($PF); later 'sh $0 unprove'."
        fi
        exit 0 ;;
    disarm)
        echo "disarm at $(date)" > "$AA/DISABLE"; sync
        [ -s "$AA/DISABLE" ] || die "DISABLE kon niet geschreven worden!"
        echo "DISABLE gezet. Volgende boot: stock usbmgr (contact uit/aan)."
        if [ -e "$PF" ] || [ -e "$PF.tmp" ]; then
            revoke_proven && echo "proven-record verwijderd (na opnieuw wapenen eerst weer strikt tellen)." \
                || echo "LET OP: proven-record kon niet verwijderd worden ($PF); later 'sh $0 unprove'."
        fi
        exit 0 ;;
    unprove)
        revoke_proven || die "proven-record kon niet verwijderd worden ($PF)"
        echo "proven-record verwijderd: volgende boots tellen weer strikt (MAXFAIL), tot de guard opnieuw genoeg gezonde boots ziet."
        exit 0 ;;
    rearm|--rearm)
        setcount0 || die "bootcount niet schrijfbaar/teruglezbaar"
        rm -f "$AA/disabled"; sync
        echo "Crash-guard gereset (bootcount=0, 'disabled' weg). DISABLE: $( [ -e "$AA/DISABLE" ] && echo 'staat NOG (arm om te activeren)' || echo nee)."
        exit 0 ;;
    ''|status|check) ;;
    *) die "onbekend subcommando '$1' (status|check|arm|disarm|rearm|arm-aapa|disarm-aapa|unprove)" ;;
esac

proc_alive() {   # zombie (Z) telt als dood (review3 m1)
    for s in /proc/[0-9]*/stat; do
        read -r line < "$s" 2>/dev/null || continue
        case "$line" in *"($1) Z "*) continue ;; *"($1) "*) return 0 ;; esac
    done
    return 1
}

read u _ < /proc/uptime
echo "uptime           : ${u%%.*}s"
if grep -q " $TARGET " "$MOUNTS"; then
    echo "bind-mount       : ACTIEF  ($(grep " $TARGET " "$MOUNTS" | tail -n 1))"
else
    echo "bind-mount       : niet actief (stock usbmgr)"
fi
m=$(md5 "$TARGET")
[ "$m" = "$PATCHED_MD5" ] && echo "usbmgr via pad   : GEPATCHT ($m)" || echo "usbmgr via pad   : stock/anders ($m)"
um=$(md5 "$UD")
case "$um" in
    "$UD_PATCHED_MD5") echo "usb_drivers.sh   : hook v2 OK ($um)" ;;
    a52bb42330acedf809da1f02ab76b07d) echo "usb_drivers.sh   : stock (geen hook)" ;;
    *) echo "usb_drivers.sh   : ONBEKEND ($um) — bekijken!" ;;
esac
echo "bootcount        : $(cat "$AA/bootcount" 2>/dev/null || echo '-')"
if [ -e "$AA/DISABLE" ]; then echo "DISABLE          : JA ($(cat "$AA/DISABLE" 2>/dev/null))"; else echo "DISABLE          : nee (gewapend)"; fi
echo "disabled (guard) : $( [ -e "$AA/disabled" ] && cat "$AA/disabled" || echo nee)"
[ -f "$AA/aa.conf" ] && echo "aa.conf          : $(tr '\n' ' ' < "$AA/aa.conf")"
# proven mode (zelfde regels als aa-early.sh)
PN=5; PMS=20
if [ -f "$AA/aa.conf" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do
        isnum "$v" || { k=; continue; }
        v=$(nz "$v")
        case "$k" in
            PROVEN_N)        { [ "$v" -eq 0 ] || { [ "$v" -ge 3 ] && [ "$v" -le 20 ]; }; } && PN=$v ;;
            PROVEN_MAXSHORT) [ "$v" -ge 5 ] && [ "$v" -le 30 ] && PMS=$v ;;
        esac
        k=
    done < "$AA/aa.conf"
fi
cu=0; ca=0
grep -q " $TARGET " "$MOUNTS" && cu=1
grep -q " $TARGET_AAPA " "$MOUNTS" && ca=1
cfp=$(fp_of $cu $ca)
if [ "$PN" -eq 0 ]; then
    echo "proven           : UIT (PROVEN_N=0 in aa.conf)"
elif read_proven; then
    if [ -z "$cfp" ]; then
        echo "proven           : - (nu niets gemount; records hieronder)"
    else
        pc=$(get_cnt "$cfp")
        if [ "$pc" -ge "$PN" ] && [ "$P_SHORT" -lt "$PMS" ]; then
            echo "proven           : JA  $pc/$PN gezonde boots voor huidige combinatie (usbmgr=$cu aapa=$ca); boots op rij zonder oordeel $P_SHORT/$PMS"
        else
            echo "proven           : nee $pc/$PN gezonde boots voor huidige combinatie (usbmgr=$cu aapa=$ca); boots op rij zonder oordeel $P_SHORT/$PMS"
        fi
    fi
    printf '%s' "$P_RECS" | awk '{ n = split($2, p, "+"); s = ""; for (i = 1; i <= n; i++) { split(p[i], q, ":"); s = s (i > 1 ? "+" : "") q[1] } print "  record         : " $1 "x " s "  (" $2 ")" }'
elif [ -e "$PF" ]; then
    echo "proven           : nee (bestand ONGELDIG -> telt als niet proven; 'sh $0 unprove' ruimt op)"
else
    echo "proven           : nee (nog geen record; drempel $PN gezonde boots)"
fi
pid=$(ps | grep '[L]_jciUSBMGR' | awk '{print $1}' | head -n 1)
echo "jciUSBMGR pid    : ${pid:--}  (comm-check: $(proc_alive L_jciUSBMGR && echo leeft || echo NIET gevonden))"
if [ -n "$pid" ] && [ -r "/proc/$pid/maps" ]; then
    grep -m1 svcjciusbmgr "/proc/$pid/maps" | awk '{print "  maps          : " $6 " (dev " $4 ", inode " $5 ")"}'
fi
echo "-- aapa-doel --"
if grep -q " $TARGET_AAPA " "$MOUNTS"; then
    echo "aapa bind-mount  : ACTIEF  ($(grep " $TARGET_AAPA " "$MOUNTS" | tail -n 1))"
else
    echo "aapa bind-mount  : niet actief (stock aapa)"
fi
m=$(md5 "$TARGET_AAPA")
case "$m" in
    "$AAPA_PATCHED_MD5") echo "aapa via pad     : GEPATCHT ($m)" ;;
    "$AAPA_ORIG_MD5")    echo "aapa via pad     : stock ($m)" ;;
    *)                   echo "aapa via pad     : ONBEKEND ($m)" ;;
esac
if [ -e "$AA/DISABLE_AAPA" ]; then echo "DISABLE_AAPA     : JA ($(cat "$AA/DISABLE_AAPA" 2>/dev/null))"; else echo "DISABLE_AAPA     : nee (aapa gewapend)"; fi
echo "aapa-payload     : $( [ "$(md5 "$AA/blmjciaapa.so.patched")" = "$AAPA_PATCHED_MD5" ] && echo OK || echo 'ontbreekt/fout')"
apid=$(ps | grep '[L]_jciAAPA' | awk '{print $1}' | head -n 1)
echo "jciAAPA pid      : ${apid:--}  (comm-check: $(proc_alive L_jciAAPA && echo leeft || echo NIET gevonden))"
if [ -n "$apid" ] && [ -r "/proc/$apid/maps" ]; then
    grep -m1 blmjciaapa "/proc/$apid/maps" | awk '{print "  maps          : " $6 " (dev " $4 ", inode " $5 ")"}'
fi
echo "--- early.log (laatste 14) ---"; tail -n 14 "$AA/early.log" 2>/dev/null
echo "--- guard.log (laatste 6) ---";  tail -n 6 "$AA/guard.log" 2>/dev/null

if [ "$1" = "check" ]; then
    warn=0
    w() { echo "  WAARSCHUWING: $*"; warn=$((warn + 1)); }
    echo "--- na-boot-controle ---"
    proc_alive L_jciUSBMGR && echo "  usbmgr         : leeft" || w "usbmgr-proces L_jciUSBMGR niet gevonden"
    if grep -q " $TARGET_AAPA " "$MOUNTS"; then
        proc_alive L_jciAAPA && echo "  aapa           : leeft (gepatcht gemount)" || w "aapa gemount maar L_jciAAPA niet gevonden"
        [ "$(md5 "$TARGET_AAPA")" = "$AAPA_PATCHED_MD5" ] || w "aapa gemount maar md5 via pad is niet de patch"
    fi
    proc_alive sshd && echo "  sshd           : draait" || w "sshd draait niet"
    ifconfig eth1 2>/dev/null | grep -q "inet addr" && echo "  eth1           : $(ifconfig eth1 | grep 'inet addr' | awk '{print $2}')" || w "eth1 zonder IP"
    if grep -q " /tmp/mnt/sd_nav " "$MOUNTS"; then echo "  sd_nav         : gemount ($(grep ' /tmp/mnt/sd_nav ' "$MOUNTS" | awk '{print $1, $3}'))"
    else w "sd_nav NIET gemount (review M4: kaartlezer + GET_PROTOCOL?)"; fi
    nv=$(ps | grep -iE 'navi|nng' | grep -v grep | head -n 3)
    [ -n "$nv" ] && { echo "  navigatie-proc :"; echo "$nv" | sed 's/^/    /'; } || w "geen navi/nng-proces gevonden (vergelijk met nulmeting fase 0)"
    echo "  dmesg reset/sda (laatste 8):"; dmesg 2>/dev/null | grep -iE "reset|sda|usb 2-" | tail -n 8 | sed 's/^/    /'
    dmesg 2>/dev/null | grep -qiE "sda.*(error|timeout)|reset high.speed USB device.*2-" && w "dmesg toont sda-fouten of USB-resets op bus 2"
    echo "  lsusb:"; lsusb 2>/dev/null | sed 's/^/    /'
    echo "  ruimte /data_persist: $(df /data_persist 2>/dev/null | tail -n 1)"
    echo "  dumps: $(du -s /data_persist/log/dumps 2>/dev/null)"
    echo "  sm-events: $(tail -n 3 /tmp/smevents.txt 2>/dev/null | tr '\n' ' ')"
    echo "--- check: $warn waarschuwing(en) ---"
fi

echo "--- AA-relevante usbmgr/aapa staat ---"
lsusb 2>/dev/null | grep -iE "18d1|04e8|0424|0b95"
DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus_hmi_socket dbus-send --print-reply --dest=com.jci.aapa /com/jci/aapa com.jci.aapa.GetAOASessionStatus 2>/dev/null | sed -n '2,4p'
exit 0
