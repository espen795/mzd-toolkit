# Release checklist (run before every GitHub release)

## One-time setup: your personal denylist (never committed)

Create `~/.config/mzd-release-denylist.txt` (or point `MZD_RELEASE_DENYLIST` at another file).
One extended regular expression per line, matched case-insensitively. Put in it everything that
must never appear in a public repository: your own name and the names of family members, your
domains, your hotspot SSID, the MAC addresses of your devices, the prefix of your home LAN.
Lines starting with `#` and empty lines are ignored.

Without this file only the built-in generic checks run (private keys, API tokens, SSH key blobs,
`/home/<user>/` paths and internal IPv4 addresses). The scanner prints a note when the file is missing.

## Every release

1. **Prove that the scanner works**

   ```sh
   sh toolkit/tools/scan-secrets.sh --self-test      # must end with: SELF-TEST PASSED
   ```

2. **Scan the working tree** (scripts, docs, drivers)

   ```sh
   sh toolkit/tools/scan-secrets.sh .                # must end with: scan-secrets: CLEAN
   ```

   Documentation placeholders are fine: `192.168.0.x`, `192.168.1.x`, `<CMU_IP>`, `YOUR_SSID`,
   `aa:bb:cc:dd:ee:ff`.

3. **Scan the git history** - a leak that was fixed in the latest commit still lives in old commits

   ```sh
   sh toolkit/tools/scan-secrets.sh --history        # must report: N commit(s) CLEAN
   ```

   If it reports findings and the repository has never been pushed, squash the history into a single
   commit first. If it was already pushed, treat whatever leaked as compromised, rotate it, and rewrite
   the history (for example with `git filter-repo`) before the repository is made public.

4. **Syntax-check every script with the target shell** (the CMU runs BusyBox ash)

   ```sh
   find toolkit -type f \( -name '*.sh' -o -name autorun \) -exec busybox ash -n {} \; -print
   ```

   `dash -n` is a good second opinion. Both must be silent apart from the file names.

5. **Check the binaries**: every `.ko` / `.bin` must be a real binary (the scanner's binary layer
   rejects, for example, an HTML login page saved as `x.ko`).

6. **Build the release**

   ```sh
   sh toolkit/tools/build-release.sh X.Y.Z /tmp/mzd-release
   ```

   The build fails if secret/runtime files, or anything the scanner flags, end up inside an archive.

7. **Tag and publish**

   ```sh
   git tag vX.Y.Z && git push origin main --tags
   ```

   Create the GitHub release and attach `mzd-toolkit-vX.Y.Z.tar.gz` (primary - the CMU has `tar` and
   `gzip` but no `unzip`), `mzd-toolkit-vX.Y.Z.zip` (PC only) and `SHA256SUMS`.

For changes that run on the car, also follow the hardware testing steps in `CONTRIBUTING.md` and `docs/TESTING.md`.
