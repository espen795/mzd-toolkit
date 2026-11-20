# CAN tooling -- Mazda CMU (HS-CAN @ 500 kbit/s, MS-CAN @ 125 kbit/s)

Tools for reading and decoding CAN traffic on the CMU. The CAN database
(`mazda-can-unified.kcd`) is derived from
[silverchris/Mazda3_Canbus_Messages](https://github.com/silverchris/Mazda3_Canbus_Messages)
(`skyactive.kcd`, `skyactive_new.kcd`, `Vehicle_Settings.kcd`), merged into one
Kayak KCD file. That upstream repository has **no license file**, so the KCD is
NOT redistributed here -- see "Getting the CAN database" below.

IMPORTANT: on the CMU the kernel is built without CAN support
(`# CONFIG_CAN is not set`), so there is no SocketCAN and no `can0` interface.
All CAN traffic is handled in userspace by the VIM/VIP coprocessor. On rooted
setups where a `can*` interface does exist (custom kernel), the scripts below
work as-is; otherwise read vehicle data over D-Bus instead -- see
`docs/CANBUS-VIM.md`.

## Files

| File | What |
|---|---|
| `can-watch.sh [iface] [kcd]` | Live decode: `candump can0 | kcd_decode.py --compact`. Filter: `CAN_IDS="202 215 228" can-watch.sh`. |
| `can-capture.sh [iface] [secs] [out]` | Timed capture (default 30 s) -> `.log` (decoded) + `.log.raw` (raw candump). |
| `can-sniff.sh [iface] [secs] [out]` | Short sniff: which CAN IDs are really alive on this car (count + KCD name). Always do this first, before a long log. |
| `can-summary.py <raw-file> [kcd]` | Count ID frequencies from a raw candump file. |
| `can-log.sh start\|stop\|status` | **Detached trip-logger**: logs raw + decoded to USB (`/tmp/mnt/sd*`, sd_nav excluded -- never `/tmp`), auto-stops after `IDLE_STOP` (60 s) without CAN traffic. Survives SSH logout (nohup). |
| `can-live.sh` | Older alias for live decode with `skyactive_new.kcd` -- prefer `can-watch.sh`. |
| `kcd_decode.py` | Decoder: candump output -> readable signals (offset/length/slope from the KCD). `--compact` = one line per frame. |
| `abbreviations.md` | Abbreviations (PCM, RBCM, HEC/IC, BSM, ...). |

## Getting the CAN database

`mazda-can-unified.kcd` is a merge of the upstream KCD files (83 enriched
messages + HUD_CONFIG 0x4F2 + the 0x480-0x49C settings/customization groups;
on ID collision the version with the most signals wins) and is **not** shipped
in this repo because the upstream repo declares no license. Fetch and build it
yourself:

```sh
git clone --depth 1 https://github.com/silverchris/Mazda3_Canbus_Messages
# merge skyactive_new.kcd + skyactive.kcd + Vehicle_Settings.kcd into
# mazda-can-unified.kcd (keep the entry with the most signals on ID collision),
# then place it next to the scripts in this directory
```

## Most interesting messages for reading

| ID | Name | Interesting signals |
|---|---|---|
| 0x202 | EngineVehicleThrottle | `speed` (km/h, slope 0.0039), `rpm`, `throttle_pos`, accelerator pedal `ApedPosPcActl` |
| 0x215 | Wheel Speed | 4 wheel speeds (16-bit big-endian) |
| 0x228 | transmission | **automatic (TCM) only**: `TransmChangeLeverPosition`, `TransmDesiredGearPosition` |
| 0x0FD | PCM_Warning_Status | **manual gear-shift indicator**: `Warn_SilGearPos_D_Dsply`, `Warn_ShiftIndicatorLight` |
| 0x420 | PCM_Warning_Status | `EngClnt_Te_Actl` (coolant temp degC), `AIR_AMB_ACTL` (outside temp, (v-511)/4 degC), odometer `OdoCount`, `FuelPulse`, all warning lamps |
| 0x09A | lights | indicators, high beam, washer |
| 0x165 | cruise control | `cruise speed`, indicator |
| 0x086 | SteeringWheelAngle | steering angle |
| 0x4FA | Engine_Info | `Engine_Load`, `IntakeAirTemp`, oil deterioration, IDM calc info |
| 0x4F2 | HUD_CONFIG | HUD brightness/position -- **produced by the CMU itself** |
| 0x43E (MS-CAN) | doors | `Door Ajar` bitfield |

## Usage on the CMU

```sh
# live view (SSH into the car, stock port 36000):
./can-watch.sh can0
CAN_IDS="202 215 420" ./can-watch.sh can0     # only speed/rpm/temp
./can-capture.sh can0 60 /tmp/can60.log        # 60 s capture
candump can0 | python3 kcd_decode.py mazda-can-unified.kcd
```

CAN sits behind the VIP coprocessor (`VIP_CAN-MAZ140`); the Linux side talks to
it over SPI via `vim_app`. See `docs/CANBUS-VIM.md` and `docs/VIP-FIRMWARE-RE.md`.

## Trip-logging workflow

```sh
# On the CMU, over SSH (factory default login cmu/mzd on port 36000):
ssh -p 36000 cmu@<CMU_IP>
sh can-sniff.sh can0 30 /tmp/sniff      # validate live IDs
sh can-log.sh start                     # detached, logs to sdx1
# ... drive ... car off => logger stops by itself (60 s no CAN traffic)
sh can-log.sh stop                      # or stop manually
# Logs end up on the USB: /tmp/mnt/sdX1/can-logs/canlog-*.log (+ .raw)
```

## D-Bus alternative (no CAN needed)

For the same data through the CMU's own API: see `docs/CANBUS-VIM.md` -- e.g.
`com.jci.vbs.bcm GetCarSpeed`, `com.jci.vbs.vdt OdoCount`,
`com.jci.vbs.diag ReadCMUFaults_Request`.
