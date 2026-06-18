#!/usr/bin/env bash
# Installer for the Claude Code context status line.
# Idempotent: copies the script into ~/.claude and sets the statusLine key in
# settings.json. All other keys (hooks, permissions, ...) are left untouched.
# NOTE: statusLine is a single value, not a list — installing this tool means
# you want THIS status line, so an existing statusLine is replaced (you'll be
# told when that happens, and the old command is printed so you can restore it).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SCRIPT_SRC="$HERE/statusline-context.sh"
SCRIPT_DST="$CLAUDE_DIR/statusline-context.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# --- dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found. Install it:  sudo pacman -S jq (Linux)  |  winget install jq (Windows)" >&2
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
# Warn (don't silently clobber) if a different statusLine is already set.
new_cmd="bash $SCRIPT_DST"
prev="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
if [ -n "$prev" ] && [ "$prev" != "$new_cmd" ]; then
  echo "⚠ replacing an existing statusLine. Previous command was:" >&2
  echo "    $prev" >&2
  echo "  (re-add it manually if you want it back)" >&2
fi
tmp="$(mktemp)"
jq --arg cmd "$new_cmd" \
   '.statusLine = {type: "command", command: $cmd}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ statusLine set → $SETTINGS"
echo
echo "Done. Open a new Claude Code session (or /resume) to see the bar."
echo "Note: the 80% chime uses paplay (Linux) or PowerShell [console]::beep (Windows)."
