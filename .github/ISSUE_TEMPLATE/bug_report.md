---
name: Bug report
about: Something in the MZD Toolkit doesn't work on the CMU
title: "[BUG] "
labels: bug
assignees: ''
---

**Describe the bug**
A clear description of what happened vs. what you expected.

**Environment (please fill in — required)**
- CMU firmware version (from `/jci/version.ini`): e.g. `59.00.502`
- Kernel (`uname -a` over SSH): e.g. `Linux 3.0.35 ... ARMv7`
- Toolkit version (banner in `menu.sh`, or `grep TOOLKIT_VERSION toolkit/lib/common.sh`): e.g. `4.8.21`
- Connection method: `wlan0` / `usb0` (tether) / `eth1` (dongle)
- USB dongle model (if relevant, `lsusb` VID:PID): e.g. `0b95:772a` ASIX AX88772
- Phone model + tethering mode (if relevant): e.g. Samsung, RNDIS `04e8:6863` vs AOA `04e8:6860`

**Steps to reproduce**
1. ...
2. ...

**Expected behavior**
...

**Actual behavior**
...

**Logs (required)**
Attach or paste:
- The run log: `mzd-data/logs/runs/vX.Y.Z-<script>-b<boot8>-r<seq>/{stdout.log,stderr.log,exit.code}` (scrub any WiFi passwords / SSH passwords first!)
- Relevant `dmesg` output: `dmesg | grep -iE 'wl12xx|watchdog|wlan|usb|eth' | tail -50`
- `ifconfig -a`, `netstat -tln`, `ps` if network/SSH related
- `/tmp/mzd-autorun.log` if it happens at boot

**Exit code** (if a script printed one): e.g. connect-nms `4`, usb-tether `6`

**Additional context**
Anything else — recent changes, firmware upgrades, USB stick reformats, etc.

> ⚠️ Never paste `secrets.conf`, `id_mzd` private keys, or real WiFi/SSH passwords into an issue.
