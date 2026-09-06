"""Unprivileged, dependency-free resource sampler. No process command lines collected."""
import collections
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

PROC = Path('/proc')
TICKS = os.sysconf('SC_CLK_TCK')
PAGE = os.sysconf('SC_PAGE_SIZE')


def rate(value):
    if value >= 1048576:
        return f'{value / 1048576:.1f} MB/s'
    return f'{value / 1024:.0f} KB/s'


def tcp_snapshot():
    sockets = {}
    try:
        result = subprocess.run(['ss', '-HtinpO'], capture_output=True, text=True, timeout=1)
        for line in result.stdout.splitlines():
            owner = re.search(r'\("([^"]+)",pid=(\d+),fd=(\d+)', line)
            fields = line.split()
            if not owner or len(fields) < 5:
                continue
            name, pid, fd = owner.groups()
            counters = dict(re.findall(r'(bytes_sent|bytes_received):(\d+)', line))
            # Endpoints distinguish concurrent sockets but are never emitted to the UI.
            key = (pid, fd, fields[3], fields[4])
            sockets[key] = {'pid': pid, 'name': name, 'sent': int(counters.get('bytes_sent', 0)),
                            'received': int(counters.get('bytes_received', 0))}
    except (OSError, subprocess.TimeoutExpired):
        pass
    return sockets


def snapshot():
    cpu = list(map(int, (PROC / 'stat').read_text().splitlines()[0].split()[1:9]))
    net = {}
    for line in (PROC / 'net/dev').read_text().splitlines()[2:]:
        name, values = line.split(':', 1)
        name = name.strip()
        if name == 'lo':
            continue
        fields = values.split()
        net[name] = (int(fields[0]), int(fields[8]))
    processes = {}
    io_hidden = 0
    for folder in PROC.iterdir():
        if not folder.name.isdigit():
            continue
        try:
            raw = (folder / 'stat').read_text()
            end = raw.rfind(')')
            fields = raw[end + 2:].split()
            # PID + start time avoids attributing old counters to a reused PID.
            key = folder.name + ':' + fields[19]
            entry = {'pid': int(folder.name), 'name': raw[raw.index('(') + 1:end],
                     'ticks': int(fields[11]) + int(fields[12]),
                     'rss': max(0, int(fields[21])) * PAGE, 'io': None}
            try:
                io = dict(line.split(': ') for line in (folder / 'io').read_text().splitlines())
                entry['io'] = (int(io['read_bytes']), int(io['write_bytes']))
            except (OSError, ValueError, KeyError):
                io_hidden += 1
            processes[key] = entry
        except (OSError, ValueError, IndexError):
            pass  # A process may exit between listing and reading.
    devices = {}
    for line in (PROC / 'diskstats').read_text().splitlines():
        f = line.split()
        name = f[2]
        # Whole physical devices only: exclude partitions, loop and device-mapper duplicates.
        if not re.fullmatch(r'(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|mmcblk\d+)', name):
            continue
        devices[name] = (int(f[5]) * 512, int(f[9]) * 512)
    return {'total': sum(cpu), 'idle': cpu[3] + cpu[4], 'net': net, 'tcp': tcp_snapshot(),
            'processes': processes, 'devices': devices, 'time': time.monotonic(), 'ioHidden': io_hidden}


def connection_summary():
    try:
        result = subprocess.run(['ss', '-Htunp'], capture_output=True, text=True, timeout=1)
        if result.returncode:
            return 'Connection details unavailable'
        apps = collections.Counter()
        for line in result.stdout.splitlines():
            # Count each socket once per application, even when several processes share it.
            apps.update(set(re.findall(r'\("([^"]+)",pid=', line)))
        if not apps:
            return 'No app-owned connections visible'
        return ' · '.join(f'{name}: {count}' for name, count in apps.most_common(4))
    except (OSError, subprocess.TimeoutExpired):
        return 'Connection details unavailable'


def make_data(previous, current, connections):
    elapsed = max(0.001, current['time'] - previous['time'])
    total = current['total'] - previous['total']
    cpu = max(0, min(100, 100 * (1 - (current['idle'] - previous['idle']) / total))) if total else 0
    memory = {line.split(':')[0]: int(line.split()[1]) for line in (PROC / 'meminfo').read_text().splitlines()}
    used = memory['MemTotal'] - memory['MemAvailable']
    disk = shutil.disk_usage(Path.home())
    cpu_rows, ram_rows, io_rows = [], [], []
    for key, p in current['processes'].items():
        old = previous['processes'].get(key)
        common = {'key': key, 'name': p['name'], 'detail': f'PID {p["pid"]}'}
        if old:
            value = max(0, (p['ticks'] - old['ticks']) / TICKS / elapsed * 100)
            cpu_rows.append(dict(common, score=value, value=f'{value:.1f}%'))
            if p['io'] is not None and old['io'] is not None:
                read, write = [max(0, a - b) / elapsed for a, b in zip(p['io'], old['io'])]
                io_rows.append(dict(common, score=read + write, value=rate(read + write),
                                    detail=f'PID {p["pid"]} · R {rate(read)} · W {rate(write)}'))
        ram_rows.append(dict(common, score=p['rss'], value=f'{p["rss"] / 1048576:.0f} MB'))

    net_rows, device_rows = [], []
    down = up = disk_rate = 0
    for name, values in current['net'].items():
        old = previous['net'].get(name, values)
        rx, tx = [max(0, a - b) / elapsed for a, b in zip(values, old)]
        down += rx
        up += tx
        net_rows.append({'key': name, 'name': name, 'score': rx + tx,
                         'value': rate(rx + tx), 'detail': f'↓ {rate(rx)}   ↑ {rate(tx)}'})
    for name, values in current['devices'].items():
        old = previous['devices'].get(name, values)
        read, write = [max(0, a - b) / elapsed for a, b in zip(values, old)]
        disk_rate += read + write
        device_rows.append({'key': 'device:' + name, 'name': name, 'score': read + write,
                            'value': rate(read + write), 'detail': f'R {rate(read)} · W {rate(write)}'})

    tcp_apps = {}
    for key, socket in current['tcp'].items():
        old = previous['tcp'].get(key)
        if old is None:
            continue
        app = tcp_apps.setdefault(socket['pid'], {'name': socket['name'], 'rx': 0, 'tx': 0})
        app['rx'] += max(0, socket['received'] - old['received']) / elapsed
        app['tx'] += max(0, socket['sent'] - old['sent']) / elapsed
    tcp_rows = [{'key': 'tcp:' + pid, 'name': app['name'], 'score': app['rx'] + app['tx'],
                 'value': rate(app['rx'] + app['tx']),
                 'detail': f'PID {pid} · ↓ {rate(app["rx"])} · ↑ {rate(app["tx"])}'}
                for pid, app in tcp_apps.items()]

    def ranked(rows):
        rows = sorted(rows, key=lambda row: (-row['score'], row['key']))[:6]
        maximum = max((r['score'] for r in rows), default=1) or 1
        return [dict(row, level=row['score'] / maximum) for row in rows]

    active_io = [row for row in io_rows if row['score'] > 0]
    io_note = 'Active processes · physical disk I/O'
    if not active_io:
        active_io = device_rows
        io_note = 'Physical drives · no visible process I/O this interval'
    if current['ioHidden']:
        io_note += ' · some process counters are restricted'
    return {
        'cpu': round(cpu), 'cores': os.cpu_count(),
        'ram': round(100 * used / memory['MemTotal']),
        'ramDetail': f'{used / 1048576:.1f} / {memory["MemTotal"] / 1048576:.1f} GB',
        'disk': round(100 * disk.used / disk.total), 'diskDetail': f'{disk.free / 1073741824:.0f} GB free',
        'download': rate(down), 'upload': rate(up), 'netRate': down + up, 'diskRate': disk_rate,
        'cpuRows': ranked(cpu_rows), 'ramRows': ranked(ram_rows), 'diskRows': ranked(active_io),
        'netRows': ranked(tcp_rows if tcp_rows else net_rows),
        'netNote': 'App traffic · sampled TCP sockets only' if tcp_rows else 'Interfaces · combined receive / send rate',
        'netInterfaces': ' · '.join(f'{r["name"]}: {r["value"]}' for r in sorted(net_rows, key=lambda r: -r['score'])[:2]),
        'ioNote': io_note, 'connections': connections,
    }


def main():
    previous = snapshot()
    connections = connection_summary()
    iteration = 0
    while True:
        time.sleep(2)
        current = snapshot()
        if iteration % 3 == 0:
            connections = connection_summary()
        print(json.dumps(make_data(previous, current, connections)), flush=True)
        previous = current
        iteration += 1


if __name__ == '__main__':
    main()
