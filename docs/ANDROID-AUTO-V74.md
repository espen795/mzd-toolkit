# Android Auto on v74 with the ORIGINAL USB hub (no hardware hub swap)

**Status:** working, verified on real hardware (firmware `MAZ_CMU-150_74.00.324`, Mazda 3 BM, original Desay USB hub `0424:2640`, USB bus 2). Android Auto appears on the head unit with a phone plugged into the stock hub port (USB device `2-1.2`), without replacing the hub with an aftermarket retrofit module.

This document describes a two-patch software fix plus a brick-proof deploy kit that lives in `toolkit-v74/aa/` of this repository.

## 1. Problem

Android Auto did not work over the original hub. Two blockers in a row, both in the stock CMU binaries:

| # | Where | Check | Consequence |
|---|-------|-------|-------------|
| 1 | `/jci/usbmgr/svcjciusbmgr.so` -> `CUsbMgrUSBDeviceTypeDetector::checkDevAndroidAuto` | `GetBus() == 1` (only the OTG bus) | a phone on bus 2 never gets an AOA request and stays in MTP mode (`04e8:6860`) |
| 2 | `/jci/aapa/blmjciaapa.so` -> `AapProc::ChangeHubSchemeToAvailable` plus gates in `UsbmgrUsbGetHubSchemeWk`/`UsbmgrUsbHubSchemeSignalWk` | hub scheme 1/2/3 -> `available=1` ("AA unavailable"); only scheme 4 (the official AA hub) -> 2; the gates require `available > 1` | aapa never runs `SetupAttributeInfo`/`AapConnectionManager::Init()` -> no RM consumer, no cdrp listener -> phone switches to AOA but no session starts |

The second cable of a retrofit module (OTG / bus 1) is only needed for the CarPlay role switch; Android Auto only needs one host port.

## 2. Solution: two 1-byte patches, bind-mounted at boot

| File | Offset | Original -> patch | md5 stock -> patched |
|------|--------|-------------------|----------------------|
| `svcjciusbmgr.so` | `0xbca27` | `beq` (0x0a) -> `b` (0xea) at `0xbca24` | `413a2569b6528d11a00eb8773a60de80` -> `b6aeec1653a26e36e4e1907832c7cbf3` |
| `blmjciaapa.so` | `0x653b4` | `mov r2,#1` (0x01) -> `mov r2,#2` (0x02) | `486628ae7b5be7c80527968a0b85ae38` -> `a9c44143c0e89d66464269446a7726e0` |

Details of the two instructions (ARM mode, 32-bit; for `svcjciusbmgr.so` the LOAD segment maps file offset 0 to vaddr 0, so file offset == vaddr):

- `svcjciusbmgr.so`, function `CUsbMgrUSBDeviceTypeDetector::checkDevAndroidAuto()` @ `0xbc734`: at vaddr/file-offset `0xbca24` the bytes `1a 00 00 0a` (`beq bca94`) become `1a 00 00 ea` (`b bca94`); i.e. byte `0xbca27`: `0x0a` -> `0xea`. Only the bus condition disappears; registers and stack stay identical, the "unsupported bus type" branch becomes dead code. This check also runs for the device after the AOA switch (`18d1:2d0x`), so both paths pass with the patch.
- `blmjciaapa.so`, function `AapProc::ChangeHubSchemeToAvailable` @ `0x6533c`: at `0x653b4` the bytes `01 20 a0 e3` (`mov r2,#1`) become `02 20 a0 e3` (`mov r2,#2`); i.e. byte `0x653b4`: `0x01` -> `0x02`. `available=2` is exactly the value a stock AA car (scheme 4) reports; the other `GetAvailable()` callers only compare against 3.

### How it works

The stock `.so` files on the root filesystem are **never overwritten**. On every boot, `aa-early.sh` copies the patched files to `/tmp/aa` (tmpfs), verifies their md5, and bind-mounts them over the originals before usbmgr/aapa start:

```
boot -> usb_drivers.sh (hook) -> aa-early.sh -> copy to /tmp/aa + md5 -> bind-mount over /jci/usbmgr/svcjciusbmgr.so and /jci/aapa/blmjciaapa.so -> verify via path + not-noexec -> touch /var/run/usb_driver_ready -> jciUSBMGR -> ... -> jciAAPA
```

Boot order (from the v74 `sm.conf`): `usb_drivers` (sets the `ready_flag`) -> `jciUSBMGR` -> `devicemanager` -> `mfid` -> `jciAAPA`. usbmgr waits for the `ready_flag` of `usb_drivers`, so a hook directly before that `touch` runs before both patched processes load.

The hook is the **only rootfs change**: 2 lines in `/jci/scripts/usb_drivers.sh`, directly before `touch /var/run/usb_driver_ready`. It starts `aa-early.sh` in the background and waits at most about 15 s; afterwards the `touch` happens anyway (fail-open -> stock). Backup `usb_drivers.sh.aabak`. md5 of `usb_drivers.sh`: stock `a52bb42330acedf809da1f02ab76b07d`, with hook `cb2b34823582b55740c8134360c183c1`.

`aa-early.sh` is also the boot hook for the optional *Applications -> Terminal* kit (`toolkit-v74/terminal/`): if `/data_persist/dev/gui/gui-early.sh` exists it is started in the background (detached, it never touches the AA state); if not, nothing happens.

On the CMU the kit lives in `/data_persist/dev/aa/`:

```
/data_persist/dev/aa/
  svcjciusbmgr.so.patched   blmjciaapa.so.patched
  aa-early.sh  aa-guard.sh  aa-install.sh  aa-status.sh  aa-uninstall.sh
  MANIFEST.md5
  (runtime: bootcount, early.log, guard.log, optionally DISABLE, DISABLE_AAPA, disabled, aa.conf, proven)
```

## 3. Brick protection

- Mount only if both the md5 of the stock file and the md5 of the patch match; after mounting, verify again via the path (md5 must be the patch) and that the mount is not `noexec`; otherwise `umount` -> stock.
- **Crash counter** (`bootcount`): incremented (written and read back) before the mount. `aa-guard.sh` resets it to 0 only if usbmgr is alive and network/sshd is up (after the GRACE period, 180 s) and, when the aapa patch is mounted, only from 420 s and only if the **same** `L_jciAAPA` pid is still alive at 480 s and is not a zombie. After 3 failed boots -> `disabled` -> everything stock. If only aapa fails while usbmgr is healthy -> only `DISABLE_AAPA`.
- Disable without SSH: the crash counter, a USB stick with an empty file `AA_BUSPATCH_DISABLE` in its root, or the serial console (`cmu`/`mzd` login, passwords verified against a hash).
- Commands: `aa-status.sh disarm` (everything off) / `disarm-aapa` (aapa only) / `rearm` / `arm` / `arm-aapa`; full return to stock: `sh /data_persist/dev/aa/aa-uninstall.sh --restore-hook` (restores the exact stock `usb_drivers.sh`) + reboot.
- **Proven mode:** after 5 healthy boots with the exact same patch combination, short trips no longer count as failed boots (the counter is not incremented). Any unhealthy judgement revokes proven mode; a safety net (`PROVEN_MAXSHORT`, default 20) revokes it after 20 consecutive boots without a health judgement, so a crash loop still falls back to stock after about 23 boots.
- **Uninstall before any firmware update:** run `aa-uninstall.sh --restore-hook` first. A firmware update replaces the rootfs, so the hook disappears anyway, and the md5 checks make the patches skip automatically on a different firmware.

## 4. Install

**This public repository does NOT ship the patched Mazda binaries** (copyright). The kit in `toolkit-v74/aa/` contains the 5 shell scripts, `MANIFEST.md5`, and the patch tool `tools/make-patched.py`. You patch your own stock files on a PC:

1. Connect to the CMU over generic SSH (see `docs/V74.md` for how to get root SSH on v74; the sshd listens on port 2222):
   ```sh
   ssh -p 2222 cmu@<CMU_IP>
   ```
2. Copy your own stock binaries from the CMU to your PC and verify they are the expected stock files:
   ```sh
   scp -P 2222 cmu@<CMU_IP>:/jci/usbmgr/svcjciusbmgr.so .
   scp -P 2222 cmu@<CMU_IP>:/jci/aapa/blmjciaapa.so .
   md5sum svcjciusbmgr.so blmjciaapa.so
   # must be 413a2569b6528d11a00eb8773a60de80 and 486628ae7b5be7c80527968a0b85ae38
   ```
3. On the PC, run the patch tool from the kit:
   ```sh
   python3 toolkit-v74/aa/tools/make-patched.py svcjciusbmgr.so blmjciaapa.so outdir/
   ```
   It verifies the stock md5 of both inputs, flips the two bytes (`0xbca27`: `0x0a`->`0xea`; `0x653b4`: `0x01`->`0x02`), and verifies the patched md5. Output in `outdir/`: `svcjciusbmgr.so.patched` (md5 `b6aeec1653a26e36e4e1907832c7cbf3`) and `blmjciaapa.so.patched` (md5 `a9c44143c0e89d66464269446a7726e0`). If a stock md5 does not match, the tool refuses: your firmware is not `74.00.324` and this patch does not apply.
4. Stage the files on the CMU. Create `/data_persist/dev/aa/stage/` and copy into it: the two `.patched` files, the 5 scripts (`aa-early.sh`, `aa-guard.sh`, `aa-install.sh`, `aa-status.sh`, `aa-uninstall.sh`) and `MANIFEST.md5` from `toolkit-v74/aa/`. Example over SSH:
   ```sh
   ssh -p 2222 cmu@<CMU_IP> 'mkdir -p /data_persist/dev/aa/stage'
   for f in outdir/svcjciusbmgr.so.patched outdir/blmjciaapa.so.patched \
            toolkit-v74/aa/scripts/aa-early.sh toolkit-v74/aa/scripts/aa-guard.sh \
            toolkit-v74/aa/scripts/aa-install.sh toolkit-v74/aa/scripts/aa-status.sh \
            toolkit-v74/aa/scripts/aa-uninstall.sh toolkit-v74/aa/MANIFEST.md5; do
     cat "$f" | ssh -p 2222 cmu@<CMU_IP> "cat > /data_persist/dev/aa/stage/$(basename "$f")"
   done
   ```
5. On the CMU, verify the transfer against the manifest and run the installer (fresh install: hook into `usb_drivers.sh` + `DISABLE` + `DISABLE_AAPA`, i.e. everything stays stock until you arm it):
   ```sh
   ssh -p 2222 cmu@<CMU_IP> 'cd /data_persist/dev/aa/stage && md5sum * && cat MANIFEST.md5'
   # the two listings must be identical, then:
   ssh -p 2222 cmu@<CMU_IP> 'cd /data_persist/dev/aa/stage && sh aa-install.sh && sh /data_persist/dev/aa/aa-status.sh'
   ```
   Expected: "Hook added ... md5 cb2b3482... read back", `DISABLE : YES`, `DISABLE_AAPA : YES`.
6. Reboot the CMU (ignition off, wait about 1 min, ignition on), then check that SSH comes back and the hook did nothing (everything stock):
   ```sh
   ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh check'
   ```
7. Arm the usbmgr patch and reboot **without a phone** connected. Wait at least 4 minutes (guard judgement at 180-240 s), then check:
   ```sh
   ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh arm'
   # ignition off / on, phone NOT connected, wait >= 4 min:
   ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh check'
   ```
   Success = bind-mount ACTIVE from `/tmp/aa/svcjciusbmgr.so`, "usbmgr via path: PATCHED", guard.log "healthy at ...s ... bootcount=0", navigation/SD card OK.
8. Arm the aapa patch and reboot **without a phone**, wait at least 9 minutes (the guard only judges aapa at 420 s and confirms at 480 s):
   ```sh
   ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh arm-aapa'
   # ignition off / on, phone NOT connected, wait >= 9 min:
   ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh check'
   ```
   Success = both bind-mounts ACTIVE, `L_jciAAPA` pid alive, guard.log "healthy at 480s (usbmgr=1 net=1 aapa=1 pid=N) -> bootcount=0", no warnings.
9. Only now plug the phone into hub port 2 (`2-1.2`), accept the Android Auto dialogs on the phone, and check again. Android Auto should appear on the screen. Do the first phone tests with the car stationary and someone present.

### Command reference (`aa-status.sh`)

All commands run on the CMU as root, e.g. `ssh -p 2222 cmu@<CMU_IP> 'sh /data_persist/dev/aa/aa-status.sh <cmd>'`:

| Command | Effect |
|---------|--------|
| `status` | show mounts, md5 via path, pid/maps, DISABLE flags, counter, proven state |
| `check` | full health check with warnings (sshd, network, SD nav, dmesg, free space) |
| `arm` | activate the usbmgr patch (takes effect next boot) |
| `disarm` | deactivate everything (`DISABLE`) |
| `rearm` | clear `disabled`/counter after analysis (keeps DISABLE) |
| `arm-aapa` | activate the aapa patch (only if counter is 0 and everything verifies) |
| `disarm-aapa` | deactivate only the aapa patch |
| `unprove` | revoke proven mode (strict counting again) |

Uninstall / rollback: `sh /data_persist/dev/aa/aa-uninstall.sh --restore-hook` restores the exact stock `usb_drivers.sh` and disables everything; `--purge` also removes the files. Always do this **before a firmware update**.

## 5. Note on the kit scripts

The kit shell scripts are shipped **unchanged** from the hardware-tested version, so their comments and log messages are in **Dutch**. `MANIFEST.md5` covers all 5 scripts and both payloads; do not edit them (the installer refuses to run if a file deviates from the manifest).

## 6. Known points and limits

- Two or three boots shortly after each other (under 3 min, or under 8 min with aapa armed) count as failed -> after 3 -> `disabled` (stock, harmless). Recovery: `sh /data_persist/dev/aa/aa-status.sh rearm` (+ `arm-aapa` if needed). In proven mode (5 healthy boots) short trips no longer count.
- A crash **after** the guard judgement (e.g. during an AA session) is outside the counter: after an unexpected reboot with the phone plugged in, **first unplug the phone**, then `disarm-aapa`.
- Every non-Apple device on bus 2 now gets one AOA request (vendor GET_PROTOCOL on endpoint 0). Devices that do not know it just STALL and are ignored; no effect observed on the nav-SD reader / ethernet adapter.
- Optional tuning lives in `/data_persist/dev/aa/aa.conf` (`KEY=value` lines only, never sourced): `MAXFAIL` (default 3), `GRACE` (180 s), `AAPA_GRACE` (420 s), `PROVEN_N` (5, 0 = off), `PROVEN_MAXSHORT` (20).
- **Only tested on one car / one firmware** (EU `74.00.324`, original Desay hub `0424:2640`, bus 2). Other regions, firmware versions, or hub types are untested; the md5 checks make the kit refuse to patch anything that does not match exactly.
