#!/usr/bin/env python3
"""analyze_trip.py - text analysis of a raw dbus-monitor capture from the
Mazda CMU: statistics, ASCII charts and a trip summary.

Usage:
    python3 analyze_trip.py <dump.raw>

CORRECTED scale factors (2026-11-17 review; an earlier analysis used wrong
scales - see docs/VEHICLE-DATA-DBUS.md):

    bcm.CarSpeedResp        (v - 2500) * 4 / 100   = km/h   (2500 = standstill)
    vdt.Veh_V_ActlEng       v / 100                = km/h   (only while driving)
    vdt.EngAout_N_Actl      v * 2                  = rpm    (estimated)
    vdt.VehLong_A_Actl      (v - 4000) / 100       = m/s^2
    vdt.Lateral_Acceleration (v - 4000) / 100      = m/s^2
    vdt.SteWhlComp_An_Est   (v - 16384) / 128      = degrees
    vdt.ApedPos_Pc_ActlArb  v / 10                 = % throttle
    vdt.GlobalRealTime      unit = 0.1 s           (NOT seconds, NOT unix)

Time axis: linear interpolation on line number between `com.jci.time`
GetDatetime method returns (unix epoch). Do not use GlobalRealTime as
seconds.
"""
import os
import re
import sys
from collections import defaultdict

HDR_RE = re.compile(
    r'^(signal|method call|method return|error)\b.*?'
    r'(?:interface=([^;]+); member=([A-Za-z_0-9]+))?\s*$'
)
SERIAL_RE = re.compile(r'serial=(\d+)')
VALUE_RE = re.compile(
    r'^\s+(uint16|uint32|int16|int32|int64|uint64|byte|boolean|double|string)'
    r'\s+(.+)$'
)
NUM_TYPES = ('uint16', 'uint32', 'int16', 'int32', 'int64', 'uint64', 'byte')


def _coerce(vtype, raw):
    raw = raw.strip()
    if vtype == 'boolean':
        return 1 if raw == 'true' else 0
    if vtype == 'double':
        return float(raw)
    if vtype == 'string':
        return raw.strip('"')
    return int(raw)


def parse_raw(path):
    """Parse raw dbus-monitor output -> (events, ts_anchors, gps_points).

    events:     list of dicts (line, kind, interface, member, serial, values)
    ts_anchors: list of (line, unix_epoch) from GetDatetime method returns
    gps_points: list of (line, lat, lon) from lds.data GetPosition returns
    """
    events = []
    ts_anchors = []
    gps_points = []
    cur = None
    with open(path, errors='replace') as f:
        lines = f.read().split('\n')
    for i, line in enumerate(lines):
        if not line.startswith(' '):
            if cur is not None and cur['values']:
                events.append(cur)
            cur = None
            m = HDR_RE.match(line)
            if not m:
                continue
            sm = SERIAL_RE.search(line)
            cur = {'line': i, 'kind': m.group(1), 'interface': m.group(2) or '',
                   'member': m.group(3) or '',
                   'serial': int(sm.group(1)) if sm else 0, 'values': []}
            # method return heuristics for anchors / GPS
            if m.group(1) == 'method return' and i + 4 < len(lines):
                a = lines[i + 1].split()
                b = lines[i + 2].split()
                if len(a) >= 2 and a[0] == 'uint32' and a[1].isdigit() \
                        and 1500000000 < int(a[1]) < 2000000000:
                    ts_anchors.append((i, int(a[1])))
                if len(a) >= 1 and a[0] == 'int32' and len(b) >= 1 \
                        and b[0] == 'uint64' \
                        and lines[i + 3].strip().startswith('double'):
                    try:
                        lat = float(lines[i + 3].split()[1])
                        lon = float(lines[i + 4].split()[1])
                        gps_points.append((i, lat, lon))
                    except (ValueError, IndexError):
                        pass
        elif cur is not None:
            vm = VALUE_RE.match(line)
            if vm:
                try:
                    cur['values'].append(_coerce(vm.group(1), vm.group(2)))
                except ValueError:
                    cur['values'].append(vm.group(2).strip())
    if cur is not None and cur['values']:
        events.append(cur)
    return events, ts_anchors, gps_points


def make_time_axis(ts_anchors):
    """Return t(line) -> seconds since first anchor, via linear interpolation."""
    if not ts_anchors:
        return None, 0.0
    xs = [a[0] for a in ts_anchors]
    ys = [a[1] for a in ts_anchors]
    t0 = ys[0]

    def t_of(line):
        if line <= xs[0]:
            return (line - xs[0]) * (ys[1] - ys[0]) / max(xs[1] - xs[0], 1) \
                if len(xs) > 1 else 0.0
        if line >= xs[-1]:
            if len(xs) > 1:
                return ys[-1] - t0 + (line - xs[-1]) * \
                    (ys[-1] - ys[-2]) / max(xs[-1] - xs[-2], 1)
            return 0.0
        # binary search
        lo, hi = 0, len(xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= line:
                lo = mid
            else:
                hi = mid
        frac = (line - xs[lo]) / max(xs[hi] - xs[lo], 1)
        return ys[lo] - t0 + frac * (ys[hi] - ys[lo])

    return t_of, ys[-1] - ys[0]


def series(events, t_of, interface, member):
    """[(t, value)] for one signal, numeric first value."""
    out = []
    for e in events:
        if e['kind'] == 'signal' and e['interface'] == interface \
                and e['member'] == member and e['values'] \
                and isinstance(e['values'][0], (int, float)):
            out.append((t_of(e['line']), e['values'][0]))
    out.sort()
    return out


def ascii_chart(data, width=80, height=14, title='', unit='', decode=None):
    if not data:
        return
    ys = [decode(y) if decode else y for _, y in data]
    ymin, ymax = min(ys), max(ys)
    if ymax == ymin:
        ymax = ymin + 1
    step = max(1, len(data) // width)
    sampled = data[::step]
    print('\n=== %s (%s) ===' % (title, unit))
    print('  min=%.2f  max=%.2f  n=%d' % (ymin, ymax, len(data)))
    for row in range(height, -1, -1):
        yval = ymin + (ymax - ymin) * row / height
        line = '%10.2f |' % yval
        for _, y in sampled:
            yd = decode(y) if decode else y
            if abs(yd - yval) <= (ymax - ymin) / height / 2:
                line += '*'
            else:
                line += ' '
        print(line)
    print(' ' * 12 + '+' + '-' * min(width, len(sampled)))


def haversine_km(a, b):
    import math
    r = 6371.0
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) \
        * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    path = argv[1]
    if not os.path.exists(path):
        sys.stderr.write('error: no such file: %s\n' % path)
        return 1

    print('=== Mazda CMU trip analysis: %s ===' % os.path.basename(path))
    events, ts_anchors, gps = parse_raw(path)
    print('messages with values: %d' % len(events))
    if ts_anchors:
        import datetime
        t0 = datetime.datetime.utcfromtimestamp(ts_anchors[0][1])
        t1 = datetime.datetime.utcfromtimestamp(ts_anchors[-1][1])
        print('time anchors (GetDatetime): %d, %s .. %s UTC (%.1f min)' %
              (len(ts_anchors), t0.strftime('%H:%M:%S'),
               t1.strftime('%H:%M:%S'), (ts_anchors[-1][1] - ts_anchors[0][1]) / 60.0))
    else:
        print('WARNING: no GetDatetime anchors found; times fall back to line numbers')
    t_of, dur = make_time_axis(ts_anchors)
    if t_of is None:
        t_of = lambda line: float(line)
        dur = 0.0

    by_iface = defaultdict(int)
    for e in events:
        if e['interface']:
            by_iface[e['interface']] += 1
    print('\n=== events per interface ===')
    for iface, cnt in sorted(by_iface.items(), key=lambda x: -x[1]):
        print('  %-40s %6d' % (iface, cnt))

    print('\n' + '=' * 80)
    print(' TRIP DATA (decoded, corrected scales)')
    print('=' * 80)

    # speed: bcm.CarSpeedResp covers the whole capture
    spd = series(events, t_of, 'com.jci.vbs.bcm', 'CarSpeedResp')
    spd_kmh = [(t, (v - 2500) * 4 / 100.0) for t, v in spd]
    spd_kmh = [(t, max(v, 0.0)) for t, v in spd_kmh]
    if spd_kmh:
        vals = [v for _, v in spd_kmh]
        moving = sum(1 for v in vals if v > 0.5)
        dist = sum(vals) * (spd_kmh[1][0] - spd_kmh[0][0] if len(spd_kmh) > 1 else 0) / 3600.0
        print('\nSPEED (bcm.CarSpeedResp): min=%.1f max=%.1f avg=%.1f km/h (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))
        print('  moving: %d/%d samples (%.0f%%), distance ~%.2f km (integrated)' %
              (moving, len(vals), 100.0 * moving / len(vals), dist))
        ascii_chart(spd_kmh, title='Speed', unit='km/h', decode=lambda p: p)

    veh_v = series(events, t_of, 'com.jci.vbs.vdt', 'Veh_V_ActlEng')
    if veh_v:
        vals = [v / 100.0 for _, v in veh_v]
        print('\nSPEED (vdt.Veh_V_ActlEng, only while driving): '
              'min=%.1f max=%.1f avg=%.1f km/h (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))

    rpm = series(events, t_of, 'com.jci.vbs.vdt', 'EngAout_N_Actl')
    if rpm:
        vals = [v * 2 for _, v in rpm]
        print('\nRPM (vdt.EngAout_N_Actl x2, estimated): min=%.0f max=%.0f '
              'avg=%.0f rpm (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))
        ascii_chart(rpm, title='Engine rpm', unit='rpm', decode=lambda p: p * 2)

    thr = series(events, t_of, 'com.jci.vbs.vdt', 'ApedPos_Pc_ActlArb')
    if thr:
        vals = [v / 10.0 for _, v in thr]
        print('\nTHROTTLE (vdt.ApedPos_Pc_ActlArb /10): min=%.1f max=%.1f '
              'avg=%.1f %% (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))
        ascii_chart(thr, title='Throttle pedal', unit='%', decode=lambda p: p / 10.0)

    lo = series(events, t_of, 'com.jci.vbs.vdt', 'VehLong_A_Actl')
    if lo:
        vals = [(v - 4000) / 100.0 for _, v in lo]
        print('\nLONGITUDINAL ACCEL: min=%.2f max=%.2f avg=%.2f m/s^2 (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))
        ascii_chart(lo, title='Longitudinal acceleration', unit='m/s^2',
                    decode=lambda p: (p - 4000) / 100.0)

    la = series(events, t_of, 'com.jci.vbs.vdt', 'Lateral_Acceleration')
    if la:
        vals = [(v - 4000) / 100.0 for _, v in la]
        print('\nLATERAL ACCEL: min=%.2f max=%.2f avg=%.2f m/s^2 (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))

    st = series(events, t_of, 'com.jci.vbs.vdt', 'SteWhlComp_An_Est')
    if st:
        vals = [(v - 16384) / 128.0 for _, v in st]
        print('\nSTEERING ANGLE: min=%.1f max=%.1f avg=%.1f deg (n=%d)' %
              (min(vals), max(vals), sum(vals) / len(vals), len(vals)))
        ascii_chart(st, title='Steering angle', unit='deg',
                    decode=lambda p: (p - 16384) / 128.0)

    fu = series(events, t_of, 'com.jci.vbs.vdt', 'FuelPulse')
    if fu:
        pulses = sum((b - a) % 256 for (_, a), (_, b) in zip(fu[:-1], fu[1:]))
        print('\nFUEL PULSES (vdt.FuelPulse, byte wrap): %d pulses over %d '
              'samples (no liter calibration)' % (pulses, len(fu)))

    odo = series(events, t_of, 'com.jci.vbs.vwm', 'Total_Distance')
    if odo:
        vals = [v for _, v in odo]
        print('\nODOMETER (vwm.Total_Distance, unit unconfirmed): '
              '%.0f .. %.0f (n=%d)' % (min(vals), max(vals), len(vals)))

    br = series(events, t_of, 'com.jci.vbs.bcm', 'BrakePedalDepressedStatus')
    if br:
        pressed = sum(1 for _, v in br if v >= 1)
        print('\nBRAKE: pressed %d/%d times' % (pressed, len(br)))

    eng = series(events, t_of, 'com.jci.vbs.eem', 'SISS_EngineState')
    if eng:
        seq = []
        for _, v in eng:
            if not seq or seq[-1] != v:
                seq.append(v)
        print('\nENGINE STATE (eem.SISS_EngineState) transitions: %s' % seq)

    grt = series(events, t_of, 'com.jci.vbs.vdt', 'GlobalRealTime')
    if len(grt) >= 2:
        span = grt[-1][1] - grt[0][1]
        print('\nGlobalRealTime span: %d units = %.1f s (unit = 0.1 s, '
              'NOT seconds)' % (span, span / 10.0))

    if gps:
        uniq = []
        for g in gps:
            if not uniq or (g[1], g[2]) != uniq[-1][1:]:
                uniq.append(g)
        gps_km = sum(haversine_km(a[1:], b[1:]) for a, b in zip(uniq[:-1], uniq[1:]))
        print('GPS: %d unique points, %.2f km (haversine)' % (len(uniq), gps_km))
        if spd_kmh:
            print('  check: integrated speed distance vs GPS should be '
                  'within ~15 %%')

    print('\n' + '=' * 80)
    print(' SUMMARY')
    print('=' * 80)
    if spd_kmh:
        vals = [v for _, v in spd_kmh]
        print('  speed:     %.1f - %.1f km/h (avg %.1f)' %
              (min(vals), max(vals), sum(vals) / len(vals)))
    if rpm:
        vals = [v * 2 for _, v in rpm]
        print('  rpm:       %.0f - %.0f (avg %.0f, x2 estimated)' %
              (min(vals), max(vals), sum(vals) / len(vals)))
    if thr:
        vals = [v / 10.0 for _, v in thr]
        print('  throttle:  %.1f - %.1f %%' % (min(vals), max(vals)))
    if lo:
        vals = [(v - 4000) / 100.0 for _, v in lo]
        print('  long acc:  %.2f - %.2f m/s^2' % (min(vals), max(vals)))
    if la:
        vals = [(v - 4000) / 100.0 for _, v in la]
        print('  lat acc:   %.2f - %.2f m/s^2' % (min(vals), max(vals)))
    if st:
        vals = [(v - 16384) / 128.0 for _, v in st]
        print('  steering:  %.1f - %.1f deg' % (min(vals), max(vals)))
    if dur:
        print('  duration:  %.1f min (from GetDatetime anchors)' % (dur / 60.0))
    print('\nNote: gear position is not on D-Bus (CAN 0x0FD only). Estimate it')
    print('from rpm/speed ratios; see make_overview_pdf.py.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
