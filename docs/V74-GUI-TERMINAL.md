# v74 GUI terminal -- the verified event chain (2026-11)

How to reach `/usr/bin/terminal` from the v74 GUI, what stock firmware does
and does not accept, and which routes actually work. Verified on real
v74.00.324 hardware (`MAZ_CMU-150_74.00.324`) plus static offline analysis
(`strings`/`grep`/`nm`) of the v74 rootfs -- no live CMU was needed for the
binary-level claims.

## 1. Bottom line

- There is **no "Settings -> System -> Terminal" entry in stock v74**. The
  string "Terminal" appears zero times in the stock
  `jci/gui/apps/syssettings/js/syssettingsApp.js`, and
  `libjciuiasyssettings.so` has no reference to `ReadDTC`, `testId` or a
  terminal. The menu entry is 100% a toolkit addition -- which is why the
  whole event chain had to be reverse-engineered instead of just read.
- **Stock v74 drops `ReadDTC testId=22`.** `startSystemScripts.sh` only knows
  code **11**. The terminal is reached through `systemHooks.sh 22`, which on
  stock firmware is only invoked by a *native mouse click* in
  `jci-systemDialog`.
- With a one-line patch to `startSystemScripts.sh` (section 4), `ReadDTC
  testId=22` works directly from GUI JS -- the v59 behavior.
- Synthetic input is possible through the JCI D-Bus devices API
  (`com.jci.cpp.devices.Keyboard`/`Mouse`), through `/dev/uinput`, and via a
  plain USB HID keyboard/mouse (`usbhid`).

## 2. Why testId=22 is dropped on stock v74

The diag/terminal route never runs inside the MMUI layer itself. None of the
46 `jci/mmui/uia/*.so` libraries, nor `svcjcimmui.so`, contain the strings
`systemHooks`, `run-terminal`, `/usr/bin/terminal` or `startSystemScripts`.
Every action towards the outside world goes over a D-Bus hop to a separate
service binary outside `jci/mmui/` -- for the diag route that is
`jci/testdiag/svcjcitestdiag.so` via the client stub `libjcitestdiag_client.so`
(linked into `libjciuiadiag.so`).

`svcjcitestdiag.so` (ARM32, not stripped) exposes D-Bus interface
`com.jci.testdiag` with, among others:

| Method | Arguments | Notes |
|---|---|---|
| `StartRoutine` | `test_id` (in, **byte, 0-255**) -> `return_value` (out) | generic passthrough |
| `ActivateTestMode` / `DeactivateTestMode` | - | |
| `ActivateJCITestMode` / `DeactivateJCITestModeMode` | - | |
| `CommanderInput` | `buttont_id` (in16), `buttont_value` (in16) | -> `TESTDIAG_CommanderInput` |
| `StopCommanderRoutine`, `NotifyDiagLostFocus`, `GetTestInfo`, `GetDiagStatus` | - | |

There is **no separate "event number" besides the testId**: `StartRoutine`
takes `test_id` as its only argument and passes it unchanged all the way to
the final shell call -- the literal format string found in the binary is:

```
/jci/scripts/startSystemScripts.sh %d
```

Internally: `StartRoutine(test_id)` (D-Bus) -> `TESTDIAG_StartRoutine_svc` ->
post `TESTDIAG_SCREEN_ID_EVT` (carrying `test_id`) onto
`g_testdiagStateMachine` -> `system("/jci/scripts/startSystemScripts.sh %d")`.
`TESTDIAG_SCREEN_ID_EVT` is testdiag's own internal state-machine event, not
a separately selectable number.

So **testId=22 works exactly as well as 11 up to and including the exec
call** -- there is no special-casing of any test_id in `svcjcitestdiag.so`.
The "11 only" restriction lives **exclusively in the shell script itself**:

```sh
# /jci/scripts/startSystemScripts.sh (stock v74, verbatim)
if [[ "$1" == "11" ]]; then
    /jci/tools/jci-systemDialog &
else
    echo "Currently only '11' is being used, you typed " $1
fi
```

That script is the single place in the whole chain that blocks "22" -- and the
single place that needs patching.

## 3. The terminal entry: diag menu item 10, page 2, native click

`jci/tools/jci-systemDialog` is a native C++ Wayland/cairo GUI (class
`jci_systemDialog`, not stripped). It contains the literal strings:

```
/jci/scripts/systemHooks.sh %d
TERMINAL        <- item label, index 22 (0-based) in the fixed list
```

The label list in the binary is in exactly the same order and count as the
`case` labels in `systemHooks.sh` (HDCP TOGGLE=1, SPEED TOGGLE=4, ...,
TERMINAL=22, WIFI AP TOGGLE=25, ... NAVIGATE TOGGLE=46), so index "TERMINAL"
= 22 maps one-to-one onto `SYSTEM_TERMINAL=22` in `systemHooks.sh`.

On a click, the C++ code itself does
`sprintf(buf, "/jci/scripts/systemHooks.sh %d", item); system(buf)` -- this is
**not an MMUI event**, just native Wayland mouse handling
(`jci_systemDialog::mouse` / `ws_mouse`, handling `wl_pointer` and
`wl_touch` -- **no keyboard input**). In the on-screen menu, TERMINAL is
**menu item 10 on page 2 (after "Next")**.

Practical consequence: `testId=11` via ReadDTC opens this dialog; from inside
the dialog a click on "TERMINAL" calls `systemHooks.sh 22` directly. That
works on stock firmware with no patch -- but it is two steps (ReadDTC 11, then
a real mouse click on the Wayland surface), not one MMUI event. Synthetic
DOM clicks from Opera JS do not land on this native surface.

## 4. The patch: delegate any code != 11

With shell access (serial `cmu` login, uid 0, or your own sshd), patch
`/jci/scripts/startSystemScripts.sh` so every code other than 11 is delegated
to `systemHooks.sh`:

```sh
sh /jci/scripts/systemHooks.sh "$1"
```

After that, `ReadDTC testId=22` from GUI JS reaches `systemHooks.sh 22` and
opens the terminal directly. `systemHooks.sh 22` itself also works verbatim
from any root shell:

```sh
sh /jci/scripts/systemHooks.sh 22
```

## 5. Synthetic input on v74

Three working layers:

- **D-Bus devices API**: `com.jci.cpp.devices.Keyboard` / `com.jci.cpp.devices.Mouse`
  expose `keyClick` / `buttonClick` / `move` (keyboard keys and mouse buttons
  are injectable over D-Bus, backed by uinput). `libjcidevices.so` references
  `/dev/uinput` and the `filtered-%s` pattern -- synthetic input through the
  devices API is supported.
- **`/dev/uinput` directly**: with root, write HID reports to `/dev/uinput`
  yourself.
- **USB HID**: `usb_drivers.sh` loads `usbhid`, so a plain USB keyboard/mouse
  plugged into the hub works as Wayland input on v74 (the dialog above reacts
  to `wl_pointer`/`wl_touch` from real USB devices; ghost-touch on the CMU
  screen makes a *synthetic* tap on the terminal item unreliable, a real USB
  mouse does not have that problem).

## 6. The MMUI event chain: SelectDiagnostics -> ActivateJCITest -> ReadDTC

The GUI apps are Opera-JS in `/jci/gui/apps/<app>/js/<app>App.js`. The stock,
unpatched `diagApp.js` shows the canonical OEM call (lines 333 and 361):

```js
framework.sendEventToMmui(this.uiaId, "ReadDTC", {payload : { testId: input}});
```

Payload and uiaId forms, both confirmed in binaries:

- **Payload**: always the wrapped form `{payload:{testId:N}}` (proven by stock
  `diagApp.js` and by the parser symbol
  `UIA_DIAG_ReadDTC_Event_PayloadWrapper_t_FromJSON` in `libjciuiadiag.so`).
  An unwrapped `{testId:22}` is not the proven OEM form.
- **uiaId**: always the **string** form ("diag", "syssettings") -- the `name=`
  value from `mmui_config.xml`, never the numeric `uiaid=` attribute. In
  `mmui_config.xml`: `uiaid="21" name="syssettings" lib="libjciuiasyssettings.so"`
  and `uiaid="25" name="diag" lib="libjciuiadiag.so"` (priority 60 > 20, so
  diag may take GUI focus from syssettings). The numeric id is only MMUI's
  internal library-loader index.

Required state transitions for the ReadDTC route:

1. Start: GUI context is syssettings/SystemTab
   (`uiaId="syssettings"`, `currentUiaId="syssettings"`,
   `currentContextId="SystemTab"`).
2. **Step 1**: send `SelectDiagnostics` to `"syssettings"` -- triggers the
   native handler `GUIIFM_Process_Syssettings_SelectDiagnostics_Evt` in
   `libjciuiasyssettings.so`; MMUI hands focus/context to diag.
3. **Wait** for the context switch to actually complete. A fixed delay (~7 s
   in the reference implementation) is the pragmatic choice; the exact
   timeout is not derivable from the binaries.
4. **Step 2**: send `ActivateJCITest` to `"diag"` (context "Diagnostics") --
   maps to D-Bus `TESTDIAG_ActivateJCITestMode` and puts the testdiag state
   machine into test mode. `DeactivateJCITest` maps to
   `DeactivateJCITestModeMode`.
5. **Wait** again.
6. **Step 3**: send `ReadDTC` with `{payload:{testId:22}}` to `"diag"` --
   triggers `GUIIFM_Process_Diag_ReadDTC_Evt` -> D-Bus `StartRoutine(22)` ->
   `startSystemScripts.sh 22`.

### Pitfalls (all observed live, v1.1-v1.9)

- Sending `ReadDTC` directly from the SystemTab context, even with spoofed
  `currentUiaId`/`currentContextId` fields, is **silently dropped**: MMUI's
  real focus must first move via the `SelectDiagnostics` transition. Spoofing
  the fields in the outgoing message does not change MMUI's internal state.
- A single `ReadDTC testId=22` without `ActivateJCITest` is dropped too --
  JCI test mode state is required.
- Chaining the events back-to-back gets stuck on the number screen; the
  pauses between the steps are required.
- On **stock** firmware the chain stops at step 6: `startSystemScripts.sh`
  only knows "11". Either apply the section-4 patch, or deliberately send
  `testId=11` in step 6 and then do the native click on "TERMINAL" in the
  dialog that appears (menu item 10, page 2).
- `jci-systemDialog` is a native Wayland surface with `wl_pointer`/`wl_touch`
  only -- synthetic DOM clicks from Opera JS never reach it, and ghost touch
  makes a synthetic tap unreliable. Use a real USB mouse (section 5) or the
  patched `testId=22` route.

## 7. Working routes on v74 -- summary

| Route | Needs patch? | Notes |
|---|---|---|
| Serial `cmu` login (uid 0) -> `sh /jci/scripts/systemHooks.sh 22` | no | serial is a working root route on v74 |
| Own sshd -> same command | no | stock sshd only accepts the Mazda key from read-only NOR |
| GUI: patched `startSystemScripts.sh` + `SelectDiagnostics` -> `ActivateJCITest` -> `ReadDTC {payload:{testId:22}}` | yes (one line) | the v59 behavior, direct from GUI JS |
| GUI stock: `ReadDTC {payload:{testId:11}}` -> dialog -> Next -> TERMINAL (item 10, page 2) | no | two steps, needs a real click on the native dialog |
| Synthetic input via `com.jci.cpp.devices.Keyboard`/`Mouse` D-Bus, `/dev/uinput`, or USB HID (`usbhid`) | no | for driving the native dialog or other surfaces |
