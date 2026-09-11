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
# What counts as a pre-render mirrors the runtime (Claude Code 2.1.269):
#   inline  (?<=^|\s)!`([^`]+)`        `!` at line start or after whitespace, so
#                                      prose "`!`…``" and "(!`…`)" never run
#   fenced  ```!\s*\n?([\s\S]*?)\n?``` one script; its last command's exit counts
# Code fences are NOT exempt: the inline pattern runs wherever it appears.
#
# The check: a command's LAST `;` / `&&` segment must carry a whitespace-delimited
# ` || `, so `git fetch || true; git log` and `sed 's|a||'` don't pass by accident.
# Fenced blocks are checked line by line — stricter than the runtime, which only
# needs the last line guarded (`#` comment lines are skipped). Keep that direction.
#
# Scope: the files Claude Code renders (skills/*/SKILL.md, commands/*.md,
# agents/*.md) plus templates/*.md — the seeds authors copy, which is how the
# unguarded form spread to seven files. Templates may carry the `!`...`` "replace
# me" placeholder. Frontmatter is skipped. Reference docs and cookbooks are read,
# never rendered, so they are out of scope — keep their examples guarded by hand.
#
# Usage:  just sdlc::verify-preflight-shell   (or bash plugin/scripts/verify-preflight-shell.sh [plugin-root])
# Exit:   0 = every pre-render guarded, 1 = unguarded pre-render found, 2 = config error
set -euo pipefail

PLUGIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
if ! cd "$PLUGIN_ROOT" 2>/dev/null; then
  echo "❌ Plugin root not found: $PLUGIN_ROOT" >&2
  exit 2
fi

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find skills commands agents -type f -name '*.md' \
    \( -name SKILL.md -o -path 'commands/*' -o -path 'agents/*' -o -path '*/templates/*' \) \
    2>/dev/null | LC_ALL=C sort
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "❌ No renderable files (skills/*/SKILL.md, commands/, agents/) under $PLUGIN_ROOT — wrong plugin root?" >&2
  exit 2
fi

unguarded=$(awk '
  function guarded(cmd,   n, seg) {
    n = split(cmd, seg, /;|&&/)
    return seg[n] ~ /[[:space:]][|][|][[:space:]]/
  }
  function report(cmd) {
    if (FILENAME ~ /\/templates\// && (cmd == "..." || cmd == "…")) return
    printf "   %s:%d: %s\n", FILENAME, FNR, cmd
  }
  { sub(/\r$/, "") }
  FNR == 1 { infm = ($0 == "---"); fence = 0; if (infm) next }
  infm { if ($0 == "---") infm = 0; next }
  fence {
    if ($0 ~ /^[[:space:]]*```/) { fence = 0; next }
    if ($0 ~ /^[[:space:]]*(#|$)/) next
    if (!guarded($0)) report($0)
    next
  }
  /^[[:space:]]*```!/ { fence = 1; next }
  {
    line = $0
    while (match(line, /(^|[[:space:]])!`[^`]+`/)) {
      cmd = substr(line, RSTART, RLENGTH)
      sub(/^[[:space:]]*!`/, "", cmd); sub(/`$/, "", cmd)
      if (!guarded(cmd)) report(cmd)
      line = substr(line, RSTART + RLENGTH)
    }
  }
' "${files[@]}")

if [[ -n "$unguarded" ]]; then
  {
    echo "❌ Unguarded \`!\` pre-render(s) — a non-zero exit aborts the whole skill/command:"
    echo "$unguarded"
    echo "   End each with a fallback: <cmd> 2>/dev/null || echo \"(<what the empty state means>)\"."
    echo "   git / gh / st all fail outside a repository. See CHANGELOG 0.2.27 (#119)."
  } >&2
  exit 1
fi

echo "✅ preflight-shell: every \`!\` pre-render in ${#files[@]} renderable files has a || fallback"
exit 0
