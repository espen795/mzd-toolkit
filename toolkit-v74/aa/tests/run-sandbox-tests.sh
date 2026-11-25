#!/bin/sh
# Lokale sandbox-test (host, NIET de CMU). Versie 3 (2 doelen: usbmgr + aapa), kit 3.1 (proven mode, sectie 12).
# Gebruik:  SUT="busybox sh" sh tests/run-sandbox-tests.sh [stock.so] [stock usb_drivers.sh]
#           SUT=dash          sh tests/run-sandbox-tests.sh
# - Scripts worden naar $T gekopieerd; alleen de pad-/timingvariabelen bovenaan (AA=, TARGET=,
#   MOUNTS=, UPTIME=, PROC=, RUN=, SYSUSB=, PARTS=, DEVDIR=, TMPAA=, DROPC=, STICKDIRS=, FAST=,
#   POLL=, MAXITER=, UD=) worden herschreven. De hookregel in aa-install.sh blijft ONGEWIJZIGD,
#   zodat de md5-controle van usb_drivers.sh echt getest wordt.
# - Gemockt via PATH: mount, umount, mv, cp (met foutinjectie-vlaggen in $T/flags/), df
#   (flags/df_out = volledige uitvoer) en sleep: `sleep 0` (FAST/POLL in de guard) zet de uptime
#   op de volgende regel van flags/tick en draait eenmalig flags/onsleep; elke andere sleep is echt.
# - In aa-early.sh wordt `[ -b "$dev" ]` vervangen door `[ -e "$dev" ]` (geen blockdevices zonder root).
# - Zonder stock.so-argument: stock wordt uit de payload gereconstrueerd (byte 0xbca27 terug naar
#   0x0a) en MOET md5 413a2569... hebben — dat is dan de echte stock-inhoud, geen nep-bestand.
#   Idem blmjciaapa.so: byte 0x653b4 terug naar 0x01 -> MOET md5 486628ae... hebben.
# - Mount-mock per doel: flags/fail_bind (alle) of flags/fail_bind.<basename>, idem bindopts en
#   fail_umount. flags/cp_setuptime: zet uptime op die waarde zodra de usbmgr-kopie naar /tmp gaat.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SUT=${SUT:-busybox sh}
T=$(mktemp -d /tmp/aabp-test.XXXXXX)
P=b6aeec1653a26e36e4e1907832c7cbf3; O=413a2569b6528d11a00eb8773a60de80
PA=a9c44143c0e89d66464269446a7726e0; OA=486628ae7b5be7c80527968a0b85ae38
UDS=a52bb42330acedf809da1f02ab76b07d; UDP=cb2b34823582b55740c8134360c183c1
REAL_MV=$(command -v mv); REAL_CP=$(command -v cp); REAL_SLEEP=$(command -v sleep)
pass=0; fail=0
ok() { echo "PASS: $*"; pass=$((pass+1)); }
ko() { echo "FAIL: $*"; fail=$((fail+1)); }
chk() { d=$1; shift; if eval "$*"; then ok "$d"; else ko "$d"; fi; }   # expressie als 1 string

if [ $# -ge 1 ]; then STOCK_SO=$1; else
    STOCK_SO=$T/stock.so; cp "$HERE/payload/svcjciusbmgr.so.patched" "$STOCK_SO"
    printf '\012' | dd of="$STOCK_SO" bs=1 seek=$((0xbca27)) conv=notrunc 2>/dev/null
fi
STOCK_AAPA=$T/stock-aapa.so; cp "$HERE/payload/blmjciaapa.so.patched" "$STOCK_AAPA"
printf '\001' | dd of="$STOCK_AAPA" bs=1 seek=$((0x653b4)) conv=notrunc 2>/dev/null
[ "$(md5sum "$STOCK_AAPA" | cut -d' ' -f1)" = "$OA" ] || { echo "stock aapa md5 klopt niet"; exit 2; }
STOCK_UD=${2:-$HERE/../analysis/2026-11-23-v74-gui-dump/raw/jci/scripts/usb_drivers.sh}
[ "$(md5sum "$STOCK_SO" | cut -d' ' -f1)" = "$O" ] || { echo "stock .so md5 klopt niet"; exit 2; }
[ "$(md5sum "$STOCK_UD" | cut -d' ' -f1)" = "$UDS" ] || { echo "stock usb_drivers.sh md5 klopt niet"; exit 2; }
echo "== SUT: $SUT"

R=$T/root; A=$R/aa; SO=$R/jci/usbmgr/svcjciusbmgr.so; SOA=$R/jci/aapa/blmjciaapa.so; UD=$R/jci/scripts/usb_drivers.sh
mk() {  # verse sandbox; standaard: geïnstalleerd + usbmgr gewapend (bootcount 0, geen DISABLE), aapa UIT (DISABLE_AAPA)
    chmod -R u+w "$T/root" 2>/dev/null; rm -rf "$T/root" "$T/flags" "$T/bin" "$T/bindsrc" "$T"/keep.*
    mkdir -p "$A" "$R/jci/usbmgr" "$R/jci/aapa" "$R/jci/scripts" "$T/bin" "$T/flags" "$R/tmp" "$R/run" \
             "$R/proc" "$R/sys/usbstor" "$R/dev" "$R/stick" "$R/stickfs"
    cp "$STOCK_SO" "$SO"; cp "$HERE/payload/svcjciusbmgr.so.patched" "$A/"
    cp "$STOCK_AAPA" "$SOA"; cp "$HERE/payload/blmjciaapa.so.patched" "$A/"; echo "test" > "$A/DISABLE_AAPA"
    cp "$STOCK_UD" "$UD"; cp "$HERE/MANIFEST.md5" "$A/"
    echo 0 > "$A/bootcount"
    : > "$R/mounts"; : > "$T/mount.calls"; : > "$R/parts"; : > "$R/dropc"
    echo "12.50 3.00" > "$R/uptime"
    for s in aa-early.sh aa-guard.sh aa-install.sh aa-status.sh aa-uninstall.sh; do
        sed -e "s#^AA=.*#AA=$A#" -e "s#^TARGET=.*#TARGET=$SO#" -e "s#^TARGET_AAPA=.*#TARGET_AAPA=$SOA#" -e "s#^UD=.*#UD=$UD#" \
            -e "s#^MOUNTS=.*#MOUNTS=$R/mounts#" -e "s#^UPTIME=.*#UPTIME=$R/uptime#" \
            -e "s#^PROC=.*#PROC=$R/proc#" -e "s#^RUN=.*#RUN=$R/run#" \
            -e "s#^SYSUSB=.*#SYSUSB=$R/sys/usbstor#" -e "s#^PARTS=.*#PARTS=$R/parts#" \
            -e "s#^DEVDIR=.*#DEVDIR=$R/dev#" -e "s#^TMPAA=.*#TMPAA=$R/tmp/aa#" \
            -e "s#^DROPC=.*#DROPC=$R/dropc#" -e "s#^STICKDIRS=.*#STICKDIRS=$R/stick#" \
            -e "s#^FAST=.*#FAST=0#" -e "s#^POLL=.*#POLL=0#" -e "s#^MAXITER=.*#MAXITER=3#" \
            -e 's#\[ -b "\$dev" \]#[ -e "$dev" ]#' \
            "$HERE/scripts/$s" > "$A/$s"
    done
    "$REAL_MV" "$A/aa-guard.sh" "$A/aa-guard.real.sh"; printf 'AAPAPROC=L_jciAAPA\nexit 0\n' > "$A/aa-guard.sh"   # stub (v3-merkteken voor arm-aapa)
    # testkopieën wijken af van het manifest -> manifest voor de sandbox opnieuw maken
    ( cd "$A" && md5sum svcjciusbmgr.so.patched blmjciaapa.so.patched aa-early.sh aa-guard.sh aa-install.sh aa-status.sh aa-uninstall.sh > MANIFEST.md5 )
    mkdir -p "$T/kit"; rm -rf "$T/kit"/*
    for f in svcjciusbmgr.so.patched blmjciaapa.so.patched aa-early.sh aa-guard.sh aa-install.sh aa-status.sh aa-uninstall.sh MANIFEST.md5; do "$REAL_CP" "$A/$f" "$T/kit/"; done
    cat > "$T/bin/mount" <<EOF
#!/bin/sh
echo "mount \$*" >> "$T/mount.calls"
case "\$*" in
  *remount*) [ -e "$T/flags/fail_remount" ] && exit 1; exit 0 ;;
  "-o bind "*) b=\$(basename "\$4"); [ -e "$T/flags/fail_bind" -o -e "$T/flags/fail_bind.\$b" ] && exit 1
       "$REAL_CP" "\$4" "$T/keep.\$b"; "$REAL_CP" "\$3" "\$4"; echo "\$3" >> "$T/bindsrc"
       o=\$(cat "$T/flags/bindopts.\$b" 2>/dev/null || cat "$T/flags/bindopts" 2>/dev/null || echo rw,relatime)
       echo "/dev/root \$4 relfs \$o 0 0" >> "$R/mounts" ;;
  "-o ro "*) n=\$(basename "\$3"); [ -d "$R/stickfs/\$n" ] || exit 1; "$REAL_CP" -r "$R/stickfs/\$n/." "\$4/" ;;
esac
exit 0
EOF
    cat > "$T/bin/umount" <<EOF
#!/bin/sh
echo "umount \$*" >> "$T/mount.calls"
b=\$(basename "\$1")
if [ -f "$T/keep.\$b" ]; then
  [ -e "$T/flags/fail_umount" -o -e "$T/flags/fail_umount.\$b" ] && exit 1
  "$REAL_CP" "$T/keep.\$b" "\$1"; rm -f "$T/keep.\$b"; grep -v " \$1 " "$R/mounts" > "$R/mounts.n"; "$REAL_CP" "$R/mounts.n" "$R/mounts"
else rm -rf "\$1"/* "\$1"/.[!.]* 2>/dev/null; fi
EOF
    # mv/cp met foutinjectie: flags/<soort> bevat een substring van het doelpad
    for c in mv cp; do
        if [ $c = mv ]; then real=$REAL_MV; else real=$REAL_CP; fi
        cat > "$T/bin/$c" <<EOF
#!/bin/sh
for last in "\$@"; do :; done
m() { [ -s "$T/flags/\$1" ] && case "\$last" in *"\$(cat "$T/flags/\$1")"*) return 0;; esac; return 1; }
m ${c}_fail && exit 1
m ${c}_noop && exit 0
"$real" "\$@"; rc=\$?
if m ${c}_corrupt; then echo "#corrupt" >> "\$last"; rm -f "$T/flags/${c}_corrupt"; fi
if [ ${c} = cp ] && [ -s "$T/flags/cp_setuptime" ]; then case "\$last" in *tmp/aa/svcjciusbmgr.so) "$real" "$T/flags/cp_setuptime" "$R/uptime";; esac; fi
if [ ${c} = cp ] && [ -s "$T/flags/cp_setuptime_aapa" ]; then case "\$last" in *tmp/aa/blmjciaapa.so) "$real" "$T/flags/cp_setuptime_aapa" "$R/uptime";; esac; fi
exit \$rc
EOF
    done
    cat > "$T/bin/sleep" <<EOS
#!/bin/sh
if [ "\$1" = 0 ]; then
  if [ -s "$T/flags/tick" ]; then head -n 1 "$T/flags/tick" > "$R/uptime"; sed -i 1d "$T/flags/tick"; fi
  if [ -f "$T/flags/onsleep" ]; then sh "$T/flags/onsleep"; rm -f "$T/flags/onsleep"; fi
  exit 0
fi
exec "$REAL_SLEEP" "\$@"
EOS
    cat > "$T/bin/df" <<EOS
#!/bin/sh
if [ -f "$T/flags/df_out" ]; then cat "$T/flags/df_out"; exit 0; fi
printf 'Filesystem           1K-blocks      Used Available Use%% Mounted on\n/dev/mmcblk0p5          123456      1000     50000   1%% /tmp/mnt/data_persist\n'
EOS
    chmod +x "$T/bin/"*
}
run() { s=$1; shift; PATH="$T/bin:$PATH" $SUT "$A/$s" "$@"; }
early() { run aa-early.sh; }
guard() { PATH="$T/bin:$PATH" $SUT "$A/aa-guard.real.sh"; }
sod() { md5sum "$SO" | cut -d' ' -f1; }
soa() { md5sum "$SOA" | cut -d' ' -f1; }
cnt() { head -n 1 "$A/bootcount" 2>/dev/null; }
reboot() { echo "12.50 3.00" > "$R/uptime"; : > "$R/mounts"; "$REAL_CP" "$STOCK_SO" "$SO"; "$REAL_CP" "$STOCK_AAPA" "$SOA"; rm -rf "$R/tmp/aa" "$T"/keep.*; }
lg() { grep -q "$1" "$A/early.log"; }
calls() { grep -q -- "$1" "$T/mount.calls"; }
setproc() { rm -rf "$R/proc"/*; i=100; for c in "$@"; do i=$((i+1)); mkdir -p "$R/proc/$i"; echo "$i ($c) S 1 1" > "$R/proc/$i/stat"; done; }
glg() { grep -q "$1" "$A/guard.log"; }
amount() { echo "/dev/root $SOA relfs rw 0 0" > "$R/mounts"; rm -f "$A/DISABLE_AAPA"; }   # aapa-doel gemount (dus gewapend)
tick() { : > "$T/flags/tick"; for x in "$@"; do echo "$x.0 1" >> "$T/flags/tick"; done; }
lorder() { a=$(grep -n -- "$1" "$A/early.log" | head -n 1 | cut -d: -f1); b=$(grep -n -- "$2" "$A/early.log" | head -n 1 | cut -d: -f1); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# ---------- 1 syntax ----------
for s in "$HERE"/scripts/*.sh "$HERE"/tests/*.sh "$HERE"/tools/*.sh; do
    if busybox sh -n "$s" && dash -n "$s"; then ok "sh -n $(basename "$s")"; else ko "sh -n $s"; fi
done
( cd "$HERE" && sh tools/make-manifest.sh > "$T/man.now" ) ; chk "MANIFEST.md5 actueel" 'cmp -s "$T/man.now" "$HERE/MANIFEST.md5"'

# review-waarde v1-hook (documentatie) en v2-hook md5
TAG='# MZD-AA-BUSPATCH'
H1='[ -f /data_persist/dev/aa/aa-early.sh ] && /bin/sh /data_persist/dev/aa/aa-early.sh </dev/null >/dev/null 2>&1'
v1=$(awk -v tag="$TAG: bind-mount gepatchte usbmgr (guarded, faalt open)" -v hook="$H1" '/^touch \/var\/run\/usb_driver_ready$/ { print tag; print hook } { print }' "$STOCK_UD" | md5sum | cut -d' ' -f1)
chk "review-md5 v1-hook = 7571eb4f... bevestigd" '[ "$v1" = 7571eb4fa9702014336b685b195ca098 ]'

# ---------- 2 aa-early: normaal + crashlus ----------
mk; early
chk "normaal: gepatcht via pad" '[ "$(sod)" = "$P" ]'
chk "normaal: bootcount=1" '[ "$(cnt)" = 1 ]'
chk "M2: bind-bron is tmpfs-kopie" 'grep -q "$R/tmp/aa/svcjciusbmgr.so" "$T/bindsrc"'
reboot; early; reboot; early
chk "crash: bootcount=3 na 3 boots, nog gemount" '[ "$(cnt)" = 3 -a "$(sod)" = "$P" ]'
reboot; early
chk "M1: 4e boot (>=MAXFAIL 3) -> disabled + stock" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'
mk; printf 'MAXFAIL=2\nGRACE=abc\nrm -rf /=1\n' > "$A/aa.conf"; echo 2 > "$A/bootcount"; early
chk "aa.conf MAXFAIL=2 gerespecteerd, rommel genegeerd" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'

# ---------- 3 B1: teller ----------
mk; touch "$A/DISABLE"; echo 0 > "$A/bootcount"; early
chk "DISABLE: stock, teller onaangeroerd" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ]'
mk; rm -f "$A/bootcount"; early
chk "B1: bootcount ontbreekt -> stock" '[ "$(sod)" = "$O" ] && lg "bootcount ontbreekt"'
for g in abc "" "-1" 99999 "1 2"; do
    mk; printf '%s\n' "$g" > "$A/bootcount"; early
    chk "B1: rommel-teller '$g' -> stock, geen mount" '[ "$(sod)" = "$O" ] && ! calls "bind"'
done
mk; echo bootcount > "$T/flags/mv_fail"; early
chk "B1: teller niet schrijfbaar (mv faalt) -> GEEN mount" '[ "$(sod)" = "$O" ] && ! calls "bind" && lg "niet aantoonbaar"'
mk; echo bootcount > "$T/flags/mv_noop"; early
chk "B1: teller-terugleesfout (mv no-op) -> GEEN mount" '[ "$(sod)" = "$O" ] && ! calls "bind"'
mk; chmod 555 "$A"; early; chmod 755 "$A"
chk "B1: /data_persist read-only -> GEEN mount" '[ "$(sod)" = "$O" ] && ! calls "bind"'

# ---------- 4 M2: /tmp-kopie ----------
mk; echo "tmp/aa/svcjciusbmgr.so" > "$T/flags/cp_corrupt"; early
chk "M2: md5-mismatch kopie in /tmp -> stock, teller niet opgehoogd" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && lg "md5 kopie"'
mk; echo "tmp/aa/svcjciusbmgr.so" > "$T/flags/cp_fail"; early
chk "M2: kopie naar /tmp mislukt -> stock" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ]'
mk; printf 'x' >> "$A/svcjciusbmgr.so.patched"; early
chk "corrupte payload -> stock" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ]'
mk; printf 'x' >> "$SO"; early
chk "andere firmware -> skip" 'lg "firmware gewijzigd"'

# ---------- 5 m3: mount-fouten zetten teller terug ----------
mk; echo 1 > "$A/bootcount"; touch "$T/flags/fail_bind"; early
chk "m3: bind-mount mislukt -> stock, teller terug op 1" '[ "$(sod)" = "$O" -a "$(cnt)" = 1 ]'
mk; echo "rw,noexec" > "$T/flags/bindopts"; early
chk "noexec -> umount + teller terug op 0" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && lg noexec'
mk; echo "rw,noexec" > "$T/flags/bindopts"; touch "$T/flags/fail_umount"; early
chk "N2: verificatie faalt + umount mislukt -> teller blijft opgehoogd (1)" '[ "$(cnt)" = 1 ] && lg "umount mislukt"'

# ---------- 6 stick kill-switch bij boot (B1) ----------
mk; mkdir "$R/sys/usbstor/1-1:1.0"; printf '8 0 1 sda\n8 1 1 sda1\n' > "$R/parts"; touch "$R/dev/sda1"; early
chk "stick: 1 interface (alleen lezer) -> geen probe, wel mount" '[ "$(sod)" = "$P" ] && ! calls "-o ro"'
mk; mkdir "$R/sys/usbstor/1-1:1.0" "$R/sys/usbstor/2-1:1.0"; printf '8 1 1 sda1\n8 17 1 sdb1\n' > "$R/parts"; touch "$R/dev/sda1" "$R/dev/sdb1"; mkdir -p "$R/stickfs/sdb1"; touch "$R/stickfs/sdb1/AA_BUSPATCH_DISABLE"; early
chk "N1: standaard geen boot-stick-probe (ook met 2 interfaces) -> gemount, geen ro-probe" '[ "$(sod)" = "$P" ] && ! calls "-o ro"'
mk; echo STICK_BASE_IFACES=1 > "$A/aa.conf"; mkdir "$R/sys/usbstor/1-1:1.0" "$R/sys/usbstor/2-1:1.0"
printf '8 0 1 sda\n8 1 1 sda1\n8 16 1 sdb\n8 17 1 sdb1\n' > "$R/parts"; touch "$R/dev/sda1" "$R/dev/sdb1" "$R/dev/sda" "$R/dev/sdb"
mkdir -p "$R/stickfs/sdb1"; touch "$R/stickfs/sdb1/AA_BUSPATCH_DISABLE"; chmod 555 "$A"; early; chmod 755 "$A"
chk "stick bij boot + /data_persist read-only -> stock, geen bind, teller onaangeroerd" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && ! calls bind && calls "-o ro"'
mk; echo STICK_BASE_IFACES=1 > "$A/aa.conf"; mkdir "$R/sys/usbstor/1-1:1.0" "$R/sys/usbstor/2-1:1.0"
printf '8 1 1 sda1\n8 17 1 sdb1\n' > "$R/parts"; touch "$R/dev/sda1" "$R/dev/sdb1"; mkdir -p "$R/stickfs/sdb1"; touch "$R/stickfs/sdb1/AA_BUSPATCH_DISABLE"; early
chk "stick bij boot (schrijfbaar) -> stock + DISABLE gezet" '[ "$(sod)" = "$O" -a -e "$A/DISABLE" ]'
mk; echo STICK_BASE_IFACES=1 > "$A/aa.conf"; mkdir "$R/sys/usbstor/1-1:1.0" "$R/sys/usbstor/2-1:1.0"; printf '8 1 1 sda1\n8 17 1 sdb1\n' > "$R/parts"; touch "$R/dev/sda1" "$R/dev/sdb1"; mkdir -p "$R/stickfs/sdb1"; early
chk "stick zonder kill-bestand -> geprobed, daarna normaal gemount" '[ "$(sod)" = "$P" ] && calls "-o ro" && calls "umount $R/tmp/aa/kill"'

# ---------- 7 guard (B2/M1) ----------
mk; echo 2 > "$A/bootcount"; setproc init L_jciUSBMGR; touch "$R/run/start_network_ready"; echo "200.0 1" > "$R/uptime"; guard
chk "guard: gezond (usbmgr + ready-vlag) op 200s -> bootcount 0" '[ "$(cnt)" = 0 -a ! -e "$A/disabled" ]'
mk; echo 2 > "$A/bootcount"; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "guard: gezond via sshd (vlag al door sm gewist) -> bootcount 0" '[ "$(cnt)" = 0 ]'
mk; echo 2 > "$A/bootcount"; setproc init sshd; echo "200.0 1" > "$R/uptime"; guard
chk "B2: usbmgr dood op 200s -> nog geen reset, nog geen disabled (herkansing)" '[ "$(cnt)" = 2 -a ! -e "$A/disabled" ]'
echo "300.0 1" > "$R/uptime"; guard
chk "B2: usbmgr dood op 300s -> disabled, teller niet gereset" '[ "$(cnt)" = 2 -a -e "$A/disabled" ]'
mk; echo 1 > "$A/bootcount"; setproc L_jciUSBMGR; echo "300.0 1" > "$R/uptime"; guard
chk "B2: usbmgr leeft maar keten niet voorbij usbmgr -> disabled" '[ "$(cnt)" = 1 -a -e "$A/disabled" ]'
mk; echo 1 > "$A/bootcount"; setproc L_jciUSBMGR sshd; echo "100.0 1" > "$R/uptime"; guard
chk "M1: vóór GRACE (100s) -> niets" '[ "$(cnt)" = 1 -a ! -e "$A/disabled" ]'
mk; echo 1 > "$A/bootcount"; echo GRACE=120 > "$A/aa.conf"; setproc L_jciUSBMGR sshd; echo "130.0 1" > "$R/uptime"; guard
chk "M1: GRACE via aa.conf (120) -> reset op 130s" '[ "$(cnt)" = 0 ]'
mk; echo 1 > "$A/bootcount"; mkdir -p "$R/stick/sdb1"; touch "$R/stick/sdb1/AA_BUSPATCH_DISABLE"; echo "50.0 1" > "$R/uptime"; guard
chk "guard: stick tijdens bedrijf -> DISABLE" '[ -s "$A/DISABLE" ]'
mk; echo 1 > "$A/bootcount"; mkdir -p "$R/stick/sdb1"; touch "$R/stick/sdb1/AA_BUSPATCH_DISABLE"; echo "50.0 1" > "$R/uptime"
chmod 555 "$A"; guard; reboot; early; chmod 755 "$A"
chk "stick + /data_persist read-only: guard kan niet schrijven, volgende boot toch stock (B1)" '[ "$(sod)" = "$O" ] && ! calls bind'

# ---------- 8 hook in usb_drivers.sh: harde tijdsgrens (m2) ----------
mk; hook=$(grep '^HOOK=' "$HERE/scripts/aa-install.sh" | sed "s/^HOOK='//; s/'\$//")
printf '#!/bin/sh\nsleep 60\n' > "$T/hang.sh"
printf '%s\necho READY\n' "$(echo "$hook" | sed "s#/data_persist/dev/aa/aa-early.sh#$T/hang.sh#g")" > "$T/hooktest.sh"
t0=$(date +%s); out=$($SUT "$T/hooktest.sh"); t1=$(date +%s)
chk "m2: hangende aa-early -> ready-touch toch na <=16s ($((t1 - t0))s)" '[ "$out" = READY -a $((t1 - t0)) -le 16 ]'
printf '#!/bin/sh\nexit 0\n' > "$T/hang.sh"; t0=$(date +%s); out=$($SUT "$T/hooktest.sh"); t1=$(date +%s)
chk "m2: snelle aa-early -> <=2s ($((t1 - t0))s)" '[ "$out" = READY -a $((t1 - t0)) -le 2 ]'
printf '%s\necho READY\n' "$(echo "$hook" | sed "s#/data_persist/dev/aa/aa-early.sh#$T/bestaat-niet.sh#g")" > "$T/hooktest.sh"
chk "hook zonder aa-early.sh -> stock door" '[ "$($SUT "$T/hooktest.sh")" = READY ]'

# ---------- 9 install + gefaseerd activeren (M3/M5) ----------
mk; rm -f "$A/bootcount"; run aa-install.sh > "$T/inst.out" 2>&1; rc=$?
chk "install: exit 0" '[ $rc -eq 0 ]'; [ $rc -eq 0 ] || cat "$T/inst.out"
chk "install: md5 usb_drivers.sh = $UDP" '[ "$(md5sum "$UD" | cut -d'\'' '\'' -f1)" = "$UDP" ]'
chk "install: backup = stock" 'cmp -s "$UD.aabak" "$STOCK_UD"'
chk "M5: install zet DISABLE + DISABLE_AAPA + bootcount 0" '[ -e "$A/DISABLE" -a "$(cnt)" = 0 ] && grep -q "^install" "$A/DISABLE_AAPA"'
chk "M3: rootfs terug naar ro + geen restanten" 'calls "remount,ro" && [ ! -e "$UD.aanew" -a ! -e "$UD.aachk" ]'
awk '/aa-early.sh/{h=NR} /^touch \/var\/run\/usb_driver_ready$/{t=NR} END{exit !(t==h+1)}' "$UD"; rc=$?; chk "install: hook vlak voor ready-flag" '[ $rc -eq 0 ]'
# m10: evidence/ wordt niet overschreven; alleen vergeleken (zonder kopregels)
diff -u "$STOCK_UD" "$UD" | tail -n +3 > "$T/d.now"; tail -n +3 "$HERE/evidence/usb_drivers.sh.diff" > "$T/d.ev"
chk "evidence/usb_drivers.sh.diff klopt met install-resultaat" 'cmp -s "$T/d.now" "$T/d.ev"'
run aa-status.sh arm > "$T/arm.out" 2>&1
chk "M5: arm geweigerd vóór eerste boot met hook" '[ -e "$A/DISABLE" ] && grep -q "nog geen boot" "$T/arm.out"'
reboot; early
chk "M5 fase 1: boot met DISABLE -> stock" '[ "$(sod)" = "$O" ] && lg "DISABLE aanwezig"'
run aa-status.sh arm > "$T/arm.out" 2>&1
chk "M5 fase 2: arm na boot -> DISABLE weg, teller 0" '[ ! -e "$A/DISABLE" -a "$(cnt)" = 0 ]'
reboot; early
chk "M5 fase 2: boot gewapend -> gepatcht" '[ "$(sod)" = "$P" -a "$(cnt)" = 1 ]'
run aa-status.sh disarm > /dev/null 2>&1; chk "disarm -> DISABLE" '[ -s "$A/DISABLE" ]'
echo x > "$A/disabled"; echo 3 > "$A/bootcount"; run aa-status.sh rearm > /dev/null 2>&1
chk "rearm: disabled weg, teller 0, DISABLE blijft" '[ ! -e "$A/disabled" -a "$(cnt)" = 0 -a -e "$A/DISABLE" ]'
run aa-status.sh check > "$T/check.out" 2>&1; rc=$?; chk "status check draait (exit 0)" '[ $rc -eq 0 ] && grep -q "na-boot-controle" "$T/check.out"'
run aa-install.sh > /dev/null 2>&1
chk "install: idempotent (md5 gelijk, DISABLE blijft)" '[ "$(md5sum "$UD" | cut -d'\'' '\'' -f1)" = "$UDP" -a -e "$A/DISABLE" ]'
echo "# extra" >> "$UD"; run aa-install.sh > "$T/inst.out" 2>&1; rc=$?
chk "m4: hook aanwezig maar md5 fout -> geweigerd" '[ $rc -ne 0 ] && grep -q "handmatig" "$T/inst.out"'

mk; echo "deadbeef  aa-early.sh" > "$T/m"; grep -v ' aa-early.sh$' "$A/MANIFEST.md5" >> "$T/m"; cp "$T/m" "$A/MANIFEST.md5"
run aa-install.sh > "$T/inst.out" 2>&1; rc=$?
chk "m5: manifest-mismatch -> geweigerd, usb_drivers.sh onaangeroerd" '[ $rc -ne 0 ] && cmp -s "$UD" "$STOCK_UD" && ! calls remount'
mk; echo "jci/scripts/usb_drivers.sh" > "$T/flags/mv_corrupt"; run aa-install.sh > "$T/inst.out" 2>&1; rc=$?
chk "M3: terugleesfout -> backup teruggezet, exact stock, ro" '[ $rc -ne 0 ] && cmp -s "$UD" "$STOCK_UD" && grep -q "weer stock" "$T/inst.out" && calls "remount,ro"'
mk; echo kapot > "$UD.aabak"; run aa-install.sh > "$T/inst.out" 2>&1; rc=$?
chk "M3: die na remount rw -> trap zet ro terug, origineel intact" '[ $rc -ne 0 ] && calls "remount,ro" && cmp -s "$UD" "$STOCK_UD"'

# ---------- 10 uninstall ----------
mk; run aa-install.sh > /dev/null 2>&1; run aa-uninstall.sh --restore-hook > "$T/un.out" 2>&1
chk "uninstall: exact stock ($UDS) + DISABLE" '[ "$(md5sum "$UD" | cut -d'\'' '\'' -f1)" = "$UDS" -a -s "$A/DISABLE" ] && grep -q teruggelezen "$T/un.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$UD.aabak"; run aa-uninstall.sh --restore-hook > "$T/un.out" 2>&1
chk "m6: uninstall zonder backup -> filter -> exact stock" '[ "$(md5sum "$UD" | cut -d'\'' '\'' -f1)" = "$UDS" ] && grep -q "via filter" "$T/un.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$UD.aabak"; echo "# vreemd" >> "$UD"; cp "$UD" "$T/ud.before"
run aa-uninstall.sh --restore-hook > "$T/un.out" 2>&1; rc=$?
chk "m6: onbekende wijziging -> NIETS gewijzigd, DISABLE wel" '[ $rc -ne 0 ] && cmp -s "$UD" "$T/ud.before" && [ -e "$A/DISABLE" ]'
mk; run aa-install.sh > /dev/null 2>&1; echo "jci/scripts/usb_drivers.sh" > "$T/flags/mv_corrupt"; run aa-uninstall.sh --restore-hook > "$T/un.out" 2>&1; rc=$?
chk "m8: uninstall-terugleesfout -> hard gemeld" '[ $rc -ne 0 ] && grep -q "EINDCONTROLE" "$T/un.out" && calls "remount,ro"'
mk; rm -rf "$A"; mkdir -p "$T/x"; sed -e "s#^AA=.*#AA=$A#" -e "s#^UD=.*#UD=$UD#" "$HERE/scripts/aa-uninstall.sh" > "$T/x/un.sh"
PATH="$T/bin:$PATH" $SUT "$T/x/un.sh" > "$T/un.out" 2>&1
chk "m7: zonder \$AA geen valse 'DISABLE gezet'" '! grep -q "DISABLE gezet" "$T/un.out"'

# ---------- 11 aapa-doel (stap 2) ----------
mk; early
chk "aapa: standaard UIT (DISABLE_AAPA) -> alleen usbmgr gemount" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "DISABLE_AAPA aanwezig" && ! calls "blmjciaapa"'
mk; rm -f "$A/DISABLE_AAPA"; early
chk "aapa gewapend: beide gemount vanaf /tmp, teller 1x opgehoogd" '[ "$(sod)" = "$P" -a "$(soa)" = "$PA" -a "$(cnt)" = 1 ] && grep -q "$R/tmp/aa/blmjciaapa.so" "$T/bindsrc"'
reboot; early
chk "aapa gewapend: 2e boot -> gedeelde teller 2" '[ "$(cnt)" = 2 -a "$(soa)" = "$PA" ]'
mk; rm -f "$A/DISABLE_AAPA"; touch "$A/DISABLE"; early
chk "DISABLE is globaal: ook aapa stock" '[ "$(sod)" = "$O" -a "$(soa)" = "$OA" -a "$(cnt)" = 0 ]'
mk; rm -f "$A/DISABLE_AAPA"; echo x > "$A/disabled"; early
chk "guard-marker disabled: beide stock" '[ "$(sod)" = "$O" -a "$(soa)" = "$OA" ]'
mk; rm -f "$A/DISABLE_AAPA"; echo 3 > "$A/bootcount"; early
chk "MAXFAIL met aapa gewapend -> disabled, beide stock" '[ -e "$A/disabled" -a "$(sod)" = "$O" -a "$(soa)" = "$OA" ]'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SOA"; early
chk "aapa stock-md5 mismatch -> alleen usbmgr gemount, teller 1" '[ "$(sod)" = "$P" -a "$(cnt)" = 1 ] && lg "\[aapa\] stock md5" && ! calls "blmjciaapa"'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$A/blmjciaapa.so.patched"; early
chk "aapa-payload corrupt -> alleen usbmgr" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "\[aapa\] md5 kopie"'
mk; rm -f "$A/DISABLE_AAPA"; echo "tmp/aa/blmjciaapa.so" > "$T/flags/cp_fail"; early
chk "aapa kopie naar /tmp mislukt -> alleen usbmgr" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ]'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SO"; early
chk "usbmgr stock-mismatch, aapa gewapend -> alleen aapa, teller 1" '[ "$(soa)" = "$PA" -a "$(cnt)" = 1 ] && lg "\[usbmgr\] stock md5"'
mk; rm -f "$A/DISABLE_AAPA"; echo "rw,noexec" > "$T/flags/bindopts.blmjciaapa.so"; early
chk "aapa mount-verificatie faalt -> umount aapa, usbmgr blijft, teller blijft 1" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "\[aapa\] verificatie na mount faalde" && calls "umount $SOA" && ! grep -q " $SOA " "$R/mounts"'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SO"; echo "rw,noexec" > "$T/flags/bindopts.blmjciaapa.so"; early
chk "alleen aapa, verificatie faalt -> umount, niets actief, teller terug 0" '[ "$(soa)" = "$OA" -a "$(cnt)" = 0 ] && lg "niets actief"'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SO"; echo "rw,noexec" > "$T/flags/bindopts.blmjciaapa.so"; touch "$T/flags/fail_umount.blmjciaapa.so"; early
chk "alleen aapa, verificatie faalt + umount mislukt -> teller blijft 1, guard gestart" '[ "$(cnt)" = 1 ] && lg "\[aapa\].*umount mislukt" && lg "guard gestart"'
mk; rm -f "$A/DISABLE_AAPA"; touch "$T/flags/fail_bind.blmjciaapa.so"; early
chk "aapa bind-mount mislukt -> usbmgr blijft, teller 1" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "\[aapa\] bind-mount mislukt"'
mk; rm -f "$A/DISABLE_AAPA"; touch "$T/flags/fail_bind"; echo 1 > "$A/bootcount"; early
chk "beide bind-mounts mislukt -> teller terug op 1" '[ "$(sod)" = "$O" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ]'
mk; rm -f "$A/DISABLE_AAPA"; echo "25.00 1" > "$T/flags/cp_setuptime"; early
chk "tijdsgrens 1 (AAPA_BUDGET 7): na usbmgr al >=7 s -> aapa overgeslagen, usbmgr wel" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" ] && lg "aapa overgeslagen"'
mk; rm -f "$A/DISABLE_AAPA"; echo "20.00 1" > "$T/flags/cp_setuptime"; early
chk "tijdsgrens 1: 8 s (12->20) -> aan aapa niet begonnen, geen kopie" '[ "$(soa)" = "$OA" ] && lg "al 8s bezig" && [ ! -e "$R/tmp/aa/blmjciaapa.so" ]'
mk; rm -f "$A/DISABLE_AAPA"
echo "/dev/root $SOA relfs rw 0 0" > "$R/mounts"; early
chk "aapa al een mountpoint -> aapa niet opnieuw, usbmgr wel" '[ "$(sod)" = "$P" ] && lg "\[aapa\] TARGET is al een mountpoint"'

# guard met aapa (review3 H1/m1/m6: standaard AAPA_GRACE 420, tweetraps met zelfde pid, zombie = dood)
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "300.0 1" > "$R/uptime"; guard
chk "H1: standaard aapa-grace 420 -> op 300s niets beoordeeld (ook al leeft aapa)" '[ "$(cnt)" = 2 -a ! -e "$A/disabled" -a ! -e "$A/DISABLE_AAPA" ] && glg "aapa-grace 420s"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; guard
chk "H1: aapa leeft op 420s -> alleen pid onthouden, teller NOG NIET gewist" '[ "$(cnt)" = 2 -a ! -e "$A/disabled" ] && glg "bevestiging op 480s"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480; guard
chk "H1: zelfde aapa-pid op 420s en 480s -> bootcount 0" '[ "$(cnt)" = 0 -a ! -e "$A/disabled" -a ! -e "$A/DISABLE_AAPA" ] && glg "gezond op 480s (usbmgr=1 net=1 aapa=1 pid=104)"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480
echo "rm -rf '$R/proc/104'; mkdir -p '$R/proc/205'; echo '205 (L_jciAAPA) S 1 1' > '$R/proc/205/stat'" > "$T/flags/onsleep"; guard
chk "H1: ander aapa-pid (herstart) bij bevestiging -> aapa gefaald, teller NIET gewist" '[ "$(cnt)" = 2 -a -f "$A/DISABLE_AAPA" ] && glg "aapa-pid 104 gezien op 420s"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480
echo "echo '104 (L_jciAAPA) Z 1 1' > '$R/proc/104/stat'" > "$T/flags/onsleep"; guard
chk "H1/m1: aapa wordt zombie na eerste beoordeling -> gefaald, teller NIET gewist" '[ "$(cnt)" = 2 -a -f "$A/DISABLE_AAPA" ]'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd; mkdir -p "$R/proc/150"; echo "150 (L_jciAAPA) Z 1 1" > "$R/proc/150/stat"; echo "480.0 1" > "$R/uptime"; guard
chk "m1: alleen een zombie-L_jciAAPA op 480s -> telt als dood -> DISABLE_AAPA, teller blijft" '[ "$(cnt)" = 2 -a -f "$A/DISABLE_AAPA" -a ! -e "$A/disabled" ]'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd; echo "440.0 1" > "$R/uptime"; guard
chk "H1: aapa dood op 440s -> nog niets (herkansing tot 480s)" '[ "$(cnt)" = 2 -a ! -e "$A/disabled" -a ! -e "$A/DISABLE_AAPA" ]'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd; echo "480.0 1" > "$R/uptime"; guard
chk "m6: usbmgr+net gezond, alleen aapa dood -> DISABLE_AAPA (niet disabled), teller blijft" '[ "$(cnt)" = 2 -a -f "$A/DISABLE_AAPA" -a ! -e "$A/disabled" ] && glg "alleen aapa schuldig"'
reboot; early
chk "m6: volgende boot -> alleen usbmgr gepatcht, aapa stock, teller 3" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 3 ]'
mk; echo 2 > "$A/bootcount"; amount; setproc init sshd; echo "480.0 1" > "$R/uptime"; guard
chk "m6: usbmgr OOK dood -> disabled (beide stock), teller blijft" '[ "$(cnt)" = 2 -a -e "$A/disabled" ] && grep -q "aapa=0" "$A/disabled"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd; rm -f "$A/DISABLE_AAPA"; mkdir "$A/DISABLE_AAPA"; echo "480.0 1" > "$R/uptime"; guard
chk "m6: DISABLE_AAPA niet schrijfbaar -> terugval op disabled" '[ -e "$A/disabled" -a "$(cnt)" = 2 ] && glg "val terug op"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450
echo "rm -rf '$R/proc/102'" > "$T/flags/onsleep"; guard
chk "H1: usbmgr valt weg na eerste gezonde beoordeling -> disabled" '[ "$(cnt)" = 2 -a -e "$A/disabled" ]'
mk; echo 2 > "$A/bootcount"; amount; setproc init sshd L_jciUSBMGR; echo "200.0 1" > "$R/uptime"; guard
chk "guard: aapa gemount + dood op 200s -> nog geen beoordeling" '[ "$(cnt)" = 2 -a ! -e "$A/disabled" -a ! -e "$A/DISABLE_AAPA" ]'
mk; echo 2 > "$A/bootcount"; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "guard: aapa NIET gemount -> L_jciAAPA niet vereist, direct reset op GRACE" '[ "$(cnt)" = 0 -a ! -e "$A/disabled" ]'
mk; echo 2 > "$A/bootcount"; echo AAPA_GRACE=200 > "$A/aa.conf"; amount; setproc L_jciUSBMGR sshd L_jciAAPA; echo "200.0 1" > "$R/uptime"; tick 230 260; guard
chk "guard: AAPA_GRACE=200 via aa.conf -> bevestigd op 260s" '[ "$(cnt)" = 0 ] && glg "aapa-grace 200s"'
mk; echo 2 > "$A/bootcount"; printf 'AAPA_GRACE=400' > "$A/aa.conf"; amount; setproc L_jciUSBMGR sshd; echo "300.0 1" > "$R/uptime"; guard
chk "m-N13: AAPA_GRACE=400 zonder newline gelezen -> op 300s niets" '[ "$(cnt)" = 2 -a ! -e "$A/DISABLE_AAPA" ] && glg "aapa-grace 400s"'
echo "470.0 1" > "$R/uptime"; guard
chk "guard: AAPA_GRACE=400 -> op 470s (na herkansing) aapa uit (DISABLE_AAPA)" '[ -f "$A/DISABLE_AAPA" -a "$(cnt)" = 2 ]'
mk; echo 1 > "$A/bootcount"; printf 'GRACE=120' > "$A/aa.conf"; setproc L_jciUSBMGR sshd; echo "130.0 1" > "$R/uptime"; guard
chk "m-N13: GRACE=120 zonder newline -> reset op 130s" '[ "$(cnt)" = 0 ]'
mk; echo 2 > "$A/bootcount"; setproc init sshd; mkdir -p "$R/proc/150"; echo "150 (L_jciUSBMGR) Z 1 1" > "$R/proc/150/stat"; echo "300.0 1" > "$R/uptime"; guard
chk "m1: usbmgr zombie -> niet gezond -> disabled" '[ "$(cnt)" = 2 -a -e "$A/disabled" ]'

# M1: usbmgr eerst helemaal af, aapa daarna; tweede tijdstoets vlak voor de aapa-mount
mk; rm -f "$A/DISABLE_AAPA"; early
chk "M1: usbmgr bind-mount OK vóór aapa bind-mount (log + mount-volgorde)" 'lorder "\[usbmgr\] bind-mount OK" "\[aapa\] bind-mount OK" && grep "bind" "$T/mount.calls" | head -n 1 | grep -q svcjciusbmgr'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SOA"; early
chk "M1: aapa stock-md5 pas na de usbmgr-mount bekeken" 'lorder "\[usbmgr\] bind-mount OK" "\[aapa\] stock md5"'
mk; rm -f "$A/DISABLE_AAPA"; echo "24.00 1" > "$T/flags/cp_setuptime_aapa"; early
chk "M1: tijdstoets 2 (>=11 s vlak voor aapa-mount) -> aapa overgeslagen, kopie weg, usbmgr gemount, teller 1" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "vlak voor mount" && [ ! -e "$R/tmp/aa/blmjciaapa.so" ] && ! calls "blmjciaapa"'
mk; rm -f "$A/DISABLE_AAPA"; printf 'x' >> "$SO"; echo "24.00 1" > "$T/flags/cp_setuptime_aapa"; early
chk "M1: alleen aapa + tijdstoets 2 -> niets gemount, teller nooit opgehoogd (0)" '[ "$(soa)" = "$OA" -a "$(cnt)" = 0 ] && ! calls bind && lg "geen doel over"'
mk; rm -f "$A/DISABLE_AAPA"; echo "22.00 1" > "$T/flags/cp_setuptime_aapa"; early
chk "M1: 10 s vlak voor aapa-mount (< 11) -> aapa wel gemount" '[ "$(soa)" = "$PA" -a "$(cnt)" = 1 ]'
mk; rm -f "$A/DISABLE_AAPA"; echo bootcount > "$T/flags/mv_fail"; early
chk "B1 met 2 doelen: teller niet schrijfbaar -> geen enkele mount (ook geen aapa)" '[ "$(sod)" = "$O" -a "$(soa)" = "$OA" ] && ! calls bind'

# m7 / m-N12 / m-N13 in aa-early
mk; echo "300.00 1" > "$R/uptime"; early
chk "m7: aa-early met de hand op lopend systeem (uptime 300) -> niets, teller onaangeroerd" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && ! calls bind && lg "niet vanuit de boot-hook"'
mk; echo 08 > "$A/bootcount"; early
chk "m-N12: teller '08' = 8 (geen octaal) -> disabled, stock" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'
mk; echo 02 > "$A/bootcount"; early
chk "m-N12: teller '02' -> 3, gemount" '[ "$(cnt)" = 3 -a "$(sod)" = "$P" ]'
mk; printf 'MAXFAIL=2' > "$A/aa.conf"; echo 2 > "$A/bootcount"; early
chk "m-N13: aa.conf MAXFAIL=2 zonder newline gelezen -> disabled" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'

# arm-aapa / disarm-aapa / status
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"
run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "arm-aapa: DISABLE_AAPA weg, usbmgr/teller onaangeroerd" '[ $rc -eq 0 -a ! -e "$A/DISABLE_AAPA" -a ! -e "$A/DISABLE" -a "$(cnt)" = 0 ]'
reboot; early
chk "arm-aapa -> volgende boot beide gepatcht" '[ "$(sod)" = "$P" -a "$(soa)" = "$PA" -a "$(cnt)" = 1 ]'
run aa-status.sh > "$T/st.out" 2>&1
chk "status toont aapa: ACTIEF + GEPATCHT via pad" 'grep -q "aapa bind-mount  : ACTIEF" "$T/st.out" && grep -q "aapa via pad     : GEPATCHT" "$T/st.out" && grep -q "DISABLE_AAPA     : nee" "$T/st.out"'
run aa-status.sh disarm-aapa > /dev/null 2>&1
chk "disarm-aapa -> DISABLE_AAPA, DISABLE niet" '[ -s "$A/DISABLE_AAPA" -a ! -e "$A/DISABLE" ]'
reboot; early
chk "disarm-aapa -> volgende boot alleen usbmgr" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" ]'
mk; run aa-install.sh > /dev/null 2>&1; printf 'x' >> "$SOA"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "arm-aapa geweigerd bij stock-aapa-mismatch" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "andere firmware" "$T/aa.out"'
mk; run aa-install.sh > /dev/null 2>&1; sed -i "/^TARGET_AAPA=/d" "$A/aa-early.sh"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "arm-aapa geweigerd met oude aa-early (v2)" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "nog geen v3" "$T/aa.out"'
mk; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "arm-aapa geweigerd zonder hook" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ]'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo 1 > "$A/bootcount"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "m5: arm-aapa geweigerd bij bootcount 1 (guard nog niet gezond)" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "niet 0" "$T/aa.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo x > "$A/disabled"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "m5: arm-aapa geweigerd als 'disabled' staat" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "crash-guard-marker" "$T/aa.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo "# x" >> "$A/aa-uninstall.sh"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1; rc=$?
chk "m5: arm-aapa geweigerd bij manifest-mismatch" '[ $rc -ne 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "MANIFEST" "$T/aa.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; run aa-status.sh arm-aapa > "$T/aa.out" 2>&1
chk "M2: arm-aapa noemt 9 min wachten + eerst telefoon los" 'grep -q "9 min" "$T/aa.out" && grep -q "EERST de telefoon" "$T/aa.out"'

# upgrade in place: v2-installatie (hook staat, usbmgr gewapend) -> v3 via stage/
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE" "$A/DISABLE_AAPA" "$A/blmjciaapa.so.patched"
echo "# oude v2" >> "$A/aa-early.sh"; cp "$UD" "$T/ud.before"; cp -r "$T/kit" "$A/stage"; : > "$T/mount.calls"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "upgrade: exit 0, modus upgrade" '[ $rc -eq 0 ] && grep -q "Modus: upgrade" "$T/up.out"'; [ $rc -eq 0 ] || cat "$T/up.out"
chk "upgrade: usb_drivers.sh NIET aangeraakt, geen remount" 'cmp -s "$UD" "$T/ud.before" && ! calls remount && [ ! -e "$UD.aanew" ]'
chk "upgrade: nieuwe bestanden geplaatst, stage weg" 'cmp -s "$A/aa-early.sh" "$T/kit/aa-early.sh" && cmp -s "$A/blmjciaapa.so.patched" "$T/kit/blmjciaapa.so.patched" && cmp -s "$A/MANIFEST.md5" "$T/kit/MANIFEST.md5" && [ ! -d "$A/stage" ] && ! ls "$A"/*.aanew >/dev/null 2>&1'
chk "upgrade: usbmgr blijft gewapend, aapa UIT" '[ ! -e "$A/DISABLE" -a -e "$A/DISABLE_AAPA" ]'
reboot; early
chk "upgrade: volgende boot usbmgr gepatcht, aapa stock" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" ]'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo "# oude v2" >> "$A/aa-early.sh"; cp "$A/aa-early.sh" "$T/early.old"
cp -r "$T/kit" "$A/stage"; printf 'x' >> "$A/stage/aa-guard.sh"; : > "$T/mount.calls"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "upgrade: corrupt bestand in stage -> geweigerd, niets geplaatst" '[ $rc -ne 0 ] && cmp -s "$A/aa-early.sh" "$T/early.old" && ! calls remount && grep -q "klopt niet" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; cp -r "$T/kit" "$A/stage"; echo "aa-early.sh" > "$T/flags/mv_fail"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "upgrade: mv aa-early faalt -> fout gemeld, oude aa-early intact, DISABLE_AAPA staat" '[ $rc -ne 0 ] && [ -e "$A/DISABLE_AAPA" ] && ! ls "$A"/*.aanew >/dev/null 2>&1'
# m2: installer draait vanuit stage/ zelf (zoals de README doet) en ruimt die als allerlaatste op
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo "# oude v2" >> "$A/aa-early.sh"; cp -r "$T/kit" "$A/stage"; : > "$R/dropc"
PATH="$T/bin:$PATH" $SUT "$A/stage/aa-install.sh" > "$T/up.out" 2>&1; rc=$?
chk "m2: upgrade vanuit stage/: exit 0, slotmeldingen, stage weg, bestanden nieuw" '[ $rc -eq 0 ] && grep -q "Upgrade klaar" "$T/up.out" && grep -q "tussenboot" "$T/up.out" && [ ! -d "$A/stage" ] && cmp -s "$A/aa-early.sh" "$T/kit/aa-early.sh"'
chk "m3: upgrade leegt page-cache vóór eindcontrole" '[ "$(cat "$R/dropc")" = 3 ]'
mk; rm -f "$A/bootcount"; cp -r "$T/kit" "$A/stage"; ( cd "$A/stage" && PATH="$T/bin:$PATH" $SUT aa-install.sh ) > "$T/inst.out" 2>&1; rc=$?
chk "m2: verse install vanuit stage/ (cd stage && sh aa-install.sh): exit 0, hook, stage weg" '[ $rc -eq 0 ] && grep -q "Fase 1 klaar" "$T/inst.out" && [ "$(md5sum "$UD" | cut -d" " -f1)" = "$UDP" ] && [ ! -d "$A/stage" ] && calls "remount,ro"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; echo "# oude v2" >> "$A/aa-early.sh"; cp "$A/aa-early.sh" "$T/early.old"; cp -r "$T/kit" "$A/stage"
printf 'Filesystem           1K-blocks      Used Available Use%% Mounted on\n/dev/mmcblk0p5          123456    120456      3000  98%% /tmp/mnt/data_persist\n' > "$T/flags/df_out"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "m4: te weinig vrije ruimte (3000 KB) -> geweigerd, niets geplaatst, stage blijft" '[ $rc -ne 0 ] && grep -q "te weinig vrije ruimte" "$T/up.out" && cmp -s "$A/aa-early.sh" "$T/early.old" && [ -d "$A/stage" ]'
mk; run aa-install.sh > /dev/null 2>&1; cp -r "$T/kit" "$A/stage"
printf 'Filesystem           1K-blocks      Used Available Use%% Mounted on\n/dev/disk/by-label/een-hele-lange-naam\n                        123456      1000     50000   1%% /tmp/mnt/data_persist\n' > "$T/flags/df_out"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "m4: busybox-df met afgebroken device-regel goed gelezen -> upgrade ok" '[ $rc -eq 0 ] && ! grep -q "niet te bepalen" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; cp -r "$T/kit" "$A/stage"; echo "df: kapot" > "$T/flags/df_out"
run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "m4: df onleesbaar -> waarschuwing, upgrade gaat door" '[ $rc -eq 0 ] && grep -q "niet te bepalen" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; printf 'x' >> "$SOA"; run aa-install.sh > "$T/up.out" 2>&1; rc=$?
chk "upgrade: stock-aapa-mismatch -> waarschuwing, geen fout" '[ $rc -eq 0 ] && grep -q "WAARSCHUWING: stock aapa" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE_AAPA"; run aa-install.sh > /dev/null 2>&1
chk "herinstallatie zet aapa weer UIT (default)" '[ -e "$A/DISABLE_AAPA" ]'

# uninstall beide
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE" "$A/DISABLE_AAPA"; run aa-uninstall.sh --purge > "$T/un.out" 2>&1
chk "uninstall --purge: DISABLE + DISABLE_AAPA, beide payloads weg, hook stock" '[ -s "$A/DISABLE" -a -s "$A/DISABLE_AAPA" -a ! -e "$A/blmjciaapa.so.patched" -a ! -e "$A/svcjciusbmgr.so.patched" ] && [ "$(md5sum "$UD" | cut -d" " -f1)" = "$UDS" ]'

# ---------- 12 proven mode (kit 3.1) ----------
FPU="usbmgr:$O:$P"; FPA="aapa:$OA:$PA"; FPB="$FPU+$FPA"
wp() { printf "$@" > "$A/proven"; }
pv() { grep -q -- "$1" "$A/proven" 2>/dev/null; }
blk() { sed -n '/^# --- proven-record/,/^# --- einde proven-record/p' "$HERE/scripts/$1"; }
chk "proven: functieblok identiek in early/guard/status" '[ -n "$(blk aa-early.sh)" ] && [ "$(blk aa-early.sh)" = "$(blk aa-guard.sh)" ] && [ "$(blk aa-early.sh)" = "$(blk aa-status.sh)" ]'
chk "proven: md5-constanten in early/guard/status gelijk" '[ "$(grep -h "^ORIG_MD5=\|^PATCHED_MD5=\|^AAPA_ORIG_MD5=\|^AAPA_PATCHED_MD5=" "$HERE/scripts/aa-early.sh" | sed "s/ *#.*//" | sort)" = "$(grep -h "^ORIG_MD5=\|^PATCHED_MD5=\|^AAPA_ORIG_MD5=\|^AAPA_PATCHED_MD5=" "$HERE/scripts/aa-guard.sh" | sort)" ] && [ "$(grep -h "^ORIG_MD5=\|^PATCHED_MD5=\|^AAPA_ORIG_MD5=\|^AAPA_PATCHED_MD5=" "$HERE/scripts/aa-guard.sh" | sort)" = "$(grep -h "^ORIG_MD5=\|^PATCHED_MD5=\|^AAPA_ORIG_MD5=\|^AAPA_PATCHED_MD5=" "$HERE/scripts/aa-status.sh" | sort)" ]'

# aa-early: drempel
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=5 %s\n' "$FPB"; early
chk "proven: drempel 5 bereikt (beide doelen) -> beide gemount, bootcount NIET opgehoogd (0)" '[ "$(sod)" = "$P" -a "$(soa)" = "$PA" -a "$(cnt)" = 0 ] && lg "proven mode: bootcount niet opgehoogd" && pv "^short=1$" && pv "^rec=5 $FPB$"'
mk; wp 'short=0\nrec=5 %s\n' "$FPU"; early
chk "proven: alleen usbmgr (aapa UIT), record usbmgr 5 -> niet opgehoogd" '[ "$(sod)" = "$P" -a "$(cnt)" = 0 ] && lg "proven mode"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=4 %s\n' "$FPB"; early
chk "proven: 4/5 -> nog normaal tellen (bootcount 1), short onaangeroerd" '[ "$(cnt)" = 1 ] && lg "4/5 gezonde boots" && ! lg "proven mode" && pv "^short=0$"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=05 %s\n' "$FPB"; early
chk "proven: voorloopnul in aantal ('05') = 5" '[ "$(cnt)" = 0 ] && lg "proven mode"'
mk; wp 'short=0\nrec=9 %s\n' "$FPB"; early
chk "proven: fingerprint wijkt af (aapa uitgezet, record voor beide) -> normaal tellen" '[ "$(sod)" = "$P" -a "$(cnt)" = 1 ] && lg "geen record voor deze combinatie"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=9 %s\n' "$FPU"; early
chk "proven: aapa nieuw gewapend (record alleen usbmgr) -> normaal tellen" '[ "$(soa)" = "$PA" -a "$(cnt)" = 1 ] && lg "geen record"'
mk; wp 'short=0\nrec=9 usbmgr:%s:%s\n' "$O" deadbeefdeadbeefdeadbeefdeadbeef; early
chk "proven: andere payload-md5 in record (firmware/payload gewijzigd) -> normaal tellen" '[ "$(cnt)" = 1 ] && ! lg "proven mode"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=2\nrec=7 %s\n' "$FPB"; printf 'x' >> "$SOA"; early
chk "proven: aapa valt bij boot af (stock-md5) -> actieve set wijkt af -> toch geteld (1), short terug op 2" '[ "$(sod)" = "$P" -a "$(cnt)" = 1 ] && ! calls blmjciaapa && lg "toch geteld: bootcount 0 -> 1" && pv "^short=2$" && lg "proven=0"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=7 %s\n' "$FPB"; echo "24.00 1" > "$T/flags/cp_setuptime_aapa"; early
chk "proven: aapa overgeslagen door tijdsgrens -> toch geteld (1)" '[ "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && lg "toch geteld"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=7 %s\n' "$FPB"; reboot; early; reboot; early; reboot; early; reboot; early
chk "proven: 4 korte ritten op rij (geen guard-oordeel) -> bootcount blijft 0, nog gemount, short=4" '[ "$(cnt)" = 0 -a "$(sod)" = "$P" -a "$(soa)" = "$PA" -a ! -e "$A/disabled" ] && pv "^short=4$"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=20\nrec=7 %s\n' "$FPB"; early
chk "proven: PROVEN_MAXSHORT (20) boots zonder oordeel -> ingetrokken, normaal tellen (1)" '[ "$(cnt)" = 1 -a ! -e "$A/proven" ] && lg "proven ingetrokken"'
mk; echo PROVEN_MAXSHORT=5 > "$A/aa.conf"; wp 'short=5\nrec=7 %s\n' "$FPU"; early
chk "proven: PROVEN_MAXSHORT=5 via aa.conf" '[ "$(cnt)" = 1 -a ! -e "$A/proven" ]'
mk; echo 2 > "$A/bootcount"; wp 'short=0\nrec=7 %s\n' "$FPU"; early
chk "proven: teller die al op 2 stond wordt niet opgehoogd" '[ "$(cnt)" = 2 -a "$(sod)" = "$P" ]'
mk; echo 3 > "$A/bootcount"; wp 'short=0\nrec=7 %s\n' "$FPU"; early
chk "proven: teller >= MAXFAIL blijft 'disabled' geven (kill-switches ongewijzigd)" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'
mk; touch "$A/DISABLE"; wp 'short=0\nrec=7 %s\n' "$FPU"; early
chk "proven: DISABLE blijft werken" '[ "$(sod)" = "$O" ] && pv "^short=0$"'
mk; echo x > "$A/disabled"; wp 'short=0\nrec=7 %s\n' "$FPU"; early
chk "proven: 'disabled' blijft werken" '[ "$(sod)" = "$O" ]'
mk; echo PROVEN_N=0 > "$A/aa.conf"; wp 'short=0\nrec=7 %s\n' "$FPU"; early
chk "proven: PROVEN_N=0 = uit -> normaal tellen" '[ "$(cnt)" = 1 ] && ! lg "proven mode" && ! lg "proven:"'
mk; echo PROVEN_N=3 > "$A/aa.conf"; wp 'short=0\nrec=3 %s\n' "$FPU"; early
chk "proven: PROVEN_N=3 via aa.conf -> 3 is genoeg" '[ "$(cnt)" = 0 ] && lg "proven mode"'
mk; printf 'PROVEN_N=2\nPROVEN_MAXSHORT=99' > "$A/aa.conf"; wp 'short=0\nrec=3 %s\n' "$FPU"; early
chk "proven: PROVEN_N=2 (buiten 3..20) genegeerd -> standaard 5 -> tellen" '[ "$(cnt)" = 1 ] && lg "3/5"'
mk; echo PROVEN_N=21 > "$A/aa.conf"; wp 'short=0\nrec=20 %s\n' "$FPU"; early
chk "proven: PROVEN_N=21 genegeerd -> standaard 5" '[ "$(cnt)" = 0 ]'
n=0
for c in 'kapot\n' 'short=x\nrec=5 FP\n' 'rec=5 FP\n' 'short=0\nrec=5\n' 'short=0\nrec=abc FP\n' 'short=0\nrec=5 FP;rm\n' 'short=0\nrec=99999 FP\n' 'short=0\nfoo=1\nrec=5 FP\n' ''; do
    n=$((n + 1)); mk; printf "$c" | sed "s#FP#$FPU#" > "$A/proven"; early
    chk "proven: corrupt bestand #$n -> niet proven, normaal tellen (1)" '[ "$(cnt)" = 1 -a "$(sod)" = "$P" ] && ! lg "proven mode" && lg "proven-bestand ongeldig"'
done
mk; { printf 'short=0\nrec=5 %s\n' "$FPU"; i=0; while [ $i -lt 40 ]; do echo; i=$((i+1)); done; head -c 1100 /dev/zero | tr '\0' '\n'; } > "$A/proven"; early
chk "proven: bestand > 1 KB -> ongeldig -> tellen" '[ "$(cnt)" = 1 ]'
mk; wp 'short=0\nrec=5 %s' "$FPU"; early
chk "proven: laatste regel zonder newline wordt gelezen" '[ "$(cnt)" = 0 ] && lg "proven mode"'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; chmod 555 "$A"; early; chmod 755 "$A"
chk "proven + /data_persist read-only -> GEEN mount (schrijfproef faalt), teller 0" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && ! calls bind'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; echo "aa/proven" > "$T/flags/mv_fail"; early
chk "proven: record niet schrijfbaar (mv faalt) -> GEEN mount" '[ "$(sod)" = "$O" ] && ! calls bind && lg "proven-record niet aantoonbaar"'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; echo "aa/proven" > "$T/flags/mv_noop"; early
chk "proven: record terugleesfout (mv no-op) -> GEEN mount" '[ "$(sod)" = "$O" ] && ! calls bind'
mk; wp 'short=3\nrec=7 %s\n' "$FPU"; touch "$T/flags/fail_bind"; early
chk "proven: niets gemount -> short terug op 3, teller 0" '[ "$(sod)" = "$O" -a "$(cnt)" = 0 ] && pv "^short=3$"'

# guard: opbouw, ophogen, intrekken
mk; k=0; while [ $k -lt 5 ]; do reboot; early; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard; k=$((k + 1)); done   # (setproc gebruikt $i)
chk "proven: 5 gezonde boots (usbmgr) -> record 5 voor usbmgr, short 0" 'pv "^rec=5 $FPU$" && pv "^short=0$" && glg "gezonde boot 5 (drempel 5) voor usbmgr=1 aapa=0 -> PROVEN"'
chk "proven: tijdens opbouw werd elke boot geteld en door de guard gewist" '[ "$(cnt)" = 0 ] && [ "$(grep -c "bootcount 0 -> 1" "$A/early.log")" -ge 5 ]'
reboot; early
chk "proven: 6e boot -> proven mode, bootcount niet opgehoogd" '[ "$(cnt)" = 0 -a "$(sod)" = "$P" ] && lg "proven mode"'
reboot; early; reboot; early; reboot; early
chk "proven: 3 korte ritten daarna -> geen 'disabled', nog gemount" '[ ! -e "$A/disabled" -a "$(sod)" = "$P" -a "$(cnt)" = 0 ] && pv "^short=4$"'
setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: gezonde boot daarna -> record 6, short 0" 'pv "^rec=6 $FPU$" && pv "^short=0$"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=2 %s\nrec=9 %s\n' "$FPB" "$FPU"; early; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480; guard
chk "proven: gezond met beide doelen (480 s) -> record beide 3, record usbmgr blijft 9" '[ "$(cnt)" = 0 ] && pv "^rec=3 $FPB$" && pv "^rec=9 $FPU$" && [ "$(grep -c "^rec=" "$A/proven")" = 2 ]'
mk; rm -f "$A/DISABLE_AAPA"; early; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; guard
chk "proven: aapa nog niet bevestigd (alleen 420 s) -> nog niet geteld" '[ ! -e "$A/proven" ]'
mk; echo kapot > "$A/proven"; early; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: guard overschrijft ongeldig bestand met geldig record 1" 'pv "^rec=1 $FPU$" && pv "^short=0$" && glg "ongeldig -> opnieuw"'
mk; early; echo "aa/proven" > "$T/flags/mv_fail"; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: guard kan record niet schrijven -> geen record, wel bootcount 0" '[ ! -e "$A/proven" -a "$(cnt)" = 0 ] && glg "niet aantoonbaar geschreven"'
mk; echo 2 > "$A/bootcount"; amount; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480; guard
chk "proven: aapa-mount met verkeerde inhoud (md5 via pad) -> gezond maar niet geteld" '[ "$(cnt)" = 0 -a ! -e "$A/proven" ] && glg "md5 via pad is niet de patch"'
mk; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: niets gemount -> niet geteld" '[ ! -e "$A/proven" ] && glg "geen doel gemount"'
mk; early; echo bootcount > "$T/flags/mv_fail"; echo 1 > "$A/bootcount"; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: bootcount-reset mislukt -> niet geteld" '[ ! -e "$A/proven" ] && glg "bootcount niet op 0"'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; early; setproc init sshd; echo "300.0 1" > "$R/uptime"; guard
chk "proven + usbmgr dood -> proven INGETROKKEN + 'disabled'" '[ ! -e "$A/proven" -a -e "$A/disabled" -a "$(cnt)" = 0 ] && glg "proven-record ingetrokken"'
reboot; early
chk "proven ingetrokken: volgende boot stock (disabled)" '[ "$(sod)" = "$O" ]'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=7 %s\nrec=8 %s\n' "$FPB" "$FPU"; early; setproc init L_jciUSBMGR sshd; echo "480.0 1" > "$R/uptime"; guard
chk "proven + alleen aapa dood -> proven ingetrokken + DISABLE_AAPA (geen disabled)" '[ ! -e "$A/proven" -a -f "$A/DISABLE_AAPA" -a ! -e "$A/disabled" -a "$(cnt)" = 0 ] && glg "alleen aapa schuldig"'
: > "$A/early.log"; reboot; early
chk "na intrekken: volgende boot alleen usbmgr en WEER geteld (1)" '[ "$(sod)" = "$P" -a "$(soa)" = "$OA" -a "$(cnt)" = 1 ] && ! lg "proven mode"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=7 %s\n' "$FPB"; early; setproc init L_jciUSBMGR sshd L_jciAAPA; echo "420.0 1" > "$R/uptime"; tick 450 480
echo "rm -rf '$R/proc/104'" > "$T/flags/onsleep"; guard
chk "proven + aapa sterft na eerste beoordeling -> ingetrokken + DISABLE_AAPA" '[ ! -e "$A/proven" -a -f "$A/DISABLE_AAPA" ]'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; early; setproc init sshd; echo "200.0 1" > "$R/uptime"; guard
chk "proven: ongezond op 200 s (nog herkansing) -> record blijft" '[ -e "$A/proven" -a ! -e "$A/disabled" ]'
mk; early; setproc init sshd; echo "300.0 1" > "$R/uptime"; guard
chk "geen proven-record + ongezond -> geen intrek-melding, wel disabled" '[ -e "$A/disabled" ] && ! glg "proven-record"'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; early; mkdir -p "$R/stick/sdb1"; touch "$R/stick/sdb1/AA_BUSPATCH_DISABLE"; echo "50.0 1" > "$R/uptime"; guard; reboot; early
chk "proven: stick-kill-switch werkt ook in proven mode" '[ -s "$A/DISABLE" -a "$(sod)" = "$O" ]'

# aa-status
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; early; wp 'short=1\nrec=5 %s\n' "$FPU"; run aa-status.sh > "$T/st.out" 2>&1
chk "status: proven JA 5/5 + record getoond" 'grep -q "proven           : JA  5/5" "$T/st.out" && grep -q "boots op rij zonder oordeel 1/20" "$T/st.out" && grep -q "record         : 5x usbmgr " "$T/st.out"'
wp 'short=0\nrec=2 %s\n' "$FPU"; run aa-status.sh > "$T/st.out" 2>&1
chk "status: opbouw 2/5 -> nee" 'grep -q "proven           : nee 2/5" "$T/st.out"'
echo kapot > "$A/proven"; run aa-status.sh > "$T/st.out" 2>&1
chk "status: ongeldig bestand gemeld" 'grep -q "ONGELDIG" "$T/st.out"'
echo PROVEN_N=0 > "$A/aa.conf"; run aa-status.sh > "$T/st.out" 2>&1; rm -f "$A/aa.conf"
chk "status: PROVEN_N=0 -> UIT" 'grep -q "proven           : UIT" "$T/st.out"'
rm -f "$A/proven"; run aa-status.sh > "$T/st.out" 2>&1
chk "status: geen record" 'grep -q "nog geen record; drempel 5" "$T/st.out"'
wp 'short=0\nrec=5 %s\n' "$FPU"; run aa-status.sh unprove > "$T/up.out" 2>&1; rc=$?
chk "unprove: record weg, exit 0" '[ $rc -eq 0 -a ! -e "$A/proven" ] && grep -q "strikt" "$T/up.out"'
reboot; early
chk "na unprove: volgende boot weer geteld" '[ "$(cnt)" = 2 ] && ! lg "proven mode"'
wp 'short=0\nrec=5 %s\n' "$FPU"; chmod 555 "$A"; run aa-status.sh unprove > "$T/up.out" 2>&1; rc=$?; chmod 755 "$A"
chk "unprove op read-only -> fout gemeld" '[ $rc -ne 0 ] && grep -q "niet verwijderd" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; wp 'short=0\nrec=5 %s\n' "$FPU"; echo x > "$A/disabled"; echo 3 > "$A/bootcount"; run aa-status.sh rearm > /dev/null 2>&1
chk "rearm laat proven-record staan" 'pv "^rec=5 $FPU$" && [ "$(cnt)" = 0 ]'
rm -f "$A/disabled"; run aa-status.sh arm-aapa > /dev/null 2>&1
chk "arm-aapa laat record staan; fingerprint (usbmgr+aapa) heeft nog geen record -> tellen" 'pv "^rec=5 $FPU$" && [ ! -e "$A/DISABLE_AAPA" ]'
rm -f "$A/DISABLE"; reboot; early
chk "na arm-aapa: nieuwe combinatie -> geteld (1)" '[ "$(cnt)" = 1 -a "$(soa)" = "$PA" ] && lg "geen record voor deze combinatie"'

# install --keep-aapa (upgrade v3 -> 3.1)
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE" "$A/DISABLE_AAPA"; wp 'short=0\nrec=1 %s\n' "$FPB"; echo "# oude v3" >> "$A/aa-early.sh"
cp "$UD" "$T/ud.before"; cp -r "$T/kit" "$A/stage"; : > "$T/mount.calls"
PATH="$T/bin:$PATH" $SUT "$A/stage/aa-install.sh" --keep-aapa > "$T/up.out" 2>&1; rc=$?
chk "upgrade --keep-aapa: exit 0, aapa blijft gewapend, rootfs niet aangeraakt, stage weg" '[ $rc -eq 0 -a ! -e "$A/DISABLE_AAPA" -a ! -e "$A/DISABLE" -a ! -d "$A/stage" ] && cmp -s "$UD" "$T/ud.before" && ! calls remount && grep -q "aapa: gewapend (blijft gewapend)" "$T/up.out"'; [ $rc -eq 0 ] || cat "$T/up.out"
chk "L2: upgrade --keep-aapa: bestanden nieuw, proven-record verwijderd" 'cmp -s "$A/aa-early.sh" "$T/kit/aa-early.sh" && [ ! -e "$A/proven" ] && grep -q "proven-record: verwijderd" "$T/up.out"'
reboot; early
chk "upgrade --keep-aapa: volgende boot beide gepatcht, geteld (geen record)" '[ "$(sod)" = "$P" -a "$(soa)" = "$PA" -a "$(cnt)" = 1 ]'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; cp -r "$T/kit" "$A/stage"; run aa-install.sh --keep-aapa > "$T/up.out" 2>&1; rc=$?
chk "upgrade --keep-aapa met aapa UIT -> blijft UIT" '[ $rc -eq 0 -a -e "$A/DISABLE_AAPA" ] && grep -q "aapa: UIT" "$T/up.out"'
mk; run aa-install.sh --keep-aapa > "$T/up.out" 2>&1; rc=$?
chk "--keep-aapa bij verse installatie -> geweigerd, usb_drivers.sh stock" '[ $rc -ne 0 ] && cmp -s "$UD" "$STOCK_UD" && grep -q "alleen bij een upgrade" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE_AAPA"; sed -i "/^TARGET_AAPA=/d" "$A/aa-early.sh"; cp -r "$T/kit" "$A/stage"; run aa-install.sh --keep-aapa > "$T/up.out" 2>&1; rc=$?
chk "--keep-aapa vanaf v2-aa-early -> geweigerd, niets geplaatst, aapa-stand ongewijzigd" '[ $rc -ne 0 -a ! -e "$A/DISABLE_AAPA" -a -d "$A/stage" ] && grep -q "nog geen v3" "$T/up.out"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE_AAPA"; printf x >> "$A/blmjciaapa.so.patched"; cp -r "$T/kit" "$A/stage"; run aa-install.sh --keep-aapa > "$T/up.out" 2>&1; rc=$?
chk "--keep-aapa met kapotte geïnstalleerde aapa-payload -> geweigerd" '[ $rc -ne 0 ] && grep -q "aapa-payload klopt niet" "$T/up.out"'
mk; run aa-install.sh --bla > "$T/up.out" 2>&1; rc=$?
chk "install: onbekende optie -> geweigerd" '[ $rc -ne 0 ] && cmp -s "$UD" "$STOCK_UD"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=5 %s\n' "$FPU"; run aa-install.sh > /dev/null 2>&1
chk "L2: gewone herinstallatie (upgrade): aapa weer UIT, proven-record verwijderd" '[ -e "$A/DISABLE_AAPA" -a ! -e "$A/proven" ]'
mk; run aa-install.sh > /dev/null 2>&1; wp 'short=0\nrec=5 %s\n' "$FPU"; run aa-uninstall.sh --purge > /dev/null 2>&1
chk "uninstall --purge verwijdert proven-record" '[ ! -e "$A/proven" ]'

# ---------- 13 review 4 (kit 3.1) ----------
# M2: mount faalt bij verificatie EN umount mislukt -> in proven mode toch strikt tellen
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; echo "rw,noexec" > "$T/flags/bindopts"; touch "$T/flags/fail_umount"; early
chk "M2: proven + noexec + umount faalt -> bootcount 1 (strikt), short terug op 0" '[ "$(cnt)" = 1 ] && lg "umount mislukt" && lg "mount niet geverifieerd en niet te unmounten -> toch geteld: bootcount 0 -> 1" && pv "^short=0$" && lg "proven=0"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=1\nrec=7 %s\n' "$FPB"; echo "rw,noexec" > "$T/flags/bindopts.blmjciaapa.so"; touch "$T/flags/fail_umount.blmjciaapa.so"; early
chk "M2: proven (beide) + alleen aapa noexec + umount faalt -> actieve set gelijk, toch geteld (1)" '[ "$(cnt)" = 1 -a "$(sod)" = "$P" ] && lg "mount niet geverifieerd" && pv "^short=1$"'
reboot; touch "$T/flags/fail_umount"; early; reboot; early; reboot; early
chk "M2: zelfde fout elke boot -> na 3 boots disabled + stock (geen 23)" '[ -e "$A/disabled" -a "$(sod)" = "$O" ]'
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; echo "rw,noexec" > "$T/flags/bindopts"; early
chk "M2: proven + noexec maar umount lukt -> niets actief, teller 0, short terug 0" '[ "$(cnt)" = 0 -a "$(sod)" = "$O" ] && pv "^short=0$"'
# L1: actieve set wijkt af + bootcount niet schrijfbaar -> short blijft PS0+1 (boot geteld voor MAXSHORT)
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=2\nrec=7 %s\n' "$FPB"; printf 'x' >> "$SOA"; echo "aa/bootcount" > "$T/flags/mv_fail"; early
chk "L1: set wijkt af + bootcount faalt -> short blijft 3, teller 0, gemeld" '[ "$(sod)" = "$P" -a "$(cnt)" = 0 ] && pv "^short=3$" && lg "bootcount niet aantoonbaar geschreven (LET OP) -> short blijft 3"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=2\nrec=7 %s\n' "$FPB"; printf 'x' >> "$SOA"; early
chk "L1: set wijkt af -> bootcount eerst (log vóór short-reset), short terug op 2" '[ "$(cnt)" = 1 ] && pv "^short=2$" && ! lg "short niet teruggezet"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=2\nrec=7 %s\n' "$FPB"; printf 'x' >> "$SOA"; echo "aa/bootcount" > "$T/flags/mv_fail"; reboot; printf 'x' >> "$SOA"
k=0; while [ $k -lt 18 ]; do early; reboot; printf 'x' >> "$SOA"; k=$((k + 1)); done; rm -f "$T/flags/mv_fail"; early
chk "L1: bootcount blijvend onschrijfbaar -> short loopt op tot MAXSHORT -> proven ingetrokken" '[ ! -e "$A/proven" -a "$(cnt)" = 1 ] && lg "proven ingetrokken"'
# L2: disarm / disarm-aapa verwijderen proven; arm / arm-aapa zetten het niet terug; verse installatie wist
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; wp 'short=0\nrec=5 %s\n' "$FPU"; run aa-status.sh disarm > "$T/d.out" 2>&1; rc=$?
chk "L2: disarm -> DISABLE + proven-record weg" '[ $rc -eq 0 -a -s "$A/DISABLE" -a ! -e "$A/proven" ] && grep -q "proven-record verwijderd" "$T/d.out"'
echo "aa-early v3 start" >> "$A/early.log"; run aa-status.sh arm > /dev/null 2>&1; rc=$?
chk "L2: arm daarna -> gewapend, proven-record NIET terug" '[ $rc -eq 0 -a ! -e "$A/DISABLE" -a ! -e "$A/proven" ]'
reboot; early
chk "L2: na disarm+arm wordt weer strikt geteld" '[ "$(cnt)" = 1 ] && ! lg "proven mode"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE" "$A/DISABLE_AAPA"; wp 'short=0\nrec=5 %s\nrec=6 %s\n' "$FPU" "$FPB"; run aa-status.sh disarm-aapa > "$T/d.out" 2>&1; rc=$?
chk "L2: disarm-aapa -> DISABLE_AAPA + hele proven-record weg (scenario F)" '[ $rc -eq 0 -a -s "$A/DISABLE_AAPA" -a ! -e "$A/proven" ]'
run aa-status.sh arm-aapa > /dev/null 2>&1; rc=$?
chk "L2: arm-aapa daarna -> gewapend, record NIET terug" '[ $rc -eq 0 -a ! -e "$A/DISABLE_AAPA" -a ! -e "$A/proven" ]'
reboot; early
chk "L2: na disarm-aapa+arm-aapa: combinatie 'beide' telt weer strikt" '[ "$(cnt)" = 1 -a "$(soa)" = "$PA" ] && ! lg "proven mode"'
mk; run aa-install.sh > /dev/null 2>&1; rm -f "$A/DISABLE"; run aa-status.sh disarm > "$T/d.out" 2>&1
chk "L2: disarm zonder record -> geen verwijdermelding" '[ -s "$A/DISABLE" ] && ! grep -q "proven" "$T/d.out"'
mk; wp 'short=0\nrec=9 %s\n' "$FPU"; touch "$A/proven.tmp"; run aa-install.sh > "$T/i.out" 2>&1; rc=$?
chk "L2: verse installatie met bestaand record (scenario P) -> record + tmp weg" '[ $rc -eq 0 -a ! -e "$A/proven" -a ! -e "$A/proven.tmp" ] && grep -q "Modus: fresh" "$T/i.out"'
# M1: PROVEN_MAXSHORT bovengrens 30
mk; echo PROVEN_MAXSHORT=30 > "$A/aa.conf"; wp 'short=25\nrec=7 %s\n' "$FPU"; early
chk "M1: PROVEN_MAXSHORT=30 geaccepteerd (short 25 -> nog proven)" '[ "$(cnt)" = 0 ] && lg "26/30"'
mk; echo PROVEN_MAXSHORT=31 > "$A/aa.conf"; wp 'short=25\nrec=7 %s\n' "$FPU"; early
chk "M1: PROVEN_MAXSHORT=31 genegeerd -> standaard 20 -> ingetrokken" '[ "$(cnt)" = 1 ] && lg "(>= 20)"'
mk; echo PROVEN_MAXSHORT=50 > "$A/aa.conf"; wp 'short=0\nrec=5 %s\n' "$FPU"; early; run aa-status.sh > "$T/st.out" 2>&1
chk "M1: status negeert PROVEN_MAXSHORT=50 (toont /20)" 'grep -q "zonder oordeel 1/20" "$T/st.out"'
mk; rm -f "$A/DISABLE_AAPA"; wp 'short=0\nrec=5 %s\n' "$FPB"; k=0; while [ $k -lt 40 ]; do reboot; early; k=$((k + 1)); [ "$(sod)" = "$O" ] && break; done
chk "M1: crashlus in proven mode (standaard) -> 23 gepatchte boots, 24e stock" '[ $k -eq 24 -a -e "$A/disabled" ]'
# L3: geen stderr-lek bij mislukte redirect; guard-logregel onafhankelijk van schrijfvolgorde
mk; wp 'short=0\nrec=7 %s\n' "$FPU"; chmod 555 "$A"; PATH="$T/bin:$PATH" $SUT "$A/aa-early.sh" 2> "$T/err.out"; chmod 755 "$A"
chk "L3: proven + read-only -> geen shellmelding op stderr" '! grep -q "proven" "$T/err.out"'
mk; wp 'short=0\nrec=4 %s\nrec=2 %s\n' "$FPU" "$FPB"; early; setproc L_jciUSBMGR sshd; echo "200.0 1" > "$R/uptime"; guard
chk "L3: guard logt het juiste aantal (5) met meerdere records" 'glg "gezonde boot 5 (drempel 5) voor usbmgr=1 aapa=0 -> PROVEN" && pv "^rec=5 $FPU$" && pv "^rec=2 $FPB$"'
chk "L3: guard-logregel gebruikt eigen variabele (pc_new)" 'grep -q "gezonde boot \$pc_new" "$HERE/scripts/aa-guard.sh"'

echo "== $pass geslaagd, $fail mislukt"
chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"
[ $fail -eq 0 ]

