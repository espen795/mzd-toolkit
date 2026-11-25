#!/bin/sh
# aa-early.sh — MZD AA bus-patch (v74), boot-fase.  Versie 3 (2 doelen, 2026-11-24, review 3),
# kit 3.1 (2026-11-25): proven mode.
# Proven mode: heeft de guard voor PRECIES deze doelcombinatie (fingerprint = stock+patch-md5 per
# doel) al >= PROVEN_N keer 'gezond' gegeven, dan wordt de teller NIET opgehoogd (korte ritten
# zetten de patch dan niet meer uit). Wel: alle md5-controles, de schrijfproef (proven-record
# 'short' +1, teruggelezen; lukt dat niet -> geen mount, B1) en de guard. Wijkt de werkelijk
# gemounte set af van de proven-combinatie -> toch tellen. PROVEN_MAXSHORT boots op rij zonder
# guard-oordeel -> proven ingetrokken (vangnet tegen een crashlus vóór het guard-oordeel).
# Aangeroepen (op de achtergrond, max ~15 s gewacht) vanuit /jci/scripts/usb_drivers.sh
# VOOR `touch /var/run/usb_driver_ready`, dus voordat sm jciUSBMGR laadt — en daarmee ook vóór
# jciAAPA (sm.conf v74: jciAAPA -> devicemanager -> mfid -> jciUSBMGR -> usb_drivers).
# Doelen (elk onafhankelijk; faalt er één, dan alleen dat doel overslaan):
#   usbmgr : /jci/usbmgr/svcjciusbmgr.so  (bus-patch)
#   aapa   : /jci/aapa/blmjciaapa.so       (available-patch, stap 2). Alleen als DISABLE_AAPA
#            ontbreekt (aa-install zet hem; `aa-status.sh arm-aapa` haalt hem weg).
# Volgorde (review3 M1: usbmgr eerst helemaal af, aapa daarna en alleen binnen de tijdsgrens):
#   uptime-toets (niet met de hand op een lopend systeem, review3 m7) -> DISABLE/disabled (beide
#   doelen) -> config -> teller lezen+valideren -> usbmgr stock-md5 -> USB-stick kill-switch
#   (zonder schrijven) -> usbmgr: kopie /tmp/aa + md5 -> teller++ (gedeeld, 1x, teruggelezen) ->
#   bind-mount + verificatie -> [tijdstoets 1: AAPA_BUDGET] aapa: stock-md5 -> kopie + md5 ->
#   [tijdstoets 2: AAPA_MOUNT_BUDGET] -> (teller++ als nog niet gedaan) -> bind-mount + verificatie
#   -> guard starten.
# Faalt altijd "open" (stock), nooit dicht. Schrijft NOOIT naar de rootfs. Geen set -e.

AA=/data_persist/dev/aa
TARGET=/jci/usbmgr/svcjciusbmgr.so
TARGET_AAPA=/jci/aapa/blmjciaapa.so
PATCHED=$AA/svcjciusbmgr.so.patched
PATCHED_AAPA=$AA/blmjciaapa.so.patched
TMPAA=/tmp/aa                                   # tmpfs: bron van de bind-mounts (review M2)
ORIG_MD5=413a2569b6528d11a00eb8773a60de80       # stock MAZ_CMU-150_74.00.324
PATCHED_MD5=b6aeec1653a26e36e4e1907832c7cbf3    # 1 byte: 0xbca27 0x0a->0xea
AAPA_ORIG_MD5=486628ae7b5be7c80527968a0b85ae38  # stock blmjciaapa.so v74
AAPA_PATCHED_MD5=a9c44143c0e89d66464269446a7726e0  # 1 byte: 0x653b4 0x01->0x02 (mov r2,#2)
MAXFAIL=3                                       # overschrijfbaar in $AA/aa.conf (1..10)
PROVEN_N=5              # aa.conf (0 = proven mode uit, anders 3..20): gezonde boots per combinatie
PROVEN_MAXSHORT=20      # aa.conf (5..30; review4 M1): zoveel proven-boots op rij zonder guard-oordeel -> proven ingetrokken
STICK_BASE_IFACES=8     # boot-stick-probe standaard UIT (review2 N1: race met nav-SD-mount); alleen na meting in fase 0 via aa.conf verlagen
STICK_WAIT=4            # s wachten op partities als er een extra massaopslag is; aa.conf (0..6)
AAPA_BUDGET=7           # s sinds start: daarna wordt aan het aapa-doel niet meer begonnen (review3 M1)
AAPA_MOUNT_BUDGET=11    # s sinds start: vlak vóór de aapa-mount nogmaals getoetst; erover = aapa overslaan (14 s-watchdog)
MAXUP=120               # s uptime: later gestart = niet vanuit de boot-hook -> niets doen (review3 m7)
KILLNAME=AA_BUSPATCH_DISABLE
MOUNTS=/proc/mounts
UPTIME=/proc/uptime
SYSUSB=/sys/bus/usb/drivers/usb-storage
PARTS=/proc/partitions
DEVDIR=/dev
LOG=$AA/early.log

# Harde zelf-watchdog: dit script mag usb_drivers.sh nooit langer dan ~14 s ophouden.
# (De hook in usb_drivers.sh wacht zelf ook maximaal ~15 s, ook als dit script in I/O hangt.)
( sleep 14; kill -9 $$ 2>/dev/null ) </dev/null >/dev/null 2>&1 &
WD=$!

up() { read u _ < "$UPTIME"; echo "${u%%.*}"; }
log() { { echo "[$(up)s] $*" >> "$LOG"; } 2>/dev/null; }
finish() { kill "$WD" 2>/dev/null; exit 0; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
T0=$(up)
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

# log klein houden
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 32768 ] && { tail -n 100 "$LOG" > "$LOG.tmp"; } 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
log "---- boot ---- aa-early v3 start (kit 3.1)"
# review3 m7: nooit met de hand op een lopend systeem (zou over een geladen .so mounten, de teller
# ophogen en een tweede guard starten). De hook draait rond 10 s uptime.
if [ "$T0" -gt "$MAXUP" ]; then log "uptime ${T0}s > ${MAXUP}s: niet vanuit de boot-hook gestart -> niets doen"; finish; fi

if [ -e "$AA/DISABLE" ]; then log "DISABLE aanwezig -> stock usbmgr + stock aapa"; finish; fi
if [ -e "$AA/disabled" ]; then log "marker 'disabled' (crash-guard) -> stock usbmgr + stock aapa"; finish; fi

# Optionele config (alleen bekende numerieke sleutels; alles anders genegeerd, nooit gesourced).
if [ -f "$AA/aa.conf" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do      # ook laatste regel zonder newline (m-N13)
        isnum "$v" || continue
        case "$k" in
            MAXFAIL)           [ "$v" -ge 1 ] && [ "$v" -le 10 ] && MAXFAIL=$v ;;
            STICK_BASE_IFACES) [ "$v" -le 8 ] && STICK_BASE_IFACES=$v ;;
            STICK_WAIT)        [ "$v" -le 6 ] && STICK_WAIT=$v ;;
            PROVEN_N)          v=$(nz "$v"); { [ "$v" -eq 0 ] || { [ "$v" -ge 3 ] && [ "$v" -le 20 ]; }; } && PROVEN_N=$v ;;
            PROVEN_MAXSHORT)   v=$(nz "$v"); [ "$v" -ge 5 ] && [ "$v" -le 30 ] && PROVEN_MAXSHORT=$v ;;
        esac
        k=
    done < "$AA/aa.conf"
fi

# Teller lezen. Ontbrekend/leeg/geen getal = fail-safe -> stock (review B1). aa-install maakt hem altijd aan.
if [ ! -f "$AA/bootcount" ]; then log "bootcount ontbreekt -> stock (herstel: aa-status.sh rearm)"; finish; fi
n=$(head -n 1 "$AA/bootcount" 2>/dev/null)
if ! isnum "$n" || [ "${#n}" -gt 3 ]; then log "bootcount onleesbaar/ongeldig ('$n') -> stock"; finish; fi
while :; do case "$n" in 0?*) n=${n#0} ;; *) break ;; esac; done   # voorloopnullen weg ('08' is geen octaal; m-N12)
if [ "$n" -ge "$MAXFAIL" ]; then
    { echo "bootcount=$n at uptime $(up)s" > "$AA/disabled"; } 2>/dev/null; sync
    log "bootcount=$n >= $MAXFAIL -> 'disabled' gezet, stock usbmgr + stock aapa"
    finish
fi

# --- Per doel: stock-controle (geen schrijfacties). check_stock <naam> <target> <payload> <stock-md5>
check_stock() {
    if grep -q " $2 " "$MOUNTS" 2>/dev/null; then log "[$1] TARGET is al een mountpoint -> niets doen"; return 1; fi
    if [ ! -f "$2" ] || [ ! -f "$3" ]; then log "[$1] bestand ontbreekt -> skip"; return 1; fi
    m=$(md5 "$2")
    if [ "$m" != "$4" ]; then log "[$1] stock md5 $m != $4 (firmware gewijzigd?) -> skip"; return 1; fi
    return 0
}
DO_U=0; WANT_A=0
check_stock usbmgr "$TARGET" "$PATCHED" "$ORIG_MD5" && DO_U=1
if [ -e "$AA/DISABLE_AAPA" ]; then
    log "[aapa] DISABLE_AAPA aanwezig -> stock aapa (arm: aa-status.sh arm-aapa)"
else
    WANT_A=1    # stock-md5 van aapa pas NA de usbmgr-mount (M1)
fi
if [ $DO_U -eq 0 ] && [ $WANT_A -eq 0 ]; then log "geen doel te patchen -> klaar"; finish; fi

# --- USB-stick kill-switch, ZONDER iets te schrijven (review B1: effect mag niet van een
# schrijfbare /data_persist afhangen). Alleen als er meer usb-storage-interfaces zijn dan de
# interne lezer: dan max STICK_WAIT s op partities wachten en elk (ongemount) ro proberen.
stick_found=
cnt=0
for i in "$SYSUSB"/*:*; do [ -e "$i" ] && cnt=$((cnt + 1)); done
if [ "$cnt" -gt "$STICK_BASE_IFACES" ]; then
    log "usb-storage interfaces: $cnt (> $STICK_BASE_IFACES) -> stick-probe (max ${STICK_WAIT}s)"
    w=0
    while [ "$w" -lt "$STICK_WAIT" ]; do
        np=$(awk '$4 ~ /^sd[a-z]+[0-9]*$/ {c++} END {print c+0}' "$PARTS" 2>/dev/null)
        [ "$np" -ge "$cnt" ] && break
        sleep 1; w=$((w + 1))
    done
    mkdir -p "$TMPAA/kill" 2>/dev/null
    for p in $(awk '$4 ~ /^sd[a-z]+[0-9]*$/ {print $4}' "$PARTS" 2>/dev/null); do
        dev=$DEVDIR/$p
        grep -q "^$dev " "$MOUNTS" 2>/dev/null && continue
        [ -b "$dev" ] || continue
        if mount -o ro "$dev" "$TMPAA/kill" 2>/dev/null; then
            [ -e "$TMPAA/kill/$KILLNAME" ] && stick_found=$dev
            umount "$TMPAA/kill" 2>/dev/null
        fi
        [ -n "$stick_found" ] && break
    done
fi
if [ -n "$stick_found" ]; then
    log "kill-switch-stick $stick_found aanwezig -> stock (DISABLE best-effort)"
    { echo "kill-switch-stick bij boot ($stick_found)" > "$AA/DISABLE"; } 2>/dev/null; sync
    finish
fi

# --- Proven mode bepalen (alleen lezen). Geldt voor de GEPLANDE set (usbmgr als stock klopt,
# aapa als niet DISABLE_AAPA); wordt de werkelijke set anders, dan wordt na de mounts toch geteld.
PLAN_FP=$(fp_of $DO_U $WANT_A)
proven=0; pbump=0; PS0=0; PFP=
if [ "$PROVEN_N" -eq 0 ]; then
    :
elif read_proven; then
    pc=$(get_cnt "$PLAN_FP")
    if [ "$pc" -lt "$PROVEN_N" ]; then
        if [ "$pc" -eq 0 ] && [ -n "$P_RECS" ]; then log "proven: geen record voor deze combinatie (doelen/firmware/payload anders) -> normaal tellen"
        else log "proven: $pc/$PROVEN_N gezonde boots voor deze combinatie -> normaal tellen"; fi
    elif [ "$P_SHORT" -ge "$PROVEN_MAXSHORT" ]; then
        revoke_proven; log "proven: $P_SHORT boots op rij zonder guard-oordeel (>= $PROVEN_MAXSHORT) -> proven ingetrokken, normaal tellen"
    else
        proven=1; PS0=$P_SHORT; PFP=$PLAN_FP
        log "proven: $pc/$PROVEN_N gezonde boots voor deze combinatie (boots op rij zonder oordeel: $PS0/$PROVEN_MAXSHORT)"
    fi
elif [ -e "$PF" ]; then
    log "proven-bestand ongeldig/onleesbaar -> niet proven, normaal tellen"
fi

# --- Payload naar tmpfs kopiëren en daar verifiëren (review M2: bind-mount houdt dan niet
# /data_persist vast). usbmgr 1,7 MB + aapa 1,5 MB RAM.  to_tmp <naam> <payload> <bestandsnaam> <patch-md5>
to_tmp() {
    dst=$TMPAA/$3
    rm -f "$dst" 2>/dev/null
    if ! { mkdir -p "$TMPAA" && cp "$2" "$dst"; } 2>/dev/null; then
        log "[$1] kopie naar $TMPAA mislukt -> stock"; return 1
    fi
    m=$(md5 "$dst")
    if [ "$m" != "$4" ]; then
        rm -f "$dst"; log "[$1] md5 kopie in $TMPAA $m != $4 -> stock"; return 1
    fi
    return 0
}

# --- Gedeelde teller VOOR de eerste mount ophogen en TERUGLEZEN (review B1), één keer per boot.
# Lukt dat niet: niet mounten (en ook geen tweede doel).
old=$n
bumped=0
bump() {
    [ $bumped -eq 1 ] && return 0
    if [ $proven -eq 1 ]; then
        # proven: teller blijft, maar de schrijfproef (B1) gebeurt via het proven-record
        if ! write_proven $((PS0 + 1)) "$PFP" "$(get_cnt "$PFP")"; then
            log "proven-record niet aantoonbaar geschreven -> GEEN mount, stock"; finish
        fi
        bumped=1; pbump=1
        log "proven mode: bootcount niet opgehoogd (blijft $old; boots op rij zonder oordeel $((PS0 + 1))/$PROVEN_MAXSHORT)"
        return 0
    fi
    n=$((old + 1))
    if ! { echo "$n" > "$AA/bootcount.tmp" && mv "$AA/bootcount.tmp" "$AA/bootcount" && sync \
           && [ "$(head -n 1 "$AA/bootcount" 2>/dev/null)" = "$n" ]; } 2>/dev/null; then
        log "bootcount niet aantoonbaar geschreven -> GEEN mount, stock"; finish
    fi
    bumped=1
    log "bootcount $old -> $n (max $MAXFAIL)"
}
restore_count() {   # review m3: als er uiteindelijk NIETS gemount is, de teller terugzetten
    [ $bumped -eq 1 ] || return 0
    if [ $pbump -eq 1 ]; then write_proven "$PS0" "$PFP" "$(get_cnt "$PFP")"; return 0; fi
    { echo "$old" > "$AA/bootcount.tmp"; } 2>/dev/null && mv "$AA/bootcount.tmp" "$AA/bootcount" 2>/dev/null; sync
}

# mount_one <naam> <bron> <target> <patch-md5>
#   return 0 = gemount + geverifieerd; 1 = niet gemount (schoon); 2 = verificatie faalde EN umount
#   mislukt (blijft gemount -> telt als actief, zodat de crash-guard blijft tellen; review2 N2).
#   rc 2 zet forced=1: deze boot wordt dan ALTIJD strikt geteld, ook in proven mode (review4 M2).
mount_one() {
    if ! mount -o bind "$2" "$3" 2>>"$LOG"; then log "[$1] bind-mount mislukt -> stock"; return 1; fi
    m=$(md5 "$3")
    opts=$(grep " $3 " "$MOUNTS" | tail -n 1)
    case "$opts" in *noexec*) bad=noexec ;; *) bad= ;; esac
    if [ "$m" != "$4" ] || [ -n "$bad" ]; then
        umount "$3" 2>>"$LOG"
        if grep -q " $3 " "$MOUNTS" 2>/dev/null; then
            log "[$1] verificatie na mount faalde (md5=$m $bad) EN umount mislukt -> blijft actief geteld"; return 2
        fi
        log "[$1] verificatie na mount faalde (md5=$m $bad) -> umount, stock"; return 1
    fi
    log "[$1] bind-mount OK vanaf $2 ($opts)"
    return 0
}
active=0; act_u=0; act_a=0; forced=0

# --- 1) usbmgr helemaal afmaken (review3 M1): kopie -> teller -> mount -> verificatie
if [ $DO_U -eq 1 ] && to_tmp usbmgr "$PATCHED" svcjciusbmgr.so "$PATCHED_MD5"; then
    bump
    mount_one usbmgr "$TMPAA/svcjciusbmgr.so" "$TARGET" "$PATCHED_MD5"
    rc=$?; [ $rc -ne 1 ] && { active=$((active + 1)); act_u=1; }; [ $rc -eq 2 ] && forced=1
fi

# --- 2) aapa, alleen binnen de tijdsgrens (twee toetsen: vóór het begin en vlak vóór de mount)
if [ $WANT_A -eq 1 ]; then
    el=$(( $(up) - T0 ))
    if [ "$el" -ge "$AAPA_BUDGET" ]; then
        log "[aapa] al ${el}s bezig (>= ${AAPA_BUDGET}s) -> aapa overgeslagen (tijdsgrens hook)"
    elif check_stock aapa "$TARGET_AAPA" "$PATCHED_AAPA" "$AAPA_ORIG_MD5" \
         && to_tmp aapa "$PATCHED_AAPA" blmjciaapa.so "$AAPA_PATCHED_MD5"; then
        el=$(( $(up) - T0 ))
        if [ "$el" -ge "$AAPA_MOUNT_BUDGET" ]; then
            rm -f "$TMPAA/blmjciaapa.so" 2>/dev/null
            log "[aapa] vlak voor mount al ${el}s bezig (>= ${AAPA_MOUNT_BUDGET}s) -> aapa overgeslagen (tijdsgrens hook)"
        else
            bump
            mount_one aapa "$TMPAA/blmjciaapa.so" "$TARGET_AAPA" "$AAPA_PATCHED_MD5"
            rc=$?; [ $rc -ne 1 ] && { active=$((active + 1)); act_a=1; }; [ $rc -eq 2 ] && forced=1
        fi
    fi
fi

if [ $active -eq 0 ]; then
    restore_count
    if [ $bumped -eq 1 ]; then log "niets actief -> stock (bootcount terug naar $old)"; else log "geen doel over -> stock"; fi
    finish
fi

# Proven, maar de werkelijk actieve set wijkt af van de proven-combinatie (bv. aapa overgeslagen door
# tijdsgrens/stock-md5/mountfout), of een mount faalde bij verificatie en is niet te unmounten
# (forced, review4 M2): deze boot toch gewoon (strikt) tellen.
# Volgorde (review4 L1): EERST de bootcount schrijven + teruglezen, pas daarna 'short' terugzetten.
# Lukt de bootcount niet, dan blijft short op PS0+1 staan (de boot telt dan in elk geval voor MAXSHORT).
if [ $pbump -eq 1 ]; then
    ACT_FP=$(fp_of $act_u $act_a)
    if [ "$ACT_FP" != "$PFP" ] || [ $forced -eq 1 ]; then
        if [ $forced -eq 1 ]; then why="mount niet geverifieerd en niet te unmounten"
        else why="actieve set (usbmgr=$act_u aapa=$act_a) wijkt af van proven-combinatie"; fi
        n=$((old + 1))
        if { echo "$n" > "$AA/bootcount.tmp" && mv "$AA/bootcount.tmp" "$AA/bootcount" && sync \
             && [ "$(head -n 1 "$AA/bootcount" 2>/dev/null)" = "$n" ]; } 2>/dev/null; then
            log "proven: $why -> toch geteld: bootcount $old -> $n"
            write_proven "$PS0" "$PFP" "$(get_cnt "$PFP")" \
                || log "proven: short niet teruggezet (blijft $((PS0 + 1))) -> telt ook voor MAXSHORT"
        else
            log "proven: $why, maar bootcount niet aantoonbaar geschreven (LET OP) -> short blijft $((PS0 + 1))"
        fi
        proven=0
    fi
fi

# Guard: reset teller alleen als usbmgr (en aapa, indien gemount) gezond is + USB-stick kill-switch.
if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh "$AA/aa-guard.sh" </dev/null >/dev/null 2>&1 &
else
    /bin/sh "$AA/aa-guard.sh" </dev/null >/dev/null 2>&1 &
fi
log "guard gestart ($active doel(en) actief: usbmgr=$act_u aapa=$act_a, proven=$proven, $(( $(up) - T0 ))s)"
finish
