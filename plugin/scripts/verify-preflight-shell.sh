#!/usr/bin/env bash
# Verify every `!`…`` pre-render the plugin ships has a `||` fallback.
#
# A pre-render that exits non-zero ABORTS the whole skill/command invocation:
# Claude never sees the body and the user gets only "Shell command failed for
# pattern ...". Outside a git repository every git / gh / st command exits
# non-zero, so one unguarded `!`git branch --show-current`` made /prime unusable
# from any non-git folder (#119, fixed in 0.2.27). The fix is the idiom /prime
# already used for `st status`:
#
#   !`git branch --show-current 2>/dev/null || echo "(not a git repository)"`
#
# The fallback text is what Claude reads, so it should name the state.
#
# Scope: the files Claude Code renders (skills/*/SKILL.md, commands/*.md,
# agents/*.md) plus templates/*.md — the seeds authors copy, which is how the
# unguarded form spread to seven files. Code fences are NOT exempt: the pattern
# runs wherever it appears in the body. Frontmatter is skipped, and so are
# reference docs that only describe the syntax (they are read, never rendered).
#
# Usage:  just sdlc::verify-preflight-shell   (or bash plugin/scripts/verify-preflight-shell.sh [plugin-root])
# Exit:   0 = every pre-render guarded, 1 = unguarded pre-render found
set -euo pipefail

PLUGIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PLUGIN_ROOT"

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find skills commands agents -type f -name '*.md' \
    \( -name SKILL.md -o -path 'commands/*' -o -path 'agents/*' -o -path '*/templates/*' \) \
    2>/dev/null | sort
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "✅ preflight-shell: no renderable files under $PLUGIN_ROOT"
  exit 0
fi

# Inline form: `!` at line start or after whitespace, then a backtick span.
# (`!` preceded by a backtick — prose like "`!`...`` injection" — is not a
# pre-render.) Fenced form: a ```! block; every non-blank line is a command.
# Templates may carry the `!`...`` placeholder (an author replaces it); in a
# rendered file the same placeholder would really run, so it stays flagged there.
unguarded=$(awk '
  function report(cmd) {
    if (FILENAME ~ /\/templates\// && (cmd == "..." || cmd == "…")) return
    printf "   %s:%d: %s\n", FILENAME, FNR, cmd
  }
  FNR == 1 { infm = ($0 == "---"); fence = 0; if (infm) next }
  infm { if ($0 == "---") infm = 0; next }
  fence {
    if ($0 ~ /^[[:space:]]*```/) { fence = 0; next }
    if ($0 ~ /[^[:space:]]/ && index($0, "||") == 0) report($0)
    next
  }
  /^[[:space:]]*```!/ { fence = 1; next }
  {
    line = $0
    while (match(line, /(^|[[:space:]])!`[^`]+`/)) {
      cmd = substr(line, RSTART, RLENGTH)
      sub(/^[[:space:]]*!`/, "", cmd); sub(/`$/, "", cmd)
      if (index(cmd, "||") == 0) report(cmd)
      line = substr(line, RSTART + RLENGTH)
    }
  }
' "${files[@]}")

if [[ -n "$unguarded" ]]; then
  {
    echo "❌ Unguarded \`!\` pre-render(s) — a non-zero exit aborts the whole skill/command:"
    echo "$unguarded"
    echo "   Add a fallback: <cmd> 2>/dev/null || echo \"(<what the empty state means>)\"."
    echo "   git / gh / st all fail outside a repository. See CHANGELOG 0.2.27 (#119)."
  } >&2
  exit 1
fi

echo "✅ preflight-shell: every \`!\` pre-render in ${#files[@]} renderable files has a || fallback"
exit 0
