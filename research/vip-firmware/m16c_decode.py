#!/usr/bin/env python3
"""Context dump around candidate CAN-SFR access sites in a flat M16C binary.

Usage: python3 -I m16c_decode.py <flat-bin> <addr...> [base] [before] [after]

For each address, prints the bytes before/after. Exact M16C opcode tables are
not embedded here (no M16C disassembler was available), so this dumps raw
context and annotates any 16-bit LE value in 0xD000-0xDFFF, letting a human
read the instruction stream. See README.md.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'vip_app.bin'
addrs = [int(x, 0) for x in sys.argv[2:]] or [0xC0000]
base = 0xC0000
before = 24
after = 24
# allow overriding base/before/after via env-style trailing args is kept simple:
data = open(path, 'rb').read()

def ctx(off, before=24, after=24):
    lo = max(0, off - base - before); hi = min(len(data), off - base + after)
    return lo + base, data[lo:hi]

for s in addrs:
    a, b = ctx(s, before, after)
    print(f"\n=== site {s:#x} (file off {s - base:#x})")
    for i in range(0, len(b), 16):
        chunk = b[i:i + 16]
        addr = a + i
        marks = []
        for j in range(len(chunk) - 1):
            v = chunk[j] | (chunk[j + 1] << 8)
            if 0xD000 <= v <= 0xDFFF:
                marks.append(f"@{addr + j:#x}={v:#06x}")
        line = f"  {addr:#07x}: " + ' '.join(f'{x:02x}' for x in chunk)
        if marks:
            line += "   ; " + " ".join(marks)
        print(line)
