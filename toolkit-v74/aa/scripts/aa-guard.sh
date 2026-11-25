#!/bin/sh
# aa-guard.sh — MZD AA bus-patch (v74), achtergrond-guard. Versie 3 (2 doelen, review 3). Gestart
# door aa-early.sh (alleen als minstens één doel gemount is). Eén gedeelde teller voor beide doelen.
# 1) Teller -> 0 ALLEEN als usbmgr gezond is (review B2):
#      - proces L_jciUSBMGR leeft en is geen zombie (comm + toestand in /proc/<pid>/stat), EN
#      - de bootketen is voorbij usbmgr gekomen: /var/run/start_network_ready is deze boot
#        gezien (gelatcht; sm verwijdert die vlag zodra start_network.sh stopt!) OF sshd draait
#        (wordt alleen door start_network.sh gestart, dat via stage_usb op jciUSBMGR wacht).
#    Beoordeling vanaf GRACE s.
#    ALS /jci/aapa/blmjciaapa.so gemount is (aapa-doel actief), dan tweetraps (review3 H1):
#      - beoordeling pas vanaf D = max(GRACE, AAPA_GRACE) (standaard 420 s: ná het laatste moment
#        waarop sm een bij de start hangende aapa nog reset);
#      - op het eerste gezonde moment T1 >= D het pid van L_jciAAPA onthouden;
#      - teller pas wissen op T1 + RECHECK als HETZELFDE pid dan nog leeft en geen zombie is
#        (zombie = dood, review3 m1). Ander/geen pid tussendoor = aapa gefaald.
#    Niet gezond tot D+RECHECK s (of aapa gefaald na T1):
#      - usbmgr + net gezond, alleen aapa dood (review3 m6) -> DISABLE_AAPA (teruggelezen);
#        volgende boot alleen usbmgr. Teller blijft staan (blijft beschermen). Lukt DISABLE_AAPA
#        niet -> 'disabled'.
#      - anders -> 'disabled' (volgende boot BEIDE doelen stock). Teller blijft staan.
# 1b) Proven mode (kit 3.1): bij elk volledig gezond oordeel (alle gemounte doelen gezond, teller
#    net op 0 gezet) wordt het record van de gemounte doelcombinatie +1 gedaan (fingerprint uit
#    /proc/mounts + md5 via pad = patch; anders niet geteld) en 'short' op 0, atomisch +
#    teruggelezen. Bij elk 'niet gezond' (ook in proven mode) wordt het proven-record ingetrokken
#    (verwijderd), daarna DISABLE_AAPA/'disabled' zoals hieronder: terug naar strikt tellen.
# 2) Kill-switch zonder SSH: bestand AA_BUSPATCH_DISABLE in de root van een USB-stick
#    -> DISABLE wordt gezet (teruggelezen); volgende boot draait stock usbmgr. Lukt schrijven
#    niet, dan beschermt de teller-verificatie in aa-early.sh (niet-schrijfbaar = geen mount).

AA=/data_persist/dev/aa
TARGET=/jci/usbmgr/svcjciusbmgr.so
ORIG_MD5=413a2569b6528d11a00eb8773a60de80
PATCHED_MD5=b6aeec1653a26e36e4e1907832c7cbf3
AAPA_ORIG_MD5=486628ae7b5be7c80527968a0b85ae38
AAPA_PATCHED_MD5=a9c44143c0e89d66464269446a7726e0
PROVEN_N=5              # aa.conf; alleen voor de logregel (de drempel geldt in aa-early.sh)
GRACE=180               # aa.conf (60..1800)
AAPA_GRACE=420          # aa.conf (60..1800): beoordelingsmoment als aapa gemount is (review3 H1)
RECHECK=60              # s: herkansing voor 'niet gezond' én bevestigingstermijn aapa-pid
FAST=1                  # pollinterval tot D (start_network_ready-vlag leeft kort)
POLL=10                 # pollinterval daarna
MAXITER=900             # veiligheidsgrens loop (~D x1 s + rest x10 s = ruim 2 uur), daarna stopt de guard
USBMGR=L_jciUSBMGR
AAPAPROC=L_jciAAPA
TARGET_AAPA=/jci/aapa/blmjciaapa.so
MOUNTS=/proc/mounts
UPTIME=/proc/uptime
PROC=/proc
RUN=/var/run
LOG=$AA/guard.log
KILLNAME=AA_BUSPATCH_DISABLE
STICKDIRS="/tmp/mnt /mnt /tmp/media"

up() { read u _ < "$UPTIME"; echo "${u%%.*}"; }
log() { { echo "[$(up)s] $*" >> "$LOG"; } 2>/dev/null; }
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

if [ -f "$AA/aa.conf" ]; then
    # '|| [ -n "$k" ]': ook een laatste regel zonder newline lezen (review2 m-N13)
    while IFS='=' read -r k v || [ -n "$k" ]; do
        isnum "$v" || continue
        case "$k" in
            GRACE)      [ "$v" -ge 60 ] && [ "$v" -le 1800 ] && GRACE=$v ;;
            AAPA_GRACE) [ "$v" -ge 60 ] && [ "$v" -le 1800 ] && AAPA_GRACE=$v ;;
            PROVEN_N)   v=$(nz "$v"); { [ "$v" -eq 0 ] || { [ "$v" -ge 3 ] && [ "$v" -le 20 ]; }; } && PROVEN_N=$v ;;
        esac
        k=
    done < "$AA/aa.conf"
fi

[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 32768 ] && { tail -n 100 "$LOG" > "$LOG.tmp"; } 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
log "guard v3 start (kit 3.1, grace ${GRACE}s, aapa-grace ${AAPA_GRACE}s, recheck ${RECHECK}s)"
aapa_mounted() { grep -q " $TARGET_AAPA " "$MOUNTS" 2>/dev/null; }

# find_pid <comm>: eerste pid met deze comm die GEEN zombie is (review3 m1). Leeg = geen.
find_pid() {
    for s in "$PROC"/[0-9]*/stat; do
        read -r line < "$s" 2>/dev/null || continue
        case "$line" in
            *"($1) Z "*) continue ;;
            *"($1) "*) echo "${line%% *}"; return 0 ;;
        esac
    done
    return 1
}
proc_alive() { find_pid "$1" >/dev/null; }
# pid_ok <pid> <comm>: dit pid bestaat nog, heeft deze comm en is geen zombie
pid_ok() {
    [ -n "$1" ] || return 1
    read -r line < "$PROC/$1/stat" 2>/dev/null || return 1
    case "$line" in
        *"($2) Z "*) return 1 ;;
        *"($2) "*) return 0 ;;
    esac
    return 1
}

check_stick() {
    for d in $STICKDIRS; do
        for f in "$d"/*/$KILLNAME; do
            [ -e "$f" ] || continue
            { echo "kill-switch via $f at uptime $(up)s" > "$AA/DISABLE"; } 2>/dev/null; sync
            if [ -s "$AA/DISABLE" ]; then
                log "kill-switch gevonden: $f -> DISABLE gezet (actief na volgende boot)"
            else
                # schrijven faalt: teller vergiftigen (lukt meestal ook niet); aa-early.sh mount
                # dan niet omdat de teller niet schrijfbaar/geldig is (B1).
                { echo x > "$AA/bootcount"; } 2>/dev/null; sync
                log "kill-switch $f: DISABLE NIET schrijfbaar -> vertrouw op teller-verificatie"
            fi
            return 0
        done
    done
    return 1
}

# prove_ok: na een volledig gezond oordeel het record van de gemounte combinatie +1 (short=0).
prove_ok() {
    fu=0; fa=0
    if grep -q " $TARGET " "$MOUNTS" 2>/dev/null; then
        [ "$(md5 "$TARGET")" = "$PATCHED_MD5" ] || { log "proven: usbmgr gemount maar md5 via pad is niet de patch -> niet geteld"; return 1; }
        fu=1
    fi
    if aapa_mounted; then
        [ "$(md5 "$TARGET_AAPA")" = "$AAPA_PATCHED_MD5" ] || { log "proven: aapa gemount maar md5 via pad is niet de patch -> niet geteld"; return 1; }
        fa=1
    fi
    fp=$(fp_of $fu $fa)
    [ -n "$fp" ] || { log "proven: geen doel gemount -> niet geteld"; return 1; }
    read_proven || { [ -e "$PF" ] && log "proven: bestand ongeldig -> opnieuw begonnen"; }
    # eigen variabele pc_new: write_proven/read_proven overschrijven de globale c/f (review4 L3)
    pc_new=$(( $(get_cnt "$fp") + 1 )); [ $pc_new -gt 9999 ] && pc_new=9999
    if write_proven 0 "$fp" "$pc_new"; then
        log "proven: gezonde boot $pc_new (drempel $PROVEN_N) voor usbmgr=$fu aapa=$fa$( [ $pc_new -ge "$PROVEN_N" ] && [ "$PROVEN_N" -gt 0 ] && echo ' -> PROVEN')"
    else
        revoke_proven
        log "proven: record niet aantoonbaar geschreven -> verwijderd (niet proven)"
    fi
}

# fail <u> <n> <statustekst>: niet gezond. Alleen aapa schuldig (usbmgr+net gezond, aapa gemount)
# -> DISABLE_AAPA; anders (of als DISABLE_AAPA niet lukt) -> 'disabled'. Teller blijft staan.
fail() {
    if [ -e "$PF" ] || [ -e "$PF.tmp" ]; then
        if revoke_proven; then log "NIET gezond: proven-record ingetrokken (terug naar strikt tellen)"
        else log "NIET gezond: proven-record kon NIET verwijderd worden"; fi
    fi
    if [ "$1" -eq 1 ] && [ "$2" -eq 1 ] && [ $am -eq 1 ]; then
        { echo "guard: aapa niet gezond at uptime ${t}s ($3)" > "$AA/DISABLE_AAPA"; } 2>/dev/null; sync
        if [ -f "$AA/DISABLE_AAPA" ] && [ -s "$AA/DISABLE_AAPA" ]; then
            log "NIET gezond na ${t}s ($3): alleen aapa schuldig -> DISABLE_AAPA gezet, volgende boot alleen usbmgr (teller blijft $(head -n 1 "$AA/bootcount" 2>/dev/null))"
            return 0
        fi
        log "DISABLE_AAPA niet schrijfbaar -> val terug op 'disabled'"
    fi
    { echo "niet gezond at uptime ${t}s ($3)" > "$AA/disabled"; } 2>/dev/null; sync
    log "NIET gezond na ${t}s ($3) -> 'disabled' gezet, volgende boot beide doelen stock"
}

net_seen=0
stick_done=0
reset_done=0
unhealthy_logged=0
pend=0; AP=; T1=0       # tweetraps aapa-beoordeling (H1)
i=0
while [ $i -lt $MAXITER ]; do
    i=$((i + 1))
    t=$(up)
    [ $net_seen -eq 0 ] && [ -e "$RUN/start_network_ready" ] && { net_seen=1; log "start_network_ready gezien"; }
    # deadline: GRACE, of later als het aapa-doel gemount is en AAPA_GRACE groter is
    am=0; D=$GRACE
    if aapa_mounted; then am=1; [ "$AAPA_GRACE" -gt "$D" ] && D=$AAPA_GRACE; fi
    if [ $reset_done -eq 0 ] && [ "$t" -ge "$D" ]; then
        u=0; n=0; a=-; ap=
        proc_alive "$USBMGR" && u=1
        { [ $net_seen -eq 1 ] || proc_alive sshd; } && n=1
        if [ $am -eq 1 ]; then
            a=0
            if [ $pend -eq 1 ]; then
                pid_ok "$AP" "$AAPAPROC" && { a=1; ap=$AP; }
            else
                ap=$(find_pid "$AAPAPROC") && a=1
            fi
        fi
        st="usbmgr=$u net=$n aapa=$a${ap:+ pid=$ap}"
        if [ $u -eq 1 ] && [ $n -eq 1 ] && [ "$a" != 0 ]; then
            if [ $am -eq 1 ] && [ $pend -eq 0 ]; then
                pend=1; AP=$ap; T1=$t
                log "aapa leeft op ${t}s (pid $AP) -> bevestiging op $((T1 + RECHECK))s (zelfde pid, geen zombie)"
            elif [ $am -eq 1 ] && [ "$t" -lt $((T1 + RECHECK)) ]; then
                :   # wachten op bevestiging
            else
                { echo 0 > "$AA/bootcount.tmp"; } 2>/dev/null && mv "$AA/bootcount.tmp" "$AA/bootcount" 2>/dev/null
                sync
                log "gezond op ${t}s ($st) -> bootcount=$(head -n 1 "$AA/bootcount" 2>/dev/null)"
                reset_done=1
                if [ "$(head -n 1 "$AA/bootcount" 2>/dev/null)" = 0 ]; then prove_ok
                else log "proven: bootcount niet op 0 -> niet geteld"; fi
            fi
        elif [ $pend -eq 1 ]; then
            # was gezond gezien; nu niet meer (aapa-pid weg/zombie/gewisseld, of usbmgr/net weg)
            fail $u $n "$st, aapa-pid $AP gezien op ${T1}s"
            reset_done=1
        elif [ "$t" -ge $((D + RECHECK)) ]; then
            fail $u $n "$st"
            reset_done=1
        elif [ $unhealthy_logged -eq 0 ]; then
            log "nog niet gezond op ${t}s ($st), herkansing tot $((D + RECHECK))s"
            unhealthy_logged=1
        fi
    fi
    if [ $stick_done -eq 0 ] && [ ! -e "$AA/DISABLE" ]; then check_stick && stick_done=1; fi
    if [ "$t" -lt "$D" ]; then sleep $FAST; else sleep $POLL; fi
done
log "guard einde"
