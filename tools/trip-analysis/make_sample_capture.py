#!/usr/bin/env python3
"""make_sample_capture.py - generate a SYNTHETIC dbus-monitor capture.

Produces a fake `dbus-monitor` .raw file in the exact format that
`make_overview_pdf.py` parses, so you can render a full sample report
WITHOUT a real capture (and therefore without any real GPS or personal data).

Everything here is invented:
  - the route is dead-reckoned from a synthetic speed/heading profile and
    placed over a generic public area (near Munich, DE) - it is NOT a real
    trip and contains no personal location.
  - speed / rpm / gear / clutch phases / braking / i-Stop / fuel are
    procedurally generated to exercise every page of the report.

Usage:
    python3 make_sample_capture.py [out.raw]

Then:
    python3 make_overview_pdf.py out.raw sample-overview.pdf
"""
import sys, math
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "sample-trip.raw"

# --- synthetic, non-personal start point (generic area near Munich, DE) ----
LAT0, LON0 = 48.2000, 11.6000
EPOCH0 = 1795500000          # fixed demo timestamp
DT = 0.5                     # seconds per sample
rng = np.random.default_rng(42)

# --- speed profile (km/h) with named markers -------------------------------
seg, marks = [], {}
def mark(name): marks[name] = len(seg)
def hold(kmh, secs): seg.extend([kmh] * int(secs / DT))
def ramp(a, b, secs): seg.extend(list(np.linspace(a, b, int(secs / DT))))

hold(0, 20)                       # engine start, idle
ramp(0, 50, 25); hold(50, 60)     # pull away, town
mark("coast"); ramp(50, 0, 14)    # coast towards a red light (clutch in)
mark("stop1"); hold(0, 25); mark("stop1_end")   # i-Stop
ramp(0, 60, 30); hold(60, 90)     # town cruise
ramp(60, 30, 10); hold(30, 20)    # roundabout
ramp(30, 120, 45)                 # motorway ramp
mark("cruise"); hold(120, 240); mark("cruise_end")   # cruise control
mark("ebrake"); ramp(120, 80, 20); mark("ebrake_end")  # engine braking, fuel cut
hold(80, 60)
ramp(80, 0, 25)                   # exit, braking
mark("stop2"); hold(0, 20); mark("stop2_end")   # i-Stop
ramp(0, 45, 20); hold(45, 40)     # final town stretch
ramp(45, 0, 15); hold(0, 10)      # park

v_kmh = np.clip(np.array(seg, float) + rng.normal(0, 0.6, len(seg)), 0, None)
N = len(v_kmh)
t = np.arange(N) * DT
idx = np.arange(N)

# --- heading / yaw: gentle wander + a few turns ----------------------------
yaw_rate = 0.05 * np.sin(t / 22.0) + 0.02 * np.sin(t / 7.0)
for c, w, amp in [(240, 8, 0.25), (300, 6, -0.3), (640, 10, 0.18)]:
    yaw_rate += amp * np.exp(-((t - c) ** 2) / (2 * w ** 2))
yaw_rate = np.where(v_kmh > 3, yaw_rate, 0.0)
heading = np.cumsum(yaw_rate * DT)

# --- dead-reckon the route (meters -> lat/lon) -----------------------------
v_ms = v_kmh / 3.6
x = np.cumsum(v_ms * np.cos(heading) * DT)
y = np.cumsum(v_ms * np.sin(heading) * DT)
lat = LAT0 + y / 111320.0
lon = LON0 + x / (111320.0 * math.cos(math.radians(LAT0)))

# --- gear selection + clutch phases ----------------------------------------
RATIO = {1: 113.0, 2: 59.0, 3: 40.0, 4: 31.0, 5: 25.0, 6: 20.0}
def gear_for(kmh):
    if kmh < 4: return 0
    for g, lim in ((1, 20), (2, 40), (3, 62), (4, 88), (5, 112)):
        if kmh < lim: return g
    return 6
target = np.array([gear_for(k) for k in v_kmh])
gear = target.copy()
# real cars report gear 0 while the clutch is pressed: 0.5-1.0 s per shift
clutch = np.zeros(N, bool)
shift_no = 0
for i in range(1, N):
    if target[i] != target[i - 1] and target[i] > 0 and target[i - 1] > 0:
        n0 = 1 + (shift_no % 2)
        clutch[i:i + n0] = True
        shift_no += 1
# coasting with the clutch in (> 6 s) towards the first red light
coast = (idx >= marks["coast"]) & (idx < marks["coast"] + int(9 / DT))
gear[clutch | coast] = 0

# --- engine state: i-Stop at the two longer stops --------------------------
istop = np.zeros(N, bool)
for a, b in (("stop1", "stop1_end"), ("stop2", "stop2_end")):
    istop[marks[a] + int(3 / DT):marks[b] - int(1 / DT)] = True

# --- rpm, throttle, accelerations ------------------------------------------
rpm = np.array([750.0 if g == 0 else RATIO[g] * k for g, k in zip(gear, v_kmh)])
# during a clutch phase the revs fall towards the next gear
for i in np.where(clutch)[0]:
    nxt = target[i]
    rpm[i] = max(900.0, RATIO[nxt] * v_kmh[i] * 1.08)
rpm[coast] = 780.0
rpm = np.clip(rpm + rng.normal(0, 15, N), 600, 6500)
rpm[istop] = 0.0

a_long = np.gradient(v_ms, DT)
cruise = (idx >= marks["cruise"]) & (idx < marks["cruise_end"])
ebrake = (idx >= marks["ebrake"]) & (idx < marks["ebrake_end"])
throttle = np.clip(10 + a_long * 14 + v_kmh * 0.15, 0, 100)
throttle[clutch | coast | istop | ebrake | cruise] = 0.0      # cruise control: pedal 0
# lift-off / clutch dip, every 3rd shift a bit harsher (gives "noticeable" shifts)
for k, i in enumerate(np.where(clutch)[0]):
    a_long[i] -= 0.5 if k % 3 else 1.6
a_lat = v_ms * yaw_rate
steer_deg = np.clip(np.degrees(yaw_rate) * 12.0, -120, 120)

# brake pedal: pressed while decelerating noticeably (from the noise-free profile)
a_clean = np.gradient(np.array(seg, float) / 3.6, DT)
brake = (a_clean < -0.7) & (v_kmh > 2)

# engine state (SISS): 3 = running/warming up, 10 = running + i-Stop possible,
# 7 = stopped by i-Stop. cylState 20 = cylinder deactivation (2 of 4) at light load.
engstate = np.where(t < 360, 3, 10)
engstate[istop] = 7
cylstate = np.where(cruise & (t > 360), 20, 0)

# fuel pulses: none with the engine off or on fuel cut (engine braking);
# cruise control keeps fuelling with the pedal at 0
fuel_rate = 0.03 + 0.002 * v_kmh + 0.004 * throttle
fuel_rate[cruise] = 0.03 + 0.0025 * v_kmh[cruise]
fuel_rate[istop | ebrake] = 0.0
fuel = np.floor(np.cumsum(fuel_rate)).astype(int) % 256

# --- emit dbus-monitor text ------------------------------------------------
def sig(f, ep, iface, member, typ, val):
    f.write("signal time=%.1f sender=:1.3 -> path=/com/jci; interface=%s; member=%s\n"
            % (ep, iface, member))
    f.write("   %s %s\n" % (typ, val))

with open(OUT, "w") as f:
    f.write("# SYNTHETIC sample capture - generated by make_sample_capture.py\n")
    f.write("# Not a real trip: route and signals are procedurally generated.\n")
    prev_brake, prev_istop, prev_eng = None, False, None
    for i in range(N):
        ep = EPOCH0 + t[i]
        kmh = v_kmh[i]
        # time anchor (com.jci.time GetDatetime reply -> uint32 epoch)
        f.write("method return time=%.1f sender=:1.9 destination=:1.3 serial=%d\n" % (ep, i + 1))
        f.write("   uint32 %d\n" % int(ep))
        sig(f, ep, "com.jci.vbs.bcm", "CarSpeedResp", "uint32", int(10000 + 100 * kmh))
        if kmh > 3:
            sig(f, ep, "com.jci.vbs.vdt", "Veh_V_ActlEng", "uint16", int(kmh * 100))
        sig(f, ep, "com.jci.vbs.vdt", "EngAout_N_Actl", "uint16", int(rpm[i] / 2))
        sig(f, ep, "com.jci.vbs.vdt", "VehLong_A_Actl", "uint16", int(np.clip(a_long[i] * 100 + 4000, 0, 65535)))
        sig(f, ep, "com.jci.vbs.vdt", "Lateral_Acceleration", "uint16", int(np.clip(a_lat[i] * 100 + 4000, 0, 65535)))
        sig(f, ep, "com.jci.vbs.vdt", "SteWhlComp_An_Est", "uint16", int(np.clip(steer_deg[i] * 128 + 16384, 0, 65535)))
        sig(f, ep, "com.jci.vbs.vdt", "ApedPos_Pc_ActlArb", "uint16", int(throttle[i] * 10))
        sig(f, ep, "com.jci.vbs.vdt", "FuelPulse", "byte", int(fuel[i]))
        sig(f, ep, "com.jci.vbs.bcm", "GearPosNotification", "byte", int(gear[i]))
        # brake pedal: 2 = pressed, 1 = released, sent on change
        b = 2 if brake[i] else 1
        if b != prev_brake:
            sig(f, ep, "com.jci.vbs.bcm", "BrakePedalDepressedStatus", "byte", b)
            prev_brake = b
        # i-Stop request: sent when the engine is stopped / restarted
        if istop[i] != prev_istop:
            sig(f, ep, "com.jci.vbs.eem", "iStpReady_Rq", "boolean", "true" if istop[i] else "false")
            prev_istop = bool(istop[i])
        # engine state / cylinder deactivation (sent on change + every 5 s)
        es = (int(engstate[i]), int(cylstate[i]))
        if es != prev_eng or i % 10 == 0:
            f.write("signal time=%.1f sender=:1.3 -> path=/com/jci; interface=com.jci.vbs.eem; member=CylinderDeactivation\n" % ep)
            f.write("   byte %d\n   byte %d\n   byte %d\n" % (int(fuel[i]), es[0], es[1]))
            if es[0] != (prev_eng or (None,))[0]:
                sig(f, ep, "com.jci.vbs.eem", "EngineState", "byte", es[0])
            prev_eng = es
        # four wheel speeds (v74 scale); slight side difference in corners
        base = 10000 + 100 * kmh
        latw = a_lat[i] * 60.0
        f.write("signal time=%.1f sender=:1.3 -> path=/com/jci; interface=com.jci.vbs.bcm; member=WheelSpeedNotification\n" % ep)
        f.write("   uint16 0\n   uint16 0\n")
        for wv in (base + latw, base - latw, base + latw, base - latw):
            f.write("   uint16 %d\n" % int(np.clip(wv + rng.normal(0, 8), 0, 65535)))
        # camera temperature heartbeat (toggles - not a real warning)
        sig(f, ep, "com.jci.vwm", "Camera_high_temperature", "boolean", "true" if i % 2 else "false")
        # GPS fix at 1 Hz (every 2nd sample)
        if i % 2 == 0:
            f.write("method return time=%.1f sender=:1.7 destination=:1.3 serial=%d\n" % (ep, 100000 + i))
            f.write("   int32 3\n")
            f.write("   uint64 %d\n" % int(ep * 1000))
            f.write("   double %.7f\n" % lat[i])
            f.write("   double %.7f\n" % lon[i])
            f.write("   int32 %d\n" % int(520 + 4 * math.sin(i / 300.0) + 2 * math.sin(i / 47.0)))
            f.write("   double %.1f\n" % (math.degrees(heading[i]) % 360))
            f.write("   double %.1f\n" % kmh)
            f.write("   double 0.9\n")
            f.write("   double 1.2\n")

print("wrote %s  (%d samples, ~%.0f min, %d shifts, synthetic)" % (OUT, N, N * DT / 60, shift_no))
