#!/bin/sh
# Maakt MANIFEST.md5 (kit-root) voor 2 payloads + 5 scripts. Draaien na ELKE scriptwijziging;
# aa-install.sh op de CMU weigert bij een afwijking (review m5).
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE" || exit 1
{
    md5sum payload/svcjciusbmgr.so.patched | sed 's#payload/##'
    md5sum payload/blmjciaapa.so.patched | sed 's#payload/##'
    for s in aa-early.sh aa-guard.sh aa-install.sh aa-status.sh aa-uninstall.sh; do
        md5sum "scripts/$s" | sed 's#scripts/##'
    done
} > MANIFEST.md5
cat MANIFEST.md5
