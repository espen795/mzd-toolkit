#!/bin/sh
# can-capture.sh [iface] [duration-seconds] [outfile]
# Capture raw CAN frames on the CMU and decode them immediately with the KCD.
# Defaults: can0, 30 s, can-capture-<timestamp>.log in the same dir as this script.
# Requires: candump + python3 on the CMU.
IFACE="${1:-can0}"
DURATION="${2:-30}"
OUT="${3:-$(dirname "$0")/can-capture-$(date +%Y%m%d-%H%M%S).log}"
KCD="$(dirname "$0")/mazda-can-unified.kcd"
DIR="$(dirname "$0")"

echo "# Capture ${DURATION}s on $IFACE -> $OUT (raw + decoded)" >&2
{
  echo "# can-capture $IFACE $(date -Is) duration=${DURATION}s kcd=$(basename "$KCD")"
  timeout "$DURATION" candump "$IFACE" 2>/dev/null | tee "$OUT.raw" | python3 "$DIR/kcd_decode.py" "$KCD"
} > "$OUT" 2>"$OUT.err"
echo "# Done: $OUT ($(wc -l < "$OUT") lines), raw: $OUT.raw" >&2
