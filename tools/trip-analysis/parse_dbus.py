#!/usr/bin/env python3
"""parse_dbus.py - parse a raw dbus-monitor capture from the Mazda CMU into
events and per-signal statistics, optionally writing a CSV.

Usage:
    python3 parse_dbus.py <dump.raw> [events.csv]

Input format: standard `dbus-monitor --address=...` output. Any line that
does not start with a space is a message header (signal / method call /
method return / error); the indented lines after it are the argument values.

Output: a table of numeric signals (count, min, max, mean, last) on stdout,
and optionally a CSV with columns: interface, member, kind, type, value,
serial.
"""
import csv
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
    if vtype in NUM_TYPES:
        return int(raw)
    return raw


def parse_raw(path):
    """Parse a raw dbus-monitor file -> list of dicts.

    Each event: {line, kind, interface, member, serial, values:[...]}
    Only the first value of each message is kept for statistics; all values
    are kept in `values` for method returns (e.g. GetPosition).
    """
    events = []
    cur = None
    with open(path, errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip('\n')
            if not line.startswith(' '):
                if cur is not None and cur['values']:
                    events.append(cur)
                cur = None
                m = HDR_RE.match(line)
                if not m:
                    continue
                sm = SERIAL_RE.search(line)
                cur = {
                    'line': lineno,
                    'kind': m.group(1),
                    'interface': m.group(2) or '',
                    'member': m.group(3) or '',
                    'serial': int(sm.group(1)) if sm else 0,
                    'values': [],
                }
            elif cur is not None:
                vm = VALUE_RE.match(line)
                if vm:
                    try:
                        cur['values'].append(_coerce(vm.group(1), vm.group(2)))
                    except ValueError:
                        cur['values'].append(vm.group(2).strip())
    if cur is not None and cur['values']:
        events.append(cur)
    return events


def signal_values(events, interface, member):
    """Return [(line, value)] for one signal, numeric first values only."""
    out = []
    for e in events:
        if (e['kind'] == 'signal' and e['interface'] == interface
                and e['member'] == member and e['values']
                and isinstance(e['values'][0], (int, float))):
            out.append((e['line'], e['values'][0]))
    return out


def stats(events):
    """Per-signal numeric statistics."""
    by_member = defaultdict(list)
    for e in events:
        if e['values'] and isinstance(e['values'][0], (int, float)) \
                and not isinstance(e['values'][0], bool):
            by_member['%s.%s' % (e['interface'], e['member'])].append(
                e['values'][0])
    return by_member


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    path = argv[1]
    out_csv = argv[2] if len(argv) > 2 else None
    if not os.path.exists(path):
        sys.stderr.write('error: no such file: %s\n' % path)
        return 1

    events = parse_raw(path)
    print('parsed %s: %d messages with values' % (path, len(events)))

    by_kind = defaultdict(int)
    by_iface = defaultdict(int)
    for e in events:
        by_kind[e['kind']] += 1
        if e['interface']:
            by_iface[e['interface']] += 1
    print('\nby message kind:')
    for k, n in sorted(by_kind.items(), key=lambda x: -x[1]):
        print('  %-14s %6d' % (k, n))
    print('\nby interface (top 15):')
    for k, n in sorted(by_iface.items(), key=lambda x: -x[1])[:15]:
        print('  %-40s %6d' % (k, n))

    st = stats(events)
    print('\nnumeric signals (%d members):' % len(st))
    print('%-58s %6s %12s %12s %12s %12s' %
          ('signal', 'n', 'min', 'max', 'mean', 'last'))
    print('-' * 116)
    for name in sorted(st):
        vals = st[name]
        if len(vals) < 2:
            continue
        print('%-58s %6d %12.2f %12.2f %12.2f %12.2f' %
              (name, len(vals), min(vals), max(vals),
               sum(vals) / len(vals), vals[-1]))

    if out_csv:
        with open(out_csv, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['line', 'kind', 'interface', 'member', 'serial',
                        'value'])
            for e in events:
                v = e['values'][0] if e['values'] else ''
                w.writerow([e['line'], e['kind'], e['interface'],
                            e['member'], e['serial'], v])
        print('\nCSV written: %s (%d rows)' % (out_csv, len(events)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
