#!/usr/bin/env python3
"""Parse an S-record region of a raw CMU firmware image into flat binaries.

Usage: python3 -I srec_build.py <image> <outdir> [region_start] [region_end]

Writes one file per contiguous S-record segment into <outdir>/seg/ plus a
segments.json index. The VIP application segment (load base 0xC0000) is the
main reverse-engineering target.

Read-only with respect to the image; run with python3 -I on untrusted data.
"""
import os, sys, json, collections

def parse_line(line):
    if len(line) < 4 or line[0:1] != b'S':
        return None
    try:
        t = chr(line[1]); cnt = int(line[2:4], 16)
        raw = bytes.fromhex(line[4:4 + 2 * cnt].decode('ascii'))
    except Exception:
        return None
    alen = {'1': 2, '2': 3, '3': 4, '5': 2, '7': 4, '8': 3, '9': 2}.get(t)
    if alen is None:
        return (t, 0, raw[:-1], cnt, True)
    if len(raw) < alen + 1:
        return None
    addr = int.from_bytes(raw[:alen], 'big'); data = raw[alen:-1]
    ok = ((cnt + sum(raw[:alen]) + sum(data) + raw[-1]) & 0xFF) == 0xFF
    return (t, addr, data, cnt, ok)

def main():
    img = sys.argv[1]
    out = sys.argv[2]
    region_start = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x200
    region_end = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x1C2000
    segdir = os.path.join(out, 'seg')
    os.makedirs(segdir, exist_ok=True)

    segments = []
    seg = None
    stats = collections.Counter(); bad = 0; s0 = []
    with open(img, 'rb') as f:
        f.seek(region_start)
        blob = f.read(region_end - region_start)

    for line in blob.split(b'\n'):
        line = line.rstrip(b'\r')
        if not line.startswith(b'S'):
            continue
        r = parse_line(line)
        if not r:
            continue
        t = r[0]; stats[t] += 1
        if t == '0':
            s0.append(r[2].decode('ascii', 'replace')); continue
        if t not in '123':
            continue
        if len(r) == 5 and not r[4]:
            bad += 1
        addr, data = r[1], r[2]
        if seg is None or seg[0] != t or addr != seg[1] + len(seg[2]):
            if seg:
                segments.append(seg)
            seg = [t, addr, bytearray(data)]
        else:
            seg[2].extend(data)
    if seg:
        segments.append(seg)

    print("record counts:", dict(sorted(stats.items())), "bad checksums:", bad)
    print(f"{len(s0)} S0 headers:")
    for h in s0:
        print("  ", repr(h))
    meta = []
    for t, addr, data in segments:
        name = f"S{t}_{addr:06X}_{len(data):06X}.bin"
        with open(os.path.join(segdir, name), 'wb') as o:
            o.write(data)
        meta.append({'type': t, 'start': addr, 'end': addr + len(data) - 1,
                     'len': len(data), 'file': name})
        print(f"  S{t}: {addr:#010x}-{addr + len(data) - 1:#010x}  {len(data)} bytes  -> {name}")
    json.dump(meta, open(os.path.join(out, 'segments.json'), 'w'), indent=1)
    print(f"wrote {os.path.join(out, 'segments.json')}")

if __name__ == '__main__':
    main()
