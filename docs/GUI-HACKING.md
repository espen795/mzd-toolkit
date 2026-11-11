# GUI hacking — injecting a Terminal menu into Settings

How the toolkit adds a **Terminal** entry under Settings → System, and the
pitfalls that cost us a debugging session. Verified on v59.00.502
(`MAZ_CMU-150_59.00.502`).

## 1. The two UI layers (recap)

- **Opera-JS apps** in `/jci/gui/apps/<app>/js/<app>App.js` — this is where the
  Settings app (`syssettings`) lives: `/jci/gui/apps/syssettings/js/syssettingsApp.js`.
- **NNG-Lua skins** in `/jci/skin/*.zip` with `_mods.lua` / `_hooks.lua`
  (Mazda's official hook points for the look layer).

The terminal patch works on the **Opera-JS layer**.

## 2. Anatomy of the syssettings patch

Three coordinated edits to `syssettingsApp.js`:

### (a) The static helper array must contain the new entry

`_SystemTabHelperArray` (around lines 315–351) maps tab keys to
`{ "index": N }`. Without a `"terminal"` entry,
`this._SystemTabHelperArray["terminal"]` is `undefined` and the tab never
renders:

```js
"terminal": { "index": 8 }     // appended to the static array
```

### (b) The generated list item must use QUOTED strings

This was the actual root cause of the "Loading..." spinner hang (the label is localized per UI language). The generator
(`tools/add-terminal-menu.sh`, awk-based) initially emitted **unquoted JS
identifiers**:

```js
// WRONG (what awk produced):
appData : SelectTerminal, text1Id : Terminal, itemStyle : style01
// CORRECT:
appData : 'SelectTerminal', text1Id : 'Terminal', itemStyle : 'style01'
```

The JS engine throws:

```
GUI_FRAMEWORK[568] Error: Caught exception in 'readyFunction' for syssettings SystemTab
Error.message: "Undefined variable: SelectTerminal"
  at syssettingsApp.js:4901 in _populateListCtrl -> _SystemTabCtxtTmpltReadyToDisplay
```

…the exception happens inside `readyFunction`, so the tab never finishes
loading and stays on the spinner forever.

**Lesson:** when generating JS with awk, always emit quoted strings
(`'\''...\''` quoting inside awk), and **validate the result before applying**
(`node --check file.js` on a PC, or grep for unquoted identifiers). The GUI
error log is `/tmp/Log.txt_00.log` — always check it when a menu hangs on
"Loading..." (the spinner label, localized per UI language).

### (c) The event handler must target the right uiaId

The `case "SelectTerminal":` handler originally used `this.uiaId` (which is
`"syssettings"`, uiaid 21) for the ReadDTC call — MMUI then routes to the wrong
service. It must be **`"diag"` (uiaid 25, see `mmui_config.xml`)** with
**testId 22**:

```js
sendEventToMmui("diag", "ReadDTC", { payload: { testId: 22 } })
```

## 3. The full patch (as applied, md5-verified)

File: `/jci/gui/apps/syssettings/js/syssettingsApp.js`

1. ~line 4906: quotes added around `SelectTerminal` / `Terminal` / `style01`.
2. ~line 352: `"terminal": { "index": 8 }` added to the static
   `_SystemTabHelperArray`.
3. ~line 2055: `sendEventToMmui("diag", "ReadDTC", {payload:{testId:22}})`
   instead of `this.uiaId`.

Also add the visible string to the dictionaries:
`/jci/gui/resources/js/syssettings/syssettingsAppDict_<locale>.js` must contain
the `"Terminal"` label.

**Backups (Mazda's own convention):** before every JS tweak, copy the original
to `<file>.js.org` — the stock firmware itself ships `systemApp.js.org` next to
`systemApp.js` (with the disclaimer timer changed 3500 → 0), so `.org` =
original backup. The toolkit uses `syssettingsApp.js.bak-terminal-fix` +
`.org`.

## 4. Activation

- The patched JS is only loaded when the HMI starts → **reboot the CMU**
  (hold **Mute + Navi ~10 s**), then Settings → System → Terminal (under About).
- Or run the terminal directly without a reboot:
  ```sh
  sh /jci/scripts/systemHooks.sh 22     # SYSTEM_TERMINAL=22
  # or:
  sh /jci/scripts/run-terminal.sh       # execs /usr/bin/terminal -f
  killall terminal                      # close it
  ```

## 5. Exploration tools

- `tools/gui-dump.sh` — pulls the whole `/jci/gui` + fonts + skin + resources
  to USB with an `MANIFEST.md5` (4169 entries) and `SUMMARY.txt` (version.ini).
  ⚠️ known bug: the BusyBox `sed -E` masking step can silently produce a
  **0-byte** masked file when it fails — treat empty masked files as "mask
  failed", not "empty on the CMU".
- `tools/os-map.sh` — maps the `/jci` tree.
- The best **D-Bus API documentation** is offline: `skin/jci_mazda_api.zip →
  api_xmls/*.xml` (NNGServerApi-DBUS.xml etc.).
- `vehsettingsApp.js` exports a huge set of `Get*/Set*` methods
  (`SetAutoHeadlightSensitivity`, `SetDaytimeRunningLights`, `SetBSM*`,
  `SetHBC`, `SetHUD*`, …) — every vehicle tweak is a
  `framework.sendRequestToDbapi(uiaId, cb, api, method, params)` call, with
  valid values listed in the same app files.

## 6. Checklist for any GUI JS patch

1. Backup: `cp file.js file.js.org`.
2. Generate with quoted strings; run `node --check` on the result.
3. Register the tab in the static helper array with a free index.
4. Use the correct uiaId for MMUI routing (check `mmui_config.xml`).
5. Reboot (Mute+Navi 10 s); check `/tmp/Log.txt_00.log` for
   `GUI_FRAMEWORK … Error` lines.
6. Keep the patch persistent by having the autorun re-apply it after updates
   (`/data_persist/dev/bin/autorun`).
