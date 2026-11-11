# CAN bus & VIM — how vehicle data actually flows

Reference for reading (and why writing is risky) CAN data on the CMU.
Derived from firmware analysis (v59 and v74) plus live logs.

## 1. There is no SocketCAN

The kernel is built **without CAN support**:

```
# CONFIG_CAN is not set
```

So there is no `/dev/can0`, no `ip link type can`, no candump. CAN traffic is
handled entirely in userspace by the **VIM** (Vehicle Interface Module):

```
┌─────────┐    ┌────────────────────┐    ┌───────────┐   SPI/IPC   ┌─────────┐   ┌──────────────┐
│  VBS    │───►│  VIM daemon        │───►│ VIM chip  │◄────────────│ VIM chip│──►│ Public +     │
│svcjcivbs│    │  /jci/vim/vim_app  │    │ (fw)      │              │         │   │ Private CAN  │
└────┬────┘    └────────────────────┘    └───────────┘              └─────────┘   └──────────────┘
     │                  ▲
     │                  │ libjcivim_api.so (IPC channel)
     ▼                  │
┌─────────────────────────────┐
│ modules libjcimod_*.so      │   can · bcm · eem · vwm · vdt · diag · settings …
└─────────────────────────────┘
```

## 2. The VIM API (`/jci/lib/libjcivim_api.so`)

Client programs talk to `vim_app` over an IPC channel:

```c
VIMC_Open()               // open IPC channel to the VIM server
VIMC_AddClient(callback)  // register as a CAN client (multiple clients allowed)
VIMC_SendMessage(...)     // send a CAN message
VIMC_ControlSPIComm()     // SPI control
VIMC_Close()              // close connection
VIMC_DeleteClient()       // deregister
```

VIM commands include `VIM_CMD_SEND_MESSAGE`, `VIM_CMD_VBS_SEND_MESSAGE`,
`VIM_CMD_ATOD_SEND_MESSAGE`, `VIM_CMD_PWR_SEND_MESSAGE`,
`VIM_CMD_SET_APP_CONTEXT`.

`/jci/vim/vim-ping` is a stock test tool that exercises exactly
`VIMC_Open → VIMC_AddClient → VIMC_SendMessage`.

### Raw-CAN reference implementation: `libjcitaplgcanl.so`

`/jci/testapp/plugins/libjcitaplgcanl.so` (one of 15 test plugins in
`/jci/testapp/plugins/`) shows the pattern:

```c
TAPLGCANL_ConnectToVIM();
TAPLGCANL_OpenCANBus(port);        // port 0 = public CAN, 1 = private CAN
// register callback TAPLGCANL_CANBusReceiveDataEvent
// received frames logged as: "CAN data: ID=%X, length=%d"
// send: "Sending CAN message to CAN port: %u (SPI ID: 0x%04X)"
// ready flag: "Sending message ReadyFlag 0x144 to VIM"
```

**Multiple clients can be registered at once** — `libjcimod_can.so` (VBS),
`libjcitaplgcanl.so` (test app) and `svcjciupdatea.so` (update service) all
register simultaneously. You can attach your own passive client next to the
stock ones without disturbing the CMU — ideal for sniffing.

## 3. VBS module API (`/jci/vbs/modules/libjcimod_can.so`)

```c
VBS_BUS_CAN_RegisterReceiveHandler()         // public CAN
VBS_BUS_CAN_RegisterReceiveHandler_Public()  // public CAN
VBS_BUS_CAN_RegisterReceiveHandler_Private() // private CAN
VBS_BUS_CAN_SendHandler()
VBS_BUS_CAN_ExtractData() / _Public() / _Private()
MODCAN_GetIndividualData()
MODCAN_GetDataOnePIDMask() / GetDataTwoPIDMask() / GetDataSplMask()
```

## 4. D-Bus exposure — the practical way to read vehicle data

The VBS modules re-publish the interesting CAN data as D-Bus methods/signals on
the **service bus** (`unix:path=/tmp/dbus_service_socket` — NOT `--system`!).

### ⚠️ Use the right bus

```
# WRONG (silently empty — the standard system bus does not exist on the CMU):
dbus-monitor --system "type='signal'"

# CORRECT:
dbus-monitor --address="unix:path=/tmp/dbus_service_socket" "type='signal',interface='com.jci.vbs.eem'"
dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply --dest=... ...
# or export DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/dbus_service_socket"
# or use the /usr/bin/dbus wrapper which sets it for you
```

### Service inventory (`com.jci.*`)

| Service | Module | Purpose |
|---|---|---|
| `com.jci.vbs.bcm` | `libjcimod_bcm.so` | speed, gear, wheels, brake, ignition, CAN status |
| `com.jci.vbs.eem` | `libjcimod_eem.so` | fuel economy, trip, i-Stop, CO2, **battery SOC** |
| `com.jci.vbs.vwm` | `libjcimod_vwm.so` | warnings, alerts, maintenance, DTC-related |
| `com.jci.vbs.diag` | `libjcimod_diag.so` | DTC read/clear, routines, VIN |
| `com.jci.vbs.settings` | `libjcimod_settings.so` | 80+ vehicle settings |
| `com.jci.vbs.vdt` | `libjcimod_vdt.so` | drive logging (`/data/vdt/`) |
| `com.jci.vbs.navi` | `libjcimod_navigation.so` | VIN, HUD, TMC, fuel type |
| `com.jci.eem` | `svcjcieem.so` | fuel-eco service |
| `com.jci.vwm` | `svcjcivwm.so` | warning service |
| `com.jci.vdt` | `svcjcivdt.so` | VDT service |
| `com.jci.vsm` | `libjciuiavsm.so` | Vehicle Status Monitor UI |
| `com.jci.settings` | `svcjciblmsettings.so` | generic key-value store |
| `com.jci.cpp.power` | `svcjcipower.so` | ACC status, safe shutdown/reboot |
| `com.jci.blmsystem` | `svcjciblmsystem.so` | system state |
| `com.jci.dataretrieval` | `dataRetrieval` | Mazda's own "collect everything to USB" tool |

### BCM methods (examples)

```
GetCarSpeed(u) → u            GetWheelSpeed() → (qqqqqqt)
GetGearPos() → y              GetIgnitionStatus() → y
GetBrkPedalDepressedStatus()  GetPrkBrkActv()
GetPublicCanStatus() / GetPrivateCanStatus()
```
Signals: `CarSpeedResp`, `WheelSpeedNotification`, `GearPosNotification`,
`BrakePedalDepressedStatus`, `IgnitionControl_Status`, `BatteryVoltageFlag`,
`PublicCanStatusNotification` / `PrivateCanStatusNotification`.

### EEM — the signals we actually used

On `com.jci.vbs.eem`:

- **`DR_SOC_MON`** — battery State Of Charge (percentage)
- **`CpctCrg_Lvl_D_Actl`** — actual charge/capacity level

Plus `Cumulative_Avg_Fuel_Economy`, `Curr_avg_drive_fuel_eco`,
`Curr_drive_fuel_eco_bar_graph_data`, `CO2_reduction`, `iStop_status_ControlStatus`,
`DistDriveEV`, `HEVSendEnergyFlowSignals`, and the `VDM_Read*` methods
(`VDM_ReadDrv1AvlFuelE`, `VDM_ReadCumAvgFuelEff`, `VDM_ReadTotRangeBstByIS`, …).

### ⚠️ Ignition-on requirement

The CMU is a **passive receiver** on the bus. Values are only refreshed while
the relevant vehicle modules (PCM/BCM/…) are awake. With **ignition ON** the
modules transmit continuously; in the quiet ACC-on/engine-off state many
signals are absent or stale. For `DR_SOC_MON` / `CpctCrg_Lvl_D_Actl` you need the
modules active. Also: **subscribe (dbus-monitor) rather than poll** — direct
`Get` on these signal-backed properties often returns nothing.

```sh
dbus-monitor --address="unix:path=/tmp/dbus_service_socket" \
  "type='signal',interface='com.jci.vbs.eem'"
```

### Diag / DTCs

`com.jci.vbs.diag` provides `ReadCMUFaults_Request()`, `ReadAVCFaults_Request()`,
`GetFaultStatus_Request(ids)`, `ClearFaults_Request(ids)`, `Routine_Request(id,
param)`, `Data_Request(DID)`, `PermanentDTCLog_Request()`. The GUI's terminal
menu reads DTCs through **uiaId `"diag"` (uiaid 25), testId 22** — see
GUI-HACKING.md. CAN ID `0x160` carries the VIP reset notification.

### Settings store

```sh
dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply \
  --dest=com.jci.settings /com/jci/settings com.jci.settings.Get_Settings_U8 \
  string:"/path" string:"group" string:"key" uint32:0 uint32:0
# types: Get_Settings_U8 / _S16 / _U32 / _BLM_Settings_pChar (string)
```

## 5. Known CAN IDs (v74 analysis; same bus on v59)

| CAN ID | Module | Likely content |
|---|---|---|
| 0x130, 0x167, 0x202, 0x24B, 0x4D9, 0x4DB, 0x4DE, 0x4F3 | EEM | continuously present; EEM flags "CAN missing" when they stop |
| 0x144 | CANL test | ReadyFlag to VIM |
| 0x160 | DIAG | VIP reset notification |
| 0x35F | MODCAN | MODCAN data |
| 0x4F0 | VWM | warning group |
| 0x49C | EEM | status value (trip reset / eco mode) |

CAN status enums used by `dataRetrieval`: `CAN_NONE`, `CAN_INACTIVE`,
`CAN_ACTIVE`, `CAN_BUS_OFF`, `CAN_MAX` (via `GetPublicCanStatus()` /
`GetPrivateCanStatus()`).

## 6. Toolkit scripts

All in `toolkit/tools/`, all using the service-bus address:

| Script | What it does |
|---|---|
| `can-monitor.sh` | `dbus-monitor` on the BCM/EEM/VWM signals for a duration |
| `vim-dump-all.sh` | full dump: ListNames, introspect of every `com.jci.*`, shm listing |
| `vehicle-data.sh` | polls the common getters (speed, gear, wheels, SOC, …) |
| `dbus-introspect.sh` | `org.freedesktop.DBus.Introspectable.Introspect` on a chosen service |
| `can-bus.sh` / `vim-deep-dive.sh` | deeper VIM/VBS exploration |

Quick manual checks on the car:

```sh
dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply \
  --dest=org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.ListNames | grep jci

dbus-send --address="unix:path=/tmp/dbus_service_socket" --print-reply \
  --dest=com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetCarSpeed uint32:0

/jci/bin/smdb-read          # Mazda's own shared-memory parser (fallback)
hexdump -C /dev/shm/smdb_vdm_vdt_current_data | head
```

## 7. Limitations & safety

- **Passive reading only.** The practical, safe path is D-Bus signals/methods
  (everything the CMU itself uses is exposed there — `dataRetrieval` proves it).
  Raw CAN via a custom VIM client (`VIMC_AddClient`) also works for sniffing.
- **Writing to the CAN bus is risky.** Sending frames on the *private* CAN bus
  can confuse safety-relevant modules (the bus carries powertrain/ADAS traffic).
  Treat write access as experimental; the toolkit does not do it.
- Both public and private CAN are reachable through the VIM; the private bus
  is where the sensitive traffic lives.
- Meaningful data requires **ignition ON**; expect silence in ACC-only.
