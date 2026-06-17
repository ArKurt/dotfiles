#!/usr/bin/env bash
# Installer for the Claude Code context status line.
# Idempotent: copies the script into ~/.claude and merges the statusLine key
# into settings.json WITHOUT clobbering existing keys (hooks, permissions, ...).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SCRIPT_SRC="$HERE/statusline-context.sh"
SCRIPT_DST="$CLAUDE_DIR/statusline-context.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# --- dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found. Install it first:  sudo pacman -S jq" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

# --- install the script ---
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"
echo "✓ script → $SCRIPT_DST"

# --- merge statusLine into settings.json (preserve everything else) ---
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
# bail clearly if the existing file is not valid JSON, rather than corrupt it
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "✗ $SETTINGS is not valid JSON — fix it manually, then re-run." >&2
  exit 1
fi
tmp="$(mktemp)"
jq --arg cmd "bash $SCRIPT_DST" \
   '.statusLine = {type: "command", command: $cmd}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ statusLine merged → $SETTINGS"
echo
echo "Done. Open a new Claude Code session (or /resume) to see the bar."
echo "Note: the 80% chime uses paplay + a freedesktop .oga (PulseAudio/PipeWire)."
