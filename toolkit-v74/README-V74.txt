========================================
 MZD TOOLKIT - v74 variant (UNTESTED)
========================================

This folder is the v59 toolkit base PLUS the v74-specific pieces:
  - lib/ensure-rw.sh        rw,sync remount helper (v74 rootfs is RO by default)
  - ssh/sshd_config_v74     your own sshd on port 2222 (stock 36000 = Mazda key only)
  - net/sshd-up-v74.sh      one-shot v74 bring-up: routing + firewall + sshd on 2222

STATUS: the v59 scripts are hardware-tested on v59.00.502. This v74 variant is
NOT fully tested on v74 hardware - only the SSH bring-up (net/sshd-up-v74.sh) is
proven on v74.00.324A. Everything else is expected to work but is unverified on v74.

See ../docs/V74.md for the working v74 access recipe and what differs from v59.
