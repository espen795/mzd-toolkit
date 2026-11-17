#!/usr/bin/env python3
"""Mazda MZD Connect Gen-1 CMU serial console rescue (watchdog bootloop).

WHAT THIS DOES
==============
Drives the CMU serial console (115200 8N1, 3.3 V) through one boot cycle of a
watchdog bootloop and applies a known fix over the factory-default serial
account:

  login: cmu      password: mzd        (factory defaults, uid 0 / root)

As soon as a root shell is detected it sends, in order:

  1. echo 1 > "/sys/class/gpio/Watchdog Disable/value"   <- stops the reboot loop
     killall -STOP sm 2>/dev/null                          <- belt and braces
  2. remount / and /jci read-write
  3. backup sm.conf and /etc/passwd (*.bak-rescue)
  4. point the sm.conf "devices" service back at the real
     /jci/devices/svc-com-jci-cpp-devices.so and restore
     display=filtered-touchscreen0 (the bootloop root cause is a service
     path that points at a shell script -- sm dlopen()s services, a .sh
     can never load, and reset_board="yes" then triggers the watchdog)
  5. remove the wrapper script, comment out any touch-filter block in
     /data_persist/dev/bin/autorun, repair a corrupted /etc/passwd
  6. verify and print a CMU_FIX_DONE_<rc> marker

It retries automatically across boot cycles (max --cycles, default 8) and
stops with a clear conclusion when the login is refused (meaning the live
/etc/passwd was changed by a previous owner -- use another rescue route).

RISKS
=====
- This writes to /jci/sm/sm.conf and /etc/passwd on the target unit. It
  creates *.bak-rescue backups first, but you are modifying a car stereo's
  system partition: read the FIX_LINES list below before applying.
- It assumes firmware v59-class behaviour (login prompt ~7 s after boot,
  devices crash ~10 s, watchdog reset ~15 s). On other firmwares the
  timing and account may differ.
- Serial adapters vary: any USB-serial dongle shows up as a generic
  /dev/ttyUSBx. Verify with dmesg which node appeared when you plugged the
  adapter in, and do a loopback test (TX shorted to RX) first. Never assume
  ttyUSB0 is the CMU.
- Wiring: CMU pin 2S (TX) -> adapter RX, adapter TX -> CMU pin 2T (RX),
  common GND, 3.3 V logic, 115200 8N1.

USAGE
=====
  python3 cmu_serial_rescue.py --dry-run              # self-test, no hardware
  python3 cmu_serial_rescue.py --apply <SERIAL_DEV>   # e.g. /dev/ttyUSB1
  python3 cmu_serial_rescue.py --apply <SERIAL_DEV> --baud 115200 \
      --cycles 8 --log rescue.log

DEFAULT IS DRY-RUN. Nothing is sent to any serial port unless --apply is
given. Requires pyserial (python3 -m pip install pyserial).

Exit codes: 0 = fix applied (CMU_FIX_DONE_0 seen), 3 = stopped after max
cycles / refused logins, 130 = interrupted, 1 = pyserial missing / bad args.
"""

import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial missing. Test with: python3 -c \"import serial\"")
    print("Install with: python3 -m pip install pyserial")
    sys.exit(1)

VERSION = "1.0"
DEFAULT_BAUD = 115200

MAX_CYCLES = 8          # max boot cycles before giving up
SHELL_ASSUME_S = 1.5    # if no 'Login incorrect' within this time after the
                        # password, assume we have a shell
POKE_S = 2.0            # in WAIT_LOGIN, send an empty line every POKE_S s
SEND_GAP_S = 0.15       # small delay between fire-and-forget lines

# Factory default serial console account (identical on every v59 unit):
# uid 0, shell /bin/sh. See docs/RECOVERY-BRICK.md.
USER = "cmu"
PASSWORD = "mzd"

# --- regexes ---------------------------------------------------------------
RE_BANNER = re.compile(r"IBC embedded bootloader|Uncompressing Linux", re.I)
# 'login:' with optional hostname prefix, but not 'Last login:' and not the
# busybox error "login: can't execute ...".
RE_LOGIN = re.compile(
    r"(?:^|[\r\n])[ \t]*(?:(?!last\b)[A-Za-z0-9_.-]{1,32}[ \t]+)?login:(?![ \t]*can't)",
    re.I)
RE_PASSWORD = re.compile(r"assword:[ \t]*", re.I)
RE_INCORRECT = re.compile(r"login incorrect", re.I)
# shell prompt: a line ending in '# ' or '$ '
RE_PROMPT = re.compile(r"(?:^|[\r\n])[^\r\n]*[#$][ \t]*(?=\r|\n|$)")
RE_FIX_DONE = re.compile(r"CMU_FIX_DONE_(\d+)")

# --- the fix (order is critical: watchdog FIRST) ----------------------------
# The GPIO "Watchdog Disable" line is what actually stops the hardware
# watchdog reset (verified on live hardware). `killall -STOP sm` only pauses
# the Service Manager; on its own it does NOT prevent the reset.
WATCHDOG_LINE = ('echo 1 > "/sys/class/gpio/Watchdog Disable/value" 2>/dev/null'
                 ' ; killall -STOP sm 2>/dev/null ; echo WD_SM_HALTED')
FIX_LINES = [
    "mount -o remount,rw / ; mount -o remount,rw /jci 2>/dev/null",
    "cp /jci/sm/sm.conf /jci/sm/sm.conf.bak-rescue",
    "sed -i -e 's|/jci/devices/devices-wrapper.sh|/jci/devices/svc-com-jci-cpp-devices.so|'"
    " -e 's|display=mzd-touch-filtered|display=filtered-touchscreen0|' /jci/sm/sm.conf",
    "rm -f /jci/devices/devices-wrapper.sh",
    "[ -f /data_persist/dev/bin/autorun ] && "
    "sed -i '/^if .*touch-filter/,/^fi/s|^|#|' /data_persist/dev/bin/autorun",
    "cp /etc/passwd /etc/passwd.bak-rescue",
    r"sed -i 's|^\(user:.*:/bin/sh\)sshd:.*|\1|' /etc/passwd",
    "grep -q '^sshd:' /etc/passwd || "
    "echo 'sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin' >> /etc/passwd",
    "sync",
    "echo CMU_FIX_DONE_$?",
    "grep -c devices-wrapper /jci/sm/sm.conf",
    "grep '^user:' /etc/passwd",
]


def timestamp():
    t = time.time()
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + (".%03d" % int((t % 1) * 1000))


class RescueSM:
    """State machine, one pass per boot cycle. feed()/tick() return actions:
    ("send", line) | ("sleep", seconds) | ("note", text) | ("done", rc) |
    ("stop", text). The same machine is dry-runnable without a serial port."""

    WAIT_LOGIN, WAIT_PASSWORD, WAIT_SHELL, FIXING, DONE, STOPPED = range(6)

    def __init__(self, max_cycles=MAX_CYCLES):
        self.max_cycles = max_cycles
        self.state = self.WAIT_LOGIN
        self.buf = ""
        self.cycles = 0
        self.bad_logins = 0
        self.t_password = None
        self.t_banner = None
        self.last_poke = None
        self.fired = False
        self.fix_rc = None

    def _reset_cycle(self):
        self.state = self.WAIT_LOGIN
        self.buf = ""
        self.t_password = None
        self.fired = False

    def _fire_fix(self, actions, reason):
        if self.fired:
            return actions
        self.fired = True
        self.state = self.FIXING
        self.buf = ""
        actions.append(("note", "root shell detected (%s) -> firing fix" % reason))
        seq = [WATCHDOG_LINE] + FIX_LINES
        for i, line in enumerate(seq):
            if i:
                actions.append(("sleep", SEND_GAP_S))
            actions.append(("send", line))
            if i == 0:
                actions.append(("note", "FIRST ACTION: watchdog disabled -> window now unlimited"))
        return actions

    def feed(self, text, now):
        actions = []
        if self.state in (self.DONE, self.STOPPED):
            return actions

        self.buf = (self.buf + text)[-30000:]

        # reboot? -> reset state machine, count a new cycle (debounce: the
        # banner lines of one boot arrive within ~2 s of each other)
        if RE_BANNER.search(text):
            if self.t_banner is None or now - self.t_banner > 4.0:
                self.cycles += 1
                self.t_banner = now
                actions.append(("note", "boot banner seen -> cycle %d/%d, state machine reset"
                                % (self.cycles, self.max_cycles)))
                if self.cycles > self.max_cycles:
                    self.state = self.STOPPED
                    actions.append(("stop", self._conclusion()))
                    return actions
            if self.state != self.WAIT_LOGIN:
                actions.append(("note", "unit rebooted mid-procedure -> restarting at login prompt"))
            self._reset_cycle()
            return actions

        if self.state == self.WAIT_LOGIN:
            if RE_LOGIN.search(self.buf):
                self.buf = ""
                self.state = self.WAIT_PASSWORD
                actions.append(("note", "login prompt detected -> sending user '%s'" % USER))
                actions.append(("send", USER))
            return actions

        if self.state == self.WAIT_PASSWORD:
            if RE_INCORRECT.search(self.buf):
                self.bad_logins += 1
                self.state = self.WAIT_LOGIN
                self.buf = ""
                actions.append(("note",
                                "LOGIN REFUSED for %s/%s (%d times) - live /etc/passwd differs "
                                "from the factory default" % (USER, PASSWORD, self.bad_logins)))
                return actions
            if RE_PASSWORD.search(self.buf):
                self.buf = ""
                self.state = self.WAIT_SHELL
                self.t_password = now
                actions.append(("note", "password prompt -> sending password"))
                actions.append(("send", PASSWORD))
            return actions

        if self.state == self.WAIT_SHELL:
            if RE_INCORRECT.search(self.buf):
                self.bad_logins += 1
                self.state = self.WAIT_LOGIN
                self.buf = ""
                actions.append(("note",
                                "LOGIN REFUSED after password (%d times)" % self.bad_logins))
                return actions
            if RE_PROMPT.search(self.buf):
                return self._fire_fix(actions, "shell prompt seen")
            return actions

        if self.state == self.FIXING:
            m = RE_FIX_DONE.search(self.buf)
            if m:
                self.fix_rc = int(m.group(1))
                self.state = self.DONE
                actions.append(("done", self.fix_rc))
            return actions

        return actions

    def tick(self, now):
        """Periodic handling without new input: poke line and shell timeout."""
        actions = []
        if self.state in (self.DONE, self.STOPPED):
            return actions
        if self.state == self.WAIT_LOGIN:
            if self.last_poke is None:
                self.last_poke = now
            elif now - self.last_poke > POKE_S:
                self.last_poke = now
                actions.append(("send", ""))  # empty line: redraw a hung prompt
        if (self.state == self.WAIT_SHELL and self.t_password is not None
                and not self.fired and now - self.t_password > SHELL_ASSUME_S):
            return self._fire_fix(actions,
                                  "%.1fs after password with no 'Login incorrect' -> shell assumed"
                                  % (now - self.t_password))
        return actions

    def _conclusion(self):
        msg = ("STOP after %d boot cycles (max %d). Fix NOT confirmed applied."
               % (self.cycles, self.max_cycles))
        if self.bad_logins:
            msg += ("\n%d x 'Login incorrect' for %s/%s: the live /etc/passwd apparently "
                    "no longer holds the factory default. Use another rescue route "
                    "(NOR boot-select flip, .up reflash, see docs/RECOVERY-BRICK.md)."
                    % (self.bad_logins, USER, PASSWORD))
        msg += "\nSee the log file for the full raw serial I/O."
        return msg


class SerialTransport:
    """Generic USB-serial port, 115200 8N1. Slow send (8 bytes per 3 ms): the
    CMU console has no flow control and the i.MX UART only a 32-byte FIFO."""

    def __init__(self, port, baud, log):
        try:
            self.ser = serial.Serial(port, baud, bytesize=serial.EIGHTBITS,
                                     parity=serial.PARITY_NONE,
                                     stopbits=serial.STOPBITS_ONE,
                                     timeout=0.05)
        except Exception as e:
            raise SystemExit("ERROR: cannot open %s (%s). Check the USB adapter, "
                             "permissions (dialout group) and that the CMU is powered (ACC)."
                             % (port, e))
        self.log = log

    def read(self):
        data = self.ser.read(4096)
        return data.decode("latin1", errors="replace") if data else ""

    def send_line(self, line):
        payload = (line + "\r").encode("ascii", errors="replace")
        ts = timestamp()
        self.log.write("[%s] TX %r\n" % (ts, line + "\r"))
        self.log.flush()
        sys.stdout.write("[%s] TX %s\n" % (ts, line if line else "<CR>"))
        sys.stdout.flush()
        for i in range(0, len(payload), 8):
            self.ser.write(payload[i:i + 8])
            self.ser.flush()
            time.sleep(0.003)

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass


class RecordingTransport:
    """Dry-run transport: records sends and prints them instead of sending."""

    def __init__(self):
        self.sent = []

    def read(self):
        return ""

    def send_line(self, line):
        self.sent.append(line)
        print("    [DRY-RUN] would send: %r" % (line + "\r" if line else "\r"))

    def close(self):
        pass


def run_actions(actions, transport, log, real=True):
    """Execute actions. Returns 'stop' when the state machine wants to stop.
    With real=False (dry-run) sends are only printed/recorded, no sleeps."""
    for kind, val in actions:
        if kind == "send":
            transport.send_line(val)
        elif kind == "sleep":
            if real:
                time.sleep(val)
        elif kind == "note":
            line = "[%s] [>>>] %s" % (timestamp(), val)
            print(line)
            log.write(line + "\n")
            log.flush()
        elif kind == "done":
            banner = [
                "****************************************************************",
                "*  *** CMU_FIX_DONE_%d SEEN - FIX APPLIED SUCCESSFULLY ***   *" % val,
                "*  watchdog disabled, sm.conf restored, wrapper removed,   *",
                "*  /etc/passwd repaired. Backups: sm.conf.bak-rescue +     *",
                "*  passwd.bak-rescue. Script stops retrying, keeps logging. *",
                "*  Power-cycle the unit to confirm the bootloop is gone.    *",
                "****************************************************************",
            ]
            for b in banner:
                print(b)
                log.write("[%s] %s\n" % (timestamp(), b))
            log.flush()
        elif kind == "stop":
            print("[%s] [>>>] %s" % (timestamp(), val))
            log.write("[%s] [>>>] %s\n" % (timestamp(), val))
            log.flush()
            return "stop"
    return None


def log_rx(log, text):
    log.write("[%s] RX %s" % (timestamp(), text))
    log.flush()
    try:
        sys.stdout.write(text)
        sys.stdout.flush()
    except Exception:
        pass


def run_real(port, baud, logpath, max_cycles):
    log = open(logpath, "a", encoding="latin1", errors="replace")
    log.write("\n===== cmu_serial_rescue v%s started %s | port=%s baud=%d 8N1 =====\n"
              % (VERSION, timestamp(), port, baud))
    log.flush()
    print("=" * 72)
    print("  MAZDA CMU SERIAL RESCUE v%s - login %s/%s, fix sm.conf + passwd"
          % (VERSION, USER, PASSWORD))
    print("  port=%s baud=%d 8N1 | log: %s" % (port, baud, logpath))
    print("=" * 72)
    transport = SerialTransport(port, baud, log)
    sm = RescueSM(max_cycles)
    print("[+] Waiting for a boot cycle... (login prompt ~7s after boot, window ~3-10s)")
    print("[+] Ctrl+C = stop. After CMU_FIX_DONE the script keeps logging only.\n")
    rc = 1
    try:
        while True:
            if sm.state == RescueSM.STOPPED:
                print("[%s] [>>>] %s" % (timestamp(), sm._conclusion()))
                rc = 3
                break
            text = transport.read()
            now = time.time()
            if text:
                log_rx(log, text)
                actions = sm.feed(text, now)
            else:
                actions = sm.tick(now)
                time.sleep(0.02)
            if run_actions(actions, transport, log) == "stop":
                rc = 3
                break
            if sm.state == RescueSM.DONE:
                rc = 0
                print("\n[+] SUCCESS (CMU_FIX_DONE_%s). Logging only - Ctrl+C to quit."
                      % sm.fix_rc)
                while True:  # passive logging, no more sends
                    text = transport.read()
                    if text:
                        log_rx(log, text)
                    else:
                        time.sleep(0.05)
    except KeyboardInterrupt:
        print("\n[%s] [>>>] interrupted by user." % timestamp())
        rc = 130
    finally:
        transport.close()
        log.write("===== end %s rc=%d =====\n" % (timestamp(), rc))
        log.flush()
        log.close()
    return rc


# --- dry-run scenarios (no hardware needed) ---------------------------------
SCENARIO_A = [  # happy path: cycle 1, prompt detected
    ("IBC embedded bootloader v1.68.17 (2015-06-01)\r\n", 0.5),
    ("Uncompressing Linux... done, booting the kernel.\r\n", 1.0),
    ("Linux version 3.0.35 #1 SMP PREEMPT\r\n", 1.5),
    ("SM Failed to load the service: \"/jci/devices/devices-wrapper.sh\"\r\n", 0.4),
    ("cmu login: ", 0.3),
    ("Password: ", 0.2),
    ("# ", 0.5),
    ("CMU_FIX_DONE_0\r\n", 0.3),
    ("0\r\n", 0.2),
    ("user:x:1000:1000::/home/user:/bin/sh\r\n", 0.2),
]

SCENARIO_B = [  # login refused -> reboot -> cycle 2 success via shell timeout
    ("IBC embedded bootloader v1.68.17 (2015-06-01)\r\n", 0.5),
    ("Uncompressing Linux... done, booting the kernel.\r\n", 1.0),
    ("cmu login: ", 0.3),
    ("Password: ", 0.2),
    ("Login incorrect\r\n", 3.5),
    ("IBC embedded bootloader v1.68.17 (2015-06-01)\r\n", 1.0),
    ("Uncompressing Linux... done, booting the kernel.\r\n", 1.5),
    ("cmu login: ", 0.3),
    ("Password: ", 0.2),
    ("", 2.0),
    ("CMU_FIX_DONE_0\r\n", 0.3),
]


def dry_run(max_cycles):
    import io
    print("=" * 72)
    print("  DRY-RUN cmu_serial_rescue v%s - state-machine self-test (no port)" % VERSION)
    print("=" * 72)
    ok = True
    for name, scenario, expect in (
        ("A: happy path (prompt detection, cycle 1)", SCENARIO_A, {"cycles": 1, "bad": 0}),
        ("B: Login incorrect -> reboot -> cycle 2 via shell timeout", SCENARIO_B,
         {"cycles": 2, "bad": 1}),
    ):
        print("\n--- scenario %s ---" % name)
        log = io.StringIO()
        tr = RecordingTransport()
        sm = RescueSM(max_cycles)
        fake_now = 1000.0
        for chunk, advance in scenario:
            if chunk:
                print("  [DRY-RUN] RX %r" % chunk)
            actions = sm.feed(chunk, fake_now)
            if run_actions(actions, tr, log, real=False) == "stop":
                break
            fake_now += advance
            actions = sm.tick(fake_now)
            if run_actions(actions, tr, log, real=False) == "stop":
                break
        core = [s for s in tr.sent if s]
        print("  sends (excluding empty pokes): %s" % core)
        last_pw = max((i for i, s in enumerate(core) if s == PASSWORD), default=-1)
        checks = [
            ("first send is user '%s'" % USER, bool(core) and core[0] == USER),
            ("password '%s' sent" % PASSWORD, PASSWORD in core),
            ("send right after the password is the watchdog-disable (FIRST fix action)",
             last_pw >= 0 and len(core) > last_pw + 1 and core[last_pw + 1] == WATCHDOG_LINE),
            ("fix contains the CMU_FIX_DONE marker", any("CMU_FIX_DONE" in s for s in core)),
            ("fix contains the sm.conf sed", any("svc-com-jci-cpp-devices.so" in s for s in core)),
            ("fix contains the passwd sed", any(s.startswith("sed -i 's|^\\(user:") for s in core)),
            ("state DONE reached", sm.state == RescueSM.DONE),
            ("CMU_FIX_DONE rc=0 read", sm.fix_rc == 0),
            ("cycles == %d" % expect["cycles"], sm.cycles == expect["cycles"]),
            ("bad_logins == %d" % expect["bad"], sm.bad_logins == expect["bad"]),
        ]
        for desc, passed in checks:
            print("    [%s] %s" % ("PASS" if passed else "FAIL", desc))
            ok = ok and passed
    print("\n%s: dry-run %s" % (timestamp(),
          "PASSED - all scenarios trigger the right actions" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(
        description="Mazda CMU serial rescue - login cmu/mzd, disable watchdog, "
                    "fix sm.conf + /etc/passwd. DRY-RUN unless --apply is given.")
    ap.add_argument("--apply", metavar="SERIAL_DEV",
                    help="actually open this serial port, e.g. /dev/ttyUSB1 "
                         "(without this flag only a dry-run self-test runs)")
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD,
                    help="baud rate (default %(default)s), 8N1")
    ap.add_argument("--log", default="cmu_serial_rescue.log",
                    help="log file (default %(default)s)")
    ap.add_argument("--cycles", type=int, default=MAX_CYCLES,
                    help="max boot cycles to try (default %(default)s)")
    ap.add_argument("--dry-run", action="store_true",
                    help="state-machine self-test, no port opened (default behaviour)")
    args = ap.parse_args()
    if args.apply is None:
        return dry_run(args.cycles)
    return run_real(args.apply, args.baud, args.log, args.cycles)


if __name__ == "__main__":
    sys.exit(main())
