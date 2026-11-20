# WARNING-FIX v2 - v74 source analysis & fix

Generated: 2026-10-30
Source: `projects/mazda-mzd/firmware-analysis/extracted/v74_extracted/rootfs/extracted_rootfs/` (cmu150_NA v74.00.324A)

## TL;DR - why the old fix-warning.sh did not work

| Assumption of old script | What v74 source actually says |
|---|---|
| Warning triggers via flags in `/mnt/data_persist/aio/` | **Incorrect.** Nothing in v74 reads `aio/warning_ack` or `no_warn.conf` |
| jci-dialog wrapper in PATH blocks the banner | **Partly.** `/jci/bin/jci-dialog` is a symlink to `/jci/tools/jci-dialog`, but the startup banner is **not** triggered via jci-dialog |
| Writing to `/mnt/data_persist` is enough | `/data_persist` is writable (symlink -> `/mnt/data_persist`), but the banner lives in `/jci` |
| os_unlock not needed | **Incorrect.** `/jci` is read-only; patching systemApp.js fails without remount rw |

**The real mechanism:** the startup banner is the `"Disclaimer"` UI context in `/jci/gui/apps/system/js/systemApp.js`, which at boot starts a timer of **3500 ms** (2 places). There is no separate flag file and no `jci-dialog --warning` call for this banner.

## 1. Disclaimer context in the GUI

File: `jci/gui/apps/system/js/systemApp.js`

- Context definition around line **318-340**:
  ```js
  "Disclaimer" : {
      "template" : "Dialog3Tmplt",
      "controlProperties": { "Dialog3Ctrl": { ... text1Id : 'DisclaimerText', ... } },
      "displayedFunction" : this._displayedDisclaimer.bind(this),
      ...
  }
  ```
- Timer init around line **611-622**: `this._disclaimerTime = { reset:true, remaining:0, ... }`
- Timer start on **2 lines** with the value 3500:
  - line **2483**: `this._disclaimerTime.remaining = 3500;` (in `_displayedDisclaimer`)
  - line **2525**: `this._disclaimerTime.remaining = 3500;` (in `_disclaimerTimedout`)
- Text: `jci/gui/resources/js/system/systemAppDict_en_US.js` line 41:
  `"DisclaimerText" : "Distraction may cause accidents. Do not operate while driving. ..."`
- Context part in `jci/mmui/mmui_config.xml` line 36: `<Context id="Disclaimer" priority="23"/>`
- The GUI loads app-JS via `jci/gui/framework/js/GuiFramework.js` (~line 1953): `path = "apps/" + uiaId` -> `apps/system/js/systemApp.js`, relative to start page `/jci/gui/index.html` (see `jci/opera/run-Opera`: `STARTPAGE="/jci/gui/index.html"`). There is **no** override from `/data_persist` for app-JS; only `index.html` line 33 optionally loads `../../data/integration/developer_mode_GuiConfig.js`.

## 2. warnguide app - something else

`jci/gui/apps/warnguide/` + `jci/mmui/uia/libjciuiawarnguide.so` concerns **vehicle warnings** (TPMS, LDWS, engine, etc.) - NOT the startup banner. Strings like `GUIIFM_Process_Warnguide_*` and `"NoWarnings" : "No Warnings Found"` confirm this. The warnguide app IS in the menu (`systemApp.js` line 749: `appName: 'warnguide'`, `mmuiEvent: 'SelectWarnGuide'`), but this is a separate feature.

## 3. jci-dialog - what it IS for

- Binary: `jci/tools/jci-dialog` (39 KB, ARM, Wayland/cairo). Symlink: `jci/bin/jci-dialog -> /jci/tools/jci-dialog`.
- Usage (from strings): `--warning`, `--title=`, `--text=`, `--cancel-label=`, `--no-cancel`.
- In v74, `jci-dialog` is **never** called from the rootfs at boot for the disclaimer; it IS called by `jci/tools/jci-systemDialog` (diagnostic toggles, e.g. "Developer Mode has been toggled: ON") via `/jci/tools/jci-dialog --title='Result' --text='...' --no-cancel &`.
- `jci/scripts/startSystemScripts.sh` starts `jci-systemDialog` only on diag-code `11`.
- **Conclusion:** a jci-dialog wrapper in PATH helps against diagnostic popups, but NOT against the startup Disclaimer. Still, we place it (defensively) in `/data_persist/dev/bin`, because according to `etc/profile` that path comes **before** `/jci/bin` in PATH:
  ```
  export PATH='/sbin:/usr/sbin:/bin:/usr/bin:/jci/bin/:/resources/dev/bin:/resources/dev/sbin:/data_persist/dev/bin:/data_persist/dev/sbin:/resources/dev/usr/bin'
  ```
  -> `/data_persist/dev/bin/jci-dialog` wins over `/jci/bin/jci-dialog`.

## 4. Writable paths in v74

- `data_persist -> /mnt/data_persist` (symlink, writable). In the rootfs tree `data_persist/` is empty; scripts use `/data_persist/log/...`, `/data_persist/testmode`, `/data_persist/reflash`.
- `data -> /mnt/data` (symlink). `developer_mode.sh` sets flags in `/data/integration/` (`developer_mode_on_flag`, `eth0_on_flag`, `developer_mode_GuiConfig.js`).
- `/jci` is **read-only** (see also the comment in `jci/scripts/developer_mode.sh`: *"/jci is read only now, this doesn't work"* on the opera.ini change). Remount rw is needed to patch `systemApp.js`.
- `etc/profile` sets `LD_LIBRARY_PATH` incl. `/data_persist/dev/lib` -> user-libs become doors for custom binaries.

## 5. Boot flow (sm.conf)

`jci/sm/sm.conf` starts via the state manager among others `stage_1.sh`, `stage_2.sh`, `stage_3.sh`, `stage_usb.sh`, `stage_wifi.sh`, `stage_gap2.sh` (`autorun="yes"`). In v74, `stage_wifi.sh` and `stage_usb.sh` are nearly empty (only shebang) - the old AIO hook in `stage_wifi.sh` therefore does **not** work anymore in v74. `stage_1.sh` is the reliable hook spot for an autorun command.

## 6. User JavaScript / developer mode

`jci/opera/opera_home/opera.ini`:
```
User JavaScript File=$OPERA_DIR/userjs/
User JavaScript=0
User JavaScript on HTTPS=1
```
`User JavaScript=0` disables userjs. `jci/opera/opera_dir/userjs/` contains only `fps.js`. Because `/jci` is read-only, `developer_mode.sh` cannot modify opera.ini (see comment in that script); the developer-mode GUI config is therefore copied to `/data/integration/developer_mode_GuiConfig.js` (loaded by `index.html` line 33). For the disclaimer, however, userjs is not needed - patching `systemApp.js` is direct and sufficient.

## 7. version.ini

`jci/version.ini` contains `JCI_SW_VER="MAZ_CMU-150_74.00.324"` and `JCI_CUSTOM_VERSION_FILE="/jci/version.ini"`. There are no "modified" flags in it; the file is used by `jci-failsafe-version.sh` and update checks. Therefore: **only make a backup, do not modify**.

## 8. The fix (fix-warning.sh v2)

1. **os_unlock** - remount rw of `/`, `/jci`, `/mnt/data_persist`, etc. (from `lib/common.sh`, with inline fallback).
2. **systemApp.js patch** - backup to `systemApp.js.org`, then `sed` both `remaining = 3500;` -> `remaining = 0;` -> disclaimer shows 0 ms and disappears immediately.
3. **jci-dialog wrapper** in `/data_persist/dev/bin/jci-dialog` (PATH precedence) that swallows `--warning`/`--error` and forwards the rest to `/jci/tools/jci-dialog`.
4. **Flag files** in `/data_persist/aio/` + `/data_persist/dev/` (AIO-compat; v74 itself does not read them, but other tools do).
5. **autorun** in `/data_persist/dev/bin/autorun` + hook in `/jci/scripts/stage_1.sh` (backup `.org`) so PATH/LD_LIBRARY_PATH are set correctly at every boot.
6. **version.ini.org** backup (file unchanged).
7. Everything logged via `log_to_usb` to `$USB_MOUNT/mzd-toolkit/logs/toolkit.log` (fallback `/tmp/toolkit.log`).

## 9. Important notes

- On v74.00.331+ fully replacing `systemApp.js` with an older (v70) version can break Wireless CarPlay. v2 therefore patches **only the two `3500` lines with sed** and leaves the rest of the v74 file intact.
- After the fix: restart the CMU (NAV+MUTE 10 s) and check whether the banner is gone.
- If `/jci` remains read-only after the remount (SELinux/mount flags), step 2 fails - check the log. In that case serial/ID7 root is needed.
