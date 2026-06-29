#!/usr/bin/env bash
# Claude Code status line: live context meter + 80% warning sound,
# plus an optional, visually-parallel budget/usage line (5h usage meter,
# session cost, lines changed, weekly usage) and the current thinking level.
# All extra data comes straight from the status-line stdin JSON
# (cost.* / rate_limits.* / effort.level) — zero deps, no network.
#
# Toggles (env; "0" disables, default in brackets):
#   CLAUDE_SL_COST        [on]  session $cost + lines +added/-removed
#   CLAUDE_SL_DURATION    [off] session wall-clock duration (⏱)
#   CLAUDE_SL_5H          [on]  5-hour usage meter + reset countdown
#   CLAUDE_SL_WEEKLY      [off] 7-day usage %
#   CLAUDE_SL_USABLE      [off] context % against autocompact-usable window
#   CLAUDE_CTX_AUTOCOMPACT_PCT [8] reserve % for usable mode (approx; tunable)
#   CLAUDE_SL_MULTILINE   [on]  render budget/usage on a 2nd line
#   CLAUDE_SL_THINKING    [on]  current thinking/effort level
#   CLAUDE_SL_THINK_ICON  [💡]  icon shown before the thinking level
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
dur_ms="$(jq -r '.cost.total_duration_ms // empty' <<<"$input")"
h5_pct="$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")"
h5_reset="$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")"
d7_pct="$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")"
think_level="$(jq -r '.effort.level // empty' <<<"$input")"   # live thinking level (newer field)

# --- ANSI palette ---
ESC=$'\033'
reset="${ESC}[0m"; dim="${ESC}[2m"
C_GREEN="${ESC}[32m"; C_YELLOW="${ESC}[33m"; C_RED="${ESC}[31m"; C_COOL="${ESC}[38;5;141m"  # light violet (EVA-01 初号机-ish); tweak 141 → 99 deeper / 183 lighter

# --- helpers ---
# on VAR DEFAULT(0/1): true if the toggle is enabled
on() {
  local v="${!1}"
  if [ -z "$v" ]; then [ "$2" = "1" ]; return $?; fi
  [ "$v" != "0" ]
}
# meter PCT LABEL PALETTE(warm|cool): a 3-char-labelled 20-cell bar, colored
# by zone (red >=80, yellow 60-79, else green[warm]/cyan[cool]); filled cells
# in the zone color, empty cells dimmed. Labels pad to 3 so stacked bars align.
meter() {
  local p="$1" label="$2" palette="$3" c cells=20 filled i fb="" eb=""
  if   [ "$p" -ge 80 ]; then c="$C_RED"
  elif [ "$p" -ge 60 ]; then c="$C_YELLOW"
  elif [ "$palette" = cool ]; then c="$C_COOL"
  else                          c="$C_GREEN"
  fi
  filled=$(( p * cells / 100 ))
  [ "$filled" -gt "$cells" ] && filled="$cells"
  [ "$filled" -lt 0 ] && filled=0
  i=0
  while [ "$i" -lt "$cells" ]; do
    if [ "$i" -lt "$filled" ]; then fb="${fb}█"; else eb="${eb}░"; fi
    i=$((i+1))
  done
  printf '%s%-3s %s%s%s%s %s%d%%%s' "$c" "$label" "$c" "$fb" "$dim" "$eb" "$c" "$p" "$reset"
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
# fmt_dur MS: milliseconds as "Xh Ym" / "Nm" / "Ns"
fmt_dur() {
  local s=$(( $1 / 1000 ))
  if   [ "$s" -ge 3600 ]; then printf '%dh%dm' $(( s/3600 )) $(( (s%3600)/60 ))
  elif [ "$s" -ge 60 ];   then printf '%dm' $(( s/60 ))
  else                         printf '%ds' "$s"
  fi
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

# --- line 1: context core (warm meter + token/branch/model/thinking) ---
line1="$(meter "$pct_int" "ctx" warm)"
[ -n "$tok" ] && line1="${line1} ${dim}${tok}${reset}"
# ⚠200k+ only matters when the window itself is ~200k; on a 1M-context model
# (size much larger) the fixed 200k flag is noise — suppress it there.
if [ "$over200k" = "true" ] && { [ -z "$size" ] || [ "$size" -le 220000 ]; }; then
  line1="${line1} ${C_RED}⚠200k+${reset}"
fi
[ -n "$branch" ] && line1="${line1} ${dim}⎇ ${branch}${reset}"
[ -n "$model" ] && line1="${line1} ${dim}${model}${reset}"
# current thinking level: stdin .effort.level (live) > ~/.claude settings > skip
if on CLAUDE_SL_THINKING 1; then
  tl="$think_level"
  [ -z "$tl" ] && tl="$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)"
  [ -n "$tl" ] && line1="${line1} ${dim}${CLAUDE_SL_THINK_ICON:-💡}${tl}${reset}"
fi

# --- line 2: budget / usage (cool 5h meter, mirrors line 1; then cost group) ---
# 5-hour usage meter + reset countdown (parallel to the ctx meter, cool color)
h5_seg=""
if on CLAUDE_SL_5H 1 && [ -n "$h5_pct" ]; then
  h5i="${h5_pct%.*}"; [ -z "$h5i" ] && h5i=0
  h5_seg="$(meter "$h5i" "5h" cool)"
  [ -n "$h5_reset" ] && h5_seg="${h5_seg} ${dim}↺$(fmt_reset "${h5_reset%.*}")${reset}"
fi
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
    cs="${cs:+$cs }${C_GREEN}+${la}${reset}/${C_RED}-${ld}${reset}"
  fi
  cost_seg="$cs"
fi
# session wall-clock duration (optional, default off)
dur_seg=""
if on CLAUDE_SL_DURATION 0 && [ -n "$dur_ms" ] && [ "$dur_ms" -gt 0 ] 2>/dev/null; then
  dur_seg="${dim}⏱$(fmt_dur "$dur_ms")${reset}"
fi
# 7-day (weekly) usage — compact, zone-colored
d7_seg=""
if on CLAUDE_SL_WEEKLY 0 && [ -n "$d7_pct" ]; then
  d7i="${d7_pct%.*}"; [ -z "$d7i" ] && d7i=0
  if   [ "$d7i" -ge 80 ]; then dc="$C_RED"; elif [ "$d7i" -ge 60 ]; then dc="$C_YELLOW"; else dc="$C_COOL"; fi
  d7_seg="${dc}7d ${d7i}%${reset}"
fi

# assemble line 2: 5h meter as the anchor, cost/weekly as a dim-· separated tail
tail=""
[ -n "$cost_seg" ] && tail="$cost_seg"
[ -n "$dur_seg" ]  && tail="${tail:+$tail  }$dur_seg"
[ -n "$d7_seg" ]   && tail="${tail:+$tail  }$d7_seg"
line2="$h5_seg"
if [ -n "$line2" ] && [ -n "$tail" ]; then
  line2="${line2}  ${dim}│${reset}  ${tail}"
elif [ -n "$tail" ]; then
  line2="$tail"
fi

# --- emit: multi-line when enabled & line 2 has content, else single line ---
if on CLAUDE_SL_MULTILINE 1 && [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  merged="$line1"
  [ -n "$line2" ] && merged="${merged} ${line2}"
  printf '%s' "$merged"
fi
