#!/usr/bin/env bash
# Install shell helpers for the selective-proxy setup documented in README.md.
#
# Environment overrides:
#   CLASH_PORT=7890       mixed port (default: 7897)
#   PROXY_SHELL=zsh       fish, zsh, or bash (default: infer from $SHELL)
#   PROXY_CONFIG=/path    target rc file (mainly useful for tests)
#   PROXY_DEFAULT_ON=1    enable proxy variables when a shell starts (default: 0)
set -euo pipefail

PORT="${CLASH_PORT:-7897}"
DEFAULT_ON="${PROXY_DEFAULT_ON:-0}"
START_MARKER="# === selective-proxy (managed by dotfiles) ==="
END_MARKER="# === selective-proxy end ==="

case "$PORT" in
  ''|*[!0-9]*) echo "✗ CLASH_PORT must be a number (got: $PORT)" >&2; exit 2 ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "✗ CLASH_PORT must be between 1 and 65535 (got: $PORT)" >&2
  exit 2
fi
case "$DEFAULT_ON" in
  0|1) ;;
  *) echo "✗ PROXY_DEFAULT_ON must be 0 or 1 (got: $DEFAULT_ON)" >&2; exit 2 ;;
esac

is_windows() {
  case "${OS:-}${OSTYPE:-}" in
    *[Ww]indows*|*msys*|*cygwin*) return 0 ;;
    *) return 1 ;;
  esac
}

if is_windows; then
  echo "ℹ Windows detected — add the PowerShell block from proxy/README.md to \$PROFILE."
  echo "  Use mixed port $PORT. The Clash/Mihomo client configuration remains manual."
  exit 0
fi

SHELL_NAME="${PROXY_SHELL:-$(basename "${SHELL:-}")}"
case "$SHELL_NAME" in
  fish)
    CONFIG="${PROXY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish}"
    ;;
  zsh)
    CONFIG="${PROXY_CONFIG:-$HOME/.zshrc}"
    ;;
  bash)
    if [ -n "${PROXY_CONFIG:-}" ]; then
      CONFIG="$PROXY_CONFIG"
    elif [ "$(uname -s)" = "Darwin" ]; then
      CONFIG="$HOME/.bash_profile"
    else
      CONFIG="$HOME/.bashrc"
    fi
    ;;
  *)
    echo "✗ unsupported shell '${SHELL_NAME:-unknown}'; set PROXY_SHELL to fish, zsh, or bash" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

TMP="$(mktemp "${TMPDIR:-/tmp}/selective-proxy.XXXXXX")"
BLOCK="$(mktemp "${TMPDIR:-/tmp}/selective-proxy-block.XXXXXX")"
trap 'rm -f "$TMP" "$BLOCK"' EXIT

if [ "$SHELL_NAME" = "fish" ]; then
  cat > "$BLOCK" <<EOF
$START_MARKER
set -g __selective_proxy_port $PORT
set -g __selective_proxy_no_proxy 'localhost,127.0.0.1,::1,.local,192.168.0.0/16,100.64.0.0/10'

function proxy
    if not contains -- --force \$argv
        if not command nc -z -w 1 127.0.0.1 \$__selective_proxy_port >/dev/null 2>&1
            echo "代理未开启:127.0.0.1:\$__selective_proxy_port 没有监听;启动 Clash/Mihomo 后重试,或使用 proxy --force" >&2
            return 1
        end
    end
    set -gx HTTP_PROXY  "http://127.0.0.1:\$__selective_proxy_port"
    set -gx HTTPS_PROXY \$HTTP_PROXY
    set -gx ALL_PROXY   "socks5h://127.0.0.1:\$__selective_proxy_port"
    set -gx NO_PROXY    \$__selective_proxy_no_proxy
    set -gx http_proxy  \$HTTP_PROXY
    set -gx https_proxy \$HTTPS_PROXY
    set -gx all_proxy   \$ALL_PROXY
    set -gx no_proxy    \$NO_PROXY
    if not contains -- --quiet \$argv
        echo "代理已开启 (127.0.0.1:\$__selective_proxy_port)"
    end
end

function unproxy
    set -e HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
    set -e http_proxy https_proxy all_proxy no_proxy
    if not contains -- --quiet \$argv
        echo '代理已关闭'
    end
end

function proxy_status
    if set -q HTTPS_PROXY
        echo "代理环境变量:开启 (\$HTTPS_PROXY)"
    else
        echo '代理环境变量:关闭'
    end
    if command nc -z -w 1 127.0.0.1 \$__selective_proxy_port >/dev/null 2>&1
        echo "本地端口:监听中 (127.0.0.1:\$__selective_proxy_port)"
    else
        echo "本地端口:未监听 (127.0.0.1:\$__selective_proxy_port)"
    end
end
EOF
  if [ "$DEFAULT_ON" = 1 ]; then
    printf '%s\n' 'proxy --quiet' >> "$BLOCK"
  else
    printf '%s\n' 'unproxy --quiet' >> "$BLOCK"
  fi
  printf '%s\n' "$END_MARKER" >> "$BLOCK"
else
  cat > "$BLOCK" <<EOF
$START_MARKER
__selective_proxy_port=$PORT
__selective_proxy_no_proxy='localhost,127.0.0.1,::1,.local,192.168.0.0/16,100.64.0.0/10'

proxy() {
  local force=0 quiet=0 arg
  for arg in "\$@"; do
    [ "\$arg" = "--force" ] && force=1
    [ "\$arg" = "--quiet" ] && quiet=1
  done
  if [ "\$force" -ne 1 ] && ! command nc -z -w 1 127.0.0.1 "\$__selective_proxy_port" >/dev/null 2>&1; then
    echo "代理未开启:127.0.0.1:\$__selective_proxy_port 没有监听;启动 Clash/Mihomo 后重试,或使用 proxy --force" >&2
    return 1
  fi
  export HTTP_PROXY="http://127.0.0.1:\$__selective_proxy_port"
  export HTTPS_PROXY="\$HTTP_PROXY"
  export ALL_PROXY="socks5h://127.0.0.1:\$__selective_proxy_port"
  export NO_PROXY="\$__selective_proxy_no_proxy"
  export http_proxy="\$HTTP_PROXY" https_proxy="\$HTTPS_PROXY"
  export all_proxy="\$ALL_PROXY" no_proxy="\$NO_PROXY"
  [ "\$quiet" -eq 1 ] || echo "代理已开启 (127.0.0.1:\$__selective_proxy_port)"
}

unproxy() {
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
  unset http_proxy https_proxy all_proxy no_proxy
  [ "\${1:-}" = "--quiet" ] || echo '代理已关闭'
}

proxy_status() {
  if [ -n "\${HTTPS_PROXY:-}" ]; then
    echo "代理环境变量:开启 (\$HTTPS_PROXY)"
  else
    echo '代理环境变量:关闭'
  fi
  if command nc -z -w 1 127.0.0.1 "\$__selective_proxy_port" >/dev/null 2>&1; then
    echo "本地端口:监听中 (127.0.0.1:\$__selective_proxy_port)"
  else
    echo "本地端口:未监听 (127.0.0.1:\$__selective_proxy_port)"
  fi
}
EOF
  if [ "$DEFAULT_ON" = 1 ]; then
    printf '%s\n' 'proxy --quiet' >> "$BLOCK"
  else
    printf '%s\n' 'unproxy --quiet' >> "$BLOCK"
  fi
  printf '%s\n' "$END_MARKER" >> "$BLOCK"
fi

# Replace only our managed block. Everything else remains byte-for-byte intact.
awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { managed=1; next }
  managed && $0 == end { managed=0; next }
  !managed { print }
' "$CONFIG" > "$TMP"

if [ -s "$TMP" ] && [ "$(tail -c 1 "$TMP" | wc -l | tr -d ' ')" = 0 ]; then
  printf '\n' >> "$TMP"
fi
printf '\n' >> "$TMP"
cat "$BLOCK" >> "$TMP"
# Preserve the rc file's permissions and a possible dotfiles symlink.
cat "$TMP" > "$CONFIG"

echo "✓ installed selective-proxy helpers for $SHELL_NAME in $CONFIG (port $PORT, default: $([ "$DEFAULT_ON" = 1 ] && echo on || echo off))"
echo "  reload with: source $CONFIG"
echo "  commands: proxy | unproxy | proxy_status"
echo "  note: Clash/Mihomo profiles are not modified; choose local-TUN or side-router mode per proxy/README.md"
