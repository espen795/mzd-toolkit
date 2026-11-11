# SSH on v59 — OpenSSH 5.9p1 quirks

The CMU ships **OpenSSH 5.9p1 (September 2011)**. That vintage imposes hard
constraints on both the server config and the client flags. Everything below was
proven on a live v59.00.502 unit.

## 1. Server: what sshd 5.9p1 accepts and rejects

**Allowed / required sshd_config options:**

```
Port 36000                     # stock CMU port is 36000, not 22
PermitRootLogin yes            # REQUIRED — the login user `cmu` is uid 0
PasswordAuthentication yes     # optional (see security note)
PubkeyAuthentication yes
StrictModes no                 # needed because /data_persist and /tmp are 777
AuthorizedKeysFile /data_persist/dev/bin/authorized_keys /tmp/mzd-sshd/authorized_keys /config-mfg/authorized_keys
```

**Forbidden / unsupported (config test fails or daemon won't start):**

- `UsePAM` — unsupported on this build; a `UsePAM yes` line blocks startup.
- `sshd -E <logfile>` — the `-E` flag does not exist in 5.9p1.
- ecdsa / ed25519 host keys — only **rsa** and **dsa**.
- Any modern KEX/cipher options you'd expect from OpenSSH ≥ 7.

**Host keys** live at `/etc/ssh/ssh_host_rsa_key` and
`/etc/ssh/ssh_host_dsa_key`. **Never regenerate them** — clients that pinned
the old key will fail.

**Password hashes:** the v59 libcrypt accepts **DES hashes only** — 13
characters, no `$…$` prefix. Generate + set with `chpasswd` and verify:

```sh
echo 'cmu:mzd' | chpasswd
awk -F: '$1=="cmu"{print $2}' /etc/shadow   # must be 13 chars, no $ prefix
```

## 2. Privilege separation requirements

sshd 5.9p1 needs its priv-sep user and directories, or it won't start:

```sh
# /etc/passwd must contain:  sshd:x:74:74:...
mkdir -p /var/empty /var/run/sshd
chmod 755 /var/empty /var/run/sshd
chown root:root /var/empty /var/run/sshd
```

## 3. StrictModes and directory permissions

With `StrictModes yes` (the stock default), sshd refuses keys in directories
that are group/world-writable. `/data_persist` and `/tmp` are mode 777 on the
CMU, which made the stock sshd silently ignore `authorized_keys`
(`Permission denied (publickey)`). Two options:

- run your own sshd instance with `StrictModes no`, or
- keep the key in a path whose parents are all `755 root:root`
  (e.g. `/config-mfg/authorized_keys`, read-only squashfs).

## 4. authorized_keys locations (all honored by the toolkit sshd)

```
/data_persist/dev/bin/authorized_keys     # canonical persist location (USB-deployable)
/tmp/mzd-sshd/authorized_keys             # runtime copy for the custom instance
/config-mfg/authorized_keys               # read-only factory partition, stock sshd
```

`toolkit/ssh/deploy-key.sh` copies a public key from USB into
`/data_persist/dev/bin/authorized_keys`; the autorun copies it into the runtime
location too.

## 5. Root filesystem must be writable for password auth

The password hash lives in `/etc/shadow` on the read-only rootfs, so password
auth requires:

```sh
mount -o remount,rw /
# ... chpasswd ...
# verify writability first:
touch /.rwtest && rm /.rwtest && echo OK
```

## 6. Client side (from your PC)

Modern OpenSSH clients refuse ssh-rsa/ssh-dss by default. The **mandatory**
flags:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa,ssh-dss \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -p 36000 cmu@<CMU_IP> -i /path/to/id_mzd
```

Persist them in `~/.ssh/config`:

```
Host mzd-cmu
    HostName <CMU_IP>
    Port 36000
    User cmu
    IdentityFile /path/to/id_mzd
    HostKeyAlgorithms +ssh-rsa,ssh-dss
    PubkeyAcceptedAlgorithms +ssh-rsa
```

Key type: **RSA-2048** (`ssh-keygen -t rsa -b 2048`). dss keys also work but are
deprecated even here; ecdsa/ed25519 do **not**.

## 7. Security notes

- Password auth on port 36000 is **brute-forceable over WiFi** (DES hash, no
  rate limiting). Prefer RSA-2048 pubkey auth; if you use a password, make it
  long and random, and firewall the port (`iptables -I INPUT --dport 36000
  -j ACCEPT` — never `-P INPUT ACCEPT`).
- A black screen does **not** mean SSH died — the CMU stays powered (and USB
  powered) while the display times out; SSH sessions persist.
- Helper scripts: `toolkit/ssh/ssh-pwd.sh` (password sshd), `install-ssh.sh`,
  `quick-fix-working.sh`.
