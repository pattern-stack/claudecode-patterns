#!/usr/bin/env bash
# Tests for plugin/lib/watch.sh: piped output is plain and byte-exact, a TTY gets colour, the heartbeat and the
# human sentences, NO_COLOR and WATCH_PLAIN, the EXIT/INT trap, and typed keys not echoing as ^[.
# The TTY cases run under util-linux `script` (a real pty); they are skipped, not failed, where it is missing.
# Run: bash plugin/lib/watch.test.sh   (exits 0 only when every case that ran passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/watch.sh"
pass=0 fail=0 skip=0
ok()   { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }
skp()  { skip=$((skip+1)); printf '  ↷ %s (skipped: %s)\n' "$1" "$2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset NO_COLOR WATCH_PLAIN
ESC=$'\033'

# A watcher exercising every call. $1 = how it ends: end | fail | exit3 | quiet
cat > "$TMP/w.sh" <<EOF
. "$W"
watch_header "watching the test board" "20 s" "23:50" "hq-5"
watch_beat "check 1 · blocked 0"
watch_line "22:00 publishing main 4f2c1a9"
watch_beat "check 2 · blocked 0"
watch_event ok "22:11 deployed 4f2c1a9; route checks: all ok" "main 4f2c1a9 is live."
watch_event wait "" "recorder didn't update its status file."
watch_event fail "22:31 EVENT blocked: web" "web is blocked on a permission prompt."
case "\${1:-end}" in
  end) watch_end "event fired after 2 checks" ;;
  fail) watch_end --fail "a failure (main red)" ;;
  exit3) exit 3 ;;
  quiet) ;;
esac
EOF

# Run it on a pty; prints what the terminal received.
HAVE_SCRIPT=0
script -q -e -c true /dev/null >/dev/null 2>&1 && HAVE_SCRIPT=1
# What the screen shows: drop the pty's \r before \n, then keep what follows the last \r (a rewritten beat)
on_tty() { script -q -e -c "$1" /dev/null 2>/dev/null | sed $'s/\r$//; s/.*\r//'; }
on_tty_raw() { script -q -e -c "$1" /dev/null 2>/dev/null; }

echo "piped"
GOLD="● watching the test board · every 20 s · until 23:50 · wakes hq-5
22:00 publishing main 4f2c1a9
22:11 deployed 4f2c1a9; route checks: all ok
◐ HH:MM  recorder didn't update its status file.
22:31 EVENT blocked: web
■ stopped: event fired after 2 checks"
out=$(bash "$TMP/w.sh" end | sed -E 's/◐ [0-9]{2}:[0-9]{2}/◐ HH:MM/')
check "byte-exact plain output (machine lines unchanged, sentence only where no machine line)" '[ "$out" = "$GOLD" ]'
check "no escape bytes when piped" '! bash "$TMP/w.sh" end | grep -q "$ESC"'
check "no carriage returns when piped (no heartbeat)" '! bash "$TMP/w.sh" end | grep -q $'"'"'\r'"'"''
out=$(bash "$TMP/w.sh" fail | tail -1)
check "watch_end --fail is plain when piped" '[ "$out" = "■ stopped: a failure (main red)" ]'

echo "exit trap"
out=$(bash "$TMP/w.sh" quiet | tail -1); rc=$?
check "no watch_end, exit 0: the trap says finished" '[ "$out" = "■ stopped: finished" ]'
out=$(bash "$TMP/w.sh" exit3 | tail -1); rc=${PIPESTATUS[0]}
bash "$TMP/w.sh" exit3 >/dev/null; rc=$?
check "exit 3: the trap says so" '[ "$out" = "■ stopped: exited with code 3" ]'
check "exit 3: the exit code is kept" '[ "$rc" = 3 ]'
cat > "$TMP/int.sh" <<EOF
. "$W"
watch_header "waiting to be interrupted"
sleep 5 & wait \$!
EOF
# set -m: without job control bash starts background jobs with SIGINT ignored, and an ignored signal can't be trapped
set -m
bash "$TMP/int.sh" > "$TMP/int.out" & pid=$!
sleep 0.5; kill -INT "$pid"; wait "$pid"; rc=$?
set +m
check "SIGINT: stopped: interrupted" '[ "$(tail -1 "$TMP/int.out")" = "■ stopped: interrupted" ]'
check "SIGINT: exit 130" '[ "$rc" = 130 ]'
bash "$TMP/int.sh" > "$TMP/term.out" & pid=$!
sleep 0.5; kill -TERM "$pid"; wait "$pid"; rc=$?
check "SIGTERM: stopped: terminated, exit 143" '[ "$(tail -1 "$TMP/term.out")" = "■ stopped: terminated" ] && [ "$rc" = 143 ]'

echo "helpers"
check "watch_age seconds" '[ "$(. "$W"; watch_age $(( $(date +%s) - 40 )))" = "40 s ago" ]'
check "watch_age minutes" '[ "$(. "$W"; watch_age $(( $(date +%s) - 190 )))" = "3 min ago" ]'
check "watch_age hours" '[ "$(. "$W"; watch_age $(( $(date +%s) - 7300 )))" = "2 h ago" ]'
check "watch_hhmm" '[ "$(. "$W"; watch_hhmm "$(date -d "today 23:50" +%s)")" = "23:50" ]'

echo "tty"
if [ "$HAVE_SCRIPT" = 1 ]; then
  out=$(on_tty "bash $TMP/w.sh end")
  raw=$(on_tty_raw "bash $TMP/w.sh end")
  check "header is coloured" 'grep -q "^${ESC}\[1;36m● watching the test board" <<<"$out"'
  check "heartbeat is written with \\r and clear-line" 'grep -q $'"'"'\r\033\[2K\033\[2m· '"'"' <<<"$raw"'
  check "the beat is cleared before the next line" 'grep -q $'"'"'check 1 · blocked 0\033\[0m\r\033\[2K22:00 publishing'"'"' <<<"$raw"'
  # a machine line that follows a beat starts with the clear-line (ESC[2K, not a colour): it is otherwise exact
  nobeat=$(sed "s/${ESC}\[2K//g" <<<"$out")
  check "machine lines are uncoloured lines of their own" 'grep -qx "22:31 EVENT blocked: web" <<<"$nobeat" && grep -qx "22:11 deployed 4f2c1a9; route checks: all ok" <<<"$nobeat"'
  check "ok sentence is green" 'grep -q "${ESC}\[32m✓ [0-9:]*  main 4f2c1a9 is live." <<<"$out"'
  check "wait sentence is yellow" 'grep -q "${ESC}\[33m◐ " <<<"$out"'
  check "fail sentence is red, after its machine line" 'grep -A1 -x "22:31 EVENT blocked: web" <<<"$out" | grep -q "${ESC}\[31m✗ "'
  check "stopped line is dim" 'grep -q "${ESC}\[2m■ stopped: event fired after 2 checks" <<<"$out"'
  out=$(on_tty "bash $TMP/w.sh fail")
  check "watch_end --fail is red" 'grep -q "${ESC}\[31m■ stopped: a failure" <<<"$out"'
  out=$(on_tty_raw "NO_COLOR=1 bash $TMP/w.sh end")
  check "NO_COLOR: no SGR colour codes" '! grep -qE "${ESC}\[[0-9;]*m" <<<"$out"'
  check "NO_COLOR: heartbeat and sentences stay (they are TTY features, not colour)" 'grep -q "· [0-9:]*  check 2" <<<"$out" && grep -q "✓ [0-9:]*  main" <<<"$out"'
  plain=$(bash "$TMP/w.sh" end | sed -E 's/[0-9]{2}:[0-9]{2}  /HH:MM  /')
  out=$(on_tty "WATCH_PLAIN=1 bash $TMP/w.sh end" | sed -E 's/[0-9]{2}:[0-9]{2}  /HH:MM  /')
  check "WATCH_PLAIN=1 on a TTY equals the piped output" '[ "$out" = "$plain" ]'

  # Typed keys: the baseline (no helper) proves this pty echoes Escape as ^[; the helper stops it.
  printf 'sleep 1.5; echo done\n' > "$TMP/raw.sh"
  printf '. "%s"; watch_header "keys"; sleep 1.5; echo done\n' "$W" > "$TMP/keys.sh"
  base=$( (sleep 0.5; printf '\033x') | script -q -e -c "bash $TMP/raw.sh" /dev/null 2>/dev/null)
  out=$( (sleep 0.5; printf '\033x') | script -q -e -c "bash $TMP/keys.sh" /dev/null 2>/dev/null)
  if grep -qF '^[' <<<"$base"; then
    check "typed Escape does not echo as ^[" '! grep -qF "^[" <<<"$out" && ! grep -q "x" <<<"$(grep -v "keys\|stopped" <<<"$out")"'
  else
    skp "typed Escape does not echo as ^[" "this pty does not echo, nothing to prove"
  fi
  printf '. "%s"; watch_header "echo restored"\n' "$W" > "$TMP/restore.sh"
  out=$(script -q -e -c "bash $TMP/restore.sh; stty -a" /dev/null 2>/dev/null)
  check "echo is back on after the watcher exits" 'grep -qE "(^| )echo( |$)" <<<"$out" && ! grep -qE "(^| )-echo( |$)" <<<"$out"'
else
  for n in colour heartbeat sentences NO_COLOR WATCH_PLAIN keys; do skp "tty: $n" "util-linux script not found"; done
fi

echo
echo "watch.sh: $pass passed, $fail failed, $skip skipped"
[ "$fail" = 0 ]
