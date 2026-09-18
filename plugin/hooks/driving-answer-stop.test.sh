#!/usr/bin/env bash
# Tests for driving-answer-stop.sh. Run: bash plugin/hooks/driving-answer-stop.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/driving-answer-stop.sh"
pass=0 fail=0
build_input() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
stops() { build_input "$1" | bash "$HOOK" 2>/dev/null | grep -q '"continue": false'; }
check() { # $1=command $2=expect(stop|go) $3=label
  if stops "$1"; then got=stop; else got=go; fi
  if [ "$got" = "$2" ]; then pass=$((pass+1)); printf '  ✓ %s\n' "$3"; else fail=$((fail+1)); printf '  ✗ %s — expected %s, got %s\n' "$3" "$2" "$got"; fi
}
check 'herdr pane send-text "$HERDR_PANE_ID" "/sdlc:answer" && herdr pane send-keys "$HERDR_PANE_ID" enter' stop 'the answer queue → stop'
check 'herdr pane send-text w11:p3 "/sdlc:answer"' stop 'queue on an explicit pane → stop'
check $'herdr pane send-text "$HERDR_PANE_ID" $\'\\e[O\' && sleep 0.3 && herdr pane send-text "$HERDR_PANE_ID" "/sdlc:answer" && herdr pane send-keys "$HERDR_PANE_ID" enter' stop 'focus-out then the queue → stop'
check $'herdr pane send-text "$HERDR_PANE_ID" $\'\\e[O\'' go 'focus-out alone → carry on'
check 'herdr pane send-text w11:p3 "/reload-plugins"' go 'other text into a pane → carry on'
check 'herdr agent prompt builder "run the tests"' go 'driving another agent → carry on'
check 'echo /sdlc:answer' go 'mentioning the command without herdr → carry on'
if printf 'not json' | bash "$HOOK" | grep -q .; then fail=$((fail+1)); echo '  ✗ malformed input produced output'; else pass=$((pass+1)); echo '  ✓ malformed input → no output (fails open)'; fi
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
