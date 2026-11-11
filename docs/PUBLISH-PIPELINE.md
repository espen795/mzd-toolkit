# Publish pipeline — from internal research to public repo

How new knowledge flows from the internal workspace into the public GitHub repo
(`espen795/mzd-toolkit`) without leaking PII, Dutch, or secrets.

## Source locations (internal, never public as-is)

| Internal path | Content |
|---|---|
| `projects/mazda-mzd/knowledge-base/` | Deep technical reference (rootfs diff, GUI architecture, system config, firmware map, binary map, CMU150 architecture) — **Dutch**, contains internal-domain/Gitea/wiki links and `<!-- project: -->` markers |
| `projects/mazda-mzd/docs/` | Design docs, changelogs, analyses — Dutch, internal paths |
| `projects/mazda-mzd/logs/from-mzd/` | Raw logs from the car (may contain MACs, IPs, SSIDs) |
| `projects/mazda-mzd/archive/usb-root*/` | Exploit files (mp3 XSS payloads) — **never publish raw** |

## Target (public)

`/path/to/mazda-mzd-toolkit-public/` → `github.com/<you>/mzd-toolkit`

## The pipeline (5 steps, ~15 min per batch)

### Step 1 — Pick & translate (ML4 subagent, isolated context)

Spawn a subagent per file (or small batch) with a strict prompt:

> Translate this Dutch Markdown file to English for a PUBLIC open-source repo.
> Rules: (1) keep all technical values, paths, commands, hex, versions verbatim;
> (2) translate prose to natural technical English; (3) remove ALL PII: no
> `<your-domain>`, no internal Gitea/wiki links, no `/home/<you>` paths, no
> `<!-- project: -->` markers, no real MACs/IPs/SSIDs — replace with
> placeholders (`<CMU_IP>`, `aa:bb:cc:dd:ee:ff`, `YOUR_SSID`);
> (4) ASCII-only output (no emoji, no diacritics);
> (5) do NOT touch files outside the given list; (6) report any uncertain
> translation, do not guess.

Verify per file: `sh toolkit/tools/selfcheck.sh <file>` must print PASS,
line count must match, `dash -n`/`busybox ash -n` for any embedded scripts.

### Step 2 — Deduplicate against existing public docs

The public `docs/` already covers: ARCHITECTURE-CMU, HARDWARE, CANBUS-VIM,
WIFI, NETWORKING, SSH-V59, GUI-HACKING, FIRMWARE, DRIVER-COMPILATION, TESTING,
TROUBLESHOOTING, USAGE, INSTALL, ROOT-ACCESS.

Before adding a translated file, grep the public `docs/` for the same topic.
If overlap: **merge into the existing public file**, don't add a duplicate.
The knowledge-base files are deeper/more raw — if a public file already covers
the topic at the right level, only port the *unique* facts (e.g. the v59-vs-v74
rootfs diff table, the full `/config-mfg` file map) into it.

### Step 3 — Scan

```sh
cd /path/to/mazda-mzd-toolkit-public
sh toolkit/tools/scan-secrets.sh --self-test   # scanner still works?
sh toolkit/tools/scan-secrets.sh .              # must print CLEAN
# Dutch residue check (all files):
python3 -I /tmp/mzd-verify/nl_check.py $(git ls-files '*.md' '*.sh' '*.txt' '*.example')
```

### Step 4 — Commit & push (deploy key, no token in chat)

```sh
git add -A
git commit -m "docs: <what> (from knowledge-base/<source>)"
git push origin main          # deploy key ~/.ssh/id_github_mzd_deploy
```

### Step 5 — Bump version + release (only when toolkit code changed)

```sh
# edit CHANGELOG.md + version in build-release.sh if needed
git tag vX.Y.Z && git push origin vX.Y.Z
sh toolkit/tools/build-release.sh X.Y.Z /tmp/mzd-rel   # secret-scan gate built in
# upload the 3 assets via GitHub Releases web UI (deploy key can't create releases)
# also: cp assets to <file-sharing>/uploads/ for your files host
```

## What NEVER goes public

- Raw logs (`logs/from-mzd/**`) — may contain MACs, IPs, SSIDs, GPS traces
- `archive/usb-root*/mp3/*` — live XSS payloads (described in ROOT-ACCESS.md, files not shipped)
- `secrets.conf`, `settings.conf`, `ssh/id_mzd*`, any key material
- `~/.config/mzd-release-denylist.txt` (the denylist itself is personal)
- Internal infra: your home-LAN prefix (e.g. `192.168.<x>.x`), your personal
  domain(s), internal Gitea/wiki hostnames, `/home/<you>` paths
- `<!-- project: path:... -->` markers

## Quick checklist per publish

- [ ] Translated (EN, ASCII-only), selfcheck PASS
- [ ] Merged into existing public doc if topic overlaps
- [ ] `scan-secrets.sh .` → CLEAN
- [ ] NL-check → 0 hits
- [ ] No raw logs / exploit files / secrets added
- [ ] Commit + push via deploy key
- [ ] (if release) tag + build + upload assets
