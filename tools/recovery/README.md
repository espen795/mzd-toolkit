# tools/recovery -- serial console rescue for a bootlooping CMU

`cmu_serial_rescue.py` automates the recovery procedure from
[docs/RECOVERY-BRICK.md](../docs/RECOVERY-BRICK.md): it watches the serial
console of a Mazda MZD Connect Gen-1 CMU stuck in a watchdog bootloop, logs
in with the factory-default serial account `cmu` / `mzd` (uid 0), disables
the hardware watchdog, and repairs the `sm.conf` / `/etc/passwd` damage that
caused the loop.

## Requirements

- Python 3 + pyserial: `python3 -m pip install pyserial`
- A 3.3 V USB-serial adapter (Prolific PL2303, CH340, ...). Wired to the CMU
  connector: **2S (TX) -> adapter RX**, **adapter TX -> 2T (RX)**, common
  **GND**, 115200 baud 8N1.
- The CMU powered (ACC). Adapters appear as a generic `/dev/ttyUSBx` -- check
  `dmesg` after plugging in which node is new, and run a loopback test
  (adapter TX shorted to RX) before trusting it.

## Usage

```sh
# 1. self-test only (default, touches no hardware):
python3 tools/recovery/cmu_serial_rescue.py --dry-run

# 2. real run against the adapter:
python3 tools/recovery/cmu_serial_rescue.py --apply /dev/ttyUSB1

# options: --baud 115200 --cycles 8 --log rescue.log
```

The script is a dry-run by default; `--apply <SERIAL_DEV>` is required to
actually open the port. It sends the watchdog-disable as the very first
command after login, then the fix lines, and prints a clear banner when it
sees `CMU_FIX_DONE_0`. It retries across up to 8 boot cycles and stops with
an explanation if `cmu`/`mzd` is refused (live `/etc/passwd` changed by a
previous owner -- use the fallback routes in
[docs/RECOVERY-BRICK.md](../docs/RECOVERY-BRICK.md) then).

All raw serial I/O with timestamps is written to the log file. The script is
non-destructive apart from the documented fix: it creates `sm.conf.bak-rescue`
and `passwd.bak-rescue` on the unit before changing anything. Read the
`FIX_LINES` list in the script header before running it on real hardware.

See [docs/RECOVERY-BRICK.md](../docs/RECOVERY-BRICK.md) for the manual
procedure, the boot timeline, the dead ends, and the CH341A/NOR last resort
([docs/NOR-FLASH-RECOVERY.md](../docs/NOR-FLASH-RECOVERY.md)).
