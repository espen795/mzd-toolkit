---
name: Feature request
about: Suggest an idea for the MZD Toolkit
title: "[FEATURE] "
labels: enhancement
assignees: ''
---

**Is your feature request related to a problem? Please describe.**
What are you trying to do on the CMU that the toolkit can't do today?

**Describe the solution you'd like**
What should the toolkit do, and how would you use it (menu option, script, config setting)?

**Environment**
- CMU firmware version (`/jci/version.ini`): e.g. `59.00.502`
- Kernel (`uname -a`): e.g. `3.0.35 ARMv7`
- Toolkit version: e.g. `4.8.21`
- Connection method you'd use: `wlan0` / `usb0` / `eth1`

**Alternatives you've considered**
E.g. existing scripts, workarounds, other projects (MZD-AIO, etc.)

**Hardware constraints to keep in mind**
The CMU runs kernel 3.0.35 / BusyBox: no `unzip`, no `iw`, no system D-Bus, `/` read-only, `wlan0` owned by NMS, `eth0` off-limits, v59 sshd = OpenSSH 5.9p1 (RSA-2048 only, no UsePAM). Scripts must be POSIX sh.

**Additional context**
Screenshots, dmesg excerpts, D-Bus introspection (`dbus-send --address=unix:path=/tmp/dbus_service_socket ...`) — anything that helps.
