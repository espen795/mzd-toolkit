# VIP firmware reverse engineering

What is known (with evidence levels) about the **VIP coprocessor** that owns the
CAN bus on the CMU, and about the paths by which the CMU can transmit on CAN.

Evidence labels:

- **[PROVEN]** -- hard bytes/structure in the binaries themselves.
- **[LIKELY]** -- strong correlation, no full instruction-level trace.
- **[HYPOTHESIS]** -- reasoned guess, not verified.

Method and helper scripts: `research/vip-firmware/`.

## 1. Hardware and firmware layout

- Main CPU: NXP i.MX6 running Linux 3.0.35, kernel built **without** CAN
  (`# CONFIG_CAN is not set`) -- no SocketCAN, no `cansend`.
- **VIP coprocessor**: Renesas M16C **R5F35MCEJFB** (RTOS MR30). It owns the
  physical CAN controllers (HS-CAN 500 kbit/s public, MS-CAN 125 kbit/s
  private) via TJA1042/1043 transceivers. CMU <-> VIP is **SPI**
  (`/dev/spidev1.0`, 4 MHz, mode 3, 20-byte frames; checksum = sum of bytes
  0..18 per the public VIP protocol documentation).
- VIP firmware modules (module table at 0xC0000 of the VIP image): `VIP_APP-MAZ150`
  10.11.501, `VIP_CAN-MAZ140` 07.09.019 (CAN driver), `VIP_DIAG-MAZ140` 02.77.502
  (UDS), `VIP_VBM-MAZ140` 15.33.632 (bus router), `CPP_VIPSPIDRVR` 02.21.502.
- VIP_APP occupies **0x00C0000-0x00F567B** (218748 bytes) inside the
  S-record region 0x200-0x1C2000 of the raw firmware image. Build a flat binary
  with `research/vip-firmware/srec_build.py`.

## 2. The VIP can transmit on CAN -- proven at address level

The M16C/60 SFR map places the on-chip CAN controller registers at
0xD400-0xD7FF. Scanning the flat VIP_APP binary for 16-bit little-endian
values in that window (which is how MOV abs16 operands appear in the code)
shows heavy use of the CAN register block **[PROVEN as address usage]**:

| Address | Refs | Example code addresses | Interpretation (M16C/60 SFR map) |
|---|---|---|---|
| 0xD400-0xD40F | 7+29 | 0xC0E13, 0xC0AA7 | CAN0 config (MKR/FIDCR/MKIVLR/MIER) |
| 0xD4FD | 239 | 0xC8A00, 0xC9475, 0xCF0DB | CAN0 mask/ID register (high frequency = RX filter setup) |
| 0xD500 | 6 | 0xC11CA, 0xCCA03, 0xCCA4E, 0xCDDBF | CAN0 mailbox 0 ID |
| 0xD50B/0xD50F | 6/15 | 0xD2266, 0xD8E63 | mailbox 0 data/DLC |
| 0xD5F4/0xD5F5 | 6/12 | 0xCBE78, 0xD0A3F, 0xCEF73 | CAN0 mailbox 15 |
| 0xD6F5 | 8 | 0xC93E3, 0xD1F17, 0xD393D | CAN0 mailbox 31 |
| 0xD7A6 | 15 | 0xD0AA3, 0xD0CEA, 0xD1CDA, 0xD1D00, 0xD1D38 | MCTL area (message control, TRQ bit) |
| 0xD7C0 | 2 | 0xC6693, 0xC6BA1 | C0CTLR (control/mode) |
| 0xD7C7 | 1 | 0xE275F | C0CLKR (bitrate) |
| 0xD7CC | 1 | 0xEB1E8 | C0EIER (error interrupt enable) |
| 0xD7D0 | 1 | 0xD0ACE | C0ECSR (error code store) |
| 0xD7F5 | 20 | 0xCB75C, 0xCF48C, 0xD074D | CAN status |
| 0xD800 | 119 | 0xC06AB.. | just past the CAN block (GPIO/other SFR) |

Context hexdumps around the mailbox-write sites (e.g. 0xD0A27-0xD0A47) show
the pattern `f4 d5 00` = opcode 0xF4 + abs16 0x00D5 -> little-endian bytes
`d5 00` = **0xD500 as a MOV operand**, in a "load register, mov to abs16
0xD500" sequence. The *semantics* (which register is a mailbox ID) follow
from the M16C/60 SFR map and remain **[LIKELY]** because no M16C
disassembler was available (see section 5).

Interrupt vectors at 0xFFD00-0xFFDFF (4-byte entries) include the SPI/CAN IRQ
handlers (e.g. 0xC611A, 0xCBD34, 0xE012E, 0xC8122, 0xF527E, 0xCCB38);
which vector is SPI vs CAN0 vs CAN1 is **[HYPOTHESIS]** without a
disassembler.

## 3. SPI dispatch table: no raw-CAN-injection command proven

At **0xC0820** in the VIP image sits a table of 512 x 2-byte entries
(0xFFFF = empty), indexed by SPI message ID (0x000-0x1FF); each entry is a
16-bit handler offset in code bank 0xC (absolute = 0xC0000 + entry).
Dispatch code around 0xD4680-0xD4880 shows the typical M16C jump-table pattern
(indexing the table at 0x0820, 345 references concentrated in 0xD4-0xDA)
**[PROVEN]**.

Handlers exist for exactly the message IDs that the public VIP protocol
documentation describes:

- 0x002, 0x030-0x051: control (heartbeat, power, mode), CMU -> VIP
- 0x080-0x0BF: key/GPIO events, VIP -> CMU
- 0x0C0-0x0E2: GPIO/ACK/NACK
- 0x100-0x1C0: vehicle data (wheel speed, yaw, reverse, VBS ready)
- 0x180: frequently referenced around 0xC05DD-0xC1182

All other IDs -- including everything from 0x200 up -- are 0xFFFF (empty)
**[PROVEN from the table]**. Conclusion: there is **no proven SPI command of
the form "transmit this arbitrary CAN frame"**. The individual handler bodies
were not fully traceable without an M16C disassembler, so a hidden handler
inside one of the populated ranges cannot be 100% excluded **[HYPOTHESIS]**, but
the table structure makes it unlikely.

## 4. How CAN-TX actually happens: fixed messages + UDS

CAN-TX from the CMU does happen, but only via **fixed, firmware-defined
messages** **[PROVEN as immediates in the code; mailbox-write interpretation
LIKELY]**:

- CAN IDs 0x480-0x49C (settings/customization "Set" messages; e.g. 0x480
  appears 71x, 0x485 62x, 0x494 23x), 0x4F2/0x4F3 (HUD config), and
  0x7DF/0x7E0 (UDS request/response, seen as immediates at e.g. 0xE420C/
  0xE4211) appear as explicit immediates in the VIP code.
- The mailbox-write sites (0xD500/0xD5F5/0xD6F5) and MCTL 0xD7A6 references
  cluster in code around 0xC1xxx, 0xC9xxx, 0xCBxxx, 0xCCxxx, 0xD0Axx -- the
  VIP_CAN/VIP_VBM TX layer **[LIKELY]**.

### Linux-side chain (ARM binaries, proven from symbols/strings) [PROVEN]

```
D-Bus (com.jci.vbs.* on unix:path=/tmp/dbus_service_socket)
  -> svcjcivbs.so (VBS core, socket /tmp/vbs_framework_socket)
  -> vbs-mod-wrapper (dlopens libjcimod_*.so; VBS_Wrap_TxCANDataSent ...)
  -> mod_can (libjcimod_can.so)
  -> vim_app (/jci/vim/vim_app; IPC server, TX queue:
     IUC_QueueTxMessage -> IUC_Tx_Msg_Handler -> SPI_Transfer on /dev/spidev1.0,
     strings "Putting message in the TX queue. ID %04x, %u B")
  -> SPI 20-byte frames -> VIP -> CAN mailbox write + MCTL TRQ
```

`vim_app` also references `/dev/cmu_io`, `/dev/input/*`, `/tmp/vim_app.pid`;
the service config declares `jciVBS` with `reset_board="yes"` and depends on
`vim_app`.

### D-Bus interfaces that reach the bus

| D-Bus interface / method | Internal path | CAN effect | Class |
|---|---|---|---|
| `com.jci.vbs.diag.GenericMessage_Request(u)` | mod_diag -> VBS core -> mod_can -> vim_app SPI -> VIP_DIAG | UDS message on 0x7DF (0x7E0 response); PID is caller-chosen but encapsulated in UDS, not raw CAN | diagnostic |
| `com.jci.vbs.diag.Routine_Request(y, q)` | same | UDS routine (0x31 etc.) on 0x7DF | diagnostic, can actuate powertrain |
| `com.jci.vbs.diag.Data_Request(y)` | same | UDS ReadDataByIdentifier (0x22), read-only | diagnostic, read-only |
| `com.jci.vbs.diag.SetFault_Request / ClearFaults_Request` | same | UDS ClearDiagnosticInformation (0x14) | diagnostic, write |
| `com.jci.settings.Set_Settings_U8` (via mod_settings) | settings -> mod_can | fixed Set messages 0x480-0x49C | comfort |
| `com.jci.navi2IHU.HUDSettings.SetHUDSetting` | -> mod_navi | 0x4F2/0x4F3 HUD | comfort |
| `com.jci.vbs.cd/am/radio/vdt/wm` methods | function module -> `gs_*TxHandler` -> mod_can | large fixed per-module ID set on the private CAN (0x3xx/0x4xx) | comfort/infotainment |
| `com.jci.vbs.bcm.GetPublic/PrivateCanStatus`, `com.jci.vbs.eem` | RX only | no TX | safe (read) |

**No D-Bus method was found that sends an arbitrary CAN ID + arbitrary
payload to the bus** [PROVEN at interface level from the introspection XML and
symbols]: everything goes either via a fixed/enum ID (settings/HUD/radio) or
through the UDS layer in mod_diag (where VIP_DIAG does the 0x7DF framing).

## 5. What could not be done, and why

- **No M16C/M32C disassembler.** GNU binutils has no m16c target; the
  community M16C toolchain commonly referenced contains only ARM
  (arm-cortexa9, gcc 4.9.1); no radare2/rizin/capstone on the analysis host.
  Workstream A was therefore done as targeted opcode/address-pattern analysis
  (see `research/vip-firmware/`), not full disassembly. A full handler trace
  (which SPI ID -> which mailbox write) is consequently **not proven**.
- **R5F35MCEJFB datasheet not at hand** -> SFR address -> register mapping is
  from general M16C/60 knowledge = **[LIKELY]**.
- **Rootfs image is not a squashfs.** The rootfs image is a flat MAST
  container (header `MAST` @0x40, page 0x1000, name table @0x1000-0x5B000,
  LDIR/JMET/META indexes further in); an `hsqs` magic sometimes reported at
  fixed offsets is a busybox string, not a filesystem. Carve ELF binaries with
  an `\x7fELF` scan (`research/vip-firmware/elfsym.py`) **[PROVEN]**.
- **libjcimod_can.so not located as a separate ELF** -- mod_can is dlopened by
  vbs-mod-wrapper from `/jci/vbs/modules`; the mod_can -> vim_app path is
  proven via socket + IUC symbols, but mod_can's internal CAN-ID table was not
  fully recovered.

## 6. Practical risks when writing to CAN

1. **Watchdog/reset.** The VIP contains watchdog strings (`VEE_WdtWrite
   Failed`, `WDT Disabled`, `QDog reset`, `TSWR reset`, `PwrMon VIP reset
   request`) and SPI-timeout handling (`SPI Timeout...`). A malformed SPI
   frame (wrong checksum/length) can reset the VIP -> CMU reboot
   (`reset_board="yes"` on jciVBS; vim_app resets the main CPU on
   communication loss) **[PROVEN strings, effect LIKELY]**.
2. **Bus-off.** The VIP CAN code has `PublicCANbusoffstart/end`,
   `PrivateCANbusoffstart/end`; wrong TX traffic (wrong bitrate/ID on the
   private 125k bus) can push the VIP into bus-off **[PROVEN strings]**.
3. **0x7DF is a broadcast UDS request.** `GenericMessage_Request` /
   `Routine_Request` reach the powertrain ECUs; a wrong routine (e.g. 0x31
   reset, 0x11 ECU reset, write routines) can reset ECUs or change their
   configuration **[LIKELY from UDS semantics + path]**.
4. **"No raw-CAN path found" does not mean "none exists"** -- without an
   M16C disassembler the individual SPI handlers are not 100% traceable
   **[HYPOTHESIS]**.

## 7. Bottom line: can the CMU transmit on CAN?

| Path | CAN-TX? | Evidence |
|---|---|---|
| Raw SPI frame CMU->VIP with self-chosen CAN ID/data | **NOT PROVEN / unknown** | dispatch table 0xC0820 has no handler for a raw-CAN ID; all CMU->VIP IDs are control/key (table 0xC0820-0xC0A20, 0xFFFF = empty; dispatch code 0xD4xxx-0xDAxxx) |
| D-Bus `com.jci.vbs.diag.*` (GenericMessage/Routine/Data/SetFault) | **YES -- but via UDS (0x7DF), not raw CAN** | mod_diag introspection + strings, 0x7DF/0x7E0 immediates in VIP at 0xE420C/0xE4211 |
| D-Bus settings/HUD (`Set_Settings_U8`, `SetHUDSetting`) | **YES -- fixed CAN IDs 0x480-0x49C / 0x4F2** | CAN-ID immediates in VIP firmware + mailbox writes 0xD500/0xD5F5 |
| D-Bus radio/cd/am/vdt function modules | **YES -- fixed per-module ID set (private CAN)** | `gs_*TxHandler` symbols in mod_cd/mod_am |
| Kernel SocketCAN (`cansend`) | **NO** | `# CONFIG_CAN is not set` |
| VIP transmits autonomously (RX->TX routing, VBM) | **YES** | VIP_VBM module + mailbox/MCTL SFR writes in VIP code |
