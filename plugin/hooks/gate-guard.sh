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
# Anchor `gh pr merge` to a *command position* — start of the command, or right
# after a shell separator / newline (`;` `&&` `||` `|` `(`). This fires on a real
# invocation but NOT on the flag string appearing inside a quoted argument (a PR
# `--body`, a `git commit -m` message) or a heredoc. Without the anchor,
# `gh pr create --body "...gh pr merge --admin..."` — e.g. docs that *describe*
# the flag — was falsely blocked. `--admin` / `-A` are matched as flag tokens.
if printf '%s' "$CMD" | grep -Eq '(^|[;&|(])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq -- '(^|[[:space:]])(--admin([[:space:]]|=|$)|-A([[:space:]]|$))'; then
    deny "SDLC gate-guard: \`gh pr merge --admin\` bypasses branch protection and Gate 2 (human PR review). Merge through the normal review path, or set SDLC_GATE_OVERRIDE=1 for a deliberate exception."
  fi
fi

# --- Rule 1: git push to the default branch (main / master) --------------------
# Match a push whose *own target ref* is main/master. Two conditions, in ONE
# regex, are both required:
#   (a) `git push` sits at a command position — start of line or right after a
#       shell separator (`;` `&&` `||` `|` `&` `(`). This is what lets a PR or
#       commit *body* that merely describes a push ("…run git push origin
#       main…") pass: there, `git push` is preceded by ordinary text, not a
#       separator, so it is not a real invocation.
#   (b) main/master appears within the SAME statement's args — i.e. only
#       non-separator chars (`[^;&|()]*`) lie between `git push` and the ref.
#       This is the fix for the cross-statement false positive: a sibling
#       command that mentions "main" (`gh pr create --base main`,
#       `git commit -m '…main…'; git push origin feat`) no longer trips the
#       guard, because that "main" is not in the push statement's own args.
# Shapes covered (all still denied):
#   git push origin main | git push origin HEAD:main | git push -f origin master
#   | git push origin develop:main | git push main | … && git push origin main
if printf '%s' "$CMD" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+push[^;&|()]*([[:space:]]|:|HEAD:)(main|master)([[:space:]]|$)'; then
  deny "SDLC gate-guard: pushing to the default branch (main/master) is blocked — work on a feature branch and open a PR (Gate 2). Set SDLC_GATE_OVERRIDE=1 for a deliberate exception."
fi

exit 0
