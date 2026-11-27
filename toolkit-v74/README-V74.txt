========================================
 MZD TOOLKIT - v74 variant (UNTESTED)
========================================

This folder is the v59 toolkit base PLUS the v74-specific pieces:
  - lib/ensure-rw.sh        rw,sync remount helper (v74 rootfs is RO by default)
  - ssh/sshd_config_v74     your own sshd on port 2222 (stock 36000 = Mazda key only)
  - net/sshd-up-v74.sh      one-shot v74 bring-up: routing + firewall + sshd on 2222
  - aa/                     Android Auto on the original hub (no hub swap)
  - terminal/               permanent "Terminal" item in Applications (RAM-only)

STATUS: the v59 scripts are hardware-tested on v59.00.502. This v74 variant is
NOT fully tested on v74 hardware. Proven on v74.00.324A: the SSH bring-up
(net/sshd-up-v74.sh), Android Auto on the original hub (aa/, see
../docs/ANDROID-AUTO-V74.md), the Applications -> Terminal item (terminal/)
and D-Bus trip logging (tools/autolog.sh).
Everything else is expected to work but is unverified on v74.

See ../docs/V74.md for the working v74 access recipe and what differs from v59.
