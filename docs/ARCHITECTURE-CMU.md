# CMU system architecture

How the Mazda Connect CMU is put together at runtime — the layers the toolkit
hooks into. Verified against a live `MAZ_CMU-150_59.00.502` (cmu150_EU) via full
GUI + logs dumps.

## 1. Big picture

```
┌──────────────────────────────────────────────────────────────┐
│  HMI: Opera Presto 2.12 browser page  /jci/gui/index.html    │
│  (Johnson Controls "JCI-IHU", © 2011–2013)                    │
│   ├─ talks over 3 WebSockets (localhost):                     │
│   │    ws://<ip>:2700  MMUI   "ihu-guiifm-protocol"  main GUI  │
│   │    ws://<ip>:2766  DBAPI  "ihu-dbapi-protocol"  key/value  │
│   │    ws://<ip>:2800  AppSDK "ihu-appsdk-protocol" app svcs   │
│   └─ does NOT speak D-Bus itself (grep 'dbus' in gui/*.js = ∅)│
├──────────────────────────────────────────────────────────────┤
│  Second UI layer: NNG-Lua skins in /jci/skin/*.zip            │
│   (_mods.lua / _hooks.lua = Mazda's own official patch hooks) │
├──────────────────────────────────────────────────────────────┤
│  Backend services (svcjci*.so) on two custom D-Bus daemons:   │
│   service bus  unix:path=/tmp/dbus_service_socket  (com.jci.*)│
│   HMI bus      unix:path=/tmp/dbus_hmi_socket                  │
│   env: JCI_SERVICE_BUS / JCI_HMI_BUS                          │
├──────────────────────────────────────────────────────────────┤
│  VBS (svcjcivbs.so) + modules libjcimod_*.so                  │
│   └─ VIM (vim_app, libjcivim_api.so) ──SPI/IPC──► VIM chip    │
│        ──► Public + Private CAN bus                           │
└──────────────────────────────────────────────────────────────┘
```

Key facts:

- **There is no standard D-Bus system bus** (`/var/run/dbus/system_bus_socket`
  does not exist). Two custom dbus-daemons run instead. Every `dbus-send` /
  `dbus-monitor` call must use `--address="unix:path=/tmp/dbus_service_socket"`
  (or set `DBUS_SESSION_BUS_ADDRESS` to that socket), otherwise you silently get
  zero services and empty captures. `/usr/bin/dbus` is a wrapper that sets the
  right address automatically.
- The kernel has **no SocketCAN** (`# CONFIG_CAN is not set`); CAN goes through
  the VIM chip over SPI/IPC (see CANBUS-VIM.md).

## 2. The Opera HMI layer (`/jci/gui/`)

- Entry point `/jci/gui/index.html` hardcodes the script load order ("ORDER IS
  IMPORTANT"):
  `GuiConfig → logDefaults → Log → ../../data/integration/developer_mode_GuiConfig.js → Utility → Websockets → GuiResources → BaseApp → GuiFramework → Localization → Debug → Multicontroller → Transitions`.
- `GuiFramework.js` (~111 KB) is the heart: `routeMmuiMsg` / `routeDbapiMsg` /
  `routeAppsdkMsg`, `sendEventToMmui`, `sendRequestToDbapi(uiaId, cb, api,
  method, params)`, `sendRequestToAppsdk`, plus context/template/focus-stack and
  transition logic (`instantiateTemplate`, `instantiateControl`,
  `_transitionChange`).
- Layout: `framework/` (8 JS), `common/` (Common.js 92 KB, GuiConfig.js,
  Multicontroller, ContextCategory, logDefaults), `common/controls/` (19
  reusable controls), `common/templates/`, `common/transitions/`,
  `resources/js/` (per-app dictionaries, ~40 locales per app), and
  `apps/<37 apps>/` each with `js/ css/ images/` (9 apps also have
  `templates/`: diag, dvd, ecoenergy, emnavi, hdtrafficimage, idm, syssettings,
  system, vsm). Largest apps by JS line count: ecoenergy (46 files), system
  (42), idm / hdtrafficimage / diag (40).
- File census of a full dump: 2547 JS, 1350 PNG, 131 CSS, 34 SCSS. Fonts are
  58 TTF / 44 MB (mostly CJK).
- `gui/resources/js/` contains dictionaries for apps that do **not** live in
  `gui/apps/` — `carplay`, `siri`, `vui`, `xmaudio`, `xmdata` — i.e. CarPlay /
  Siri / XM radio resources exist but their app code runs natively on the
  MMUI side.
- `guiConfig._setDeveloperMode(true)` (in
  `gui/common/js/developer_mode_GuiConfig.js`, copied to
  `/data/integration/developer_mode_GuiConfig.js`) enables
  `screenNameLabelEnabled`, `showFrameworkErrorAlerts`,
  `showStringIdFailure`. Mazda convention: the flag files
  `developer_mode_on_flag`, `cpugauge_off_flag`, `eth0_on_flag` under
  `/mnt/data/integration/` are **empty files whose presence = enabled**.

### The three WebSockets are an input surface

Ports 2700 (MMUI), 2766 (DBAPI), 2800 (AppSDK) on localhost accept GUI
commands. A JS injection via developer mode, or a proxy in front of these
sockets, equals remote control of the HMI. The toolkit's terminal-menu patch
(see GUI-HACKING.md) works by injecting into the syssettings app that talks to
these sockets.

## 3. The NNG-Lua skin layer (`/jci/skin/*.zip`)

Two UI layers sit on top of each other:

1. **Opera-JS** (`/jci/gui`) for app logic.
2. **NNG-Lua** skins in `/jci/skin/*.zip` for the Mazda "look".

- `_skin_jci_mazda.zip` (~9.5 MB, 1466 files) = 1458 **BMP bitmaps** in
  `ui_jci_mazda/800_480/` + `main_scheme.ui` + `.vpr`/`.spr` + `info.ini` (skin
  version e.g. `9.12.129.694912`). Colors/images live here as bitmaps, **not**
  in CSS. Replacing skin zips changes the look without touching JS.
- Per-feature zips (`tmc.zip`, `weather.zip`, `gas_prices.zip`, `help.zip`,
  `driveralerts.zip`, `hwydrive.zip`, `mapcustom.zip`, `junctionview.zip`, …)
  contain `ui_jci_mazda/common/ui/*.lua` + `.ui` + `.css` + **`_mods.lua` /
  `_hooks.lua`** + `ux/<feature>/global.ui`. `_mods.lua`/`_hooks.lua` are
  Mazda's *official* patch mechanism for this layer.
- `skin/jci_mazda_api.zip` = `api_xmls/*.xml` — **the best D-Bus documentation
  available** (`NNGServerApi-DBUS.xml` 39 KB, `navi2NNG-DBUS.xml`,
  `SystemIPCApi-DBUS.xml`, …), readable without the car.
- `north_america.zip` = `scheme/day/color.ini` — per-region color schemes.

## 4. D-Bus services and the VIM/VBS chain

The backend services (`svcjci*.so`) own the `com.jci.*` names on the service
bus. Full inventory, method lists and CAN IDs are in CANBUS-VIM.md. The chain
is:

```
GUI/MMUI/apps  ──WebSocket──►  svcjci* services  ──D-Bus──►  VBS modules
   (svcjcimmui, svcjcieem, …)      com.jci.vbs.*              (libjcimod_*)
                                                                  │
                                                                  ▼
                                              vim_app ──SPI/IPC──► VIM chip ──► CAN
```

`svcjcivbs` (VBS) keeps all current vehicle data in **shared memory** —
`/dev/shm/smdb_vdm*` (`smdb_vdm_vdt_current_data`, `smdb_vdm_vdt_pid_data`,
`smdb_vdm_vdt_history_data`, `smdb_vdm_vdt_odr_data`,
`smdb_vdm_vdt_warninglamp_data`, `smdb_vdm_vdt_warninglamp_history_data`,
`smdb_vdm_vdt_settings_data`, `smdb_vdm`). Mazda's own `/jci/bin/smdb-read`
binary parses these — a useful fallback when D-Bus signals are quiet.

## 5. Boot / autorun hook chain

```
/jci/scripts/stage_wifi.sh  ──►  /data_persist/dev/bin/autorun
```

- `/` is `relfs` on `/dev/ffx01p1`; `/jci` lives on it. There is no separate
  read-only `/jci` mount — remount `/` `rw` to patch GUI files.
- `/data_persist` (`/dev/mmcblk0p2`, 572 MB, `relfs rw`) is the **only
  partition that reliably survives and is writable** — the toolkit installs to
  `/data_persist/mzd-toolkit` and its autorun hook to
  `/data_persist/dev/bin/autorun`.
- The toolkit also patches `stage_1.sh` in addition to `stage_wifi.sh`
  (idempotent, `.org` backups, 3-strike fail-counter that restores the original).
- `warning_ack`: writing `1` to `/data_persist/aio/warning_ack` and
  `/data_persist/dev/no_warn` suppresses the startup warning dialogs.

## 6. Process notes

- `vim_app` runs as a daemon (multiple threads); `svcjcivbs` runs with ~56
  threads. SPI is live (`spidev` loaded, `spi_imx` interrupts 63/64/66).
- NMS (`com.jci.blm_nms`) **owns** `wpa_supplicant` and `udhcpc` — never start a
  second wpa_supplicant and never kill NMS's udhcpc (check the pid path first).
- `wpa_supplicant` is started by NMS with `-c /tmp/wpa_supplicant.conf`
  (the toolkit's config), **not** `/etc/wpa_supplicant.conf`.
- wpa_supplicant's control socket is per-interface:
  `/var/run/wpa_supplicant-wlan0/` — plain `wpa_cli -i wlan0` fails with
  "non-global ctrl_ifname"; use `wpa_cli -p /var/run/wpa_supplicant-wlan0 -i wlan0`.

## 7. Privilege separation for sshd

The stock OpenSSH 5.9p1 sshd needs its priv-sep user and directories:

- user `sshd` with **uid 74** in `/etc/passwd`,
- `/var/empty` and `/var/run/sshd` (mode 755, root:root).

Without these, sshd refuses to start (or its config test fails). See
SSH-V59.md for the full quirks list.
