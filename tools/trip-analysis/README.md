# Trip analysis tools

Analyze a raw `dbus-monitor` capture from the Mazda CMU service bus
(`unix:path=/tmp/dbus_service_socket`). See `docs/VEHICLE-DATA-DBUS.md` for
the signal list, the corrected scale factors and what is *not* available on
D-Bus (gear position, turn signals, doors, ... - those need an OBD CAN
adapter).

## Capturing on the CMU

Install `toolkit-v59/tools/autolog.sh` on the CMU (e.g. as
`/data_persist/dev/bin/mzd-dbus-autolog.sh`, started from
`/data_persist/dev/bin/autorun`). It writes one pair of files per boot to a
USB stick:

```
<usb>/dbus-logs/dbus-b<bootid>-u<uptime>.raw    full dbus-monitor output
<usb>/dbus-logs/dbus-b<bootid>-u<uptime>.meta   START/STOP + heartbeats
```

Or capture manually:

```sh
dbus-monitor --address="unix:path=/tmp/dbus_service_socket" > /tmp/mnt/sdX1/dump.raw
```

## Analyzing on a PC

All paths are command-line arguments; nothing is hardcoded.

```sh
python3 parse_dbus.py   <dump.raw> [events.csv]   # events + per-signal stats
python3 analyze_trip.py <dump.raw>                # text stats + ASCII charts
python3 make_overview_pdf.py <dump.raw> <out.pdf> # 6-page PDF overview
```

Notes:

- Run `make_overview_pdf.py` with plain `python3`, **not** `python3 -I`:
  numpy/matplotlib live in the user site-packages. Requires numpy and
  matplotlib.
- `make_overview_pdf.py` prints a control line at the end:
  `OK <file> dur=... dist=... gps=... ...`. `dist` (integrated speed) and
  `gps` (haversine over the GPS fixes) should agree within ~15 %; if not, a
  scale factor is wrong.
- The PDF has 6 pages: summary, timeline, shift behavior (estimated gear),
  driving dynamics, route + warnings, data inventory.

## PRIVACY

A raw capture contains **GPS coordinates and timestamps of real trips**.
Treat it as personal data: never commit or publish `.raw` files, and strip
page 5 (route) from the PDF before sharing it.

## Corrected scale factors (do not reuse the old ones)

| Signal | Conversion |
|---|---|
| `bcm.CarSpeedResp` (uint32) | `(v-2500)*4/100` = km/h, 2500 = standstill |
| `vdt.Veh_V_ActlEng` (uint16) | `v/100` = km/h (only sent while driving) |
| `vdt.EngAout_N_Actl` (uint16) | `v*2` = rpm (estimated) |
| `vdt.VehLong_A_Actl` / `vdt.Lateral_Acceleration` | `(v-4000)/100` = m/s^2 |
| `vdt.SteWhlComp_An_Est` | `(v-16384)/128` = degrees |
| `vdt.ApedPos_Pc_ActlArb` | `v/10` = % |
| `vdt.FuelPulse` (byte) | cumulative counter, wraps at 256 |
| `vdt.GlobalRealTime` | unit = **0.1 s** (not seconds, not unix) |
| `com.jci.time` `GetDatetime` return | unix epoch - use as time axis |
| `lds.data` `GetPosition` return | `int32, uint64, double lat, double lon` |
