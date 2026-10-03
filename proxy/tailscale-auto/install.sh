#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if (( EUID != 0 )); then
  echo 'Run with sudo -A bash install.sh (or sudo bash install.sh).'
  exit 1
fi
python3 - <<'PY'
import json
config = json.load(open('config.json'))
if 'YOUR_HOME_WIFI_SSID' in config['home_ssids']:
    raise SystemExit('Replace YOUR_HOME_WIFI_SSID in config.json before installation.')
PY
backup="/var/backups/tailscale-proxy/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for path in /etc/tailscale-proxy.json /etc/systemd/system/tailscaled.service.d/10-clash-proxy.conf /etc/systemd/system/tailscale-proxy-sync.service /etc/systemd/system/tailscale-proxy-sync.timer /etc/NetworkManager/dispatcher.d/90-tailscale-proxy /usr/local/libexec/tailscale-proxy-sync; do
  if [[ -f "$path" ]]; then cp --parents -a "$path" "$backup/"; fi
done
install -Dm755 sync.py /usr/local/libexec/tailscale-proxy-sync
install -Dm644 config.json /etc/tailscale-proxy.json
install -Dm644 10-clash-proxy.conf /etc/systemd/system/tailscaled.service.d/10-clash-proxy.conf
install -Dm644 tailscale-proxy-sync.service /etc/systemd/system/tailscale-proxy-sync.service
install -Dm644 tailscale-proxy-sync.timer /etc/systemd/system/tailscale-proxy-sync.timer
install -Dm755 90-tailscale-proxy /etc/NetworkManager/dispatcher.d/90-tailscale-proxy
systemctl daemon-reload
systemctl restart tailscaled
systemctl enable --now tailscale-proxy-sync.timer
echo "Backup: $backup"
