#!/bin/sh
# can-sniff.sh [iface] [secs] [outfile]
# Short CAN sniff on the CMU: which message IDs are actually alive on the bus,
# with counts and KCD names. Useful before a long logging session to validate
# which IDs this particular car transmits (the KCD comes from another Mazda3).
#
# Example:  sh can-sniff.sh can0 30 /tmp/sniff30
# Output:   count/ID/name table to stdout (and to outfile), raw to outfile.raw
DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE="${1:-}"
SECS="${2:-30}"
OUT="${3:-}"
[ -z "$IFACE" ] && IFACE="$(ls /sys/class/net 2>/dev/null | grep '^can' | head -n 1)"
KCD="$DIR/mazda-can-unified.kcd"
RAW="$(mktemp /tmp/sniff.XXXXXX 2>/dev/null || echo /tmp/sniff.$$)"

echo "# sniff ${SECS}s on ${IFACE:-NO-IFACE} -> $RAW" >&2
if [ -z "$IFACE" ]; then echo "ERROR: no can* interface in /sys/class/net" >&2; exit 1; fi
command -v candump >/dev/null 2>&1 || { echo "ERROR: candump not present" >&2; exit 1; }

timeout "$SECS" candump "$IFACE" > "$RAW" 2>/dev/null
echo "# raw frames: $(wc -l < "$RAW")" >&2
python3 "$DIR/can-summary.py" "$RAW" "$KCD"
if [ -n "$OUT" ]; then
    python3 "$DIR/can-summary.py" "$RAW" "$KCD" > "$OUT" 2>/dev/null
    cp "$RAW" "$OUT.raw"
    echo "# written: $OUT + $OUT.raw" >&2
fi
