#!/bin/sh
# gui-status.sh [status|disable|enable|unmount]
G=/data_persist/dev/gui; T=/jci/gui/apps/system/js/systemApp.js
case "$1" in
  disable) touch $G/DISABLE; echo "DISABLE gezet (volgende boot stock)";;
  enable)  rm -f $G/DISABLE; echo 0 > $G/bootcount; echo "weer actief vanaf volgende boot";;
  unmount) umount $T && echo "umount OK (GUI herladen of reboot om stock te zien)";;
  *) echo "mount   : $(grep -c " $T " /proc/mounts) ($(md5sum $T | cut -d' ' -f1))"
     echo "DISABLE : $([ -f $G/DISABLE ] && cat $G/DISABLE || echo nee)"
     echo "teller  : $(cat $G/bootcount 2>/dev/null) proven $(cat $G/proven 2>/dev/null)/3"
     echo "inetd   : $(netstat -ltn 2>/dev/null | grep -c 127.0.0.1:9997)"
     tail -6 $G/early.log;;
esac
