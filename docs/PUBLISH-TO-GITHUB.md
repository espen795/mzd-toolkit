# Publishing this repo to GitHub (one-time setup + every release)

You do NOT need to give anyone (including an AI assistant) your GitHub API key or
password. GitHub push happens from **your own machine** with **your own** credentials.
The repo on disk is already clean and sanitized — see SECURITY-AUDIT.md.

## 1. Create the repo on GitHub (web UI, 1 minute)

1. Go to https://github.com/new
2. Repository name: `mazda-mzd-toolkit` (or your preferred name)
3. Description: `Open-source toolkit for Mazda Connect CMU (MZD): WiFi, SSH, USB tethering, LAN, CAN/VIM vehicle data, backups — firmware v59/v74`
4. **Public**, add README (we already have one), license MIT (we ship LICENSE)
5. Do NOT add .gitignore/.github defaults (we ship our own) — or let GitHub add them, then commit ours over.
6. Click **Create repository**.

## 2. Push from this machine (you type this, not the AI)

```bash
cd /path/to/mazda-mzd-toolkit-public   # clone the repo locally, then cd into it

# Option A — HTTPS (asks for username + Personal Access Token once, then caches it)
git remote add origin https://github.com/<YOUR-USERNAME>/mazda-mzd-toolkit.git
git push -u origin main
# When asked for a password, use a PAT: https://github.com/settings/tokens
# (scopes: repo). Store it in your password manager, never in chat.

# Option B — SSH (recommended long-term)
# ssh-keygen -t ed25519 -C "your@email"   (if you don't have a key yet)
# add ~/.ssh/id_ed25519.pub at https://github.com/settings/keys
git remote add origin git@github.com:<YOUR-USERNAME>/mazda-mzd-toolkit.git
git push -u origin main
```

## 3. First release

```bash
# Build the USB image (fails automatically if secrets leak into the archive)
sh toolkit/tools/build-release.sh 4.8.21 /tmp/mzd-release
# -> mzd-toolkit-v4.8.21.tar.gz (PRIMARY for the car) + .zip (PC only) + SHA256SUMS

# Tag + push
git tag v4.8.21
git push origin v4.8.21
```

Then on GitHub: **Releases → Draft a new release → choose tag v4.8.21 → attach the
three files from /tmp/mzd-release → Publish.**

## 4. Every future release

Follow `RELEASE-CHECKLIST.md` in the repo root. In short: build → secret sweep →
syntax check → tag → push → GitHub release with tar.gz + zip + SHA256SUMS.

## 5. Repo settings to enable (GitHub web UI)

- Settings → General → Features: **Issues** on, **Discussions** optional, **Wiki** off (we use docs/)
- Settings → Branches → Add rule: require PR reviews for `main` (protects you from accidental pushes)
- Settings → Security → **Secret scanning** on (GitHub will alert if a key ever slips in)
- Settings → Code scanning (CodeQL) optional for the shell scripts
- About (right sidebar): topics `mazda`, `mazda-connect`, `cmu`, `mzd`, `infotainment`, `can-bus`, `embedded-linux`, `jailbreak`-free wording: `reverse-engineering`, `automotive`
