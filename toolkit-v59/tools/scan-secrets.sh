#!/bin/sh
# ============================================================
# MZD Toolkit - scan-secrets.sh
# Pre-publish scanner: finds secrets and personal data in a directory tree.
# Runs on the maintainer's PC / build host (not on the car).
#
# Usage:
#   sh tools/scan-secrets.sh [DIR]       scan DIR (default: .)
#                                        exit 0 = clean, 1 = findings, 2 = usage error
#   sh tools/scan-secrets.sh --history   scan the full tree of EVERY commit (blobs stay in history after a fix)
#   sh tools/scan-secrets.sh --self-test prove that the scanner detects planted leaks
#
# Two pattern layers:
#   1. GENERIC (built in, safe to publish)
#        private keys, API tokens, SSH key blobs, /home/<user>/ paths,
#        internal IPv4 addresses (10.x, 172.16-31.x, 192.168.2-255.x).
#        192.168.0.x and 192.168.1.x are accepted as documentation examples.
#   2. PERSONAL (local file, NEVER committed)
#        $MZD_RELEASE_DENYLIST or ~/.config/mzd-release-denylist.txt
#        One extended regex per line (names, domains, SSIDs, MAC addresses, LAN prefixes).
#        Lines starting with '#' and empty lines are ignored. Matching is case-insensitive.
#        Without the file only layer 1 runs (a note is printed).
# ============================================================

GENERIC_KEYS='BEGIN [A-Z ]*PRIVATE KEY|ssh-(rsa|ed25519|dss|ecdsa-sha2-[a-z0-9]+) AAAA|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'
GENERIC_PATHS='/home/[a-z_][a-z0-9_-]*/|/Users/[A-Za-z0-9_-]+/'
GENERIC_IP='(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.([2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.[0-9]{1,3})([^0-9]|$)'
# Lines matching this are accepted even if they match a generic rule:
#   /home/cmu/     the car's own vendor build path (embedded in the kernel modules)
#   192.168.53.x   the fixed subnet of the toolkit's own AP mode (a functional constant, not a LAN of the maintainer)
#   the rest       documentation placeholders
ALLOW_LINE='/home/(cmu|user|youruser|username)/|/Users/(you|user|username|name)/|192[.]168[.]53[.]'

DENYLIST="${MZD_RELEASE_DENYLIST:-$HOME/.config/mzd-release-denylist.txt}"

load_personal() {
    PERSONAL=""
    if [ -f "$DENYLIST" ]; then
        PERSONAL=$(grep -vE '^[[:space:]]*(#|$)' "$DENYLIST" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
    fi
}

# scan_dir DIR -> prints findings, returns 1 if any
scan_dir() {
    _dir="$1"
    _found=0

    # --- text files: generic layer (case-sensitive) ---
    # Self-exclusion: this scanner and SECURITY-AUDIT.md document the pattern
    # strings themselves, so they must not be flagged as findings.
    _out=$(grep -rInE "$GENERIC_KEYS|$GENERIC_PATHS|$GENERIC_IP" "$_dir" --exclude-dir=.git --exclude=scan-secrets.sh --exclude=SECURITY-AUDIT.md 2>/dev/null | grep -vE "$ALLOW_LINE" | head -200)
    if [ -n "$_out" ]; then
        echo "[FINDING] generic patterns (keys / tokens / user paths / internal IPs):"
        echo "$_out" | cut -c1-200 | sed 's/^/    /'
        _found=1
    fi

    # --- text files: personal layer (case-insensitive) ---
    if [ -n "$PERSONAL" ]; then
        _out=$(grep -rInEi "$PERSONAL" "$_dir" --exclude-dir=.git --exclude=scan-secrets.sh --exclude=SECURITY-AUDIT.md --exclude=RELEASE-CHECKLIST.md 2>/dev/null | head -200)
        if [ -n "$_out" ]; then
            echo "[FINDING] personal denylist patterns ($DENYLIST):"
            echo "$_out" | cut -c1-200 | sed 's/^/    /'
            _found=1
        fi
    fi

    # --- binaries: keys / tokens / personal terms, and "is it a real binary?" ---
    _bin=$(find "$_dir" -path '*/.git' -prune -o -type f \( -name '*.ko' -o -name '*.bin' -o -name '*.o' -o -name '*.img' \) -print 2>/dev/null)
    _binout=""
    if [ -n "$_bin" ]; then
        _binout=$(echo "$_bin" | while IFS= read -r _f; do
            if command -v file >/dev/null 2>&1; then
                file -b "$_f" | grep -qE 'ELF|data|firmware|archive' || echo "NOT-A-REAL-BINARY: $_f ($(file -b "$_f" | cut -c1-60))"
            fi
            grep -aqE "$GENERIC_KEYS" "$_f" 2>/dev/null && echo "KEY/TOKEN IN BINARY: $_f"
            if [ -n "$PERSONAL" ]; then
                grep -aqiE "$PERSONAL" "$_f" 2>/dev/null && echo "PERSONAL TERM IN BINARY: $_f"
            fi
        done)
    fi
    if [ -n "$_binout" ]; then
        echo "[FINDING] binary files:"
        echo "$_binout" | sed 's/^/    /'
        _found=1
    fi
    return $_found
}

selftest() {
    T=$(mktemp -d /tmp/mzd-scan-selftest.XXXXXX) || exit 2
    trap 'rm -rf "$T"' EXIT INT TERM
    SELF="$0"
    _fail=0
    echo "--- scan-secrets self-test ---"

    mkdir -p "$T/clean"
    printf 'examples: 192.168.0.2 and 192.168.1.10\nvendor path /home/cmu/build/x.c is allowed\nplaceholder <CMU_IP> YOUR_SSID aa:bb:cc:dd:ee:ff\n' > "$T/clean/ok.txt"
    if MZD_RELEASE_DENYLIST=/nonexistent sh "$SELF" "$T/clean" >/dev/null 2>&1; then
        echo "ok   : clean tree passes (documentation placeholders are accepted)"
    else
        echo "FAIL : clean tree was flagged"; _fail=1
    fi

    printf '# test denylist\nZZ_PLANTED_NAME_ZZ\n' > "$T/deny.txt"
    plant() { # description content
        rm -rf "$T/leak"; mkdir -p "$T/leak"
        printf '%s\n' "$2" > "$T/leak/x.txt"
        if MZD_RELEASE_DENYLIST="$T/deny.txt" sh "$SELF" "$T/leak" >/dev/null 2>&1; then
            echo "FAIL : NOT detected: $1"; _fail=1
        else
            echo "ok   : detected $1"
        fi
    }
    plant "private key header"        "-----BEGIN RSA ""PRIVATE KEY-----"
    plant "github token"              "token=ghp_""0123456789abcdefghijklmnopqrstuvwxyz"
    plant "ssh public key blob"       "ssh-rsa ""AAAAB3NzaC1yc2EAAAADAQABAAABAQ"
    plant "10.x internal IP"          "gateway 10.20.""30.40"
    plant "172.16-31 internal IP"     "gateway 172.20.""1.1"
    plant "192.168.7.x internal IP"   "gateway 192.168.7.""9"
    plant "/home/<user> path"         "cd /home/""alice/project"
    plant "personal denylist term"    "owner is zz_planted_name_zz (case-insensitive)"

    # binary layer
    rm -rf "$T/leak"; mkdir -p "$T/leak"
    printf '<html>login page saved as module</html>\n' > "$T/leak/fake.ko"
    if command -v file >/dev/null 2>&1; then
        if MZD_RELEASE_DENYLIST="$T/deny.txt" sh "$SELF" "$T/leak" >/dev/null 2>&1; then
            echo "FAIL : HTML saved as .ko not detected"; _fail=1
        else
            echo "ok   : detected non-binary saved as .ko"
        fi
    fi
    if [ "$_fail" = 0 ]; then echo "SELF-TEST PASSED"; exit 0; fi
    echo "SELF-TEST FAILED"; exit 1
}

history_scan() {
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: not inside a git repository" >&2; exit 2; }
    load_personal
    _hbad=0
    _n=0
    for _c in $(git rev-list --all); do
        _n=$((_n + 1))
        _d=$(mktemp -d /tmp/mzd-hist.XXXXXX) || exit 2
        git archive "$_c" | tar -x -C "$_d" 2>/dev/null
        if ! _o=$(scan_dir "$_d"); then
            _hbad=1
            echo "[HISTORY] commit $(echo "$_c" | cut -c1-8): findings"
            echo "$_o" | sed "s|$_d/||" | head -8 | cut -c1-170 | sed 's/^/    /'
        fi
        rm -rf "$_d"
    done
    if [ "$_hbad" = 0 ]; then echo "scan-secrets --history: $_n commit(s) CLEAN"; exit 0; fi
    echo "scan-secrets --history: FINDINGS in history - rewrite/squash history before the first push"
    exit 1
}

case "${1:-}" in
    --self-test) selftest ;;
    --history) history_scan ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
esac

DIR="${1:-.}"
[ -d "$DIR" ] || { echo "ERROR: not a directory: $DIR" >&2; exit 2; }

load_personal
if [ -z "$PERSONAL" ]; then
    echo "NOTE: no personal denylist at $DENYLIST - only the generic checks run."
else
    echo "Personal denylist loaded: $DENYLIST ($(echo "$PERSONAL" | tr '|' '\n' | wc -l | tr -d ' ') patterns)"
fi
echo "Scanning: $DIR"

if scan_dir "$DIR"; then
    echo "scan-secrets: CLEAN"
    exit 0
fi
echo "scan-secrets: FINDINGS - do not publish until they are fixed"
exit 1
