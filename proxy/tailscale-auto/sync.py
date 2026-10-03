#!/usr/bin/python3
"""Select tailscaled's proxy from active Wi-Fi and local proxy availability."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

CONFIG = Path('/etc/tailscale-proxy.json')
STATE = Path('/run/tailscale-proxy')


def run(*args):
    return subprocess.check_output(args, text=True, timeout=8).strip()


def networks():
    result = []
    for row in run('nmcli', '-t', '-f', 'UUID,TYPE', 'connection', 'show', '--active').splitlines():
        uuid, kind = row.split(':', 1)
        if kind == '802-11-wireless':
            ssid = run('nmcli', '-g', '802-11-wireless.ssid', 'connection', 'show', uuid)
            result.append(ssid)
        elif kind in ('802-3-ethernet', 'gsm', 'cdma'):
            result.append(None)
    return result


def choose(active, excluded, ready):
    if any(ssid in excluded for ssid in active if ssid is not None):
        return 'direct', 'home-wifi'
    if not active:
        return 'direct', 'offline'
    if ready:
        return 'proxy', 'external-proxy-ready'
    return 'direct', 'external-proxy-unavailable'


def plan(config):
    active = networks()
    try:
        with socket.create_connection(('127.0.0.1', config['port']), timeout=0.5):
            ready = True
    except OSError:
        ready = False
    mode, reason = choose(active, config['home_ssids'], ready)
    return mode, reason


def atomic(path, content):
    fd, name = tempfile.mkstemp(dir=STATE)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    config = json.loads(CONFIG.read_text())
    mode, reason = plan(config)
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    envfile = STATE / 'environment'
    url = f"http://127.0.0.1:{config['port']}" if mode == 'proxy' else ''
    content = '\n'.join([
        f'HTTP_PROXY={url}', f'HTTPS_PROXY={url}',
        'NO_PROXY=localhost,127.0.0.1,::1',
        'http_proxy=', 'https_proxy=', 'ALL_PROXY=', 'all_proxy=', 'no_proxy=', '',
    ])
    if action == 'status':
        print(json.dumps({'desired': mode, 'reason': reason,
                          'applied': envfile.read_text() if envfile.exists() else None}))
    elif action == 'prepare':
        STATE.mkdir(mode=0o755, exist_ok=True)
        atomic(envfile, content)
        print(f'tailscale-proxy: {mode} ({reason})', flush=True)
    elif action == 'reconcile':
        # A disconnected network should not repeatedly restart the VPN.
        if reason == 'offline':
            return
        if not envfile.exists() or envfile.read_text() != content:
            print(f'tailscale-proxy: switching to {mode} ({reason})', flush=True)
            subprocess.run(['systemctl', 'try-restart', 'tailscaled.service'],
                           check=True, timeout=30)
    else:
        raise ValueError('expected prepare, reconcile, or status')


if __name__ == '__main__':
    main()
