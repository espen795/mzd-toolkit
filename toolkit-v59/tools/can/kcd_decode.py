#!/usr/bin/env python3
"""Decode Mazda HS-CAN frames using a Kayak KCD file (e.g. mazda-can-unified.kcd).

Usage on the CMU (or locally with candump output):
  candump can0 | python3 kcd_decode.py mazda-can-unified.kcd
  echo "can0 215 [8] 01 02 ..." | python3 kcd_decode.py mazda-can-unified.kcd
  ... | python3 kcd_decode.py mazda-can-unified.kcd --compact   # one line per frame

KCD = XML: <Message id="0x215" name="Wheel Speed" length="8"><Signal name=.. offset=.. length=../></Message>
Bit numbering in KCD (Kayak) is Motorola big-endian style: offset = MSB bit index.
"""
import sys, re, xml.etree.ElementTree as ET

NS = "{http://kayak.2codeornot2code.org/1.0}"

def load_kcd(path):
    tree = ET.parse(path)
    msgs = {}
    for bus in tree.getroot().iter(NS + "Bus"):
        busname = bus.get("name")
        for m in bus.iter(NS + "Message"):
            mid = int(m.get("id"), 16)
            sigs = []
            for s in m.iter(NS + "Signal"):
                val = s.find(NS + "Value")
                slope = float(val.get("slope", "1")) if val is not None and val.get("slope") else 1.0
                intercept = float(val.get("intercept", "0")) if val is not None and val.get("intercept") else 0.0
                notes_el = s.find(NS + "Notes")
                sigs.append({
                    "name": s.get("name"),
                    "offset": int(s.get("offset", "0")),
                    "length": int(s.get("length", "1")),
                    "big": s.get("endianess", "little") == "big",
                    "slope": slope, "intercept": intercept,
                    "notes": (notes_el.text if notes_el is not None and notes_el.text else ""),
                })
            msgs[mid] = {"name": m.get("name"), "len": int(m.get("length", "8")), "bus": busname, "signals": sigs}
    return msgs

def extract(data_bytes, sig):
    """Extract signal value from data bytes. KCD offset = bit index from MSB (Motorola)."""
    off, ln, big = sig["offset"], sig["length"], sig["big"]
    if big:
        # Motorola: offset is MSB position in big-endian bit numbering across the whole message
        val = 0
        for i in range(ln):
            bitpos = off + i
            byte_i = bitpos // 8
            bit_i = 7 - (bitpos % 8)
            if byte_i < len(data_bytes):
                val = (val << 1) | ((data_bytes[byte_i] >> bit_i) & 1)
    else:
        # Intel/little-endian: offset is LSB bit index
        val = 0
        for i in range(ln):
            bitpos = off + i
            byte_i = bitpos // 8
            bit_i = bitpos % 8
            if byte_i < len(data_bytes):
                val |= ((data_bytes[byte_i] >> bit_i) & 1) << i
    return val * sig["slope"] + sig["intercept"]

def decode_line(line, msgs, compact=False):
    # candump formats: "can0  215   [8]  01 02 03 ..." or "(2026-..) can0 215#0102..."
    m = re.search(r"\b([0-9A-Fa-f]{3,8})\s+(?:\[\d+\]\s+)?([0-9A-Fa-f ]+)|([0-9A-Fa-f]{3,8})#([0-9A-Fa-f]+)", line)
    if not m:
        return None
    if m.group(1):
        can_id = int(m.group(1), 16)
        data = bytes.fromhex(re.sub(r"\s+", "", m.group(2)))
    else:
        can_id = int(m.group(3), 16)
        data = bytes.fromhex(m.group(4))
    msg = msgs.get(can_id)
    if not msg:
        return f"0x{can_id:03X}  <unknown>  {data.hex()}"
    if compact:
        # one line: only signals with a non-zero/meaningful value or a scale factor
        parts = []
        for s in msg["signals"]:
            v = extract(data, s)
            if v != 0 or s["slope"] != 1:
                parts.append(f"{s['name']}={v:g}")
        return f"0x{can_id:03X} {msg['name']}: " + (" ".join(parts) if parts else "(all zero)")
    out = [f"0x{can_id:03X} {msg['name']}"]
    for s in msg["signals"]:
        v = extract(data, s)
        out.append(f"  {s['name']} = {v:g}" + (f"   ; {s['notes']}" if s["notes"] else ""))
    return "\n".join(out)

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    compact = "--compact" in sys.argv
    kcd = args[0] if args else "mazda-can-unified.kcd"
    msgs = load_kcd(kcd)
    print(f"# loaded {len(msgs)} CAN messages from {kcd}", file=sys.stderr)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        r = decode_line(line, msgs, compact=compact)
        if r:
            print(r)
