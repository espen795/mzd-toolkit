#!/usr/bin/env python3
"""Hexdump a window around absolute addresses in a flat M16C binary.

Usage: python3 -I m16c_hexdump.py <flat-bin> <addr...> [base]
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'vip_app.bin'
addrs = [int(x, 0) for x in sys.argv[2:]]
base = int(sys.argv[-1], 0) if len(sys.argv) > 2 and sys.argv[-1].startswith('0x') and len(sys.argv) > 3 else 0xC0000
if len(sys.argv) > 3:
    base = int(sys.argv[-1], 0)
data = open(path, 'rb').read()
for a in addrs:
    off = a - base
    lo = max(0, off - 32); hi = min(len(data), off + 48)
    print(f"\n=== {a:#x}")
    for i in range(lo, hi, 16):
        print(f"  {base + i:#07x}: " + ' '.join(f'{x:02x}' for x in data[i:i + 16]))
