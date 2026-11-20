# Vehicle data via D-Bus - signals, scaling, trip logging and analysis

What the CMU exposes about the car on its D-Bus service bus, how to log it,
and how to analyze a capture. Cross-references: ARCHITECTURE-CMU.md (bus
layout), CANBUS-VIM.md (CAN/VIM chain and per-service method lists).

Verification status is marked per item: **verified** = checked against a live
capture on real hardware (CMU firmware v59, 6-speed manual gearbox),
**estimated** = derived from the capture but not cross-checked against the
dashboard / cluster, **unverified** = seen in the dump but meaning or scale
not confirmed.

## 1. How vehicle data reaches the CMU

- The kernel has **no SocketCAN** (`CONFIG_CAN is not set`): no `can0`, no
  `candump`. CAN is handled in userspace by the VIM chip over SPI/IPC
  (see CANBUS-VIM.md).
- The VIP co-processor reads the CAN bus and forwards a **fixed selection** of
  messages. `svcjcivbs` publishes those as D-Bus signals on the service bus:

  ```
  unix:path=/tmp/dbus_service_socket     (interfaces com.jci.vbs.*)
  ```

- Whatever the VIP does not forward is **invisible to the CMU**. For free CAN
  access you need a separate OBD CAN adapter on the diagnostic port.
- Subscribe rather than poll - direct `Get` on signal-backed properties often
  returns nothing:

  ```sh
  dbus-monitor --address="unix:path=/tmp/dbus_service_socket" \
    "type='signal',interface='com.jci.vbs.vdt'"
  # or the wrapper that sets the address automatically: /usr/bin/dbus
  # method calls: jci_dbus_send --print-reply --dest=com.jci.vbs.bcm \
  #   /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0
  ```

## 2. Signals and CORRECTED scale factors

Scales below are the corrected values from the 2026-11-17 review. An earlier
analysis used wrong scales (see the correction notes at the end of this
table) - do not reuse those.

| Signal | Type | Conversion | Status |
|---|---|---|---|
| `vdt.Veh_V_ActlEng` | uint16 | `/100` = km/h | verified (high); only sent while driving; reads ~10 % low vs. GPS distance |
| `bcm.CarSpeedResp` | uint32 | `(v-2500)*4/100` = km/h, **2500 = standstill** | verified (high); linear relation `v = 2500 + Veh_V/4` observed |
| `vdt.EngAout_N_Actl` | uint16 | `x2` = rpm | estimated (raw ~350 at idle -> ~700 rpm); not checked against the tachometer |
| `vdt.VehLong_A_Actl` | uint16 | `(v-4000)/100` = m/s^2 | estimated |
| `vdt.Lateral_Acceleration` | uint16 | `(v-4000)/100` = m/s^2 | estimated |
| `vdt.SteWhlComp_An_Est` | uint16 | `(v-16384)/128` = degrees | estimated |
| `vdt.ApedPos_Pc_ActlArb` | uint16 | `/10` = % throttle pedal | estimated |
| `vdt.FuelPulse` | byte | cumulative counter, wraps at 256 | seen; no calibration to liters |
| `vdt.OdoCount` | byte | counter, wraps | seen |
| `vdt.GlobalRealTime` (also vwm) | uint32 | **unit = 0.1 s** (not unix time, not seconds) | verified (high) |
| `com.jci.time` `GetDatetime` (method return) | uint32 | **unix epoch** - use this as the time axis; correct even when the system clock sits at 1970 | verified (high) |
| `lds.data` `GetPosition` (method return) | int32, uint64, double lat, double lon, ... | GPS position | verified (high) |
| `vwm.Total_Distance` | uint32 | odometer counter (unit unconfirmed) | unverified |
| `eem.SISS*`, `iStp*` | various | start-stop (i-Stop) status | seen |
| `vwm.Camera_high_temperature` | boolean | **heartbeat**: toggles continuously, not a real warning | verified (high) |

Correction notes (mistakes made in an earlier analysis of the same data):

- `bcm.CarSpeedResp` is **not** `/100` - that made standstill read as a
  "constant 25 km/h"; 2500 is zero.
- `vdt.EngAout_N_Actl` is **not** raw rpm - multiply by 2.
- `GlobalRealTime` is **not** seconds - the unit is 0.1 s.

The scales were derived from a capture, not verified against the dashboard;
speed and rpm can deviate on the order of 10 %.

## 3. Gear position is NOT available on D-Bus

- `bcm.GetGearPos` returns `UnknownMethod`; `GearPosNotification` was never
  observed. (The D-Bus method lists in CANBUS-VIM.md come from other firmware
  versions - on this unit the signal simply is not delivered.)
- CAN `0x228` (`TransmDesiredGearPosition`) belongs to the **automatic**
  transmission (TCM) and does not exist on a manual gearbox.
- The number shown next to the speed in the instrument cluster is the PCM
  shift-up indicator: CAN `0x0FD` `PCM_Warning_Status` ->
  `Warn_SilGearPos_D_Dsply` (3 bits, offset 11) + `Warn_ShiftIndicatorLight`
  (offset 3). It goes from the PCM to the instrument cluster, **not** via the
  VIP to the CMU. Readable only with an OBD CAN adapter.
- **Estimation from rpm/speed works**: each gear is a straight line in an
  rpm-vs-speed plot. Illustrative example from one capture: the two dominant
  clusters sat around 60 and 40 rpm per km/h (ratio ~1.5), consistent with
  2nd and 3rd gear. Idle rpm while moving above ~9 km/h means coasting
  (clutch in / neutral). The exact gear numbering is only certain after a
  **calibration drive**: deliberately shift through 1..6 and note the speeds.

## 4. Not available via D-Bus at all

Gear position (manual), turn signals / headlight switch (CAN `0x09A`
`Instrument Cluster Lights`: `Headlight_Switch`, `Turn_Ind_Cmd_Left/Right`,
...), doors, windows, wipers. These need an OBD CAN adapter.

## 5. Logging on the CMU (autolog)

- Script on the CMU: `/data_persist/dev/bin/mzd-dbus-autolog.sh`, started at
  the end of `/data_persist/dev/bin/autorun` (`sh ... &`). A cleaned-up,
  installable copy ships in this repo as `toolkit-v59/tools/autolog.sh`.
- v2 writes, per CMU boot / start:
  - `<usb>/dbus-logs/dbus-b<bootid>-u<uptime>.raw` - full `dbus-monitor`
    output (headers + values)
  - `<usb>/dbus-logs/dbus-b<bootid>-u<uptime>.meta` - START/STOP with reason,
    heartbeat every 30 s
- Bugs fixed in v2 (present in v1): no shell loop with two `date` forks per
  line (~400 forks/s while driving), `trap` so a stop line is always written,
  periodic `sync`, the real PID in the pidfile (v1 wrote a literal `$!`,
  allowing duplicate loggers), waits up to 180 s for the D-Bus socket instead
  of exiting silently, and no separate `.log` file (v1's contained only
  headers without values).
- Stop conditions: `touch /tmp/mzd-dbus-autolog.stop`, or the `.raw` not
  growing for 60 s (engine off).
- Volume: ~140 lines/s stationary, ~210 lines/s driving, roughly 6-7 MB per
  11 minutes.
- Trip separation: one file per CMU boot. The analysis tools also split a
  file into trips themselves on engine-off / >5 min standstill.

## 6. Analyzing a capture (tools/trip-analysis/)

```sh
python3 tools/trip-analysis/parse_dbus.py   <dump.raw> [events.csv]
python3 tools/trip-analysis/analyze_trip.py <dump.raw>
python3 tools/trip-analysis/make_overview_pdf.py <dump.raw> <overview.pdf>
```

- Do **not** run the PDF script with `python3 -I`: numpy/matplotlib live in
  the user site-packages.
- All paths are CLI arguments; nothing is hardcoded.
- `make_overview_pdf.py` works like this:
  1. Parses the dump: any line not starting with a space is a message header
     (`signal` / `method call` / `method return` / `error`); the indented
     lines after it are the values.
  2. Time axis: linear interpolation on line number between `GetDatetime`
     method returns (unix epoch). Never use `GlobalRealTime` as seconds.
  3. GPS: `GetPosition` method returns (`int32`, `uint64`, `double lat`,
     `double lon`).
  4. Speed over the whole capture: `bcm.CarSpeedResp`
     (`(v-2500)*4/100`), resampled onto a 0.5 s grid (last value held).
     `Veh_V_ActlEng` is only sent while driving.
  5. Gear estimate from rpm (x2) / speed, only above 5 km/h.
  6. Pages (A4 landscape, matplotlib `PdfPages`): summary with KPI tiles and
     conclusions, timeline (speed/rpm/throttle/estimated gear), shift
     behavior, driving dynamics (G-G diagram, steering/throttle histograms),
     route (GPS) + warning timeline, and a "what we do and don't get" table.
  7. The script prints a control line at the end
     (`OK <file> dur=... dist=... gps=... ...`). Compare `dist` (from speed)
     with `gps`: they should agree within ~15 %, otherwise a scale is wrong.

### Privacy warning

A raw dump contains **GPS coordinates and timestamps of real trips** - treat
it as personal data: do not publish it, and strip the route page (or the GPS
samples) before sharing a PDF. The repo ships only the tools, never dumps.

## 7. Verified vs. not - summary

| Claim | Status |
|---|---|
| VIP forwards only a fixed selection; no SocketCAN on the CMU | verified |
| Scale factors in section 2 (incl. the three corrections) | verified against a live capture; rpm x2 and the ~10 % speed bias are estimated |
| `GetDatetime` = unix epoch, usable as time axis | verified |
| `GlobalRealTime` unit = 0.1 s | verified |
| `Camera_high_temperature` = heartbeat, not a warning | verified |
| Gear position not on D-Bus; only via CAN 0x0FD (OBD adapter) | verified (method unknown, signal absent) |
| Gear estimation from rpm/speed; cluster ratios | estimated, calibration drive pending |
| `FuelPulse` -> liters, `Total_Distance` unit | unproven |
