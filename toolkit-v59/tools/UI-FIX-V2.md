# MZD UI Terminal Fix v2 - Documentation

**Date:** 2026-10-30
**Firmware target:** 59.00.502 EU N (Mazda 3 BM, compatibility group 5)
**Analysis based on:** v74 rootfs extraction (`mazda-firmware-analysis/extracted/v74_extracted/rootfs/extracted_rootfs/`)

---

## 🔴 What was WRONG in v1 (ui.sh v1)?

### Bug 1: Wrong path for integration flags
- **v1 did:** set flags in `/mnt/data_persist/integration/`
- **Should be:** set flags in `/data/integration/` (= `/mnt/data/integration/`)

**Why:** In the v74 rootfs, `/data` is a **symlink to `/mnt/data`**:
```
/data -> /mnt/data
/data_persist -> /mnt/data_persist
```

The GUI optionally loads this file (from `jci/gui/index.html` line 33):
```html
<script src="../../data/integration/developer_mode_GuiConfig.js" type="text/javascript"></script>
```

`../../` from `/jci/gui/` = `/` (root), so the path is **`/data/integration/developer_mode_GuiConfig.js`**.

If you put the flags in `/mnt/data_persist/integration/`, the GUI can **never** find them, because `/data` points to `/mnt/data`, not to `/mnt/data_persist`!

### Bug 2: No check whether the `/data` symlink exists
In v59 it is possible that `/data` **does not exist at all** as a symlink. Then loading `developer_mode_GuiConfig.js` fails anyway, regardless of where you put the file.

### Bug 3: developer_mode_GuiConfig.js was not copied
v1 did not copy the GuiConfig to the integration dir. In v74, `developer_mode.sh` does this explicitly:
```sh
cp /jci/gui/common/js/developer_mode_GuiConfig.js /data/integration/developer_mode_GuiConfig.js
```

### Bug 4: systemHooks.sh event 22 was not called correctly
In v74, `SYSTEM_TERMINAL=22` in `systemHooks.sh`:
```sh
$SYSTEM_TERMINAL)
    /jci/scripts/run-terminal.sh
    ;;
```
v1 called `run-terminal.sh` directly without going through systemHooks.

### Bug 5: No reboot instruction
After setting the flags the CMU must **reboot** (Mute + Navi 10s) before the GUI loads the GuiConfig. v1 did not state this clearly.

---

## ✅ How it works NOW (v2)

### Filesystem structure (v74, probably also v59):
```
/                           (root, read-only after boot)
├── data -> /mnt/data       (symlink, data partition)
├── data_persist -> /mnt/data_persist  (symlink, persist partition - WE use this for autorun/SSH)
├── jci/
│   ├── scripts/
│   │   ├── developer_mode.sh    # sets flags in /data/integration/
│   │   ├── systemHooks.sh       # event 22 = SYSTEM_TERMINAL -> run-terminal.sh
│   │   └── run-terminal.sh      # start /usr/bin/terminal -f + ivi-shell focus
│   └── gui/
│       ├── index.html           # loads ../../data/integration/developer_mode_GuiConfig.js
│       └── common/js/
│           ├── GuiConfig.js              # guiConfig object, _setDeveloperMode()
│           └── developer_mode_GuiConfig.js  # calls guiConfig._setDeveloperMode(true)
└── usr/bin/
    ├── terminal    # Weston/Wayland terminal binary
    └── ivi-shell   # IVI shell controller (focus, z-layer, alpha)
```

### Flowchart "Developer Mode ON":
```
1. sh ui.sh dev
   └─> ensure_data_symlink()  # create /data -> /mnt/data if needed
   └─> sh /jci/scripts/developer_mode.sh on  (if it exists)
       └─> mkdir -p /data/integration
       └─> touch /data/integration/developer_mode_on_flag
       └─> touch /data/integration/eth0_on_flag
       └─> cp /jci/gui/common/js/developer_mode_GuiConfig.js /data/integration/
   OR (fallback if developer_mode.sh does not exist):
       └─> set the same flags + copy manually in /data/integration/

2. REBOOT CMU (Mute + Navi 10s)

3. At boot the GUI loads index.html:
   └─> <script src="../../data/integration/developer_mode_GuiConfig.js">
       └─> guiConfig._setDeveloperMode(true)
           └─> screenNameLabelEnabled = true
           └─> showFrameworkErrorAlerts = true
           └─> showStringIdFailure = true

4. Settings menu now shows extra developer items (incl. Terminal trigger)
```

### Flowchart "Start terminal":
```
sh ui.sh terminal
└─> sh /jci/scripts/systemHooks.sh 22
    └─> case 22: /jci/scripts/run-terminal.sh
        └─> modprobe usbhid
        └─> /usr/bin/terminal -f &       # fullscreen terminal
        └─> sleep 1
        └─> ivi-shell -f "Wayland Terminal"   # focus
        └─> ivi-shell -z "Wayland Terminal":10000 &  # z-layer above everything
        └─> ivi-shell -a "Wayland Terminal":255 &    # alpha 255 (opaque)
```

---

## 📁 Files in v2

| File | Purpose |
|------|---------|
| `tools/ui.sh` | Main script: dev on/off, terminal start/stop, status, fix |
| `tools/install-terminal-menu.sh` | Makes terminal setup permanent via autorun in `/mnt/data_persist/dev/bin/` |
| `tools/UI-FIX-V2.md` | This document |

---

## 🚀 Usage

```sh
# On the CMU (via SSH as root, or via USB autorun):

# 1. Developer mode on (sets flags in /data/integration/)
sh /mnt/sdb1/mzd-toolkit/tools/ui.sh dev

# 2. REBOOT: hold Mute + Navi for 10 seconds

# 3. After reboot: Settings -> Terminal button appears
#    OR start directly:
sh /mnt/sdb1/mzd-toolkit/tools/ui.sh terminal

# 4. Close terminal:
sh /mnt/sdb1/mzd-toolkit/tools/ui.sh exit

# 5. Check status:
sh /mnt/sdb1/mzd-toolkit/tools/ui.sh status

# 6. Make permanent (runs at every boot):
sh /mnt/sdb1/mzd-toolkit/tools/install-terminal-menu.sh
# Then reboot: Mute + Navi 10s
```

---

## 🔧 Troubleshooting

### "Terminal button does not appear after reboot"
1. Check `sh ui.sh status` - do you see `/data/integration/developer_mode_on_flag`?
2. Check `ls -la /data` - is it a symlink to `/mnt/data`?
3. If `/data` does not exist: `ln -sf /mnt/data /data` (as root)
4. Check `ls -la /data/integration/developer_mode_GuiConfig.js`
5. Check log: `cat /tmp/mzd-terminal-setup.log`

### "developer_mode.sh not found"
v59 may not have `/jci/scripts/developer_mode.sh`. The v2 ui.sh then sets the flags manually in `/data/integration/`.

### "terminal binary not found"
Check `ls -la /usr/bin/terminal`. If it is missing, the terminal app is not installed on v59.

### "/jci is read-only"
You do NOT need to write to /jci - all flags go to `/data/integration/` (that is on the data partition, writable).

---

## 📚 Sources (v74 rootfs analysis)

- `jci/scripts/developer_mode.sh` - official developer mode script
- `jci/scripts/systemHooks.sh` - event dispatcher (22 = terminal)
- `jci/scripts/run-terminal.sh` - start terminal + ivi-shell focus
- `jci/gui/index.html` line 33 - optionally loads GuiConfig
- `jci/gui/common/js/GuiConfig.js` - `_setDeveloperMode()` function
- `jci/gui/common/js/developer_mode_GuiConfig.js` - calls `_setDeveloperMode(true)`
- Rootfs: `/data -> /mnt/data` symlink (confirmed in extraction)
