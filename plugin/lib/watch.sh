# watch.sh: make a watcher's or loop's pane readable to a person who opens it.
# Source it from a bash script:   . "$PLUGIN/lib/watch.sh"
# Convention and examples: plugin/skills/skill-authoring/watchers.md
#
#   watch_header <what> <every> <until> <wakes>   ● line; stops typed keys from echoing (^[); installs the EXIT trap
#   watch_beat <text>                             dim line rewritten in place (TTY only; nothing when piped)
#   watch_line <text>                             a plain line (step lines, machine lines), clearing the beat first
#   watch_event <ok|wait|fail> <machine> <human>  the machine line exactly as given, then (TTY only) a coloured sentence
#   watch_end [--fail] <why>                      ■ stopped: <why>   (the EXIT trap writes one if you didn't)
#   watch_hhmm <epoch>  watch_age <epoch>         23:50   ·   "40 s ago" / "3 min ago" / "2 h ago"
#
# Output rules. The machine line is never coloured or changed, so parents keep matching it by content.
# Heartbeat and human sentences: only when stdout is a TTY (and WATCH_PLAIN is not 1).
# Colour: only on a TTY with NO_COLOR unset. Piped or logged, the output is the header, the machine lines and
# the stopped line, as plain text.

# _watch_mode sets _W_TTY and _W_COLOR. Every public function calls it first, in the caller's shell: inside a
# $(...) stdout is a pipe, so [ -t 1 ] there would always say "not a TTY".
_watch_mode() {
  _W_TTY=0 _W_COLOR=0
  if [ -t 1 ] && [ "${WATCH_PLAIN:-0}" != 1 ]; then
    _W_TTY=1
    [ -z "${NO_COLOR:-}" ] && _W_COLOR=1
  fi
  return 0
}
_watch_tty() { [ "${_W_TTY:-0}" = 1 ]; }
# _watch_sgr <code>: an SGR escape when colour is on, else nothing (safe inside $(...): reads _W_COLOR)
_watch_sgr() { [ "${_W_COLOR:-0}" = 1 ] && printf '\033[%sm' "$1"; return 0; }

_WATCH_BEAT=0 _WATCH_ENDED=0 _WATCH_STTY="" _WATCH_TTYFD=""

_watch_clear_beat() {
  if [ "$_WATCH_BEAT" = 1 ]; then printf '\r\033[2K'; _WATCH_BEAT=0; fi
}

watch_hhmm() { date -d "@$1" +%H:%M; }

watch_age() {
  local s=$(( $(date +%s) - $1 ))
  [ "$s" -lt 0 ] && s=0
  if [ "$s" -lt 60 ]; then echo "$s s ago"
  elif [ "$s" -lt 3600 ]; then echo "$(( s / 60 )) min ago"
  else echo "$(( s / 3600 )) h ago"; fi
}

watch_header() {
  _watch_mode
  local what=$1 every=${2:-} until=${3:-} wakes=${4:-} rest=""
  [ -n "$every" ] && rest+=" · every $every"
  [ -n "$until" ] && rest+=" · until $until"
  [ -n "$wakes" ] && rest+=" · wakes $wakes"
  # Typed keys: nobody reads stdin, and with echo off Escape no longer prints ^[ into the pane.
  if [ -t 0 ]; then
    _WATCH_STTY=$(stty -g 2>/dev/null) && stty -echo 2>/dev/null
    exec {_WATCH_TTYFD}<&0 </dev/null  # keep the terminal on a spare fd, only to restore echo at exit
  fi
  trap '_watch_on_exit $?' EXIT
  trap '_WATCH_WHY=interrupted; exit 130' INT
  trap '_WATCH_WHY=terminated; exit 143' TERM
  printf '%s● %s%s%s%s%s\n' "$(_watch_sgr '1;36')" "$what" "$(_watch_sgr 0)" "$(_watch_sgr 2)" "$rest" "$(_watch_sgr 0)"
}

watch_beat() {
  _watch_mode
  _watch_tty || return 0
  printf '\r\033[2K%s· %s  %s%s' "$(_watch_sgr 2)" "$(date +%H:%M:%S)" "$1" "$(_watch_sgr 0)"
  _WATCH_BEAT=1
}

watch_line() {
  _watch_mode
  _watch_clear_beat
  printf '%s\n' "$1"
}

watch_event() {
  _watch_mode
  local kind=$1 machine=$2 human=${3:-} mark code
  case $kind in
    ok) mark='✓' code=32 ;;
    wait) mark='◐' code=33 ;;
    fail) mark='✗' code=31 ;;
    *) mark='•' code=0 ;;
  esac
  [ -n "$machine" ] && watch_line "$machine"
  if [ -n "$human" ] && { _watch_tty || [ -z "$machine" ]; }; then
    _watch_clear_beat
    printf '%s%s %s  %s%s\n' "$(_watch_sgr "$code")" "$mark" "$(date +%H:%M)" "$human" "$(_watch_sgr 0)"
  fi
  return 0
}

watch_end() {
  _watch_mode
  local code=2
  [ "${1:-}" = --fail ] && { code=31; shift; }
  _watch_clear_beat
  printf '%s■ stopped: %s%s\n' "$(_watch_sgr "$code")" "$1" "$(_watch_sgr 0)"
  _WATCH_ENDED=1
}

_watch_restore_tty() {
  if [ -n "$_WATCH_STTY" ] && [ -n "$_WATCH_TTYFD" ]; then stty "$_WATCH_STTY" <&"$_WATCH_TTYFD" 2>/dev/null; fi
  _WATCH_STTY=""
}

_watch_on_exit() {
  local rc=$1
  if [ "$_WATCH_ENDED" != 1 ]; then
    if [ -n "${_WATCH_WHY:-}" ]; then watch_end --fail "$_WATCH_WHY"
    elif [ "$rc" = 0 ]; then watch_end "finished"
    else watch_end --fail "exited with code $rc"; fi
  fi
  _watch_restore_tty
  return "$rc"
}
