#!/usr/bin/env bash
# Claude Code status line: live context meter + 80% warning sound,
# plus optional budget/usage line (session cost, lines changed, 5h & weekly
# rate-limit usage with reset countdown). All extra data comes straight from
# the status-line stdin JSON (cost.* / rate_limits.*) — zero deps, no network.
#
# Toggles (env; "0" disables, default in brackets):
#   CLAUDE_SL_COST        [on]  session $cost + lines +added/-removed
#   CLAUDE_SL_5H          [on]  5-hour usage % + reset countdown
#   CLAUDE_SL_WEEKLY      [off] 7-day usage %
#   CLAUDE_SL_USABLE      [off] context % against autocompact-usable window
#   CLAUDE_CTX_AUTOCOMPACT_PCT [8] reserve % for usable mode (approx; tunable)
#   CLAUDE_SL_MULTILINE   [on]  render budget/usage on a 2nd line
#   CLAUDE_SL_THINKING    [on]  current thinking/effort level (🧠high)
#   CLAUDE_CTX_WINDOW           override context window size (existing)

input="$(cat)"

# --- extract fields (defensive: missing fields fall back, never break) ---
pct="$(jq -r '.context_window.used_percentage // empty' <<<"$input")"
used="$(jq -r '.context_window.total_input_tokens // empty' <<<"$input")"
size="$(jq -r '.context_window.context_window_size // empty' <<<"$input")"
over200k="$(jq -r '.exceeds_200k_tokens // false' <<<"$input")"
session="$(jq -r '.session_id // "default"' <<<"$input")"
branch="$(jq -r '.workspace.current_branch // .git.branch // empty' <<<"$input")"
model="$(jq -r '.model.display_name // .model.id // empty' <<<"$input")"
# absorbed from ccstatusline's feature set — all present in the stdin payload:
cost_usd="$(jq -r '.cost.total_cost_usd // empty' <<<"$input")"
lines_add="$(jq -r '.cost.total_lines_added // empty' <<<"$input")"
lines_del="$(jq -r '.cost.total_lines_removed // empty' <<<"$input")"
h5_pct="$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")"
h5_reset="$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")"
d7_pct="$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")"
think_level="$(jq -r '.effort.level // empty' <<<"$input")"   # live thinking level (newer field)

# --- helpers ---
# on VAR DEFAULT(0/1): true if the toggle is enabled
on() {
  local v="${!1}"
  if [ -z "$v" ]; then [ "$2" = "1" ]; return $?; fi
  [ "$v" != "0" ]
}
# zone_col PCT: ANSI color by usage zone (green <60, yellow 60-79, red >=80)
zone_col() {
  if   [ "$1" -ge 80 ]; then printf '\033[31m'
  elif [ "$1" -ge 60 ]; then printf '\033[33m'
  else                       printf '\033[32m'
  fi
}
# fmt_reset EPOCH: seconds-from-now as "Xh Ym" / "Nm" / "now"
fmt_reset() {
  local target="$1" now diff h m
  now="$(date +%s)"
  diff=$(( target - now ))
  [ "$diff" -le 0 ] && { printf 'now'; return; }
  h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"; else printf '%dm' "$m"; fi
}

# --- effective context window: env var > model detection > API report ---
# CLAUDE_CTX_WINDOW overrides everything; known model patterns fill in
# what the API sometimes under-reports (e.g. deepseek via Anthropic proxy).
recalc_pct=0
if [ -n "$CLAUDE_CTX_WINDOW" ] && [ "$CLAUDE_CTX_WINDOW" -gt 0 ] 2>/dev/null; then
  size="$CLAUDE_CTX_WINDOW"
  recalc_pct=1
else
  case "$model" in
    deepseek*|DeepSeek*) size=1000000; recalc_pct=1 ;;
  esac
fi

# Recalculate percentage when we overrode the window (API % is relative to
# its own window, which understates usage against the real capacity).
if [ "$recalc_pct" -eq 1 ] && [ -n "$used" ] && [ "$size" -gt 0 ]; then
  pct=$(( used * 100 / size ))
  pct_int="$pct"
fi

# Fallback if percentage is absent (very start of a session)
[ -z "$pct" ] && pct=0
pct_int="${pct%.*}"
[ -z "$pct_int" ] && pct_int=0

# --- usable-context mode: rescale % against the autocompact-usable window ---
# Claude auto-compacts before the window is truly full, so raw % is optimistic.
# usable window = size * (100 - reserve)/100; bar/%/alarm key off this instead.
if on CLAUDE_SL_USABLE 0 && [ -n "$used" ] && [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
  reserve="${CLAUDE_CTX_AUTOCOMPACT_PCT:-8}"
  usable_win=$(( size * (100 - reserve) / 100 ))
  if [ "$usable_win" -gt 0 ]; then
    pct=$(( used * 100 / usable_win ))
    [ "$pct" -gt 100 ] && pct=100
    pct_int="$pct"
  fi
fi

# --- 80% one-shot alarm (only chime when CROSSING up over 80) ---
# Cross-platform: use paplay on Linux, PowerShell beep on Windows, fallback silent.
play_alarm() {
  if command -v paplay >/dev/null 2>&1; then
    paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga >/dev/null 2>&1 &
  elif command -v powershell >/dev/null 2>&1; then
    powershell -c '[console]::beep(880,200)' >/dev/null 2>&1
  fi
}
state_file="/tmp/claude-ctx-alarm-${session}.state"
last="$(cat "$state_file" 2>/dev/null || echo 0)"
if [ "$pct_int" -ge 80 ] && [ "$last" -lt 80 ]; then
  play_alarm
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
green=$'\033[32m'
red=$'\033[31m'

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

# --- line 1: context core (unchanged look) ---
line1="${col}ctx ${bar} ${pct_int}%${reset}"
[ -n "$tok" ] && line1="${line1} ${dim}${tok}${reset}"
# ⚠200k+ only matters when the window itself is ~200k; on a 1M-context model
# (size much larger) the fixed 200k flag is noise — suppress it there.
if [ "$over200k" = "true" ] && { [ -z "$size" ] || [ "$size" -le 220000 ]; }; then
  line1="${line1} ${col}⚠200k+${reset}"
fi
[ -n "$branch" ] && line1="${line1} ${dim}⎇ ${branch}${reset}"
[ -n "$model" ] && line1="${line1} ${dim}${model}${reset}"
# current thinking level: stdin .effort.level (live) > ~/.claude settings > skip
if on CLAUDE_SL_THINKING 1; then
  tl="$think_level"
  [ -z "$tl" ] && tl="$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)"
  [ -n "$tl" ] && line1="${line1} ${dim}🧠${tl}${reset}"
fi

# --- line 2: budget / usage (all optional, all from stdin) ---
# session cost + lines changed
cost_seg=""
if on CLAUDE_SL_COST 1; then
  cs=""
  if [ -n "$cost_usd" ]; then
    cfmt="$(printf '%.2f' "$cost_usd" 2>/dev/null)"
    [ -n "$cfmt" ] && cs="${dim}\$${cfmt}${reset}"
  fi
  la="${lines_add:-0}"; ld="${lines_del:-0}"
  if [ "$la" -gt 0 ] 2>/dev/null || [ "$ld" -gt 0 ] 2>/dev/null; then
    cs="${cs:+$cs }${green}+${la}${reset}/${red}-${ld}${reset}"
  fi
  cost_seg="$cs"
fi
# 5-hour rate-limit usage + reset countdown
h5_seg=""
if on CLAUDE_SL_5H 1 && [ -n "$h5_pct" ]; then
  h5i="${h5_pct%.*}"; [ -z "$h5i" ] && h5i=0
  c="$(zone_col "$h5i")"
  h5_seg="${c}5h ${h5i}%${reset}"
  [ -n "$h5_reset" ] && h5_seg="${h5_seg} ${dim}↺$(fmt_reset "${h5_reset%.*}")${reset}"
fi
# 7-day (weekly) usage
d7_seg=""
if on CLAUDE_SL_WEEKLY 0 && [ -n "$d7_pct" ]; then
  d7i="${d7_pct%.*}"; [ -z "$d7i" ] && d7i=0
  c="$(zone_col "$d7i")"
  d7_seg="${c}7d ${d7i}%${reset}"
fi

line2=""
for s in "$cost_seg" "$h5_seg" "$d7_seg"; do
  [ -n "$s" ] && line2="${line2:+$line2 }$s"
done

# --- emit: multi-line when enabled & line 2 has content, else single line ---
if on CLAUDE_SL_MULTILINE 1 && [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  merged="$line1"
  [ -n "$line2" ] && merged="${merged} ${line2}"
  printf '%s' "$merged"
fi
