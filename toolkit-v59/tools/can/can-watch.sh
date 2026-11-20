#!/bin/sh
# can-watch.sh [iface] [kcd] -- live human-readable CAN on the CMU.
# Optional ID filter:  CAN_IDS="202 215 228" can-watch.sh can0
# Stop with Ctrl-C. Output = one line per frame with decoded signals.
# Requires: candump + python3 on the CMU, and a KCD database next to this script.
IFACE="${1:-can0}"
KCD="${2:-$(dirname "$0")/mazda-can-unified.kcd}"
DIR="$(dirname "$0")"

echo "# Live CAN decode on $IFACE with $(basename "$KCD")" >&2
if [ -n "$CAN_IDS" ]; then
  IDS=""
  for i in $CAN_IDS; do IDS="$IDS,$i"; done
  IDS="${IDS#,}"
  candump "$IFACE" -f "$IDS" 2>/dev/null | python3 "$DIR/kcd_decode.py" "$KCD" --compact
else
  candump "$IFACE" 2>/dev/null | python3 "$DIR/kcd_decode.py" "$KCD" --compact
fi
