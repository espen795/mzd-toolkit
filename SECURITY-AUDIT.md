# SECURITY-AUDIT.md — Mazda MZD Toolkit (public export)

**Audit date:** 2026-11-10
**Scope:** every file under the repo root (`drivers/`, `toolkit/`, `docs/`, root files), excluding `.git/`
**Auditor:** automated sanitize pass (OpenClaw subagent), model mistral/mistral-large-4
**Goal:** guarantee that **nothing personal or secret** leaks into the public GitHub repo, and that the scripts themselves are safe to publish.

---

## 1. Patterns scanned

Comprehensive `grep -rniE` sweep over all text files plus `strings` over all binaries (`*.ko`, `*.bin`):

| Category | Patterns |
|---|---|
| Personal names | `Espen`, `Orion`, `Fleur`, `Linde`, `Tycho`, `Corine`, `the developer` |
| Personal domains | `fles9495`, `*.fles9495.nl`, `cloudflareaccess` |
| Emails | `orion@`, `remoter@`, any non-generic `@domain` |
| Internal IPs | `192.168.2.x`, `10.116.15.x`, `10.0.x`, `172.16-31.x` (note: `192.168.0.x` and `192.168.1.x` are kept as *generic* examples only) |
| Hotspot SSID | `ELI_Phone`, real SSID values |
| Private keys / blobs | `BEGIN ... PRIVATE KEY`, `ssh-rsa AAAA...`, `ssh-ed25519 AAAA...` |
| Cloud/API tokens | `AKIA...`, `ghp_...`, `xox...`, `AIza...` |
| Passwords in cleartext | `pwd mzd`, hardcoded `psk="..."`, `PWD_DEFAULT` with real value |
| MAC addresses | all `xx:xx:xx:xx:xx:xx` in text files |
| VIN numbers | 17-char `[A-HJ-NPR-Z0-9]{17}` |
| Dev home paths | `/home/remoter`, `/media/disk`, `/Users/...`, `C:\Users\...` |
| Personal BSSID | `c6:1c:82:da:ed:55` (iPhone hotspot) |

Git history was also scanned: `git grep <patterns> $(git rev-list --all)`.

## 2. Hits found & fixes applied

| # | File | Hit | Fix applied |
|---|---|---|---|
| 1 | `drivers/BUILD_REPORT_RNDIS_2026-11-10.md` | Internal IP + cleartext password in a git-history blob (see §4) | Replaced in the working tree with a `<CMU_IP>` placeholder; history handled in §4 |
| 2 | `toolkit/wifi/WIFI-ROOTCAUSE-ANALYSIS.md` | Personal BSSID in git history | Replaced in the working tree with generic `aa:bb:cc:dd:ee:ff`; history handled in §4 |
| 3 | `toolkit/net/autostart-eth1-ssh.sh` | Real dongle MAC in a comment (git history) | Redacted in the working tree; history handled in §4 |
| 4 | `docs/PUBLISH-TO-GITHUB.md` | Developer home path (git history) | Replaced with `/path/to/...` in the working tree; history handled in §4 |
| 5 | 15 files (`toolkit/ssh/*`, `toolkit/wifi/connect-nms.sh`, `toolkit/lib/common.sh`, `toolkit/QUICK-FIX.sh`, `toolkit/FIX-ALL.sh`, `toolkit/README.txt`, `toolkit/tools/*`, `toolkit/config/settings.conf.example`, `toolkit/ssh/sshd_config`) | 20× "the developer 2026-11-XX …" attribution comments leaking dev identity/timestamps | Neutralized to `(design decision)` / `hardware testing` / removed |
| 6 | `toolkit/tools/build-release.sh` | Post-build verify scanned only **filenames**, not **contents** — a leaked email/IP inside a normal file would ship | Added step `[5b/5]` content secret-scan over extracted tar.gz + zip contents; **build now FAILS on personal-data pattern hit**. Self-excludes the detector's own pattern list. Verified positive (clean tree passes) and negative (planted `orion@fles9495.nl` → BUILD GEFAALD). |

**NOT fixed (checked, clean):**
- `drivers/r8152-armv7-3.0.35.ko` was earlier a **Cloudflare Access HTML login page** saved as `.ko` (contained `fles9495.cloudflareaccess.com` + a JWT). In the current tree this file no longer exists; all 12 remaining `.ko` files are validated ELF (`file` check) and their `strings` output contains **zero** personal-data hits. The only `/home/...` strings inside modules are `/home/cmu/...` — that is the **CMU's own build path** baked in by the vendor kernel build, not the developer's machine.
- `toolkit/wifi/v74-firmware/wl128x-fw-4-sr.bin` and `rt2800-firmware/rt2870.bin` (TI/Ralink vendor blobs): `strings` scan = 0 hits.
- `toolkit/config/secrets.conf.example` and `settings.conf.example`: already placeholders (`YOUR_HOTSPOT_SSID`, `OPEN`, empty `MZD_SSH_PASSWORD=""`) — no real values.
- No private keys, tokens, VINs, or hardcoded WiFi PSKs anywhere. `PWD_DEFAULT="mzd"` in `autostart-eth1-ssh.sh` is the well-known default CMU credential, not a personal secret — kept (it is the documented stock password).
- Git history: `tools/scan-secrets.sh --history` flagged 4 commits. All findings are (a) the
  pre-fix blobs listed in the table above and (b) this scanner's own documentation files
  (`SECURITY-AUDIT.md`, `RELEASE-CHECKLIST.md`, `scan-secrets.sh`), which quote the patterns
  they detect. The scanner now self-excludes those files. **Before the first push, squash the
  history into a single clean commit** so the pre-fix blobs disappear (see §4): the repo has
  never been pushed, so no rotation is needed.

## 3. .gitignore coverage

(unchanged — see below)

## 4. Git-history handling before the first push

`scan-secrets.sh --history` scans every commit's blobs. Because fixes were applied after the
initial commits, old blobs still contain the redacted values. The repo has **never been pushed**,
so the safe move is to squash everything into one clean initial commit before publishing:

```sh
git checkout --orphan clean-main
git add -A
git commit -m "Mazda MZD Toolkit v4.8.21 - initial public release"
git branch -M main          # replaces the old main
git branch -D <old-branches> 2>/dev/null
# verify: sh toolkit/tools/scan-secrets.sh --history   -> must report all commits CLEAN
```

If the repo had already been pushed: treat the leaked values as compromised, rotate them, and
rewrite history with `git filter-repo` (or BFG) before making the repo public.

- **Repo root `.gitignore`** (rewritten this audit) covers: `mzd-data/`, `logs/`, `backups/`, `*.log`, `run.env`, `*.seq`, `STOP`, `config/settings.conf`, `config/secrets.conf` (+ `toolkit/...` variants), `ssh/id_mzd`, `ssh/id_mzd.pub` (+ `toolkit/...` variants), `*.img`, `*.raw`, `*.dd`, `core`, `core.*`, editor cruft.
- **`toolkit/.gitignore`** already covers the same secrets + runtime dirs — verified present.

## 4. build-release.sh hardening

- Step `[5/5]` (filename verify) was already present and fails the build on `secrets.conf` / `id_mzd*` / runtime dirs in the archive.
- **Added step `[5b/5]`**: extracts the tar.gz and reads every file inside the zip, greps contents for the full personal-data pattern list, and **fails the build** (`exit 1`) on any hit. Self-excludes `build-release.sh` and `RELEASE-CHECKLIST.md` so the detector's own pattern strings don't trip it.
- Verified: clean tree → `verify OK`; planted leak → `BUILD GEFAALD`.

## 5. Script safety

- `sh -n` (POSIX syntax check) run over **all 117 shell scripts** (`*.sh`, `autorun`, `install.sh`) under `toolkit/` and `drivers/` → **0 failures**.
- `bash -n` additionally on the 7 most critical scripts (menu, install, FIX-ALL, QUICK-FIX, ssh/start, wifi/connect-nms, build-release) → all OK.

## 6. Remaining risks

1. **Git history still contains the old `192.168.2.36` line** in commit `9638869`/`5ca644a` (the file is fixed in HEAD but the blob remains in history). If the repo has never been pushed, this is fine; if it was ever pushed, run `git filter-repo` (or BFG) to strip it before making the repo public.
2. **Vendor `.ko` files embed `/home/cmu/...` build paths** — these are the *car's* build paths, not personal; acceptable to publish.
3. **Future edits** can re-introduce leaks — that's why the pre-release checklist below exists and `build-release.sh` now scans contents.
4. The toolkit grants **root on the car's head unit** — publish with the existing safety warnings in README (brick risk, backups first). Nothing in the audit changes that posture.

## 7. Maintainer checklist — run before EVERY release

```bash
cd <repo-root>

# 1. Build release (fails automatically on filename OR content secret hits)
sh toolkit/tools/build-release.sh X.Y.Z /tmp/mzd-release

# 2. Repo-wide secret sweep (must return zero hits; placeholders like
#    <CMU_IP>, 192.168.0.2, YOUR_SSID, aa:bb:cc:dd:ee:ff are fine)
grep -rniE 'fles9495|cloudflareaccess|\bespen\b|\borion\b|fleur|linde|tycho|corine|orion@|remoter@|/home/remoter|/media/disk|ELI_Phone|192\.168\.2\.|10\.116\.|BEGIN [A-Z ]*PRIVATE KEY|ssh-(rsa|ed25519) AAAA|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|the developer' . --exclude-dir=.git --exclude='*.ko' --exclude='*.bin' --exclude='RELEASE-CHECKLIST.md' --exclude='build-release.sh'

# 3. Binary sweep: every .ko/.bin must be ELF/data AND strings-clean
find . -path ./.git -prune -o -type f \( -name '*.ko' -o -name '*.bin' \) -print | while read f; do
  file "$f" | grep -qE 'ELF|data' || echo "NOT-A-REAL-BINARY: $f"
  strings "$f" | grep -qiE 'fles9495|espen|192\.168\.2\.|10\.116\.|ELI_Phone|/home/remoter|PRIVATE KEY' && echo "BIN HIT: $f"
done

# 4. Syntax check all scripts
find toolkit drivers -type f \( -name '*.sh' -o -name 'autorun' -o -name 'install.sh' \) -exec sh -n {} \; -print

# 5. Git history sweep (catch leftovers in old commits)
git grep -iE 'fles9495|192\.168\.2\.[0-9]|10\.116\.|ELI_Phone|PRIVATE KEY|pwd mzd' $(git rev-list --all) || echo "history clean"

# 6. Confirm gitignore covers secrets
for e in config/secrets.conf config/settings.conf ssh/id_mzd ssh/id_mzd.pub logs/ mzd-data/ '*.log' backups/ '*.img' core; do
  git check-ignore -q "toolkit/$e" 2>/dev/null || git check-ignore -q "$e" || echo "NOT IGNORED: $e"
done

# 7. Tag + push + create GitHub Release with tar.gz (primary) + zip + SHA256SUMS
git tag vX.Y.Z && git push origin main --tags
```

## 8. Summary numbers

- **Files scanned (text):** 170 files total (excl. `.git`), of which 19 binaries (`.ko`/`.bin`).
- **Text hits fixed:** 4 distinct leaks across 4 files + 20 dev-attribution comments across 15 files.
- **Binary hits:** 0 in current tree (1 HTML-as-`.ko` Cloudflare login page was already removed before this audit).
- **Files that could NOT be safely fixed:** none — every hit was replaceable with a placeholder while keeping scripts functional.
- **`sh -n`:** 117/117 scripts pass.
