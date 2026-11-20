# Rootfs diff report: Mazda CMU firmware v59 vs v74

**Date:** 2026-11-11
**Analysis:** Mazda CMU-150 rootfs images (MAST container format)
**Files:**
- v59: `cmu_rootfs_v59.img` (93.6 MB / 98,140,160 bytes / `0x5D98000`)
- v74: `cmu_rootfs_v74.img` (477.9 MB / 501,153,792 bytes / `0x1DDF0000`)

---

## 1. Container format: MAST

Both images start with an identical **MAST header at offset 64 (0x40)**:

```
00000040  4d 41 53 54 0c 00 01 02 00 10 00 00 f0 dd 01 00   MAST............
00000050  ac a0 b0 03 00 00 00 00 58 58 58 58 58 58 00 00   ........XXXXXX..
00000060  00 00 00 00 00 00 00 00 ee dd 01 00 ef dd 01 00   ...............
00000070  ec dd 01 00 ed dd 01 00 00 00 00 00 00 00 00 00   ...............
```

| Field | Offset | Value | Meaning |
|---|---|---|---|
| magic | 0x40 | `MAST` | container magic |
| page size | 0x48 | `0x1000` (4096) | page size |
| total pages | 0x4C | `0x1DDF0` | = v74 file size / 0x1000 (501,153,792 bytes) |
| serial | 0x58 | `<HW_SERIAL>` (6 ASCII chars, redacted) | hardware serial |
| partition pages | 0x68-0x74 | `0x1DDEE, 0x1DDEF, 0x1DDEC, 0x1DDED` | 4 META/JMET blocks at end of image |

**Important:** the MAST header is **identical** in both images -- v59 is a truncated version (93.6 MB) of the same container structure. The internal data is a **relfs** (Datalight Reliance Nitro v2.7) filesystem -- visible from strings such as `relfs.ko`, `Reliance Nitro v2.7.`, `flash_relfs_part "/dev/ffx01" "1" "${ROOTFS}" "rootfs"`. File paths are embedded as ASCII strings in the image (relfs stores metadata in JMET blocks at the end; see `0x1DDEC000` = `JMET` magic with entries like `syssettingsApp.j...`).

**Kernel:** both images contain kernel **3.0.35 SMP preempt mod_unload ARMv7** (i.MX6). **BusyBox v1.19.2** in both. **OpenSSH 5.9p1** in v74 (v59 likewise per toolkit docs).

---

## 2. Diff summary

v74 is **5x larger** than v59 (478 MB vs 94 MB). All paths found in v59 are also present in v74 -- v59 is a strict subset. In v74, **1,395 extra file paths** were found (849 -> 2,244 unique paths).

| Category | v59 | v74 | New in v74 | Removed |
|---|---:|---:|---:|---:|
| `/jci` total | 471 | 954 | 483 | 0 |
| -- JCI C++ framework (`/jci/cpp`) | 265 | 332 | 67 | 0 |
| -- BLM config (`/jci/blm`) | 47 | 207 | 160 | 0 |
| -- DSP configs (`/jci/dsp`) | 4 | 41 | 37 | 0 |
| -- Native GUI images (`/jci/nativegui`) | 3 | 209 | 206 | 0 |
| -- GUI Opera HTML5 (`/jci/gui`) | 1 | 3 | 2 | 0 |
| -- JCI libs (`/jci/lib`) | 10 | 15 | 5 | 0 |
| -- Opera browser (`/jci/opera`) | 4 | 7 | 3 | 0 |
| -- AppSDK (`/jci/appsdk`) | 1 | 3 | 2 | 0 |
| -- Scripts (`/jci/scripts`) | 55 | 56 | 1 | 0 |
| -- Other `/jci` | 214 | 393 | 179 | 0 |
| `/etc` total | 60 | 168 | 108 | 0 |
| -- SSH config (`/etc/ssh`) | 8 | 16 | 8 | 0 |
| -- D-Bus config (`/etc/dbus-1`) | 0 | 7 | 7 | 0 |
| `/config-mfg` | 6 | 9 | 3 | 0 |
| `/data_persist` | 6 | 24 | 18 | 0 |
| `/usr` | 36 | 230 | 194 | 0 |
| `/lib` (kernel modules) | 3 | 94 | 91 | 0 |
| `/var` | 49 | 138 | 89 | 0 |
| `/boot` (dev headers) | 1 | 33 | 32 | 0 |
| `/home` (build paths) | 3 | 81 | 78 | 0 |
| D-Bus service names (`com.jci.*`) | 442 | 1265 | 823 | 0 |

---

## 3. MAST header & internal structure

- **Offset 0x00-0x3F:** null padding
- **Offset 0x40 (64):** `MAST` magic + metadata (see table above)
- **Offset 0x1000:** start of relfs data (first file: `busybox`)
- **Offset 0x1DDEC000-0x1DDEE000 (v74):** 4 trailing blocks:
  - `0x1DDEC000` / `0x1DDED000`: **JMET** blocks -- relfs metadata with file names (`syssettingsApp.j`, `s.test-restore`, `syssettingsAppDi`, `ct_en_US.js`)
  - `0x1DDEE000` / `0x1DDEF000`: **META** blocks -- partition tables with page pointers

---

## 4. Storage layout: NOR flash vs eMMC

The CMU-150 has two distinct non-volatile storage devices, and a `.up` firmware update treats them very differently:

| Area | Device | Writable? | Effect of a `.up` update |
|---|---|---|---|
| `/config-mfg` (incl. `authorized_keys`, `passwd`, factory data) | **NOR flash** (`mtdblock5`) | read-only | **never overwritten** -- survives every firmware update |
| `/` rootfs (relfs on `/dev/ffx01p1`), `/jci`, `/etc`, `/usr` | **eMMC** | read-only at runtime (remountable rw) | **fully overwritten** by the update |
| `/data_persist` (autorun hook, dev tools, keys, logs) | eMMC data partition | read-write | survives the update, **but** `neutralizeid7` deletes `/data_persist/dev/bin/autorun` on every update |

Consequences for toolkit users:

- The stock `sshd_config` points at `AuthorizedKeysFile /config-mfg/authorized_keys` -- a read-only NOR location. Keys placed there survive updates; keys only in the rootfs or in the autorun hook do not.
- After any `.up` update the autorun hook is gone (`neutralizeid7`), so the rescue/autorun hook must be re-installed (see `V74-UPDATE-PROCEDURE.md` and `V74-ACCESS.md`).

---

## 5. New `/jci/` paths in v74 (selected)

### 5.1 GUI / Opera HTML5 UI
| Path | Note |
|---|---|
| `/jci/gui/common/js/developer_mode_GuiConfig.js` | **New developer mode hook** -- in v74 copied by `developer_mode.sh` to `/data/integration/developer_mode_GuiConfig.js` |
| `/jci/opera/DEMO/demo1.html`, `demo2.html` | Opera demo pages |
| `/jci/opera/opera_home/opera.ini` | Opera home config |
| `/jci/nativegui/images/` (206 paths) | PNG icons incl. `HorizontalSensors/BackCtr_*.png`, `BackLt_*.png`, `BackRt_*.png` -- **rear-view camera UI** |

### 5.2 AppSDK
| Path | Note |
|---|---|
| `/jci/appsdk/appsdk_plugin_config.xml` | AppSDK plugin config (new in v74) |
| `/jci/appsdk/plugins/` | plugin directory |

### 5.3 Kernel modules in `/jci/` root (new in v74)
```
/jci/com_jci.ko
/jci/com_jci_cpp_nvram.ko
/jci/cpp_os_ver_char.ko
/jci/cpp_os_ver_proc.ko
/jci/jci_panic.ko
/jci/dsrc_acm.ko
/jci/com.jci.cpp.drivers.DebugLed.ko
/jci/com.jci.cpp.drivers.GpioChip.ko
/jci/com.jci.cpp.drivers.KmsgFilter.ko
/jci/com.jci.cpp.drivers.Led.ko
/jci/com.jci.cpp.drivers.Log.ko
/jci/com.jci.cpp.drivers.lvds_drv.ko
```

### 5.4 New JCI libraries (`/jci/lib/`)
```
libjciahaservice.so      (Apple CarPlay/HAS service -- NEW)
libjcicommon.so          (NEW)
libjcidbus.so            (D-Bus client lib -- NEW)
libjcilvds_server.so     (LVDS display server -- NEW)
libjciusbmgrcomm.so      (USB manager comm -- NEW)
```
Libraries present in both: `libjci.so`, `libiap.so` (Apple iAP), `libbttr.so`, `libjcibttrcpp.so`, `libjciahaplugin.so`, `libjcistitcherservice.so`, `libpandora.so`, `libstitcher.so`.

**CarPlay / Android Auto:** v74 ships the Apple CarPlay stack natively (`libjciahaservice.so`, `libjciahaplugin.so`, `libiap.so` iAP2, `/jci/cdrp/rm_iap_conflict_conf.xml`, and the `/jci/blm/btrvr/*` Siri/EyesFree keys). This is why a v74 update overwrites any previously installed CarPlay/Android Auto retrofit -- see `V74-UPDATE-PROCEDURE.md`.

### 5.5 BLM config (160 new keys)
New in v74: `/jci/blm/bthf/*` (8 keys: AutoAnswer, DoNotDisturb, RingTone...), `/jci/blm/btrvr/*` (7 keys: Siri/EyesFree), `/jci/blm/msg/*` (36 keys: SMS/email/MAP timeouts), `/jci/blm/navi/*`, `/jci/blm/radio/*` (12 keys), `/jci/blm/vwm/*` (19 keys: vehicle warning messages), `/jci/blm/traffic/EnabletrafficFeature`, `/jci/blm/vdtcon/FsProtocol/SnifferEnabled`.

### 5.6 DSP configs (37 new XML files)
`/jci/dsp/dsp_J03-*.xml`, `dsp_J12-*.xml`, `dsp_J36A-*.xml`, `dsp_J53-*.xml`, `dsp_J71-*.xml`, `dsp_J72Array2-*.xml`, `dsp_J78Array-*.xml`, `dsp_hoshiden_*.xml` -- each with `-Bose.xml` and `-NoBose.xml` variants. v59 had only 4 DSP configs.

### 5.7 Scripts -- empty stage scripts in v74
- New: `/jci/scripts/set_hci_logging.sh` (Bluetooth HCI logging)
- All 55 v59 scripts are also present in v74, including `stage_wifi.sh`, `start_network.sh`, `start_wifi.sh`, `usb_drivers.sh`, `config-update.sh`, `jci-log.sh`, `start_eth1_dhcp.sh`.
- **On v74 the "stage" scripts are empty (shebang only)** -- but `sm` still executes them, so a hook line appended to them still works. `start_network.sh` does have real content and runs as root at boot (loads usbnet/asix, starts eth1 DHCP, starts sshd) -- a good hook point.

### 5.8 JCI C++ framework (`/jci/cpp/`)
New subdirs in v74: `bar/` (12 type defs), `foo/` (12 type defs), `msgs/` (5 settings), `nvram/` (Block.cpp, LinuxBlock.cpp), `config/`, `offboard/`, `test/`. Growth in `common/` (93->111), `devices/` (24->31), `settings/` (41->53).

### 5.9 Navigation (NNG)
```
/jci/nng/NNG_debugging_OFF.ini
/jci/nng/NNG_debugging_ON.ini
/jci/nng/NNG_debugging_ON_Path.ini
/jci/nng_twn/          (TWN = Taiwan navigation)
/jci/navi2NNG/         (navi to NNG bridge)
```

### 5.10 SKU / region files (`/jci_mazda/` -- new in v74)
```
/jci_mazda/sku_aus.ini, sku_eu.ini, sku_feur.ini, sku_gcc.ini, sku_hkg-mac.ini,
sku_isr.ini, sku_jap.ini, sku_latam.ini, sku_na.ini, sku_rus-tur-eu.ini, sku_saf.ini,
sku_sea.ini, sku_twn.ini   (+ .PK variants)
/jci_mazda_api/global.ui, main.ui
```

### 5.11 Other new /jci paths
- `/jci/cdrp/rm_iap_conflict_conf.xml` -- iAP conflict config
- `/jci/settings/configurations/blm_*-system.xml` (33 files)
- `/jci/nms/nms_config.xml`, `/jci/nms/plugins/libjcinms{net,wifi}.so`
- `/jci/vcm/vcm_config.xml`, `/jci/vui/vui_config.xml`, `/jci/vui/tts/tts_config.xml`
- `/jci/mmui/mmui_config.xml`
- `/jci/dbapi/plugins.xml`, `/jci/dbapi/plugins/libdbapi`
- `/jci/ttsplayer/tts_config.xml`
- `/jci/testapp/atcommands.xml`
- `/jci/utils/uca_mazda_cmu_eu_*.zip` (collation tables: cyrillic, greek, hebrew, latin1, latin2) + `libjcitextcoll_uca.so`
- `/jci/bthf/prompts/IncomingCall_*.wav` (33 languages)
- `/jci/audiosettings/*.xml` (BeepPlay, BTHFVolumePrompt, NAVIVOLVolumePrompt, RINGTONEVolumePrompt)
- `/jci/integration/config-mfg-bak`
- `/jci/Desktop/`, `/jci/bsp/`, `/jci/build_release/`, `/jci/documentation/`, `/jci/default/`, `/jci/msgs/`

---

## 6. `/etc/` changes

### 6.1 SSH (`/etc/ssh/`) -- **config identical, extra files in v74**

**sshd_config is byte-identical in v59 and v74:**
```ini
Port 36000
AddressFamily inet
Protocol 2
PermitRootLogin yes
StrictModes no
RSAAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /config-mfg/authorized_keys
PasswordAuthentication no      # CI-2953
PermitEmptyPasswords yes
ChallengeResponseAuthentication no
AllowAgentForwarding yes
AllowTcpForwarding yes
UsePrivilegeSeparation no
Compression no
```

| File | v59 | v74 |
|---|---|---|
| `ssh_host_rsa_key`, `ssh_host_dsa_key`, `ssh_host_key` | yes | yes |
| `ssh_host_ecdsa_key` | no | yes **NEW** |
| `sshd_config`, `sshd` | yes | yes |
| `ssh_config` (client) | no | yes NEW |
| `moduli`, `primes` | no | yes NEW |
| `ssh_known_hosts`, `ssh_known_hosts2`, `shosts.equiv`, `sshrc` | no | yes NEW |

**Security relevant:** `AuthorizedKeysFile /config-mfg/authorized_keys` -- the pubkey lives in `/config-mfg/authorized_keys` (present in both versions). `PasswordAuthentication no` -- password auth is OFF in the stock config (the toolkit has to patch this).

**Important for root access after an update:** `/config-mfg` sits in **NOR flash** (`mtdblock5`, read-only) and is **never** overwritten by a `.up` firmware update -> SSH keys placed there keep working after every update.

### 6.2 D-Bus (new in v74)
```
/etc/dbus-1/system.conf, session.conf, hmi.conf, service.conf
/etc/dbus-1/hmi.d/, service.d/
/etc/dbus-1/machine-id
/var/run/dbus/system_bus_socket, pid
/var/lib/dbus/machine-id
```
v59 had no `/etc/dbus-1/` config paths -- v74 adds an extra `hmi.conf` bus next to the existing `service.conf`.

### 6.3 Bluetooth (new in v74)
```
/etc/bluetooth/main.conf, audio.conf, input.conf, network.conf, serial.conf
```

### 6.4 Other new /etc files in v74
`/etc/.pwd.lock`, `/etc/aliases`, `/etc/asound.conf`, `/etc/blkid.tab`, `/etc/hosts.allow`, `/etc/hosts.deny`, `/etc/exports`, `/etc/nsswitch.conf`, `/etc/ld.so.preload`, `/etc/fuse.conf`, `/etc/gpsd/device-hook`, `/etc/default/gpsd`, `/etc/iAP/Bundle.txt`, `/etc/iAP/Protocols.txt`, `/etc/pki/nssdb`, `/etc/pki/tls/certs/`, `/etc/ssl/certs/ca-certificates.crt`, `/etc/dlt.conf`, `/etc/dlt-system.conf`, `/etc/eventlog.conf`, `/etc/machine-id`, `/etc/DeviceManagerCfg.txt`, `/etc/MSC/MountPath.txt`, `/etc/MSC/MountReadOnly`, `/etc/persistency_dal_blacklistExample.txt`, `/etc/opkg/`, `/etc/popt.d/`, `/etc/arm_systype`, `/etc/ppp/auth-up`, `/etc/ppp/auth-down`, `/etc/cert/ca.pem`, `/etc/cert/ca2.pem`, `/etc/cert/user.pem`, `/etc/cert/user.prv`, `/etc/publickey`, `/etc/e164_cc`, `/etc/egd-pool`, `/etc/entropy`.

---

## 7. `/config-mfg/` and `/data_persist/` (security-relevant)

### 7.1 `/config-mfg/` -- SSH authorized_keys location (NOR flash)
| File | v59 | v74 |
|---|---|---|
| `authorized_keys` | yes | yes (unchanged path -- this is the AuthorizedKeysFile) |
| `bt_addr.dat`, `csr_maxtxpwr.dat`, `<factory-serial>.dat`, `testmode.conf`, `wl1271-nvs.bin` | yes | yes |
| `eol_test_date.dat` | no | yes NEW |
| `fvt_test_date.dat` | no | yes NEW |
| `mfg-version.ini` | no | yes NEW |

### 7.2 `/data_persist/` -- autorun & logs
| Path | v59 | v74 |
|---|---|---|
| `/data_persist/dev/bin/autorun` | yes | yes (autostart hook point -- deleted by `neutralizeid7` on every `.up` update; the toolkit patches `stage_wifi.sh` to link to it) |
| `/data_persist/dev/bin`, `dev/lib`, `dev/sbin` | yes | yes |
| `/data_persist/reflash/backup/convert/settings` | yes | yes |
| `/data_persist/log/error_logs/` | yes | yes |
| `/data_persist/log/dumps/`, `partition_usage/`, `saved_logs/`, `saved_resource_data/` (+ count files) | no | yes NEW (more extensive logging) |
| `/data_persist/compactwnn`, `devmgr_debug`, `testmode.conf`, `vwm_flexible_support`, `reflash` | no | yes NEW |
| `/mnt/data_persist/dev/bin/autorun`, `/mnt/data_persist/reflash/backup/convert/favorites/update-fav-data.flg` | yes | yes |

---

## 8. D-Bus services (`com.jci.*`)

- **v59:** 442 unique `com.jci.*` names
- **v74:** 1,265 unique names -- **823 new, 0 removed**

New services in v74 (filtered, 143 of them), among others:
```
com.jci.appsdkclient              -- AppSDK client (NEW)
com.jci.WaylandManager            -- Wayland display manager (NEW)
com.jci.V4LCAMCLIENT               -- V4L camera client (NEW)
com.jci.Driverid                  -- driver identification (NEW)
com.jci.BTPairing                 -- BT pairing service (NEW)
com.jci.guiManager                -- GUI manager (NEW)
com.jci.email / com.jci.email_client  -- email (NEW)
com.jci.dab_client                -- DAB radio (NEW)
com.jci.audio.amplifier           -- audio amp control (NEW)
com.jci.blm.msg.*                 -- messaging BLM (NEW: am, bca, pb, settings, tts)
com.jci.blm.navi / navi2ihu_client -- navigation (NEW)
com.jci.cpp.drivers.*             -- new kernel driver services (DebugLed, GpioChip, Led, Log, lvds_drv, KmsgFilter)
com.jci.cpp.nvram                 -- NVRAM service (NEW)
com.jci.lvds.*                    -- LVDS display services (NEW)
com.jci.mmui.nms_client           -- NMS client via MMUI (NEW)
```

Services present in both: `com.jci.vbs.radio`, `com.jci.audio.am_client`, `com.jci.rm_ipc_*`, `com.jci.settings.tv_client`, etc.

---

## 9. Security changes summary

| Aspect | v59 | v74 | Impact |
|---|---|---|---|
| sshd port | 36000 | 36000 | unchanged |
| `AuthorizedKeysFile` | `/config-mfg/authorized_keys` | same | unchanged -- pubkey route keeps working |
| `PasswordAuthentication` | `no` | `no` | unchanged -- toolkit patch needed for password auth |
| `PermitRootLogin` | `yes` | `yes` | unchanged -- cmu user is uid 0 |
| ssh host keys | RSA + DSA | RSA + DSA + **ECDSA** | v74 sshd supports more key types |
| OpenSSH version | 5.9p1 | 5.9p1 (strings) | same -- only RSA/DSA pubkeys accepted by the client |
| Certificates | `/jci/certificates/jci_root_cert.pem` | + `dev/jci_root_cert.pem`, `certcrl.pem` | v74 has dev + production CRL |
| `/jci/keys/` | -- | `mazpubkey.pem`, `private_key.pem` | v74 contains private key material in the rootfs |
| D-Bus | service bus only | + **hmi.conf** (extra bus) | v74 has 2 D-Bus sockets: `/tmp/dbus_service_socket` + `/tmp/dbus_hmi_socket` |
| developer mode | `developer_mode.sh` present | + `developer_mode_GuiConfig.js` -> `/data/integration/` | v74 has an explicit developer mode GUI hook |
| `/etc/ppp/auth-up`, `auth-down` | no | yes | v74 has PPP auth hooks |
| `/usr/sbin/usb_authd` | no | yes | v74 has a USB auth daemon |

**`neutralizeid7`:** on v74 this binary runs during every `.up` update and deletes the `/data_persist/dev/bin/autorun` hook -- after each update the rescue/autorun hook must be re-installed manually (see `V74-UPDATE-PROCEDURE.md`, post-update re-root steps in `V74-ACCESS.md`).

---

## 10. GUI changes (Opera HTML5)

- `/jci/gui/index.html` -- present in both
- `/jci/gui/common/js/developer_mode_GuiConfig.js` -- **new in v74**, copied by `developer_mode.sh` to `/data/integration/developer_mode_GuiConfig.js` and loaded by `index.html` if present there. Enables `screenNameLabelEnabled`, `showFrameworkErrorAlerts`, `showStringIdFailure`.
- `/jci/opera/DEMO/demo1.html`, `demo2.html` -- new
- `/jci/opera/opera_home/opera.ini` -- new
- 206 new PNG images in `/jci/nativegui/images/` -- incl. `HorizontalSensors/BackCtr_*.png` etc. -> **rear-view camera (BCA) UI assets** added in v74.

---

## 11. Version info (version.ini strings)

Both images contain the following in the `version.ini` region (offset ~`0x01B89058`):
```ini
[VersionInfo]
JCI_OEM_PART_NUMBER="BHS3-669C0-"
JCI_SW_PART_NUMBER="SWI10-23001-704R03"
JCI_SW_VER="MAZ_CMU-150_59.00.502"
```
The v74 image additionally contains `MAZ_CMU-150_59.00.503` and `MAZ_CMU-150_58.78.006` strings (older versions in reflash/backup code). The `JCI_SW_VER` inside the image itself is **59.00.502 in both** -- the v74 label lives in the MAST container/serial, not in version.ini. Other version strings in v74: `58.77.999`, `58.77.001-004`, `54.59.106`, `54.86.100`, `52.13.100`, `72.31.255` (GPS module versions).

---

## 12. Conclusion & implications for the toolkit

1. **v74 is a superset of v59** -- nothing removed, 1,395 paths added. Rollback to v59 is technically possible via reflash.
2. **SSH config unchanged** -- port 36000, `AuthorizedKeysFile /config-mfg/authorized_keys`, `PasswordAuthentication no`, `PermitRootLogin yes`. The toolkit pubkey route via `/config-mfg/authorized_keys` or `/data_persist/dev/authorized_keys` keeps working. v74 sshd does have an extra `ssh_host_ecdsa_key` -- modern clients can still only use RSA/DSA (OpenSSH 5.9p1 server).
3. **D-Bus doubled** -- v74 runs 2 buses (`service` + `hmi`). NMS WiFi connectivity (`com.jci.nms`) exists in both, but v74 has 823 extra service names.
4. **Developer mode** is more explicit in v74 (`developer_mode_GuiConfig.js` -> `/data/integration/`).
5. **New kernel modules** in the `/jci/` root of v74 (driver .ko files) -- loaded via `/jci/scripts/` stage scripts (which are empty in v74 but still executed).
6. **Larger attack surface:** `/jci/keys/private_key.pem`, `/etc/cert/user.prv`, `/usr/sbin/usb_authd`, PPP auth hooks -- v74 contains more credential material in the rootfs.
7. **WiFi (NMS)** scripts (`start_wifi.sh`, `stage_wifi.sh`) unchanged in path -- the v74 WiFi instability (known from toolkit docs) evidently lives in binaries/libs, not in scripts.
