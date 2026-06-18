#!/usr/bin/env bash
# selective-proxy installer — append the shell proxy block (terminal fallback).
#
# Idempotent + only-add: if the block already exists it does nothing, and it
# never touches your other config. The Clash-client side (TUN + prepend-rules)
# is GUI/manual — see README.md.
#
#   CLASH_PORT=7890 ./install.sh   # override the mixed port (default 7897)
set -euo pipefail

PORT="${CLASH_PORT:-7897}"
MARKER="# === Clash 代理 (selective-proxy) ==="

is_windows() { case "${OS:-}${OSTYPE:-}" in *[Ww]indows*|*msys*|*cygwin*) return 0;; *) return 1;; esac; }

if is_windows; then
  echo "ℹ Windows detected — shell env vars are manual on Windows."
  echo "  Add the PowerShell block from README.md to your \$PROFILE (port $PORT)."
  echo "  Clash side (TUN + prepend-rules) is GUI/manual on every platform."
  exit 0
fi

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ℹ fish not found — skipping fish block."
  echo "  For bash/zsh, add the export lines from README.md to your rc file (port $PORT)."
  exit 0
fi

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

if grep -qF "$MARKER" "$CONFIG"; then
  echo "✓ proxy block already present in $CONFIG — nothing to do."
  exit 0
fi

cat >> "$CONFIG" <<EOF

$MARKER
# 默认开启:终端启动的 CLI(claude/codex/curl/git...)默认走代理
set -gx http_proxy  http://127.0.0.1:$PORT
set -gx https_proxy http://127.0.0.1:$PORT
set -gx all_proxy   socks5://127.0.0.1:$PORT
set -gx no_proxy    localhost,127.0.0.1,::1

# 临时开关:本会话 unproxy 关、proxy 开
function proxy
    set -gx http_proxy  http://127.0.0.1:$PORT
    set -gx https_proxy http://127.0.0.1:$PORT
    set -gx all_proxy   socks5://127.0.0.1:$PORT
    set -gx no_proxy    localhost,127.0.0.1,::1
    echo "代理已开启 ($PORT)"
end

function unproxy
    set -e http_proxy https_proxy all_proxy no_proxy
    echo "代理已关闭"
end
# === Clash 代理 (selective-proxy) end ===
EOF

echo "✓ appended proxy block to $CONFIG (port $PORT)"
echo "  open a new terminal, or run: source $CONFIG"
echo "  reminder: configure the Clash client (TUN + prepend-rules) per README.md"
