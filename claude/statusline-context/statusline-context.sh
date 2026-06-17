#!/usr/bin/env bash
# Claude Code status line: live context meter + 80% warning sound.
# Reads the status-line JSON from stdin (context_window.* fields), renders a
# progress bar, and plays a one-shot warning chime when usage crosses 80%.

input="$(cat)"

# --- extract fields (defensive: missing fields fall back, never break) ---
pct="$(jq -r '.context_window.used_percentage // empty' <<<"$input")"
used="$(jq -r '.context_window.total_input_tokens // empty' <<<"$input")"
size="$(jq -r '.context_window.context_window_size // empty' <<<"$input")"
over200k="$(jq -r '.exceeds_200k_tokens // false' <<<"$input")"
session="$(jq -r '.session_id // "default"' <<<"$input")"
branch="$(jq -r '.workspace.current_branch // .git.branch // empty' <<<"$input")"
model="$(jq -r '.model.display_name // .model.id // empty' <<<"$input")"

# Fallback if percentage is absent (very start of a session)
[ -z "$pct" ] && pct=0
pct_int="${pct%.*}"
[ -z "$pct_int" ] && pct_int=0

# --- 80% one-shot alarm (only chime when CROSSING up over 80) ---
state_file="/tmp/claude-ctx-alarm-${session}.state"
last="$(cat "$state_file" 2>/dev/null || echo 0)"
if [ "$pct_int" -ge 80 ] && [ "$last" -lt 80 ]; then
  paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga >/dev/null 2>&1 &
fi
echo "$pct_int" > "$state_file"

# --- progress bar (20 cells) ---
cells=20
filled=$(( pct_int * cells / 100 ))
[ "$filled" -gt "$cells" ] && filled=$cells
bar=""
i=0
while [ "$i" -lt "$cells" ]; do
  if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  i=$((i+1))
done

# --- color by zone (ANSI): green <60, yellow 60-79, red >=80 ---
if   [ "$pct_int" -ge 80 ]; then col=$'\033[31m'   # red
elif [ "$pct_int" -ge 60 ]; then col=$'\033[33m'   # yellow
else                              col=$'\033[32m'   # green
fi
reset=$'\033[0m'
dim=$'\033[2m'

# --- token count vs window, human-readable (e.g. 210k/1000k) ---
tok=""
if [ -n "$used" ]; then
  usedk="$(( used / 1000 ))k"
  if [ -n "$size" ] && [ "$size" -gt 0 ]; then
    tok="${usedk}/$(( size / 1000 ))k"
  else
    tok="$usedk"
  fi
fi

# --- assemble line ---
out="${col}ctx ${bar} ${pct_int}%${reset}"
[ -n "$tok" ] && out="${out} ${dim}${tok}${reset}"
# ⚠200k+ only matters when the window itself is ~200k; on a 1M-context model
# (size much larger) the fixed 200k flag is noise — suppress it there.
if [ "$over200k" = "true" ] && { [ -z "$size" ] || [ "$size" -le 220000 ]; }; then
  out="${out} ${col}⚠200k+${reset}"
fi
[ -n "$branch" ] && out="${out} ${dim}⎇ ${branch}${reset}"
[ -n "$model" ] && out="${out} ${dim}${model}${reset}"

printf '%s' "$out"
