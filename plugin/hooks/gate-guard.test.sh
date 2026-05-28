#!/usr/bin/env bash
# Tests for gate-guard.sh — the PreToolUse merge/push guard.
# Dependency-light: needs `jq` OR `python3` to build the input JSON (same deps
# the hook itself uses). Run: bash plugin/hooks/gate-guard.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/gate-guard.sh"
pass=0 fail=0

# Build the PreToolUse stdin payload for a given command + tool.
build_input() { # $1=command  $2=tool(default Bash)
  local cmd="$1" tool="${2:-Bash}"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg t "$tool" --arg c "$cmd" '{tool_name:$t, tool_input:{command:$c}}'
  else
    python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$tool" "$cmd"
  fi
}
run() { build_input "$1" "${2:-Bash}" | bash "$HOOK" 2>/dev/null; }   # $3 unused
denied() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

ok()   { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }
assert_deny()  { if denied "$(run "$1")"; then ok "$2"; else bad "$2 — expected DENY, got allow"; fi; }
assert_allow() { if denied "$(run "$1")"; then bad "$2 — expected ALLOW, got deny"; else ok "$2"; fi; }

echo "Rule 2 — gh pr merge --admin:"
assert_deny  'gh pr merge 5 --admin'                              'real admin merge → deny'
assert_deny  'gh pr merge 5 --squash --delete-branch --admin'    'admin among other flags → deny'
assert_deny  'gh pr merge 5 -A'                                   'short -A flag → deny'
assert_deny  'foo && gh pr merge 5 --admin'                       'admin merge after && → deny'
assert_allow 'gh pr merge 5 --squash --delete-branch'            'normal merge (no admin) → allow'
# The regression this fix is about: the flag string inside a quoted arg / prose.
assert_allow 'gh pr create --base main --body "see: gh pr merge --admin (blocked)"' 'PR body mentioning the flag → allow'
assert_allow 'git commit -m "doc: explain gh pr merge --admin behavior"'            'commit msg mentioning the flag → allow'
assert_allow 'echo "run gh pr merge 5 --admin to bypass"'                            'echo mentioning the flag → allow'

echo "Rule 1 — push to default branch:"
assert_deny  'git push origin main'                              'push to main → deny'
assert_deny  'git push -f origin master'                         'force push to master → deny'
assert_deny  'git push origin HEAD:main'                         'push HEAD:main → deny'
assert_allow 'git push origin docs/agent-governance'            'push to feature branch → allow'
assert_allow 'git push -u origin dug/observability'            'push to namespaced feature branch → allow'
assert_allow 'git commit -m "will merge to main after review"'  'commit msg mentioning main → allow'

echo "Cross-cutting:"
assert_allow 'rm -rf /tmp/whatever'                              'unrelated command → allow'
# Override: same dangerous command, with the human-set env var.
if denied "$(build_input 'gh pr merge 5 --admin' | SDLC_GATE_OVERRIDE=1 bash "$HOOK" 2>/dev/null)"; then
  bad 'SDLC_GATE_OVERRIDE=1 → allow'
else ok 'SDLC_GATE_OVERRIDE=1 → allow'; fi
# Non-Bash tool passes through (same dangerous string, tool=Edit → allow).
if denied "$(run 'gh pr merge 5 --admin' Edit)"; then bad 'non-Bash (Edit) tool → allow'; else ok 'non-Bash (Edit) tool → allow'; fi

echo
printf 'gate-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
