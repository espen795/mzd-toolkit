#!/usr/bin/env python3
"""make_overview_pdf.py - graphical PDF overview of a raw dbus-monitor capture
from the Mazda CMU.

Usage:
    python3 make_overview_pdf.py <dump.raw> <overview.pdf>

Do NOT run with `python3 -I`: numpy/matplotlib live in the user site-packages.

Time axis: linear interpolation on line number between `com.jci.time`
GetDatetime method returns (unix epoch).

CORRECTED scales (2026-11-17 review; an earlier analysis had wrong scales):
    vdt.Veh_V_ActlEng        v / 100              = km/h (only while driving)
    bcm.CarSpeedResp         (v - 2500) * 4 / 100 = km/h (2500 = standstill)
    vdt.EngAout_N_Actl       v * 2                = rpm (estimated)
    vdt.VehLong_A_Actl       (v - 4000) / 100     = m/s^2
    vdt.Lateral_Acceleration (v - 4000) / 100     = m/s^2
    vdt.SteWhlComp_An_Est    (v - 16384) / 128    = degrees
    vdt.ApedPos_Pc_ActlArb   v / 10               = %
    vdt.GlobalRealTime       unit = 0.1 s         (NOT seconds)

The script prints a control line at the end:
    OK <file> dur=... dist=... gps=... ...
Compare `dist` (integrated speed) with `gps`: they should agree within ~15 %,
otherwise a scale factor is wrong.

PRIVACY: the route page contains real GPS coordinates. Remove page 5 (or
regenerate without it) before sharing the PDF outside your own machine.
"""
import math
import os
import re
import sys
from collections import Counter, defaultdict

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

SRC = sys.argv[1] if len(sys.argv) > 1 else 'dump.raw'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'overview.pdf'

HDR_RE = re.compile(
    r'^(signal|method call|method return|error)\b.*?'
    r'(?:interface=([^;]+); member=([A-Za-z_0-9]+))?\s*$'
)
SERIAL_RE = re.compile(r'serial=(\d+)')
VALUE_TYPES = ('uint16', 'uint32', 'byte', 'int32', 'int16', 'boolean',
               'double', 'string', 'uint64', 'int64')

with open(SRC, errors='replace') as f:
    lines = f.read().split('\n')

# ---------- parse ----------
events = []       # [line, iface, member, kind, [values]]
ts_anchor = []    # (line, epoch)
gps = []          # (line, lat, lon)
cur = None
for i, l in enumerate(lines):
    if not l.startswith(' '):
        if cur:
            events.append(cur)
        cur = None
        m = HDR_RE.match(l)
        if not m:
            continue
        kind, iface, member = m.group(1), m.group(2) or '', m.group(3) or ''
        cur = [i, iface, member, kind, []]
        if kind == 'method return' and i + 4 < len(lines):
            a = lines[i + 1].split()
            b = lines[i + 2].split()
            if len(a) >= 2 and a[0] == 'uint32' and a[1].isdigit() \
                    and 1500000000 < int(a[1]) < 2000000000:
                ts_anchor.append((i, int(a[1])))
            if a and a[0] == 'int32' and b and b[0] == 'uint64' \
                    and lines[i + 3].strip().startswith('double'):
                try:
                    gps.append((i, float(lines[i + 3].split()[1]),
                                float(lines[i + 4].split()[1])))
                except (ValueError, IndexError):
                    pass
    elif cur is not None:
        p = l.split(None, 1)
        if len(p) == 2 and p[0] in VALUE_TYPES:
            v = p[1]
            if p[0] == 'boolean':
                v = 1 if v.strip() == 'true' else 0
            elif p[0] == 'double':
                try:
                    v = float(v)
                except ValueError:
                    pass
            elif p[0] == 'string':
                v = v.strip('"')
            else:
                try:
                    v = int(v)
                except ValueError:
                    pass
            cur[4].append(v)
if cur:
    events.append(cur)

if not ts_anchor:
    sys.exit('error: no GetDatetime time anchors found in %s' % SRC)

ta = np.array(ts_anchor, dtype=float)


def t_of(line):
    """seconds since first anchor"""
    return float(np.interp(line, ta[:, 0], ta[:, 1]) - ta[0, 1])


import datetime
T0 = datetime.datetime.utcfromtimestamp(ta[0, 1])
T1 = datetime.datetime.utcfromtimestamp(ta[-1, 1])
DUR = ta[-1, 1] - ta[0, 1]


def series(iface, member):
    xs, ys = [], []
    for ln, ifc, mem, kind, vals in events:
        if ifc == iface and mem == member and kind == 'signal' and vals \
                and isinstance(vals[0], (int, float)):
            xs.append(t_of(ln))
            ys.append(vals[0])
    return np.array(xs), np.array(ys, dtype=float)


tv, v = series('com.jci.vbs.vdt', 'Veh_V_ActlEng'); v = v / 100.0
tr, rpm = series('com.jci.vbs.vdt', 'EngAout_N_Actl'); rpm = rpm * 2
tlo, alo = series('com.jci.vbs.vdt', 'VehLong_A_Actl'); alo = (alo - 4000) / 100.0
tla, ala = series('com.jci.vbs.vdt', 'Lateral_Acceleration'); ala = (ala - 4000) / 100.0
tst, st = series('com.jci.vbs.vdt', 'SteWhlComp_An_Est'); st = (st - 16384) / 128.0
tth, th = series('com.jci.vbs.vdt', 'ApedPos_Pc_ActlArb'); th = th / 10.0
tfu, fu = series('com.jci.vbs.vdt', 'FuelPulse')
tbc, bcm = series('com.jci.vbs.bcm', 'CarSpeedResp')
# bcm.CarSpeedResp covers the whole capture (Veh_V_ActlEng only while driving)
vb = np.clip((bcm - 2500) * 4 / 100.0, 0, None)
grid = np.arange(0, ta[-1, 1] - ta[0, 1], 0.5)


def zoh(tx, y):
    i = np.searchsorted(tx, grid, side='right') - 1
    return np.where(i >= 0, y[np.clip(i, 0, None)], 0)


vg, rg = zoh(tbc, vb), zoh(tr, rpm)

# derived quantities
dist_km = float(vg.sum()) * 0.5 / 3600.0
fuel_pulses = int(sum((b - a) % 256 for a, b in zip(fu[:-1], fu[1:]))) \
    if len(fu) > 1 else 0


def hav(a, b):
    r = 6371.0
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) \
        * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


gpsu = []
for g in gps:
    if not gpsu or (g[1], g[2]) != gpsu[-1][1:]:
        gpsu.append(g)
gps_km = float(sum(hav(a[1:], b[1:]) for a, b in zip(gpsu[:-1], gpsu[1:]))) \
    if len(gpsu) > 1 else 0.0

# gear estimate: rpm / speed at the Veh_V_ActlEng timestamps
rpm_at_v = np.interp(tv, tr, rpm) if len(tv) and len(tr) else np.array([])
moving = v > 5
ratio = np.where(moving, rpm_at_v / np.maximum(v, 0.1), np.nan)
# illustrative boundaries (rpm per km/h); calibrate with a dedicated drive
GEARS = [('1', 95, 200), ('2', 48, 75), ('3', 33, 47.9), ('4?', 25, 32.9)]


def gear_of(r):
    if np.isnan(r):
        return 'stil/<5'
    for n, lo, hi in GEARS:
        if lo <= r <= hi:
            return n
    return 'overgang'


def gear_full(vv, rr):
    if vv <= 5:
        return 'stil/<5'
    if rr < 760 and vv > 9:
        return 'coast'
    return gear_of(rr / vv)


gears = [gear_full(a, b) for a, b in zip(v, rpm_at_v)] if len(v) else []
gear_time = defaultdict(float)
for vv, rr in zip(vg, rg):
    gear_time[gear_full(vv, rr)] += 0.5
drive_t = grid[vg > 0.5]
DRIVE_FROM, DRIVE_TO = (float(drive_t[0]), float(drive_t[-1])) if len(drive_t) else (0.0, 0.0)

# signal inventory
svc = Counter()
for e in events:
    if e[1] and e[3] == 'signal':
        svc[e[1].replace('com.jci.', '')] += 1

# warnings / lamps timeline
warn_members = ['Camera_high_temperature', 'ColdStrtDisable_Telltale',
                'Light_Types', 'LampActivationNotify', 'HECIlluminationStatus',
                'SISS_WarningLamp_G', 'SISS_WarningLamp_R', 'SISSStatus',
                'SISS_EngineState', 'iStpReady_Rq', 'BrakePedalDepressedStatus',
                'RVM_state', 'SchMnt_Oil_B_Rq', 'SchMnt_Tyre_B_Rq',
                'WshrLvl_D_Actl', 'VehSpeedFlag']
warn = {m: [] for m in warn_members}
for ln, ifc, mem, kind, vals in events:
    if mem in warn and vals and kind == 'signal':
        warn[mem].append((t_of(ln), vals[0]))

# ---------- layout ----------
C1, C2, C3, CG = '#9c1c1c', '#1f4e79', '#e08a00', '#666666'
plt.rcParams.update({'font.size': 9, 'axes.spines.top': False,
                     'axes.spines.right': False, 'axes.titleweight': 'bold',
                     'axes.titlesize': 11})
A4 = (11.69, 8.27)


def header(fig, title, sub=''):
    fig.text(0.04, 0.955, title, fontsize=17, weight='bold', color=C1)
    if sub:
        fig.text(0.04, 0.925, sub, fontsize=9.5, color=CG)
    fig.text(0.96, 0.02, 'CMU D-Bus capture %s' % T0.strftime('%d-%m-%Y'),
             ha='right', fontsize=7, color=CG)


def tmin(x):
    return x / 60.0


with PdfPages(OUT) as pdf:
    # ===== 1. summary =====
    fig = plt.figure(figsize=A4)
    header(fig, 'Trip overview - what the CMU tells us',
           'Source: %s  |  %s - %s (CMU clock)  |  %d D-Bus messages' %
           (os.path.basename(SRC), T0.strftime('%H:%M:%S'),
            T1.strftime('%H:%M:%S'), len(events)))
    kpis = [('logged', '%.1f min' % (DUR / 60.0)),
            ('distance (speed)', '%.2f km' % dist_km),
            ('distance (GPS)', '%.2f km' % gps_km),
            ('max speed', '%.0f km/h' % (vg.max() if len(vg) else 0)),
            ('driving', '%.1f min' % ((DRIVE_TO - DRIVE_FROM) / 60.0)),
            ('max rpm', '~%.0f rpm' % (rpm.max() if len(rpm) else 0)),
            ('max G long', '%.2f g' % (np.abs(alo).max() / 9.81 if len(alo) else 0)),
            ('max G lat', '%.2f g' % (np.abs(ala).max() / 9.81 if len(ala) else 0)),
            ('standstill', '%.0f %%' % (100 * gear_time['stil/<5'] / DUR if DUR else 0)),
            ('fuel pulses', '%d' % fuel_pulses)]
    for k, (lab, val) in enumerate(kpis):
        x = 0.04 + (k % 5) * 0.19
        y = 0.78 - (k // 5) * 0.13
        fig.patches.append(plt.Rectangle((x, y), 0.175, 0.105,
                                         transform=fig.transFigure,
                                         color='#f3eeee', zorder=0))
        fig.text(x + 0.012, y + 0.065, val, fontsize=16, weight='bold', color=C1)
        fig.text(x + 0.012, y + 0.022, lab, fontsize=8.5, color=CG)
    ax = fig.add_axes([0.14, 0.08, 0.33, 0.50])
    names, cnts = zip(*svc.most_common(10)) if svc else ([], [])
    if names:
        ax.barh(list(names)[::-1], list(cnts)[::-1], color=C2)
        ax.set_title('Signals per CMU service')
        for i_, c in enumerate(list(cnts)[::-1]):
            ax.text(c, i_, ' %d' % c, va='center', fontsize=7.5)
    fig.text(0.53, 0.56, 'How to read this', fontsize=11, weight='bold')
    notes = [
        '- Scales are the corrected 2026-11-17 values:',
        '   CarSpeedResp = (v-2500)*4/100 km/h (2500 = standstill),',
        '   rpm = raw x2 (estimated), GlobalRealTime unit = 0.1 s.',
        '- Gear position is NOT on D-Bus (CAN 0x0FD -> cluster only).',
        '   It is estimated here from rpm/speed; calibrate with a',
        '   dedicated 1..6 shift drive before trusting the labels.',
        '- Camera_high_temperature toggles continuously: heartbeat,',
        '   not a real warning.',
        '- Not visible via D-Bus: turn signals, doors, wipers,',
        '   headlight switch (CAN 0x09A) - need an OBD CAN adapter.',
        '- PRIVACY: page 5 contains the real GPS route.',
    ]
    for k, s in enumerate(notes):
        fig.text(0.53, 0.52 - k * 0.033, s, fontsize=9.5)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== 2. timeline =====
    fig, axs = plt.subplots(4, 1, figsize=A4, sharex=True,
                            gridspec_kw={'hspace': 0.25})
    fig.subplots_adjust(top=0.88, bottom=0.07, left=0.07, right=0.97)
    header(fig, 'Trip timeline',
           'Speed, rpm, throttle and estimated gear over time (minutes from start)')
    axs[0].plot(tmin(grid), vg, color=C1, lw=1)
    axs[0].fill_between(tmin(grid), vg, color=C1, alpha=.12)
    axs[0].set_ylabel('km/h')
    axs[0].set_title('Speed (bcm.CarSpeedResp)', loc='left')
    axs[1].plot(tmin(tr), rpm, color=C2, lw=.8)
    axs[1].set_ylabel('rpm')
    axs[1].set_title('Engine rpm (estimated x2)', loc='left')
    axs[2].plot(tmin(tth), th, color=C3, lw=.8, drawstyle='steps-post')
    axs[2].set_ylabel('%')
    axs[2].set_title('Throttle pedal', loc='left')
    gmap = {'stil/<5': 0, 'coast': 0.5, '1': 1, '2': 2, '3': 3, '4?': 4}
    gy = np.array([gmap.get(g, np.nan) for g in gears], dtype=float)
    axs[3].scatter(tmin(tv), gy, s=4, color=C1)
    axs[3].set_yticks([0, .5, 1, 2, 3, 4], ['stil', 'coast', '1', '2', '3', '4'])
    axs[3].set_title('Estimated gear (from rpm/speed)', loc='left')
    axs[3].set_xlabel('minutes')
    for a in axs:
        a.grid(alpha=.25)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== 3. gears =====
    fig = plt.figure(figsize=A4)
    header(fig, 'Shift behavior (estimated)',
           'The CMU does not receive the gear position; it is derived from rpm/speed')
    ax = fig.add_axes([0.06, 0.10, 0.50, 0.75])
    cols = {'1': '#c0392b', '2': C3, '3': C2, '4?': '#2e8b57', 'coast': '#8fbc8f',
            'overgang': '#bbbbbb'}
    for g, c in cols.items():
        sel = np.array([x == g for x in gears])
        if sel.any():
            ax.scatter(v[sel], rpm_at_v[sel], s=7, color=c, label=g, alpha=.75)
    xs = np.linspace(0, max(v.max(), 1) + 3, 50)
    for n, lo, hi in GEARS:
        mid = (lo + hi) / 2
        ax.plot(xs, xs * mid, ls='--', lw=.7, color=CG)
        xe = min(max(vg.max(), 1) + 1, (rpm.max() * 1.1 / mid) if mid else 1)
        ax.text(xe, xe * mid, ' %s' % n, fontsize=8, color=CG)
    ax.set_xlim(0, max(vg.max(), 1) + 4)
    ax.set_ylim(0, max(rpm.max() * 1.15, 1))
    ax.set_xlabel('speed km/h')
    ax.set_ylabel('rpm (estimated)')
    ax.legend(frameon=False)
    ax.set_title('rpm vs speed - each line = one gear')
    ax.grid(alpha=.25)
    ax2 = fig.add_axes([0.64, 0.50, 0.32, 0.33])
    order = [o for o in ['stil/<5', '1', '2', '3', '4?', 'coast', 'overgang']
             if gear_time.get(o, 0) > 0]
    vals = [gear_time[o] / 60 for o in order]
    ax2.bar(order, vals, color=[CG] + [cols.get(o, CG) for o in order[1:]])
    ax2.set_ylabel('minutes')
    ax2.set_title('Time per gear')
    ax2.tick_params(axis='x', labelrotation=30, labelsize=8)
    for i_, val in enumerate(vals):
        ax2.text(i_, val, '%.1f' % val, ha='center', va='bottom', fontsize=8)
    txt = ['How to read this?', '',
           'A manual gearbox has a fixed rpm/speed ratio',
           'per gear, so the points fall on straight lines.',
           "'coast' = driving at idle rpm (clutch in /",
           "neutral); 'overgang' = shifting.", '',
           'The grouping is an estimate. A calibration drive',
           '(deliberately shift 1..6) makes it exact.']
    for k, s in enumerate(txt):
        fig.text(0.64, 0.42 - k * 0.028, s, fontsize=9,
                 weight='bold' if k == 0 else None)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== 4. dynamics =====
    fig = plt.figure(figsize=A4)
    header(fig, 'Driving dynamics', 'G forces, steering angle and throttle use')
    ax = fig.add_axes([0.06, 0.10, 0.36, 0.72])
    lat_on_long = np.interp(tlo, tla, ala) if len(tlo) and len(tla) \
        else np.zeros_like(alo)
    ax.scatter(lat_on_long / 9.81, alo / 9.81, s=4, color=C2, alpha=.35)
    for r in (0.1, 0.2, 0.3, 0.4):
        ax.add_patch(plt.Circle((0, 0), r, fill=False, ls=':', color=CG, lw=.7))
        ax.text(r * .71, r * .71, '%sg' % r, fontsize=7, color=CG)
    ax.set_xlim(-.5, .5)
    ax.set_ylim(-.5, .5)
    ax.set_aspect('equal')
    ax.axhline(0, color=CG, lw=.5)
    ax.axvline(0, color=CG, lw=.5)
    ax.set_xlabel('lateral (g)   left <-> right')
    ax.set_ylabel('braking <-> accelerating (g)')
    ax.set_title('G-G diagram')
    ax = fig.add_axes([0.52, 0.56, 0.44, 0.26])
    if len(st):
        ax.hist(st, bins=np.arange(-60, 61, 5), color=C3)
    ax.set_title('Steering angle (degrees)')
    ax.set_xlabel('degrees')
    ax = fig.add_axes([0.52, 0.12, 0.44, 0.30])
    if len(th):
        ax.hist(th, bins=np.arange(0, max(th.max(), 10) + 2.5, 2.5), color=C1)
    ax.set_title('Throttle (%)')
    ax.set_xlabel('% pressed')
    if len(th):
        ax.text(0.98, 0.9, 'max %.0f %%  |  avg %.1f %%' % (th.max(), th.mean()),
                transform=ax.transAxes, ha='right', fontsize=8.5)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== 5. route + warnings =====
    fig = plt.figure(figsize=A4)
    header(fig, 'Route and warnings',
           'GPS from lds.data GetPosition; warnings/lamps from VWM and EEM. '
           'PRIVACY: this page contains real coordinates.')
    ax = fig.add_axes([0.05, 0.10, 0.38, 0.74])
    if gpsu:
        la_ = np.array([g[1] for g in gpsu])
        lo_ = np.array([g[2] for g in gpsu])
        sc = ax.scatter(lo_, la_, c=[t_of(g[0]) / 60 for g in gpsu],
                        cmap='viridis', s=12)
        ax.plot(lo_, la_, color=CG, lw=.6)
        ax.plot(lo_[0], la_[0], 'o', color='green', ms=9)
        ax.plot(lo_[-1], la_[-1], 's', color=C1, ms=9)
        ax.set_aspect(1 / math.cos(math.radians(la_.mean())))
        fig.colorbar(sc, ax=ax, shrink=.6, label='minute')
        ax.ticklabel_format(useOffset=False)
        ax.tick_params(labelsize=7)
    ax.set_title('Route (GPS, %d unique points, %.2f km)' % (len(gpsu), gps_km))
    ax = fig.add_axes([0.55, 0.10, 0.42, 0.74])
    shown = [m for m in warn_members if warn[m]]
    for k, m in enumerate(shown):
        pts = warn[m]
        xs_ = [tmin(p[0]) for p in pts]
        ys_ = [p[1] if isinstance(p[1], (int, float)) else 1 for p in pts]
        on = [x for x, y in zip(xs_, ys_) if y]
        off = [x for x, y in zip(xs_, ys_) if not y]
        ax.scatter(on, [k] * len(on), marker='|', s=90, color=C1)
        ax.scatter(off, [k] * len(off), marker='|', s=90, color='#bbbbbb')
        ax.text(DUR / 60 + .2, k, '%dx' % len(pts), va='center', fontsize=7,
                color=CG)
    ax.set_yticks(range(len(shown)), shown, fontsize=7.5)
    ax.set_xlabel('minutes')
    ax.set_xlim(0, DUR / 60 + 1.2)
    ax.set_title('Warnings/lamps (red = active/on)')
    ax.grid(axis='x', alpha=.25)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== 6. data inventory =====
    fig = plt.figure(figsize=A4)
    header(fig, 'What we do and don\'t get',
           'Vehicle data available via the CMU (D-Bus) vs. what a CAN adapter adds')
    rows = [
        ['Speed', 'yes', 'vdt.Veh_V_ActlEng /100; bcm.CarSpeedResp = 2500 + v/4'],
        ['RPM', 'yes', 'vdt.EngAout_N_Actl (x2, estimated)'],
        ['Throttle', 'yes', 'vdt.ApedPos_Pc_ActlArb /10 %'],
        ['G forces long/lat', 'yes', 'VehLong_A_Actl / Lateral_Acceleration (v-4000)/100 m/s^2'],
        ['Steering angle', 'yes', 'SteWhlComp_An_Est (v-16384)/128 degrees'],
        ['Fuel', 'partial', 'FuelPulse counter (no calibration to liters)'],
        ['Brake pedal', 'partial', 'bcm.BrakePedalDepressedStatus, only on change'],
        ['GPS / compass', 'yes', 'lds.data GetPosition'],
        ['Start-stop (i-Stop)', 'yes', 'eem.SISS*, iStp*'],
        ['Maintenance / washer', 'yes', 'vwm.SchMnt_*, WshrLvl_D_Actl'],
        ['Odometer', 'yes', 'vwm.Total_Distance, vdt.OdoCount'],
        ['Gear position (manual)', 'NO', 'CAN 0x0FD Warn_SilGearPos_D_Dsply - not forwarded to CMU'],
        ['Turn signals / headlights', 'NO', 'CAN 0x09A - OBD CAN adapter only'],
        ['Doors / windows / wipers', 'NO', 'OBD CAN adapter only'],
    ]
    ax = fig.add_axes([0.04, 0.08, 0.92, 0.80])
    ax.axis('off')
    tb = ax.table(cellText=rows, colLabels=['Data', 'Via CMU?', 'Source / scale'],
                  loc='upper center', colWidths=[.22, .10, .68], cellLoc='left')
    tb.auto_set_font_size(False)
    tb.set_fontsize(9)
    tb.scale(1, 1.75)
    for (r, c), cell in tb.get_celld().items():
        cell.set_edgecolor('#dddddd')
        if r == 0:
            cell.set_facecolor(C1)
            cell.get_text().set_color('white')
            cell.get_text().set_weight('bold')
        elif c == 1:
            val = rows[r - 1][1]
            cell.set_facecolor({'yes': '#dff0d8', 'partial': '#fcf3d6',
                                'NO': '#f6d6d6'}[val])
    fig.text(0.04, 0.05,
             'Scales were derived from a capture and not verified against the '
             'dashboard; speed/rpm can deviate ~10 %.', fontsize=8, color=CG)
    pdf.savefig(fig)
    plt.close(fig)

    d = pdf.infodict()
    d['Title'] = 'CMU trip overview'
    d['Author'] = 'mzd-toolkit'

print('OK %s  dur=%.1fmin  dist=%.2fkm  gps=%.2fkm  vmax=%.1f  fuelpulses=%d  '
      'gears=%s' % (OUT, DUR / 60.0, dist_km, gps_km,
                    float(v.max()) if len(v) else 0, fuel_pulses,
                    {k: round(x / 60, 2) for k, x in gear_time.items()}))
if dist_km > 0 and gps_km > 0:
    dev = abs(dist_km - gps_km) / gps_km * 100
    print('speed-vs-GPS deviation: %.1f %% (should be within ~15 %%)' % dev)
