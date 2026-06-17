#!/usr/bin/env bash
# Installer: play a custom sound when Claude Code wants your attention
# (the Notification hook — fires when Claude is waiting for input, a choice,
# or a permission). Ships its own audio file so it's reproducible across machines.
#
# This tool OWNS the Notification sound: it strips any existing sound-playing
# Notification hook (e.g. the old window-attention chime) and installs this one.
# Non-sound Notification hooks, and all other keys, are left untouched.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SND_SRC="$HERE/help-me.mp3"
SND_DST="$CLAUDE_DIR/notify-help-me.mp3"

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found. Install it first:  sudo pacman -S jq" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"
install -m 0644 "$SND_SRC" "$SND_DST"
echo "✓ sound → $SND_DST"

# Play command: try mpv → ffplay → mpg123 (any mp3-capable player), never fail
# the turn. paplay can't decode mp3, so it's intentionally not used here.
SOUND_CMD='{ command -v mpv >/dev/null && mpv --no-video --really-quiet "$HOME/.claude/notify-help-me.mp3"; } || { command -v ffplay >/dev/null && ffplay -nodisp -autoexit -loglevel quiet "$HOME/.claude/notify-help-me.mp3"; } || { command -v mpg123 >/dev/null && mpg123 -q "$HOME/.claude/notify-help-me.mp3"; } || true'

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "✗ $SETTINGS is not valid JSON — fix it manually, then re-run." >&2
  exit 1
fi

# Drop any Notification group that plays a sound (old window-attention or ours),
# then append ours. → replaces the old chime AND is idempotent on re-run.
tmp="$(mktemp)"
jq --arg cmd "$SOUND_CMD" '
  .hooks //= {} |
  .hooks.Notification //= [] |
  .hooks.Notification |= map(select(
    ([.hooks[]?.command]
      | map(test("paplay|ffplay|mpv|mpg123|aplay|afplay|window-attention|notify-help-me"; "i"))
      | any) | not
  )) |
  .hooks.Notification += [{"hooks": [{"type": "command", "command": $cmd, "async": true}]}]
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "✓ Notification hook set → $SETTINGS (any old sound chime replaced)"
echo
echo "Done. Fires next time Claude waits on you. Re-running is safe (no dupes)."
echo "Players tried: mpv → ffplay → mpg123. Install one if none present."
