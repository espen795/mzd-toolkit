#!/usr/bin/env python3
"""make-patched-systemapp.py - build systemApp.js.patched from YOUR OWN stock file.

This repository does not ship Mazda/JCI files. Copy the stock file from your CMU
(firmware MAZ_CMU-150_74.00.324) to a PC, then run:

    python3 make-patched-systemapp.py <stock systemApp.js> [out=systemApp.js.patched]

Source on the CMU: /jci/gui/apps/system/js/systemApp.js
The stock md5 is checked, systemApp-terminal.diff is applied (needs the `patch`
tool), and the result is checked against the md5 that gui-early.sh expects.
Nothing is written if a check fails.
"""
import hashlib, os, shutil, subprocess, sys, tempfile

STOCK_MD5 = "383d7e688256e09b825ced9e3eb69ee9"
PATCHED_MD5 = "8e02903549579fbe98f195ce567c00ef"
HERE = os.path.dirname(os.path.abspath(__file__))
DIFF = os.path.join(HERE, "systemApp-terminal.diff")


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "systemApp.js.patched")
    got = md5(src)
    if got != STOCK_MD5:
        print("FAIL %s: md5 %s is not the v74.00.324 stock md5 %s - wrong file or firmware" % (src, got, STOCK_MD5))
        return 1
    with tempfile.TemporaryDirectory() as t:
        work = os.path.join(t, "systemApp.js")
        shutil.copyfile(src, work)
        r = subprocess.run(["patch", "--binary", "-s", work, DIFF], capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL: patch did not apply:\n" + r.stdout + r.stderr); return 1
        if md5(work) != PATCHED_MD5:
            print("FAIL: patched md5 %s != expected %s" % (md5(work), PATCHED_MD5)); return 1
        shutil.copyfile(work, out)
    print("OK   %s -> %s  (md5 %s)" % (src, out, PATCHED_MD5))
    return 0


if __name__ == "__main__":
    sys.exit(main())
