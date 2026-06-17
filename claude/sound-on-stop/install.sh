#!/usr/bin/env bash
# Installer: play a chime when Claude Code finishes a turn (the Stop hook).
# Idempotent — adds the hook only if an identical command isn't already there,
# and merges into settings.json WITHOUT touching other keys.
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

# The sound command. paplay (Linux) or PowerShell beep (Windows).
# `|| true` so a missing player never makes the hook fail the turn.
case "$(uname -s)" in
  *MINGW*|*CYGWIN*|*MSYS*)
    SOUND_CMD='powershell -c "[console]::beep(660,150)"'
    ;;
  *)
    SOUND_CMD='paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true'
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found. Install it:  sudo pacman -S jq (Linux)  |  winget install jq (Windows)" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "✗ $SETTINGS is not valid JSON — fix it manually, then re-run." >&2
  exit 1
fi

# Append a Stop hook group only if no existing Stop hook runs this exact command.
tmp="$(mktemp)"
jq --arg cmd "$SOUND_CMD" '
  .hooks //= {} |
  .hooks.Stop //= [] |
  if ([.hooks.Stop[].hooks[]?.command] | index($cmd)) then .
  else .hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd, "async": true}]}]
  end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "✓ Stop chime ensured in $SETTINGS"
echo "  command: $SOUND_CMD"
echo
echo "Done. Takes effect in new turns. Re-running this is safe (won't duplicate)."
echo "Not on Arch / no PulseAudio? Installer auto-detects Windows (PowerShell beep)."
