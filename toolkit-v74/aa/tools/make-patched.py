#!/usr/bin/env python3
"""make-patched.py - build the two Android Auto patch payloads from YOUR stock files.

This repository does not ship Mazda/JCI binaries. Copy the two stock libraries
from your own CMU (firmware MAZ_CMU-150_74.00.324) to a PC, then run:

    python3 make-patched.py <stock svcjciusbmgr.so> <stock blmjciaapa.so> [outdir]

outdir defaults to ../payload (next to MANIFEST.md5). Each file is checked
against the known stock md5, exactly one byte is changed, and the result is
checked against the known patched md5 (the values in MANIFEST.md5). If any
check fails, nothing is written for that file.

    svcjciusbmgr.so  offset 0xbca27  0x0a -> 0xea   (beq -> b @0xbca24,
                     checkDevAndroidAuto: drop the "bus 1 only" check)
    blmjciaapa.so    offset 0x653b4  0x01 -> 0x02   (mov r2,#1 -> mov r2,#2,
                     ChangeHubSchemeToAvailable: available=2 like a stock AA car)
"""
import hashlib, os, sys

PATCHES = [
    # (output name, offset, original byte, new byte, stock md5, patched md5)
    ("svcjciusbmgr.so.patched", 0xbca27, 0x0a, 0xea,
     "413a2569b6528d11a00eb8773a60de80", "b6aeec1653a26e36e4e1907832c7cbf3"),
    ("blmjciaapa.so.patched", 0x653b4, 0x01, 0x02,
     "486628ae7b5be7c80527968a0b85ae38", "a9c44143c0e89d66464269446a7726e0"),
]


def md5(data):
    return hashlib.md5(data).hexdigest()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "..", "payload")
    os.makedirs(outdir, exist_ok=True)
    ok = True
    for src, (name, off, old, new, stock_md5, patched_md5) in zip(sys.argv[1:3], PATCHES):
        data = bytearray(open(src, "rb").read())
        got = md5(data)
        if got != stock_md5:
            print("FAIL %s: md5 %s is not the known v74 stock md5 %s - wrong file or firmware"
                  % (src, got, stock_md5))
            ok = False
            continue
        if data[off] != old:
            print("FAIL %s: byte at 0x%x is 0x%02x, expected 0x%02x" % (src, off, data[off], old))
            ok = False
            continue
        data[off] = new
        if md5(data) != patched_md5:
            print("FAIL %s: patched md5 %s != expected %s" % (src, md5(data), patched_md5))
            ok = False
            continue
        dst = os.path.join(outdir, name)
        open(dst, "wb").write(bytes(data))
        print("OK   %s -> %s  (md5 %s)" % (src, dst, patched_md5))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
