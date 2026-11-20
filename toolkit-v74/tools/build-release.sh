#!/bin/sh
# ============================================================
# MZD Toolkit - build-release.sh (v4.8.0, W5 packaging)
# Builds release assets from toolkit/:
#   - mzd-toolkit-vX.Y.Z.tar.gz  PRIMARY for the MZD/CMU
#     (the CMU busybox has tar+gzip but NO unzip - proven by the
#      environment dump of a real unit)
#   - mzd-toolkit-vX.Y.Z.zip     for the PC only
#   - SHA256SUMS                 checksums for both assets
#   - POST-BUILD VERIFY: the build FAILS if secrets/runtime data end up in an asset,
#     or if the asset CONTENTS match the secret/personal-data scanner
#     (tools/scan-secrets.sh: generic patterns + your local denylist)
# No zip/unzip needed on the build host: zip falls back to python3 zipfile
# (the MZD side never unpacks zip).
#
# Usage (on a PC / Debian host):
#   sh tools/build-release.sh [version] [output-dir]
#   version default = TOOLKIT_VERSION from lib/common.sh
#   e.g.: sh tools/build-release.sh "" /tmp/mzd-release
# ============================================================

TOOLKIT_SRC="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
DEFAULT_VER=$(grep -oE 'TOOLKIT_VERSION="[0-9.]+"' "$TOOLKIT_SRC/lib/common.sh" 2>/dev/null | head -1 | tr -d 'TOOLKIT_VERSION="' | tr -d '"')
VERSION="${1:-${DEFAULT_VER:-4.8.3}}"
OUTDIR="${2:-/tmp/mzd-release-v$VERSION}"

[ -f "$TOOLKIT_SRC/menu.sh" ] || { echo "ERROR: run from toolkit/ (menu.sh not found in $TOOLKIT_SRC)"; exit 1; }

STAGE="$(mktemp -d /tmp/mzd-stage.XXXXXX)" || exit 1
PKG="mzd-toolkit"
PKGDIR="$STAGE/$PKG"
mkdir -p "$PKGDIR" || exit 1

echo "========================================"
echo " MZD Toolkit release build v$VERSION"
echo "========================================"
echo "Source : $TOOLKIT_SRC"
echo "Stage  : $PKGDIR"
echo "Output : $OUTDIR"
echo ""

# ------------------------------------------------------------
# 1. Copy toolkit/ to the stage, with exclusions:
#    runtime logs, backups, .git, STOP/PID files, editor temp files,
#    v4.8.0: mzd-data/ runs run.env *.seq + SECRETS (settings.conf,
#    secrets.conf, id_mzd*) - secrets must NEVER end up in a release asset
# ------------------------------------------------------------
echo "[1/6] Copy toolkit -> stage (exclusions: logs/ backups/ .git *.log STOP mzd-data/ runs run.env *.seq secrets)"
( cd "$TOOLKIT_SRC" && tar -cf - \
    --exclude='./logs' \
    --exclude='./backups' \
    --exclude='./.git' \
    --exclude='./mzd-data' \
    --exclude='./runs' \
    --exclude='run.env' \
    --exclude='*.seq' \
    --exclude='*.log' \
    --exclude='STOP' \
    --exclude='.rwtest_common' \
    --exclude='./config/settings.conf' \
    --exclude='./config/secrets.conf' \
    --exclude='./ssh/id_mzd' \
    --exclude='./ssh/id_mzd.pub' \
    --exclude='./tools/tests' \
    . ) | ( cd "$PKGDIR" && tar -xf - )

# Sanity: menu.sh + lib/common.sh must be present
[ -f "$PKGDIR/menu.sh" ] || { echo "ERROR: menu.sh missing in stage"; rm -rf "$STAGE"; exit 1; }
[ -f "$PKGDIR/lib/common.sh" ] || { echo "ERROR: lib/common.sh missing in stage"; rm -rf "$STAGE"; exit 1; }

mkdir -p "$OUTDIR"

# ------------------------------------------------------------
# 2. tar.gz PRIMARY (MZD): top dir mzd-toolkit/ in the archive,
#    unpack on the CMU:  tar -xzf mzd-toolkit-vX.Y.Z.tar.gz -C ${USB_MOUNT}/
# ------------------------------------------------------------
echo "[2/6] Create tar.gz (MZD primary)..."
TARGZ="$OUTDIR/${PKG}-v${VERSION}.tar.gz"
( cd "$STAGE" && tar -czf "$TARGZ" "$PKG" ) || { echo "ERROR: tar.gz failed"; rm -rf "$STAGE"; exit 1; }
echo "  -> $TARGZ"

# ------------------------------------------------------------
# 3. zip for the PC ONLY. Try the 'zip' binary, otherwise python3 zipfile.
# ------------------------------------------------------------
echo "[3/6] Create zip (PC only)..."
ZIPF="$OUTDIR/${PKG}-v${VERSION}.zip"
if command -v zip > /dev/null 2>&1; then
    ( cd "$STAGE" && zip -qr "$ZIPF" "$PKG" )
else
    python3 - "$STAGE" "$PKG" "$ZIPF" <<'PYEOF'
import os, sys, zipfile
stage, pkg, out = sys.argv[1], sys.argv[2], sys.argv[3]
EXCLUDE_DIRS = {"logs", "backups", ".git", "mzd-data", "runs", "tests"}
EXCLUDE_FILES = {"STOP", ".rwtest_common", "settings.conf", "secrets.conf",
                 "id_mzd", "id_mzd.pub", "run.env"}
root = os.path.join(stage, pkg)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if fn.endswith(".log") or fn.endswith(".seq") or fn in EXCLUDE_FILES:
                continue
            full = os.path.join(dirpath, fn)
            arc = os.path.relpath(full, stage)
            z.write(full, arc)
PYEOF
fi
if [ -f "$ZIPF" ]; then
    echo "  -> $ZIPF"
else
    echo "  WARNING: zip could not be built (no zip/python3) - tar.gz remains primary"
fi

# ------------------------------------------------------------
# 4. SHA256SUMS (both assets; FAT corruption on USB sticks is proven - L3)
# ------------------------------------------------------------
echo "[4/6] SHA256 checksums..."
SUMS="$OUTDIR/SHA256SUMS"
: > "$SUMS"
( cd "$OUTDIR" && for f in "${PKG}-v${VERSION}.tar.gz" "${PKG}-v${VERSION}.zip"; do
    [ -f "$f" ] && sha256sum "$f" >> "$SUMS"
done )
echo "  -> $SUMS"
cat "$SUMS"

# ------------------------------------------------------------
# 5. POST-BUILD VERIFY (v4.8.0): an asset must NEVER contain
#    secrets or runtime data. The build fails on a hit.
# ------------------------------------------------------------
echo "[5/6] Post-build verify (secrets/runtime in asset = FAIL)..."
_VERIFY_FAIL=0
if command -v tar >/dev/null 2>&1; then
    _HITS=$(tar -tzf "$TARGZ" 2>/dev/null | grep -E 'secrets\.conf$|config/settings\.conf$|ssh/id_mzd|mzd-data/|/runs/|run\.env$|\.seq$' || true)
    if [ -n "$_HITS" ]; then
        echo "  [FAIL] tar.gz contains forbidden entries:"
        echo "$_HITS" | sed 's/^/    /'
        _VERIFY_FAIL=1
    else
        echo "  tar.gz clean (no secrets/runtime)"
    fi
fi
if [ -f "$ZIPF" ]; then
    if command -v unzip >/dev/null 2>&1; then
        _HITS=$(unzip -l "$ZIPF" 2>/dev/null | grep -E 'secrets\.conf$|config/settings\.conf$|ssh/id_mzd|mzd-data/|/runs/|run\.env$|\.seq$' || true)
    else
        _HITS=$(python3 -c "import zipfile,sys; [print(n) for n in zipfile.ZipFile(sys.argv[1]).namelist() if any(x in n for x in ('secrets.conf','config/settings.conf','ssh/id_mzd','mzd-data/','/runs/','run.env','.seq'))]" "$ZIPF" 2>/dev/null || true)
    fi
    if [ -n "$_HITS" ]; then
        echo "  [FAIL] zip contains forbidden entries:"
        echo "$_HITS" | sed 's/^/    /'
        _VERIFY_FAIL=1
    else
        echo "  zip clean (no secrets/runtime)"
    fi
fi

# ------------------------------------------------------------
# 6. CONTENT scan: file names alone are not enough. Unpack both assets and run the
#    secret/personal-data scanner over their CONTENTS (generic patterns + the local
#    denylist; see tools/scan-secrets.sh). The build FAILS on any finding.
# ------------------------------------------------------------
echo "[6/6] Content scan over asset contents (secret/personal-data findings = FAIL)..."
_CONTENT_HITS=0
SCANNER="$TOOLKIT_SRC/tools/scan-secrets.sh"
if [ ! -f "$SCANNER" ]; then
    echo "  [FAIL] scanner missing: $SCANNER"
    _CONTENT_HITS=1
else
    _TMPX="$(mktemp -d /tmp/mzd-verify.XXXXXX)"
    mkdir -p "$_TMPX/tar" "$_TMPX/zip"
    tar -xzf "$TARGZ" -C "$_TMPX/tar" 2>/dev/null
    echo "  --- tar.gz ---"
    sh "$SCANNER" "$_TMPX/tar" || _CONTENT_HITS=1
    if [ -f "$ZIPF" ] && command -v python3 >/dev/null 2>&1; then
        python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ZIPF" "$_TMPX/zip" 2>/dev/null
        echo "  --- zip ---"
        sh "$SCANNER" "$_TMPX/zip" || _CONTENT_HITS=1
    fi
    rm -rf "$_TMPX"
fi
if [ "$_VERIFY_FAIL" = "1" ] || [ "$_CONTENT_HITS" = "1" ]; then
    echo ""
    echo "========================================"
    echo " BUILD FAILED: secrets/runtime/personal data in release asset!"
    echo "========================================"
    rm -rf "$STAGE"
    exit 1
fi
echo "  verify OK"

# ------------------------------------------------------------
# Wrap-up + MZD unpack instructions
# ------------------------------------------------------------
rm -rf "$STAGE"
echo ""
echo "========================================"
echo " Release v$VERSION complete in $OUTDIR"
echo "========================================"
echo "Assets:"
ls -la "$OUTDIR"
echo ""
echo "On the MZD (tar.gz primary - NO unzip available):"
echo "  tar -xzf ${PKG}-v${VERSION}.tar.gz -C /tmp/mnt/sdX1/   (USB mount; sdX1 = your stick)"
echo "  sh /tmp/mnt/sdX1/mzd-toolkit/install.sh"
echo ""
echo "Verify checksums (PC or MZD with sha256sum):"
echo "  cd <dir with assets> && sha256sum -c SHA256SUMS"
exit 0
