#!/usr/bin/env python3
"""make_overview_pdf.py - Graphical PDF overview of a Mazda CMU D-Bus dump.

Usage: python3 -I make_overview_pdf.py dbus-dump.raw overview.pdf

Time axis: interpolation of com.jci.time GetDatetime replies (epoch s) over the line number.
Scales (CMU D-Bus, own analysis 2026-11-17):
  Veh_V_ActlEng /100 = km/h        CarSpeedResp(bcm) = 2500 + v/4  (2500 = standstill)
  EngAout_N_Actl x2 = rpm (estimated: raw ~350 at idle)
  VehLong_A_Actl / Lateral_Acceleration: (v-4000)/100 m/s2
  SteWhlComp_An_Est: (v-16384)/128 degrees      ApedPos_Pc_ActlArb /10 = %
"""
import re, sys, os, math, datetime
from collections import Counter, defaultdict
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

SRC = sys.argv[1] if len(sys.argv) > 1 else "dbus-dump.raw"
OUT = sys.argv[2] if len(sys.argv) > 2 else "overview.pdf"

HDR = re.compile(r'^(signal|method call|method return|error) .*?(?:interface=([^;]+); member=([A-Za-z_0-9]+))?$')
lines = open(SRC, errors="replace").read().split("\n")

# ---------- parse ----------
events = []          # (line, iface, member, kind, [values])
ts_anchor = []       # (line, epoch)
gps = []             # (line, lat, lon)
cur = None
for i, l in enumerate(lines):
    if not l.startswith(" "):
        if cur: events.append(cur)
        cur = None
        m = HDR.match(l)
        if not m: continue
        kind, iface, member = m.group(1), m.group(2), m.group(3)
        cur = [i, iface or "", member or "", kind, []]
        if kind == "method return" and i + 4 < len(lines):
            a, b = lines[i + 1].split(), lines[i + 2].split()
            if a[:1] == ["uint32"] and a[1].startswith("179"):
                ts_anchor.append((i, int(a[1])))
            if a[:1] == ["int32"] and b[:1] == ["uint64"] and lines[i + 3].strip().startswith("double"):
                # GetPosition: int32 fix, uint64 time, lat, lon, int32 altitude(m), heading(deg), speed(km/h), DOP, DOP
                try:
                    gps.append((i, *[float(lines[i + k].split()[1]) for k in range(3, 10)]))
                except (IndexError, ValueError):
                    gps.append((i, float(lines[i + 3].split()[1]), float(lines[i + 4].split()[1]), *[np.nan] * 5))
    elif cur is not None:
        p = l.split(None, 1)
        if len(p) == 2 and p[0] in ("uint16", "uint32", "byte", "int32", "int16", "boolean", "double", "string"):
            v = p[1]
            if p[0] == "boolean": v = 1 if v.strip() == "true" else 0
            elif p[0] == "double": v = float(v)
            elif p[0] == "string": v = v.strip('"')
            else: v = int(v)
            cur[4].append(v)
if cur: events.append(cur)

ta = np.array(ts_anchor, dtype=float)
def t_of(line):  # seconds since start
    return np.interp(line, ta[:, 0], ta[:, 1]) - ta[0, 1]
T0 = datetime.datetime.fromtimestamp(ta[0, 1])
T1 = datetime.datetime.fromtimestamp(ta[-1, 1])
DUR = ta[-1, 1] - ta[0, 1]

def series(iface, member):
    xs, ys = [], []
    for ln, ifc, mem, kind, vals in events:
        if ifc == iface and mem == member and kind == "signal" and vals and isinstance(vals[0], (int, float)):
            xs.append(t_of(ln)); ys.append(vals[0])
    return np.array(xs), np.array(ys, dtype=float)

tv, v = series("com.jci.vbs.vdt", "Veh_V_ActlEng"); v = v / 100.0
tr, rpm = series("com.jci.vbs.vdt", "EngAout_N_Actl"); rpm = rpm * 2
tlo, alo = series("com.jci.vbs.vdt", "VehLong_A_Actl"); alo = (alo - 4000) / 100.0
tla, ala = series("com.jci.vbs.vdt", "Lateral_Acceleration"); ala = (ala - 4000) / 100.0
tst, st = series("com.jci.vbs.vdt", "SteWhlComp_An_Est"); st = (st - 16384) / 128.0
tth, th = series("com.jci.vbs.vdt", "ApedPos_Pc_ActlArb"); th = th / 10.0
tfu, fu = series("com.jci.vbs.vdt", "FuelPulse")
tbc, bcm = series("com.jci.vbs.bcm", "CarSpeedResp")
# bcm.CarSpeedResp covers the whole dump (Veh_V_ActlEng only while driving): v = (raw-2500)*4/100 km/h
# v59: 2500 = standstill, (raw-2500)*4/100. v74 (calibrated 2026-11-23 against Veh_V): 10000 = standstill, (raw-10000)/100
if np.median(bcm) > 8000:
    vb = np.clip((bcm - 10000) / 100.0, 0, None)
else:
    vb = np.clip((bcm - 2500) * 4 / 100.0, 0, None)
grid = np.arange(0, ta[-1, 1] - ta[0, 1], 0.5)
def zoh(tx, y):
    i = np.searchsorted(tx, grid, side="right") - 1
    return np.where(i >= 0, y[np.clip(i, 0, None)], 0)
vg, rg = zoh(tbc, vb), zoh(tr, rpm)

# derived quantities
dist_km = vg.sum() * 0.5 / 3600.0
fuel_pulses = int(sum(((b - a) % 256) for a, b in zip(fu[:-1], fu[1:])))
def hav(a, b):
    R = 6371.0; la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))
gpsu = []
for g in gps:
    if not gpsu or (g[1], g[2]) != gpsu[-1][1:3]: gpsu.append(g)
gps_km = sum(hav(a[1:], b[1:]) for a, b in zip(gpsu[:-1], gpsu[1:]))

# gear estimate: rpm/v at the v timestamps
rpm_at_v = np.interp(tv, tr, rpm)
moving = v > 5
ratio = np.where(moving, rpm_at_v / np.maximum(v, 0.1), np.nan)
GEARS = [("1e", 95, 140), ("2e", 50, 70), ("3e", 35.5, 45), ("4e", 28, 34), ("5e", 22.6, 27.5), ("6e", 18, 22.4)]  # calibration drive 2026-11-23
def gear_of(r):
    if np.isnan(r): return "stil/<5"
    for n, lo, hi in GEARS:
        if lo <= r <= hi: return n
    return "overgang"
def gear_full(vv, rr):
    if vv <= 5: return "stil/<5"
    if rr < 760 and vv > 9: return "uitrollen"
    return gear_of(rr / vv)
gears = [gear_full(a, b) for a, b in zip(v, rpm_at_v)]
gear_time = defaultdict(float)
for vv, rr in zip(vg, rg):
    gear_time[gear_full(vv, rr)] += 0.5

# ---------- extra signals (inventory 2026-11-23) ----------
def raw(member, kind="signal"):
    return [(t_of(ln), vals) for ln, ifc, mem, k, vals in events if mem == member and k == kind and vals]

# actual gear position: bcm.GearPosNotification (v74) 1-6, 0 = neutral/clutch, 14 = probably reverse
_gp = raw("GearPosNotification")
HAS_GP = len(_gp) > 5
gp_t = np.array([t for t, _ in _gp]); gp_v = np.array([x[0] for _, x in _gp], dtype=float)
gp_grid = zoh(gp_t, gp_v) if HAS_GP else np.full_like(grid, np.nan)
gp_time = defaultdict(float)
GP_NAME = {0: "neutraal", 1: "1e", 2: "2e", 3: "3e", 4: "4e", 5: "5e", 6: "6e", 14: "achteruit?"}
# Internal bucket keys stay stable (used as dict keys / comparisons); DISP maps
# them to English only where a label is shown to the user.
DISP = {"1e": "1st", "2e": "2nd", "3e": "3rd", "4e": "4th", "5e": "5th", "6e": "6th",
        "stil/<5": "stop/<5", "uitrollen": "coast", "overgang": "transition",
        "neutraal": "neutral", "achteruit?": "reverse?"}
def disp(k): return DISP.get(k, k)
if HAS_GP:
    for vv, gg in zip(vg, gp_grid):
        gp_time["stil/<5" if vv <= 5 else GP_NAME.get(int(gg), f"code {int(gg)}")] += 0.5
est_grid = np.array([gear_full(a, b) for a, b in zip(vg, rg)])
_cmp = (vg > 5) & np.isin(gp_grid, [1, 2, 3, 4, 5, 6]) & np.isin(est_grid, ["1e", "2e", "3e", "4e", "5e", "6e"])
gp_agree = (np.array([GP_NAME.get(int(g), "") for g in gp_grid[_cmp]]) == est_grid[_cmp]).mean() * 100 if _cmp.any() else float("nan")
shifts = int(sum(1 for a, b in zip(gp_v[:-1], gp_v[1:]) if b in (1, 2, 3, 4, 5, 6) and a != b))

# four wheel speeds: bcm.WheelSpeedNotification f2..f5, scale = CarSpeedResp (v74)
_ws = raw("WheelSpeedNotification")
HAS_WS = len(_ws) > 100 and len(_ws[0][1]) >= 6
if HAS_WS:
    tw = np.array([t for t, _ in _ws]); wraw = np.array([x[2:6] for _, x in _ws], dtype=float)
    wk = np.clip((wraw - 10000) / 100.0, 0, None) if np.median(wraw) > 8000 else np.clip((wraw - 2500) * 4 / 100.0, 0, None)
    wmean = wk.mean(1)
    lat_w = np.interp(tw, tla, ala)
    side_diff = (wk[:, 0] + wk[:, 2]) - (wk[:, 1] + wk[:, 3])   # side A (f2,f4) - side B (f3,f5)
    _mv = wmean > 30
    side_corr = np.corrcoef(side_diff[_mv], lat_w[_mv])[0, 1] if _mv.sum() > 10 else float("nan")
    _str = _mv & (np.abs(lat_w) < 0.3) & (wmean > 80)
    wheel_dev = ((wk[_str] / wmean[_str, None]).mean(0) - 1) * 100 if _str.sum() > 50 else np.zeros(4)

# extended GPS
GP = np.array([(t_of(g[0]), *g[1:]) for g in gps], dtype=float) if gps else np.zeros((0, 8))
HAS_GPSX = len(GP) and GP.shape[1] >= 8 and not np.isnan(GP[:, 5]).all()
if HAS_GPSX:
    _gm = GP[:, 5] > 40
    gps_vs_car = np.interp(GP[_gm, 0], tbc, vb) / GP[_gm, 5]
    speedo_dev = (np.median(gps_vs_car) - 1) * 100

# speed limit from navigation (NNG GuidanceChangedForHUD: f3 street, f4 limit, f5==3 -> limit valid)
_gd = raw("GuidanceChangedForHUD")
lim_pts = [(t, int(x[4]) if len(x) > 5 and x[5] == 3 else 0) for t, x in _gd if len(x) > 5]
HAS_LIM = sum(1 for _, l in lim_pts if l) >= 2
if HAS_LIM:
    lim_grid = zoh(np.array([t for t, _ in lim_pts]), np.array([l for _, l in lim_pts], float))
    _lv = (lim_grid > 0) & (vg > 5)
    over = vg > lim_grid + 5
    over_pct = (over & _lv).sum() / max(1, _lv.sum()) * 100
    lim_cov = _lv.sum() / max(1, (vg > 5).sum()) * 100
streets = [x[3] for _, x in _gd if len(x) > 3 and isinstance(x[3], str) and x[3]]

# brake pedal: bcm.BrakePedalDepressedStatus 2 = pressed, 1 = released (only on change + repeated when shifting)
_br = raw("BrakePedalDepressedStatus")
br_t = np.array([t for t, _ in _br]); br_v = np.array([x[0] for _, x in _br], dtype=float)
brake_presses = int(sum(1 for i_, x in enumerate(br_v) if x == 2 and (i_ == 0 or br_v[i_ - 1] != 2)))
brake_grid = zoh(br_t, br_v) if len(br_t) else np.zeros_like(grid)
brake_time = (brake_grid == 2).sum() * 0.5

# i-Stop
_is = raw("iStpReady_Rq")
istop_t = [t for t, x in _is if x[0]]
istop_n = len(istop_t)
istop_deny = {m.replace("iStpDeny", "").replace("_B_Actl", ""): [(t, x[0]) for t, x in raw(m)]
              for m in ("iStpDenyAC_B_Actl", "iStpDenyBatt_B_Actl", "iStpDenyDPF_B_Actl", "iStpDenyNrange_B_Actl")}
engst = raw("EngineState")

# CylinderDeactivation (yyy) = fuelPulse_for_DispCylState, sISS_EngineState, cylState (svcjcieem: cylState 20 -> 2/4 cyl.)
_cd = raw("CylinderDeactivation")
cd_t = np.array([t for t, _ in _cd]); cd_v = np.array([x[1] if len(x) > 1 else np.nan for _, x in _cd], dtype=float)
cd_c = np.array([x[2] if len(x) > 2 else np.nan for _, x in _cd], dtype=float)
cyl2_pct = ((zoh(cd_t, cd_c) == 20) & (vg > 5)).sum() / max(1, (vg > 5).sum()) * 100 if len(cd_t) else 0.0

# wifi
wifi_tries = len(raw("Connect", "method call")) or len(raw("InterfaceConnecting"))
can_missing = [x[0] for _, x in raw("CAN_Missing")] + [x[0] for _, x in raw("CAN_Missing_Error")]
td = raw("Total_Distance")
odo_from, odo_to = (td[0][1][0], td[-1][1][0]) if td else (None, None)
HAS_STEER = len(st) > 10

drive_t = grid[vg > 0.5]
DRIVE_FROM, DRIVE_TO = (drive_t[0], drive_t[-1]) if len(drive_t) else (0, 0)

# signal inventory
inv = Counter((e[1], e[2], e[3]) for e in events if e[1])
svc = Counter()
for (ifc, mem, kind), n in inv.items():
    if kind == "signal": svc[ifc.replace("com.jci.", "")] += n

# lamps / warnings
warn_members = ["Camera_high_temperature", "ColdStrtDisable_Telltale", "Light_Types", "LampActivationNotify",
                "HECIlluminationStatus", "SISS_WarningLamp_G", "SISS_WarningLamp_R", "SISSStatus",
                "SISS_EngineState", "iStpReady_Rq", "BrakePedalDepressedStatus", "RVM_state",
                "SchMnt_Oil_B_Rq", "SchMnt_Tyre_B_Rq", "WshrLvl_D_Actl", "VehSpeedFlag"]
warn = {m: [] for m in warn_members}
for ln, ifc, mem, kind, vals in events:
    if mem in warn and vals and kind == "signal":
        warn[mem].append((t_of(ln), vals[0]))

# ---------- layout ----------
C1, C2, C3, CG = "#9c1c1c", "#1f4e79", "#e08a00", "#666666"
plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.titleweight": "bold", "axes.titlesize": 11})
A4 = (11.69, 8.27)

def header(fig, title, sub=""):
    fig.text(0.04, 0.955, title, fontsize=17, weight="bold", color=C1)
    if sub: fig.text(0.04, 0.925, sub, fontsize=9.5, color=CG)
    fig.text(0.96, 0.02, f"Mazda 3 BM - CMU D-Bus dump {T0:%d-%m-%Y}", ha="right", fontsize=7, color=CG)

def tmin(x): return x / 60.0

with PdfPages(OUT) as pdf:
    # ===== 1. Summary =====
    fig = plt.figure(figsize=A4); header(fig, "Trip overview - what the CMU tells us",
        f"Source: {os.path.basename(SRC)}  |  {T0:%H:%M:%S} - {T1:%H:%M:%S} (CMU clock)  |  {len(events):,} D-Bus messages".replace(",", "."))
    kpis = [("Logged", f"{DUR/60:.1f} min"), ("Distance (speed)", f"{dist_km:.2f} km"),
            ("Distance (GPS)", f"{gps_km:.2f} km"), ("Max speed", f"{vg.max():.0f} km/h"),
            ("Driving", f"{(DRIVE_TO-DRIVE_FROM)/60:.1f} min"), ("Max rpm", f"~{rpm.max():.0f} rpm"),
            ("Max G long.", f"{np.abs(alo).max()/9.81:.2f} g"), ("Max G lat.", f"{np.abs(ala).max()/9.81:.2f} g"),
            ("Standstill", f"{gear_time['stil/<5']/DUR*100:.0f} %"), ("Fuel pulses", f"{fuel_pulses:,}".replace(",", ".")),
            ("Gear shifts", f"{shifts}" if HAS_GP else "-"), ("Brake presses", f"{brake_presses}"),
            ("i-Stop engine off", f"{istop_n}x"),
            ("Above limit (+5)", f"{over_pct:.0f} %" if HAS_LIM else "-"),
            ("Speedometer vs GPS", f"{speedo_dev:+.1f} %" if HAS_GPSX else "-")]
    for k, (lab, val) in enumerate(kpis):
        x = 0.04 + (k % 5) * 0.19; y = 0.80 - (k // 5) * 0.115
        fig.patches.append(plt.Rectangle((x, y), 0.175, 0.098, transform=fig.transFigure, color="#f3eeee", zorder=0))
        fig.text(x + 0.012, y + 0.058, val, fontsize=15, weight="bold", color=C1)
        fig.text(x + 0.012, y + 0.018, lab, fontsize=8.5, color=CG)
    ax = fig.add_axes([0.14, 0.06, 0.33, 0.38])
    names, cnts = zip(*svc.most_common(10))
    ax.barh(names[::-1], cnts[::-1], color=C2); ax.set_title("Signals per CMU service")
    for i_, c in enumerate(cnts[::-1]): ax.text(c, i_, f" {c}", va="center", fontsize=7.5)
    fig.text(0.53, 0.44, "Key findings", fontsize=11, weight="bold")
    gt = gp_time if HAS_GP else gear_time
    sixth = gt.get("6e", 0) / max(1, (DRIVE_TO - DRIVE_FROM)) * 100
    concl = [
        f"- ~{(DRIVE_TO-DRIVE_FROM)/60:.0f} min driving, {dist_km:.1f} km (GPS {gps_km:.1f} km"
        + (f", odometer {odo_to - odo_from} km)." if odo_from is not None else ")."),
        "- v74: CarSpeedResp = 10000 + 100 x km/h; distance matches GPS within 2 %.",
        (f"- NEW: actual gear position via bcm.GearPosNotification; {shifts} gear shifts," if HAS_GP else
         "- Gear position not in this dump; only estimated from rpm/speed."),
        (f"   {sixth:.0f} % of driving time in 6th gear. Estimate agrees {gp_agree:.0f} %." if HAS_GP else
         f"   ~{sixth:.0f} % of driving time in 6th gear (estimated)."),
        (f"- Speedometer (CMU) deviates {speedo_dev:+.1f} % from GPS speed." if HAS_GPSX else ""),
        (f"- Navigation limit known for {lim_cov:.0f} % of driving time; {over_pct:.0f} % >5 km/h above it." if HAS_LIM else ""),
        f"- {brake_presses}x braked ({brake_time/60:.1f} min brake pedal), i-Stop stopped the engine {istop_n}x.",
        ("- Steering angle (SteWhlComp_An_Est) does not exist on v74." if not HAS_STEER else ""),
        "- Not via D-Bus: turn signals, doors, wipers, headlights, coolant,",
        "   fuel level, outside temperature, tyre pressure -> OBD-CAN needed.",
    ]
    concl = [c for c in concl if c]
    for k, s in enumerate(concl): fig.text(0.53, 0.405 - k * 0.032, s, fontsize=9.2)
    pdf.savefig(fig); plt.close(fig)

    # ===== 2. Timeline =====
    fig, axs = plt.subplots(4, 1, figsize=A4, sharex=True, gridspec_kw={"hspace": 0.25})
    fig.subplots_adjust(top=0.88, bottom=0.07, left=0.07, right=0.97)
    header(fig, "Trip timeline", "Speed, rpm, throttle and estimated gear over time (minutes from start)")
    axs[0].plot(tmin(grid), vg, color=C1, lw=1); axs[0].fill_between(tmin(grid), vg, color=C1, alpha=.12)
    axs[0].set_ylabel("km/h"); axs[0].set_title("Speed (bcm.CarSpeedResp)", loc="left")
    axs[1].plot(tmin(tr), rpm, color=C2, lw=.8); axs[1].set_ylabel("rpm"); axs[1].set_title("Engine speed (estimated x2)", loc="left")
    axs[2].plot(tmin(tth), th, color=C3, lw=.8, drawstyle="steps-post"); axs[2].set_ylabel("%"); axs[2].set_title("Throttle pedal", loc="left")
    gmap = {"stil/<5": 0, "uitrollen": 0.5, "1e": 1, "2e": 2, "3e": 3, "4e": 4, "5e": 5, "6e": 6}
    gy = np.array([gmap.get(g, np.nan) for g in gears], dtype=float)
    axs[3].scatter(tmin(tv), gy, s=4, color="#bbbbbb", label="estimated (rpm/speed)")
    if HAS_GP:
        gpp = np.where(gp_grid == 14, np.nan, gp_grid)
        axs[3].plot(tmin(grid), np.where(vg > 0.5, gpp, np.nan), color=C1, lw=1.1, drawstyle="steps-post", label="actual (GearPosNotification)")
        axs[3].legend(frameon=False, fontsize=7.5, loc="lower right", ncol=2)
    axs[3].set_yticks([0, .5, 1, 2, 3, 4, 5, 6], ["N/stop", "coast", "1", "2", "3", "4", "5", "6"])
    axs[3].set_title("Gear", loc="left"); axs[3].set_xlabel("minutes")
    for a in axs: a.grid(alpha=.25)
    pdf.savefig(fig); plt.close(fig)

    # ===== 3. Gears =====
    fig = plt.figure(figsize=A4); header(fig, "Shifting behaviour",
        (f"Colour = actual gear (bcm.GearPosNotification); lines = calibrated rpm/speed ratio. Agreement {gp_agree:.0f} %"
         if HAS_GP else "Estimated from the rpm / speed ratio"))
    if HAS_GP:
        gp_at_v = zoh(gp_t, gp_v)[np.clip(np.searchsorted(grid, tv) - 1, 0, None)]
        gears_plot = ["stil/<5" if vv <= 5 else GP_NAME.get(int(g), "overgang") for vv, g in zip(v, gp_at_v)]
        gears_plot = ["uitrollen" if g == "neutraal" else g for g in gears_plot]
    else:
        gears_plot = gears
    ax = fig.add_axes([0.06, 0.10, 0.50, 0.75])
    cols = {"1e": "#c0392b", "2e": C3, "3e": C2, "4e": "#2e8b57", "5e": "#1f618d", "6e": "#6c3483", "uitrollen": "#8fbc8f", "overgang": "#bbbbbb"}
    for g, c in cols.items():
        sel = np.array([x == g for x in gears_plot])
        if sel.any(): ax.scatter(v[sel], rpm_at_v[sel], s=7, color=c, label=disp("neutraal" if g == "uitrollen" and HAS_GP else g), alpha=.75)
    xs = np.linspace(0, v.max() + 3, 50)
    for n, lo, hi in GEARS:
        mid = (lo + hi) / 2; ax.plot(xs, xs * mid, ls="--", lw=.7, color=CG)
        xe = min(vg.max() + 1, rpm.max() * 1.1 / mid); ax.text(xe, xe * mid, f" {disp(n)}", fontsize=8, color=CG)
    ax.set_xlim(0, vg.max() + 4); ax.set_ylim(0, rpm.max() * 1.15)
    ax.set_xlabel("speed km/h"); ax.set_ylabel("engine speed rpm (estimated)"); ax.legend(frameon=False)
    ax.set_title("RPM vs speed - each line = one gear"); ax.grid(alpha=.25)
    ax2 = fig.add_axes([0.64, 0.50, 0.32, 0.33])
    _gtm = dict(gp_time) if HAS_GP else dict(gear_time)
    if HAS_GP: _gtm["uitrollen"] = _gtm.pop("neutraal", 0) + _gtm.pop("achteruit?", 0)
    order = [o for o in ["stil/<5", "1e", "2e", "3e", "4e", "5e", "6e", "uitrollen", "overgang"] if _gtm.get(o, 0) > 0]
    vals = [_gtm[o] / 60 for o in order]
    ax2.bar([disp("neutraal" if o == "uitrollen" and HAS_GP else o) for o in order], vals,
            color=[CG if o == "stil/<5" else cols[o] for o in order]); ax2.set_ylabel("minutes")
    ax2.set_title("Time per gear"); ax2.tick_params(axis="x", labelrotation=30, labelsize=8)
    for i_, val in enumerate(vals): ax2.text(i_, val, f"{val:.1f}", ha="center", va="bottom", fontsize=8)
    txt = ["How to read this", "",
           "A manual gearbox has a fixed ratio per gear",
           "between rpm and speed; the points fall on straight lines.",
           "Ratios (calibration drive 23-11): 1st ~113, 2nd ~59, 3rd ~40,",
           "4th ~31, 5th ~25, 6th ~20 rpm per km/h.", "",
           "On v74 the BCM sends the gear position itself" if HAS_GP else "",
           "(GearPosNotification: 1-6, 0 = neutral/clutch," if HAS_GP else "",
           "14 when parking = probably reverse)." if HAS_GP else "",
           f"{shifts} shifts into a gear." if HAS_GP else ""]
    for k, s in enumerate(txt): fig.text(0.64, 0.42 - k * 0.028, s, fontsize=9, weight="bold" if k == 0 else None)
    pdf.savefig(fig); plt.close(fig)

    # ===== 4. Driving dynamics =====
    fig = plt.figure(figsize=A4); header(fig, "Driving dynamics", "G-forces, " + ("steering angle" if HAS_STEER else "brake pedal") + " and throttle usage")
    ax = fig.add_axes([0.06, 0.10, 0.36, 0.72])
    lat_on_long = np.interp(tlo, tla, ala)
    ax.scatter(lat_on_long / 9.81, alo / 9.81, s=4, color=C2, alpha=.35)
    for r in (0.1, 0.2, 0.3, 0.4):
        ax.add_patch(plt.Circle((0, 0), r, fill=False, ls=":", color=CG, lw=.7)); ax.text(r * .71, r * .71, f"{r}g", fontsize=7, color=CG)
    ax.set_xlim(-.5, .5); ax.set_ylim(-.5, .5); ax.set_aspect("equal")
    ax.axhline(0, color=CG, lw=.5); ax.axvline(0, color=CG, lw=.5)
    ax.set_xlabel("lateral (g)   left <-> right"); ax.set_ylabel("braking <-> accelerating (g)")
    ax.set_title("G-G diagram")
    ax = fig.add_axes([0.52, 0.56, 0.44, 0.26])
    if HAS_STEER:
        ax.hist(st, bins=np.arange(-60, 61, 5), color=C3); ax.set_title("Steering angle (degrees)"); ax.set_xlabel("degrees")
    else:
        # brake events: deceleration (longitudinal G) in the 3 s after pressing
        pr = [t for i_, (t, x) in enumerate(zip(br_t, br_v)) if x == 2 and (i_ == 0 or br_v[i_ - 1] != 2)]
        decel = [np.interp(np.linspace(t, t + 3, 7), tlo, alo).min() / 9.81 for t in pr]
        ax.hist(decel, bins=np.arange(-0.5, 0.11, 0.05), color=C3)
        ax.set_title(f"Brake events: strongest deceleration after pressing ({len(pr)}x)"); ax.set_xlabel("g (negative = braking)")
        ax.text(0.02, 0.85, "steering angle: not available on v74", transform=ax.transAxes, fontsize=8, color=CG)
    ax = fig.add_axes([0.52, 0.12, 0.44, 0.30])
    ax.hist(th, bins=np.arange(0, max(th.max(), 10) + 2.5, 2.5), color=C1)
    ax.set_title("Throttle pedal (%)"); ax.set_xlabel("% pressed")
    ax.text(0.98, 0.9, f"max {th.max():.0f} %  |  avg. {th.mean():.1f} %", transform=ax.transAxes, ha="right", fontsize=8.5)
    pdf.savefig(fig); plt.close(fig)

    # ===== 4b. Wheels + speedometer =====
    if HAS_WS or HAS_GPSX:
        fig = plt.figure(figsize=A4); header(fig, "Wheel speeds and speedometer",
            "bcm.WheelSpeedNotification (4 wheels, same scale as CarSpeedResp) and GPS speed from lds.data GetPosition")
        if HAS_WS:
            ax = fig.add_axes([0.06, 0.52, 0.38, 0.32])
            lbl = ["front left", "front right", "rear left", "rear right"]
            ax.bar(lbl, wheel_dev, color=[C1, C1, C2, C2]); ax.axhline(0, color=CG, lw=.6)
            for i_, d in enumerate(wheel_dev): ax.text(i_, d, f"{d:+.2f}%", ha="center", va="bottom" if d >= 0 else "top", fontsize=8)
            ax.set_ylabel("% vs. average"); ax.set_title("Deviation per wheel (straight, >80 km/h)")
            ax = fig.add_axes([0.56, 0.52, 0.40, 0.32])
            sel = np.where(_mv)[0][::5]
            ax.scatter(lat_w[sel] / 9.81, side_diff[sel], s=3, alpha=.3, color=C2)
            ax.set_xlabel("lateral G"); ax.set_ylabel("km/h  left - right")
            ax.set_title(f"Corners: left/right difference vs lateral G (r = {side_corr:.2f})"); ax.grid(alpha=.25)
        if HAS_GPSX:
            ax = fig.add_axes([0.06, 0.09, 0.38, 0.30])
            ax.hist((gps_vs_car - 1) * 100, bins=np.arange(-5, 5.01, 0.25), color=C3)
            ax.axvline(speedo_dev, color=C1, lw=1.2); ax.set_xlabel("% (CMU speed / GPS speed - 1)")
            ax.set_title(f"Speed CMU vs GPS (>40 km/h): median {speedo_dev:+.2f} %")
        txt = ["What do you see?", "",
               "- Order from the firmware (libjcimod_bcm: FrontLeft,",
               "  FrontRight, RearLeft, RearRight). The left-right difference follows",
               f"  lateral G almost perfectly (r = {side_corr:.2f}): outer wheel turns faster." if HAS_WS else "",
               "- Front wheels (driven) turn ~0.3 % faster than the rear.",
               "- A wheel that consistently turns faster = smaller circumference:",
               "  lower tyre pressure or more wear (indirect TPMS principle).",
               "  Track this over several trips; a jump is a warning sign.",
               "- CMU speed vs GPS: the CMU passes on the BCM wheel speed,",
               "  the instrument cluster usually shows a few % more (legal requirement)."]
        for k, s in enumerate(txt): fig.text(0.54, 0.37 - k * 0.029, s, fontsize=9, weight="bold" if k == 0 else None)
        pdf.savefig(fig); plt.close(fig)

    # ===== 4c. Limit + altitude =====
    if HAS_LIM or HAS_GPSX:
        fig, axs = plt.subplots(2, 1, figsize=A4, sharex=True, gridspec_kw={"hspace": 0.3, "height_ratios": [2, 1]})
        fig.subplots_adjust(top=0.86, bottom=0.08, left=0.07, right=0.97)
        header(fig, "Speed vs. limit and altitude profile",
               "Limit from navigation (NNG GuidanceChangedForHUD, only with an active route); altitude from GPS (m)")
        axs[0].plot(tmin(grid), vg, color=C2, lw=.9, label="speed")
        if HAS_LIM:
            lg = np.where(lim_grid > 0, lim_grid, np.nan)
            axs[0].plot(tmin(grid), lg, color="k", lw=1.4, drawstyle="steps-post", label="limit (navigation)")
            ov = np.where(over & (lim_grid > 0), vg, np.nan)
            axs[0].plot(tmin(grid), ov, color=C1, lw=1.2, label=">5 km/h above limit")
            axs[0].set_title(f"Limit known for {lim_cov:.0f} % of driving time; {over_pct:.0f} % of that more than 5 km/h above it", loc="left")
        _tsr = raw("TSRInformation")  # NNG: (country code, functional road class, built-up area)
        if len(_tsr) >= 2:
            bu = zoh(np.array([t for t, _ in _tsr]), np.array([x[2] if len(x) > 2 else 0 for _, x in _tsr], float))
            axs[0].fill_between(tmin(grid), 0, 135, where=bu == 1, color="#f0e0a0", alpha=.45, step="post", label="built-up area (navigation flag)")
        axs[0].set_ylabel("km/h"); axs[0].legend(frameon=False, fontsize=8, ncol=4, loc="upper left"); axs[0].grid(alpha=.25)
        if HAS_GPSX:
            axs[1].plot(tmin(GP[:, 0]), GP[:, 3], color="#2e8b57", lw=.9)
            axs[1].set_ylabel("m"); axs[1].set_title(f"GPS altitude (min {np.nanmin(GP[:, 3]):.0f} m, max {np.nanmax(GP[:, 3]):.0f} m) - coarse, 1 m steps", loc="left")
        axs[1].set_xlabel("minutes"); axs[1].grid(alpha=.25)
        pdf.savefig(fig); plt.close(fig)

    # ===== 4d. Engine, stop-start, brakes =====
    fig = plt.figure(figsize=A4); header(fig, "Engine, i-Stop and brakes",
        "eem.iStpReady_Rq / iStpDeny*, SISS_EngineState, bcm.BrakePedalDepressedStatus, eem.CylinderDeactivation (yyy)")
    ax = fig.add_axes([0.20, 0.50, 0.76, 0.34])
    rows_t = []
    rows_t.append(("i-Stop ready", [(t, x[0]) for t, x in _is]))
    for k_, pts in istop_deny.items():
        if pts: rows_t.append((f"i-Stop denied: {k_}", pts))
    rows_t.append(("brake pedal", [(t, 1 if x == 2 else 0) for t, x in zip(br_t, br_v)]))
    for k, (name, pts) in enumerate(rows_t):
        on = [tmin(t) for t, x in pts if x]; off = [tmin(t) for t, x in pts if not x]
        ax.scatter(on, [k] * len(on), marker="|", s=110, color=C1); ax.scatter(off, [k] * len(off), marker="|", s=110, color="#bbbbbb")
    ax.set_yticks(range(len(rows_t)), [r[0] for r in rows_t], fontsize=8); ax.set_xlim(0, DUR / 60 + 1)
    ax.set_title("Events (red = on/active)"); ax.grid(axis="x", alpha=.25); ax.set_xlabel("minutes")
    ax = fig.add_axes([0.20, 0.09, 0.40, 0.30])
    if len(cd_t):
        ax.plot(tmin(cd_t), cd_v, color=C2, lw=.8, drawstyle="steps-post", label="SISS_EngineState")
        ax.plot(tmin(cd_t), cd_c, color=C1, lw=1.2, drawstyle="steps-post", label="cylState (20 = 2 cylinders)")
        ax.set_title("Engine state and cylinder mode"); ax.set_xlabel("minutes"); ax.grid(alpha=.25); ax.legend(frameon=False, fontsize=7.5)
    txt = ["What do you see?", "",
           f"- {brake_presses}x braked, {brake_time/60:.1f} min in total.",
           f"- i-Stop: engine automatically off {istop_n}x.",
           "- SISS_EngineState: " + " > ".join(str(x[0]) for _, x in engst[:8]),
           "  Firmware: 1,2,6,7,8,9 = engine not combusting (0/4).",
           "  3 = running (first ~6 min), 10 = running, i-Stop possible.",
           "- CylinderDeactivation = (fuel pulse, EngineState,",
           f"  cylState). cylState = 20 -> 2 of 4 cylinders: {cyl2_pct:.0f} %",
           "  of driving time" + (" (never: not equipped?)." if cyl2_pct == 0 else "."),
           (f"- CAN_Missing reported: {', '.join(str(c) for c in can_missing)}" if can_missing else ""),
           "  (missing CAN messages, mostly around engine start)." if can_missing else ""]
    for k, s in enumerate(txt): fig.text(0.65, 0.37 - k * 0.029, s, fontsize=9, weight="bold" if k == 0 else None)
    pdf.savefig(fig); plt.close(fig)

    # ===== 4e. Map =====
    if len(gpsu) > 20:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import osm_map
            g_t = np.array([t_of(g[0]) for g in gpsu]); g_la = np.array([g[1] for g in gpsu]); g_lo = np.array([g[2] for g in gpsu])
            g_v = np.interp(g_t, grid, vg)
            fig = plt.figure(figsize=A4); header(fig, "Route on the map",
                f"{len(gpsu)} GPS points, coloured by speed  |  start = green, end = red  |  {gps_km:.1f} km")
            ax = fig.add_axes([0.03, 0.04, 0.84, 0.86])
            lc, z = osm_map.draw_route(ax, g_la, g_lo, g_v, vmax=max(110, g_v.max()))
            cax = fig.add_axes([0.89, 0.15, 0.015, 0.6]); fig.colorbar(lc, cax=cax, label="km/h")
            pdf.savefig(fig, dpi=200); plt.close(fig)
            # detail: first and last ~12 minutes (city)
            fig = plt.figure(figsize=A4); header(fig, "Detail: departure and arrival", "First and last 12 minutes of the trip, coloured by speed")
            for k, (a_, b_, ttl) in enumerate([(g_t[0], g_t[0] + 720, "Departure"), (g_t[-1] - 720, g_t[-1], "Arrival")]):
                s_ = (g_t >= a_) & (g_t <= b_)
                if s_.sum() < 5: continue
                ax = fig.add_axes([0.03 + k * 0.48, 0.06, 0.45, 0.80])
                osm_map.draw_route(ax, g_la[s_], g_lo[s_], g_v[s_], vmax=110, lw=3.2, show_start=(k == 0), show_end=(k == 1))
                ax.set_title(f"{ttl} ({tmin(a_):.0f}-{tmin(b_):.0f} min)", fontsize=11, weight="bold")
            pdf.savefig(fig, dpi=200); plt.close(fig)
            # interactive map with markers
            mk = []
            for t in istop_t: mk.append([float(np.interp(t, g_t, g_la)), float(np.interp(t, g_t, g_lo)), f"i-Stop engine off ({tmin(t):.1f} min)", "#1f4e79"])
            for i_, (t, x) in enumerate(zip(br_t, br_v)):
                if x == 2 and (i_ == 0 or br_v[i_ - 1] != 2):
                    d_ = np.interp(np.linspace(t, t + 3, 7), tlo, alo).min() / 9.81
                    if d_ < -0.2: mk.append([float(np.interp(t, g_t, g_la)), float(np.interp(t, g_t, g_lo)), f"hard braking {d_:.2f} g ({tmin(t):.1f} min)", "#c0392b"])
            for t, x in _gp:
                pass
            html = os.path.splitext(OUT)[0] + "-map.html"
            osm_map.leaflet_html(html, g_la, g_lo, g_v, f"Mazda trip {T0:%d-%m-%Y}", extra_markers=mk)
            print("map:", html, "zoom", z)
        except Exception as e:
            print("map skipped:", e)

    # ===== 5. Route + warnings =====
    fig = plt.figure(figsize=A4); header(fig, "Route and warnings", "GPS from com.jci.lds.data GetPosition; warnings/lamps from VWM and EEM")
    ax = fig.add_axes([0.05, 0.10, 0.38, 0.74])
    if gpsu:
        la_ = np.array([g[1] for g in gpsu]); lo_ = np.array([g[2] for g in gpsu])
        sc = ax.scatter(lo_, la_, c=[t_of(g[0]) / 60 for g in gpsu], cmap="viridis", s=12)
        ax.plot(lo_, la_, color=CG, lw=.6); ax.plot(lo_[0], la_[0], "o", color="green", ms=9); ax.plot(lo_[-1], la_[-1], "s", color=C1, ms=9)
        ax.set_aspect(1 / math.cos(math.radians(la_.mean()))); fig.colorbar(sc, ax=ax, shrink=.6, label="minute")
        ax.ticklabel_format(useOffset=False); ax.tick_params(labelsize=7)
    ax.set_title(f"Route (GPS, {len(gpsu)} unique points, {gps_km:.2f} km)")
    ax = fig.add_axes([0.55, 0.10, 0.42, 0.74])
    shown = [m for m in warn_members if warn[m]]
    for k, m in enumerate(shown):
        pts = warn[m]
        xs_ = [tmin(p[0]) for p in pts]; ys_ = [p[1] if isinstance(p[1], (int, float)) else 1 for p in pts]
        on = [x for x, y in zip(xs_, ys_) if y]; off = [x for x, y in zip(xs_, ys_) if not y]
        ax.scatter(on, [k] * len(on), marker="|", s=90, color=C1); ax.scatter(off, [k] * len(off), marker="|", s=90, color="#bbbbbb")
        ax.text(DUR / 60 + .2, k, f"{len(pts)}x", va="center", fontsize=7, color=CG)
    ax.set_yticks(range(len(shown)), shown, fontsize=7.5); ax.set_xlabel("minutes"); ax.set_xlim(0, DUR / 60 + 1.2)
    ax.set_title("Warnings/lamps (red = active/on)"); ax.grid(axis="x", alpha=.25)
    pdf.savefig(fig); plt.close(fig)

    # ===== 6. Data inventory =====
    fig = plt.figure(figsize=A4); header(fig, "What do we have and what not?", "Car data available via the CMU (D-Bus) versus what a CAN adapter would add")
    rows = [
        ["Speed", "yes", "vdt.Veh_V_ActlEng /100; bcm.CarSpeedResp v74 = 10000 + 100 x km/h"],
        ["Wheel speeds (4x)", "yes", "bcm.WheelSpeedNotification (id, len, FL, FR, RL, RR, ts); scale as CarSpeedResp"],
        ["Engine speed", "yes", "vdt.EngAout_N_Actl (x2, estimated)"],
        ["Gear position", "yes" if HAS_GP else "NO", "bcm.GearPosNotification 1-6, 0 = neutral (v74)" if HAS_GP else "not in this dump"],
        ["Throttle pedal", "yes", "vdt.ApedPos_Pc_ActlArb /10 %"],
        ["G-forces long./lat.", "yes", "VehLong_A_Actl / Lateral_Acceleration (v-4000)/100 m/s2"],
        ["Steering angle", "yes" if HAS_STEER else "NO", "SteWhlComp_An_Est (v-16384)/128 degrees" if HAS_STEER else "SteWhlComp_An_Est missing on v74"],
        ["Brake pedal", "yes", "bcm.BrakePedalDepressedStatus 2 = pressed, 1 = released"],
        ["Fuel", "partial", "vdt.FuelPulse counter; ml/pulse still to be calibrated with a fill-up"],
        ["GPS", "yes", "lds.data GetPosition: lat, lon, altitude, heading, km/h, 2x DOP"],
        ["Navigation: street + limit", "partial", "NNG GuidanceChangedForHUD (active route); TSRInformation = country, road class, built-up area"],
        ["Start-stop (i-Stop)", "yes", "eem.iStpReady_Rq, iStpDeny* (AC, battery, DPF, N)"],
        ["Engine state / cylinders", "partial", "SISS_EngineState (enum partly known), CylinderDeactivation.cylState 20 = 2/4"],
        ["Odometer", "yes", "vwm/vdt.Total_Distance (km), vdt.OdoCount (~5000 pulses/km)"],
        ["Turn signals / headlights", "NO", "only via OBD-CAN"],
        ["Coolant / outside temp.", "NO", "only via OBD (PID 05 / 46)"],
        ["Fuel level / tyre pressure", "NO", "only via OBD-CAN"],
        ["Doors / windows / wipers", "NO", "only via OBD-CAN"],
    ]
    ax = fig.add_axes([0.04, 0.08, 0.92, 0.80]); ax.axis("off")
    tb = ax.table(cellText=rows, colLabels=["Data item", "Via CMU?", "Source / scale"], loc="upper center",
                  colWidths=[.22, .10, .68], cellLoc="left")
    tb.auto_set_font_size(False); tb.set_fontsize(8.5); tb.scale(1, 1.45)
    for (r, c), cell in tb.get_celld().items():
        cell.set_edgecolor("#dddddd")
        if r == 0: cell.set_facecolor(C1); cell.get_text().set_color("white"); cell.get_text().set_weight("bold")
        elif c == 1:
            val = rows[r - 1][1]
            cell.set_facecolor({"yes": "#dff0d8", "partial": "#fcf3d6", "NO": "#f6d6d6"}[val])
    fig.text(0.04, 0.05, "Scales are derived from this dump and not verified against the instrument cluster. "
             "Speed/rpm may deviate by ~10 %.", fontsize=8, color=CG)
    pdf.savefig(fig); plt.close(fig)

    d = pdf.infodict(); d["Title"] = "Mazda CMU trip overview"; d["Author"] = "mzd-toolkit"

print(f"drive {DRIVE_FROM:.0f}-{DRIVE_TO:.0f}s gps span", t_of(gpsu[0][0]), t_of(gpsu[-1][0]), "rpm0-time", (rg<100).sum()*0.5)
print(f"OK {OUT}  dur={DUR/60:.1f}min  dist={dist_km:.2f}km gps={gps_km:.2f}km  vmax={v.max():.1f}  "
      f"fuelpulses={fuel_pulses}  gears={ {disp(k): round(x/60, 2) for k, x in gear_time.items()} }")
print("ratio hist (moving):", np.histogram(ratio[~np.isnan(ratio)], bins=[0, 18, 22.5, 27.5, 34, 45, 70, 140, 999])[0])
