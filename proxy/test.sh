#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/selective-proxy-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "✗ $*" >&2; exit 1; }
assert_count() {
  local expected="$1" pattern="$2" file="$3" actual
  actual="$(grep -cF "$pattern" "$file" || true)"
  [ "$actual" = "$expected" ] || fail "expected $expected occurrence(s) of '$pattern' in $file, got $actual"
}

# The dispatcher must run on macOS Bash 3.2 (no mapfile/readarray).
DISPATCHER_OUTPUT="$(bash "$ROOT/install.sh")"
grep -q '^  proxy$' <<< "$DISPATCHER_OUTPUT" || fail 'dispatcher did not list proxy'

ZSH_RC="$TMP/.zshrc"
printf '%s\n' '# keep-me' > "$ZSH_RC"
HOME="$TMP" PROXY_SHELL=zsh PROXY_CONFIG="$ZSH_RC" CLASH_PORT=17897 bash "$ROOT/proxy/install.sh" >/dev/null
assert_count 1 '# === selective-proxy (managed by dotfiles) ===' "$ZSH_RC"
grep -qF '# keep-me' "$ZSH_RC" || fail 'installer overwrote existing zsh config'
grep -qF '__selective_proxy_port=17897' "$ZSH_RC" || fail 'zsh port missing'

# Reinstall updates the managed block instead of appending another one.
HOME="$TMP" PROXY_SHELL=zsh PROXY_CONFIG="$ZSH_RC" CLASH_PORT=17898 bash "$ROOT/proxy/install.sh" >/dev/null
assert_count 1 '# === selective-proxy (managed by dotfiles) ===' "$ZSH_RC"
grep -qF '__selective_proxy_port=17898' "$ZSH_RC" || fail 'zsh port was not updated'

# Updating a symlinked dotfile must not replace the symlink itself.
LINK_TARGET="$TMP/zshrc-target"
LINK_RC="$TMP/zshrc-link"
printf '%s\n' '# linked-config' > "$LINK_TARGET"
ln -s "$LINK_TARGET" "$LINK_RC"
HOME="$TMP" PROXY_SHELL=zsh PROXY_CONFIG="$LINK_RC" CLASH_PORT=17900 bash "$ROOT/proxy/install.sh" >/dev/null
[ -L "$LINK_RC" ] || fail 'installer replaced a symlinked rc file'
grep -qF '__selective_proxy_port=17900' "$LINK_TARGET" || fail 'installer did not update symlink target'

# Default-off clears inherited variables; forced enable sets both cases; disable clears them.
HTTP_PROXY=old HTTPS_PROXY=old ALL_PROXY=old NO_PROXY=old \
http_proxy=old https_proxy=old all_proxy=old no_proxy=old \
zsh -c "source '$ZSH_RC'; [ -z \"\${HTTPS_PROXY:-}\" ]; proxy --force --quiet; [ \"\$HTTPS_PROXY\" = http://127.0.0.1:17898 ]; [ \"\$all_proxy\" = socks5h://127.0.0.1:17898 ]; unproxy --quiet; [ -z \"\${HTTP_PROXY:-}\" ]" \
  || fail 'zsh helper behavior is incorrect'

FISH_RC="$TMP/config.fish"
HOME="$TMP" PROXY_SHELL=fish PROXY_CONFIG="$FISH_RC" CLASH_PORT=17899 bash "$ROOT/proxy/install.sh" >/dev/null
assert_count 1 '# === selective-proxy (managed by dotfiles) ===' "$FISH_RC"
grep -qF 'set -g __selective_proxy_port 17899' "$FISH_RC" || fail 'fish port missing'

if HOME="$TMP" PROXY_SHELL=zsh PROXY_CONFIG="$ZSH_RC" CLASH_PORT=invalid bash "$ROOT/proxy/install.sh" >/dev/null 2>&1; then
  fail 'invalid port was accepted'
fi

echo '✓ selective-proxy tests passed'
