#!/usr/bin/env python3
"""Find M16C MOV instructions whose abs16 operand lands in 0xD000-0xDFFF.

Usage: python3 -I m16c_movscan.py <flat-bin> [base] [lo] [hi]

Scans these encodings (Renesas M16C/60 series software manual):
  MOV.B #imm8, abs16   : 8C ib aw16            (filler 1)
  MOV.W #imm16, abs16  : 89 iw16 aw16          (filler 3)
  generic op aw16      : many read/write forms (filler 0)
  generic op b aw16    : indexed forms         (filler 1)
Prints an opcode histogram so you can see which encoding the compiler used.
Pattern scanner, not a disassembler; see README.md.
"""
import collections, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'vip_app.bin'
base = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0xC0000
LO = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0xD000
HI = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0xDFFF

data = open(path, 'rb').read()

def scan(opcodes, filler, label):
    res = collections.defaultdict(list)
    for i in range(len(data) - filler - 2):
        if data[i] in opcodes:
            aw = data[i + filler] | (data[i + filler + 1] << 8)
            if LO <= aw <= HI:
                res[aw].append((base + i, data[i]))
    print(f"\n## {label}: opcode(s) {sorted(hex(o) for o in opcodes)} filler={filler}")
    tot = 0
    for aw in sorted(res):
        ops = collections.Counter(o for _, o in res[aw])
        print(f"  {aw:#06x}: {len(res[aw])}x ops={ {hex(k): v for k, v in ops.items()} } @ {[hex(a) for a, _ in res[aw][:4]]}")
        tot += len(res[aw])
    print(f"  total {tot}")

scan({0x8C}, 1, "MOV.B #imm8, abs16  (8C ib aw16)")
scan({0x89}, 3, "MOV.W #imm16, abs16 (89 iw aw16)")
scan({0x8A, 0x8B, 0x8D, 0x8E, 0xE4, 0xE5, 0xE6, 0xE7, 0xC4, 0xC5, 0xC7,
      0xEC, 0xED, 0xEE, 0xEF, 0xF4, 0xF5, 0xF6, 0xF7, 0x8F, 0x9F}, 0,
     "op aw16 (filler=0)")
scan({0x6E, 0x6F, 0x7E, 0x7D, 0x7C, 0x75, 0x72, 0x73, 0x77, 0x64, 0x65, 0x66,
      0x67, 0x68, 0x69, 0x6A, 0x6B, 0x60, 0x61, 0x62, 0x63}, 1, "op b aw16 (filler=1)")
