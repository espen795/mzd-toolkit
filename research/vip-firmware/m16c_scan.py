#!/usr/bin/env python3
"""M16C/60 (M16C/60 series) SFR-access scanner for a flat VIP_APP binary.

Usage: python3 -I m16c_scan.py <flat-bin> [base]

The M16C memory model: SFR area 0x0000-0x03FF (special function registers),
RAM 0x0400+, ROM code from 0xC0000. The on-chip CAN controller registers live
in the 0xD400-0xD7FF window on this part, so 16-bit little-endian values in
that window appearing in the code are candidate MOV abs16 operands
(mailbox / MCTL / control registers).

This script reports:
  1. all 16-bit LE values in 0xD300-0xD800 found in the binary, with counts
     and example code addresses;
  2. MOV.B #imm8, abs8 (opcode 0xC6) targets in the low SFR page;
  3. MOV.W #imm16, abs16 (opcode 0x89) targets in the CAN window;
  4. a generic "any opcode followed by an abs16 in the CAN window" histogram.

It is a pattern scanner, not a disassembler; see README.md.
"""
import sys, collections

path = sys.argv[1] if len(sys.argv) > 1 else 'vip_app.bin'
base = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0xC0000
data = open(path, 'rb').read()
print(f"# scanning {path} len={len(data)} base={base:#x}")

# 1) all 16-bit LE values in the CAN-SFR candidate window 0xD300-0xD800
hits = collections.Counter()
locs = collections.defaultdict(list)
for i in range(len(data) - 1):
    v = data[i] | (data[i + 1] << 8)
    if 0xD300 <= v <= 0xD800:
        hits[v] += 1
        if len(locs[v]) < 8:
            locs[v].append(base + i)
print("\n## 16-bit LE address values 0xD300-0xD800 (mov to/from SFR via abs16)")
for v, c in sorted(hits.items()):
    print(f"  {v:#06x}: {c}x  @ {[hex(x) for x in locs[v][:6]]}")

# 2) MOV.B #imm8, abs8 -> C6 ii aa (abs8 covers the low SFR page)
print("\n## C6 ii aa (MOV.B #imm8, abs8) targets (aa 0x00-0xFF)")
c6 = collections.Counter()
c6locs = collections.defaultdict(list)
for i in range(len(data) - 2):
    if data[i] == 0xC6:
        aa = data[i + 2]
        c6[aa] += 1
        if len(c6locs[aa]) < 5:
            c6locs[aa].append(base + i)
print("  targets (aa, count):", {hex(k): v for k, v in sorted(c6.items())})

# 3) MOV.W #imm16, abs16 -> 89 iw(2) aw(2 LE), aw in the CAN window
print("\n## 89 iw aw (candidate MOV.W #imm16, abs16), aw in 0xD300-0xD800")
w89 = collections.Counter()
w89locs = collections.defaultdict(list)
for i in range(len(data) - 4):
    if data[i] == 0x89:
        aw = data[i + 3] | (data[i + 4] << 8)
        if 0xD300 <= aw <= 0xD800:
            w89[aw] += 1
            if len(w89locs[aw]) < 6:
                w89locs[aw].append((base + i, data[i + 1] | (data[i + 2] << 8)))
for v, c in sorted(w89.items()):
    print(f"  {v:#06x}: {c}x @ {[(hex(a), hex(im)) for a, im in w89locs[v][:6]]}")

# 4) generic: any opcode followed (after k filler bytes) by abs16 in the window
print("\n## ANY opcode with abs16 operand in 0xD300-0xD800 (opcode histogram)")
gen = collections.Counter()
genlocs = collections.defaultdict(list)
for i in range(len(data) - 3):
    aw = data[i + 2] | (data[i + 3] << 8)
    if 0xD300 <= aw <= 0xD800:
        op = data[i]
        gen[op] += 1
        if len(genlocs[(op, aw)]) < 4:
            genlocs[(op, aw)].append(base + i)
print("  opcodes:", {hex(k): v for k, v in gen.most_common(20)})
for (op, aw), l in sorted(genlocs.items()):
    if gen[op] >= 3:
        print(f"  op={op:#04x} aw={aw:#06x} count={gen[(op, aw)]} @ {[hex(x) for x in l[:4]]}")
