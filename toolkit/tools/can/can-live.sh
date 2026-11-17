#!/bin/sh
# can-live.sh [can-iface] [kcd-file] -- older alias for live decode with
# skyactive_new.kcd; prefer can-watch.sh, which defaults to mazda-can-unified.kcd.
# Requires: candump (busybox/iproute2) and python3 on the CMU.
IFACE="${1:-can0}"
KCD="${2:-$(dirname "$0")/skyactive_new.kcd}"
SCRIPT_DIR="$(dirname "$0")"

echo "# Live decode on $IFACE with $KCD" >&2
candump "$IFACE" 2>/dev/null | python3 "$SCRIPT_DIR/kcd_decode.py" "$KCD"
