#!/usr/bin/env bash
# gate-guard.sh — PreToolUse hook that hard-blocks the two never-correct
# merge-bypass actions, so the SDLC "human gate before merge" guarantee is
# enforced control flow rather than a narrative "Do NOT" the lead might skip
# under load or in a long autonomous loop.
#
# Blocks (deny):
#   1. `git push` targeting the default branch (main / master) — implementer
#      and specifier both state "never push to main"; this enforces it.
#   2. `gh pr merge ... --admin` — admin-merge bypasses branch protection and
#      review (Gate 2), defeating the human gate.
#
# Escape hatch: set SDLC_GATE_OVERRIDE=1 in the environment for a deliberate,
# human-authorized exception.
#
# Design notes:
# - Matches only on the Bash tool. Other tools pass through untouched.
# - FAILS OPEN: if stdin can't be parsed (no jq + no python3, malformed JSON),
#   it allows the call. A guard must never wedge the user's shell — it is a
#   backstop to the narrative rules, not the sole line of defence.
# - Output contract: PreToolUse deny via
#   { "hookSpecificOutput": { "hookEventName": "PreToolUse",
#     "permissionDecision": "deny", "permissionDecisionReason": "..." } }
#   Allow == exit 0 with no stdout. Wired in plugin/hooks/hooks.json.

set -u

# Deliberate override — human-authorized exception.
if [ "${SDLC_GATE_OVERRIDE:-}" = "1" ]; then
  exit 0
fi

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

# Extract tool name + command string. Prefer jq, fall back to python3, else
# fail open (allow) — never block on a parse failure.
TOOL=""
CMD=""
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_name",""))' 2>/dev/null)"
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
else
  exit 0
fi

# Only Bash commands carry merge/push actions.
[ "$TOOL" = "Bash" ] || exit 0
[ -z "$CMD" ] && exit 0

deny() {
  # $1 = reason (single line)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# --- Rule 2: gh pr merge --admin (and -A short flag) ---------------------------
if printf '%s' "$CMD" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge'; then
  if printf '%s' "$CMD" | grep -Eq -- '(--admin|[[:space:]]-A([[:space:]]|$))'; then
    deny "SDLC gate-guard: \`gh pr merge --admin\` bypasses branch protection and Gate 2 (human PR review). Merge through the normal review path, or set SDLC_GATE_OVERRIDE=1 for a deliberate exception."
  fi
fi

# --- Rule 1: git push to the default branch (main / master) --------------------
# Match a push whose ref token is main/master in the common shapes:
#   git push origin main | git push origin HEAD:main | git push -f origin master
#   git push origin :main (delete is allowed — skip) is NOT matched below.
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+push'; then
  # Push args that name main/master as the *target* branch.
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(main|master)([[:space:]]|$)|(:|HEAD:)(main|master)([[:space:]]|$)'; then
    deny "SDLC gate-guard: pushing to the default branch (main/master) is blocked — work on a feature branch and open a PR (Gate 2). Set SDLC_GATE_OVERRIDE=1 for a deliberate exception."
  fi
fi

exit 0
