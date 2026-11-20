#!/usr/bin/env python3
"""can-summary.py <raw-candump-file|-> [kcd] -- count CAN-ID frequencies and map names from a KCD.

Output (sorted by count desc):
  count   0xID   name (bus)   [in KCD / UNKNOWN]
Usage: can-sniff.sh calls this automatically; standalone:
  candump can0 > /tmp/x.raw  (a few sec), then: python3 can-summary.py /tmp/x.raw mazda-can-unified.kcd
"""
import sys, re, collections
import xml.etree.ElementTree as ET

NS = "{http://kayak.2codeornot2code.org/1.0}"

def kcd_names(path):
    names = {}
    try:
        for bus in ET.parse(path).getroot().iter(NS + "Bus"):
            bname = bus.get("name") or "?"
            for m in bus.iter(NS + "Message"):
                mid = int(m.get("id"), 16)
                names.setdefault(mid, (m.get("name") or "?", bname))
    except Exception as e:
        print(f"# KCD not readable ({e}) -- ID counting only", file=sys.stderr)
    return names

def main():
    raw = sys.argv[1] if len(sys.argv) > 1 else "-"
    kcd = sys.argv[2] if len(sys.argv) > 2 else "mazda-can-unified.kcd"
    names = kcd_names(kcd)
    counts = collections.Counter()
    total = 0
    fh = sys.stdin if raw == "-" else open(raw, "r", errors="replace")
    for line in fh:
        m = re.search(r"\bcan\d+\s+([0-9A-Fa-f]{2,8})\b", line)
        if m:
            counts[int(m.group(1), 16)] += 1
            total += 1
    if raw != "-":
        fh.close()
    print(f"# total {total} frames, {len(counts)} unique IDs")
    print(f"# {'count':>8}  {'ID':<6} name (bus)")
    for mid, c in counts.most_common():
        nm, bus = names.get(mid, ("<unknown>", "?"))
        print(f"{c:>8}  0x{mid:03X}  {nm} ({bus})")

if __name__ == "__main__":
    main()
