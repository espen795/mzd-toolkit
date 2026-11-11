# Publishing this repo to GitHub (one-time setup + every release)

You do NOT need to give anyone (including an AI assistant) your GitHub API key or
password. GitHub push happens from **your own machine** with **your own** credentials.
The repo on disk is already clean and sanitized — see SECURITY-AUDIT.md.

## 1. The repo already exists (public, empty initial commit)

`https://github.com/<your-user>/mzd-toolkit` — reading it needs no auth at all
(public repo: `git clone`, Releases, raw files and even the REST API all work
anonymously). Only **writing** (push) needs credentials.

## 2. Push from this machine (you type this, not the AI)

```bash
cd /path/to/mazda-mzd-toolkit-public

# Option A — HTTPS + Personal Access Token (classic, scopes: repo)
#   token: https://github.com/settings/tokens  (store in password manager, NEVER in chat)
#   this host has credential.helper=store, so after one successful login it is cached
#   in ~/.git-credentials
git remote add origin https://github.com/<your-user>/mzd-toolkit.git
git push -u origin main
# first push to an existing repo with an "Initial commit": use -f (safe: nothing to lose)
#   git push -f origin main

# Option B — SSH (recommended long-term)
#   1. upload ~/.ssh/id_ed25519.pub at https://github.com/settings/keys
#   2. verify: ssh -T git@github.com   -> "Hi <your-user>! ..."
git remote add origin git@github.com:<your-user>/mzd-toolkit.git
git push -f origin main
```

**Never** paste a token/key into a chat with an AI assistant — it ends up in logs.
If a token ever leaks: revoke it immediately at https://github.com/settings/tokens.

## 3. First release

```bash
# Build the USB image (fails automatically if secrets leak into the archive)
sh toolkit/tools/build-release.sh 4.8.21 /tmp/mzd-release
# -> mzd-toolkit-v4.8.21.tar.gz (PRIMARY for the car) + .zip (PC only) + SHA256SUMS

git tag v4.8.21
git push origin v4.8.21
```

Then on GitHub: **Releases → Draft a new release → choose tag v4.8.21 → attach the
three files from /tmp/mzd-release → Publish.**

## 4. Every future release

Follow `RELEASE-CHECKLIST.md` in the repo root: scanner self-test → tree scan →
history scan → syntax check → binary check → build → tag → push → GitHub release.

## 5. Repo settings to enable (GitHub web UI, no credentials needed beyond your login)

- Settings → General → Features: **Issues** on, **Discussions** optional, **Wiki** off (we use docs/)
- Settings → Branches → protect `main` (require PR review)
- Settings → Security → **Secret scanning** ON (GitHub alerts if a key ever slips in)
- About (sidebar): description + topics: `mazda`, `mazda-connect`, `cmu`, `mzd`,
  `infotainment`, `can-bus`, `embedded-linux`, `automotive`, `reverse-engineering`
- Description suggestion: "Open-source toolkit for the Mazda Connect CMU: WiFi, SSH,
  USB tethering, wired LAN, CAN/VIM vehicle data, backups — firmware v59/v74. Made with AI."
