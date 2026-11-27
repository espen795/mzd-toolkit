#!/bin/sh
# gui-early.sh v1 (2026-11-27) — OEMPLUS Terminal-item in Applicaties, RAM-only.
# Gestart op de achtergrond door aa-early.sh (boot-hook usb_drivers.sh, ~10 s), dus vóór Opera (~14 s).
# Doet: md5-checks -> kopie naar /tmp -> bind-mount over systemApp.js -> inetd 127.0.0.1:9997.
# Schrijft NOOIT naar de rootfs. Faalt altijd open (stock). Uitzetten: touch $G/DISABLE.
# Crash-guard: teller voor de mount; gezond = Opera leeft op 180 s -> teller 0. 3x op rij niet
# gezond -> DISABLE. Na 3 gezonde boots (proven) telt een korte boot niet meer.
G=/data_persist/dev/gui
T=/jci/gui/apps/system/js/systemApp.js
TMPD=/tmp/gui-early
STOCK=383d7e688256e09b825ced9e3eb69ee9     # systemApp.js MAZ_CMU-150_74.00.324
PATCH=8e02903549579fbe98f195ce567c00ef     # + Terminal-item (grijs tijdens rijden)
INETD_CONF=/data_persist/dev/bin/mzd-inetd.conf
MAXFAIL=3; PROVEN_N=3; HEALTHY_AT=180; MAXUP=60
LOG=$G/early.log
up() { cut -d. -f1 /proc/uptime; }
l() { echo "[$(up)s] $*" >> $LOG; }
num() { v=$(cat "$1" 2>/dev/null); case "$v" in ''|*[!0-9]*) echo 0;; *) echo "$v";; esac; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

[ -d $G ] || exit 0
if [ -f $LOG ] && [ "$(wc -c < $LOG)" -gt 20000 ]; then tail -c 8000 $LOG > $LOG.tmp && mv $LOG.tmp $LOG; fi
l "---- boot ---- gui-early v1"
[ "$(up)" -le $MAXUP ] || [ "$1" = "--manual" ] || { l "uptime > ${MAXUP}s en niet --manual -> niets"; exit 0; }
[ -f $G/DISABLE ] && { l "DISABLE aanwezig -> stock"; exit 0; }
grep -q " $T " /proc/mounts && { l "al gemount -> niets"; exit 0; }

n=$(num $G/bootcount); p=$(num $G/proven)
if [ "$n" -ge $MAXFAIL ]; then l "bootcount $n >= $MAXFAIL -> DISABLE"; echo "auto $(date)" > $G/DISABLE; exit 0; fi
if [ "$p" -lt $PROVEN_N ]; then
    echo $((n + 1)) > $G/bootcount; sync
    [ "$(num $G/bootcount)" = $((n + 1)) ] || { l "teller niet schrijfbaar -> stock"; exit 0; }
    l "bootcount $n -> $((n + 1)) (max $MAXFAIL), proven $p/$PROVEN_N"
else
    l "proven $p/$PROVEN_N -> teller niet opgehoogd ($n)"
fi

[ "$(md5 $T)" = $STOCK ] || { l "stock-md5 wijkt af ($(md5 $T)) -> skip"; exit 0; }
mkdir -p $TMPD && cp $G/systemApp.js.patched $TMPD/systemApp.js
[ "$(md5 $TMPD/systemApp.js)" = $PATCH ] || { l "patch-md5 fout -> skip"; rm -f $TMPD/systemApp.js; exit 0; }
mount --bind $TMPD/systemApp.js $T || { l "mount faalt -> stock"; exit 0; }
if [ "$(md5 $T)" = $PATCH ]; then l "systemApp.js gemount (opera nog niet gestart: $( [ -z "$(pidof opera)" ] && echo ja || echo NEE ))"
else umount $T 2>/dev/null; l "verificatie faalt -> umount"; exit 0; fi

# inetd-trigger + gezond-check (achtergrond)
(
  sleep 20
  if [ -f $INETD_CONF ] && ! pgrep -f mzd-inetd.conf >/dev/null 2>&1; then
      /usr/sbin/inetd -e -f $INETD_CONF </dev/null >/dev/null 2>&1 &
      sleep 2; netstat -ltn 2>/dev/null | grep -q "127.0.0.1:9997" && l "inetd luistert op 9997" || l "inetd start mislukt"
  fi
  while [ "$(up)" -lt $HEALTHY_AT ]; do sleep 10; done
  if pidof opera >/dev/null 2>&1 && grep -q " $T " /proc/mounts; then
      echo 0 > $G/bootcount; p=$(num $G/proven); [ "$p" -lt 99 ] && echo $((p + 1)) > $G/proven; sync
      l "gezond op $(up)s (opera $(pidof opera)) -> bootcount 0, proven $(num $G/proven)"
  else
      l "NIET gezond op $(up)s (opera=$(pidof opera)) -> teller blijft"
  fi
) </dev/null >/dev/null 2>&1 &
exit 0
