#!/bin/sh
# install-terminal.sh (run ON the CMU as root) - install the permanent "Terminal" item in Applications (v74).
#
# Usage:  copy this folder (with the systemApp.js.patched you built on the PC) to the CMU, then:
#         sh install-terminal.sh [source-dir]          (default: the directory of this script)
#
# Writes ONLY to /data_persist (never to the rootfs):
#   /data_persist/dev/gui/        gui-early.sh, gui-status.sh, systemApp.js.patched
#   /data_persist/dev/bin/        mzd-terminal-trigger.sh, mzd-inetd.conf (127.0.0.1:9997 -> trigger)
# Started at every boot by the boot hook of the Android Auto kit (toolkit-v74/aa, aa-early.sh).
# Takes effect after the next reboot. Undo: sh /data_persist/dev/gui/gui-status.sh disable
SRC=${1:-$(cd "$(dirname "$0")" && pwd)}
G=/data_persist/dev/gui; B=/data_persist/dev/bin
PATCH=8e02903549579fbe98f195ce567c00ef
STOCK=383d7e688256e09b825ced9e3eb69ee9
T=/jci/gui/apps/system/js/systemApp.js
die() { echo "ERROR: $*" >&2; exit 1; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

[ "$(id -u)" = 0 ] || die "run as root"
grep -q '74\.00' /jci/version.ini 2>/dev/null || die "not firmware v74 - this patch is v74.00.324 only"
[ "$(md5 $T)" = $STOCK ] || grep -q " $T " /proc/mounts || die "stock systemApp.js md5 differs ($(md5 $T)) - wrong firmware?"
for f in gui-early.sh gui-status.sh systemApp.js.patched mzd-terminal-trigger.sh; do
    [ -f "$SRC/$f" ] || die "$SRC/$f missing (build systemApp.js.patched on the PC first: make-patched-systemapp.py)"
done
[ "$(md5 "$SRC/systemApp.js.patched")" = $PATCH ] || die "systemApp.js.patched md5 wrong - rebuild it with make-patched-systemapp.py"
for f in gui-early.sh gui-status.sh mzd-terminal-trigger.sh; do sh -n "$SRC/$f" || die "syntax error in $f"; done

mkdir -p $G $B || die "cannot create $G / $B"
cp "$SRC/gui-early.sh" "$SRC/gui-status.sh" "$SRC/systemApp.js.patched" $G/ || die "copy to $G failed"
cp "$SRC/mzd-terminal-trigger.sh" $B/ || die "copy to $B failed"
chmod 755 $G/gui-early.sh $G/gui-status.sh $B/mzd-terminal-trigger.sh
echo "127.0.0.1:9997 stream tcp nowait cmu /bin/sh sh $B/mzd-terminal-trigger.sh" > $B/mzd-inetd.conf
[ "$(md5 $G/systemApp.js.patched)" = $PATCH ] || die "copy of systemApp.js.patched is corrupt"
rm -f $G/DISABLE; echo 0 > $G/bootcount
sync
echo "Installed in $G and $B."
if grep -q 'gui-early.sh' /data_persist/dev/aa/aa-early.sh 2>/dev/null; then
    echo "Boot hook found (AA kit aa-early.sh). Reboot the CMU (Mute+Navi 10 s): 'Terminal' appears in Applications."
else
    echo "WARNING: no boot hook. Install the AA kit (toolkit-v74/aa, kit 3.2+) - its aa-early.sh starts gui-early.sh."
fi
echo "Status: sh $G/gui-status.sh   Undo: sh $G/gui-status.sh disable (next boot stock)"
