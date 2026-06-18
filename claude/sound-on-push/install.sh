#!/usr/bin/env bash
# Installer: play a victory fanfare when a `git push` SUCCEEDS (PostToolUse /
# Bash hook). Ships its own audio so it's reproducible across machines.
#
# Gating, all decided at hook runtime from the hook's stdin JSON:
#   - only fires when the command actually invokes "git push" (anchored so
#     `echo "git push"` won't trigger it), and NOT a `--dry-run` / `-n` push
#   - stays SILENT if the push output shows failure (rejected / fatal: /
#     failed to push / permission denied / authentication failed / could not
#     read) — we don't celebrate a failed push
#   - otherwise (incl. "Everything up-to-date") → fanfare 🎺
#
# This tool OWNS the push sound: it strips any prior PostToolUse hook that
# references push-done, then installs this one. Other PostToolUse hooks and
# all other keys are left untouched. Idempotent — re-running won't duplicate.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SND_SRC="$HERE/victory-fanfare.mp3"
SND_DST="$CLAUDE_DIR/sounds/push-done.mp3"

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found. Install it:  sudo pacman -S jq (Linux)  |  winget install jq (Windows)" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR/sounds"
install -m 0644 "$SND_SRC" "$SND_DST"
echo "✓ sound → $SND_DST"

# The hook command (stored verbatim in settings.json, expanded at hook runtime).
# Player fallback: mpv → ffplay → mpg123 → Windows PowerShell beep. paplay can't
# decode mp3, so it's intentionally skipped. `|| true` so a missing player never
# fails the turn.
SOUND_CMD='input=$(cat); cmd=$(printf "%s" "$input" | jq -r ".tool_input.command"); printf "%s" "$cmd" | grep -qE "(^|[;&|] *)git +push" || exit 0; printf "%s" "$cmd" | grep -qE -- "--dry-run|[[:space:]]-n([[:space:]]|$)" && exit 0; printf "%s" "$input" | jq -r ".tool_response | tostring" | grep -qiE "rejected|fatal:|failed to push|permission denied|authentication failed|could not read" && exit 0; { command -v mpv >/dev/null && mpv --no-video --really-quiet "$HOME/.claude/sounds/push-done.mp3"; } || { command -v ffplay >/dev/null && ffplay -nodisp -autoexit -loglevel quiet "$HOME/.claude/sounds/push-done.mp3"; } || { command -v mpg123 >/dev/null && mpg123 -q "$HOME/.claude/sounds/push-done.mp3"; } || { case "$(uname -s)" in *MINGW*|*CYGWIN*|*MSYS*) powershell -c "[console]::beep(880,200)";; esac; } || true'

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "✗ $SETTINGS is not valid JSON — fix it manually, then re-run." >&2
  exit 1
fi

# Drop any PostToolUse group whose command references our push-done sound, then
# append ours. → replaces an older version AND is idempotent on re-run.
tmp="$(mktemp)"
jq --arg cmd "$SOUND_CMD" '
  .hooks //= {} |
  .hooks.PostToolUse //= [] |
  .hooks.PostToolUse |= map(select(
    ([.hooks[]?.command] | map(test("push-done"; "i")) | any) | not
  )) |
  .hooks.PostToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": $cmd, "async": true}]}]
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "✓ PostToolUse hook set → $SETTINGS (any old push sound replaced)"
echo
echo "Done. Fires next time a git push succeeds. Re-running is safe (no dupes)."
echo "Players tried: mpv → ffplay → mpg123. Install one if none present."
