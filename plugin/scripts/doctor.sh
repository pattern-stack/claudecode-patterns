#!/usr/bin/env bash
# doctor.sh — sdlc environment & config health checks.
#
# Surfaces Claude Code / sdlc misconfigurations that silently break the harness,
# so a footgun shows up as a named finding instead of a cryptic mid-session error.
#
# Modes:
#   doctor.sh                 Human-readable report of all checks.
#                             Exit: 0 = clean, 1 = error finding(s), 2 = environment error.
#   doctor.sh --hook <Event>  Quiet guard for hooks. Emits ONE
#                             hookSpecificOutput.additionalContext JSON only when an
#                             ERROR-severity finding exists; silent otherwise. ALWAYS
#                             exits 0 — a passive health check must never block a prompt.
#
# Checks (each is a check_<name> fn appending "SEV<TAB>file<TAB>detail" to FINDINGS):
#   1. worktreecreate-provider — WorktreeCreate is a PROVIDER hook: a registered hook
#      REPLACES the built-in `git worktree add` and must print the created worktree path
#      to stdout, synchronously. A passive (async / telemetry-emitter) registration
#      returns no path and breaks every `isolation:"worktree"` Agent spawn with
#      "WorktreeCreate hook failed: hook succeeded but returned no worktree path".
#      (See CHANGELOG 0.2.14 / claude-platform/reference/settings.md.)
#
# To add a check: write check_<name>, append findings via add_finding, and call it
# from the "run checks" block. ERROR = definitively broken; INFO = worth a human look.
#
# Invoke:  just sdlc::doctor   |   bash plugin/scripts/doctor.sh
# Requires: jq.
#
# NOTE: -e is intentionally OFF so every check runs even when a sub-command returns
# non-zero (e.g. grep with no match).
set -uo pipefail

MODE="report"
EVENT="UserPromptSubmit"
if [[ "${1:-}" == "--hook" ]]; then
  MODE="hook"
  EVENT="${2:-UserPromptSubmit}"
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# User-editable hook config sources — where misconfigurations actually land.
# Plugin-shipped hooks under ~/.claude/plugins/cache/** are intentionally NOT scanned:
# several cached versions coexist and only the enabled one is live, so scanning them
# yields false positives. Plugin authors validate their own hooks.json in CI.
HOOK_SOURCES=(
  "$PROJECT_ROOT/.claude/settings.json"
  "$PROJECT_ROOT/.claude/settings.local.json"
  "$PROJECT_ROOT/hooks/hooks.json"
  "$HOME/.claude/settings.json"
)

# Resolve to existing files, de-duplicated by canonical path so the same file reached
# via two entries (e.g. project root == $HOME) is scanned once. Bash-3.2 safe: no
# associative arrays, no realpath.
SCAN_FILES=()
for f in "${HOOK_SOURCES[@]}"; do
  [[ -f "$f" ]] || continue
  d=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || d=$(dirname "$f")
  rp="$d/$(basename "$f")"
  dup=""
  for s in ${SCAN_FILES[@]+"${SCAN_FILES[@]}"}; do
    [[ "$s" == "$rp" ]] && { dup=1; break; }
  done
  [[ -n "$dup" ]] || SCAN_FILES+=("$rp")
done

# Nothing to scan → clean by definition.
if [[ ${#SCAN_FILES[@]} -eq 0 ]]; then
  [[ "$MODE" == "hook" ]] && exit 0
  printf 'sdlc doctor — config health\n\n  ✅ worktreecreate-provider — no hook config files found to scan\n\nResult: all checks passed.\n'
  exit 0
fi

# Fast path for hook mode: if "WorktreeCreate" appears in none of the sources, bail
# instantly with no jq cost (keeps the per-prompt UserPromptSubmit hook near-free).
if [[ "$MODE" == "hook" ]]; then
  grep -q "WorktreeCreate" "${SCAN_FILES[@]}" 2>/dev/null || exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  [[ "$MODE" == "hook" ]] && exit 0   # never block a prompt; just stay quiet
  echo "❌ doctor: jq not installed (brew install jq)" >&2
  exit 2
fi

# FINDINGS: newline-separated "SEV<TAB>file<TAB>detail"
FINDINGS=""
add_finding() { FINDINGS+="${1}"$'\t'"${2}"$'\t'"${3}"$'\n'; }

check_worktreecreate_provider() {
  local f async cmd
  for f in "${SCAN_FILES[@]}"; do
    while IFS=$'\t' read -r async cmd; do
      [[ -z "${async}${cmd}" ]] && continue
      if [[ "$async" == "true" ]]; then
        add_finding "ERROR" "$f" "WorktreeCreate → ${cmd} (async:true) — an async provider hook can never return the worktree path."
      elif [[ "$cmd" =~ emit\.(sh|mjs|js|py) ]]; then
        add_finding "ERROR" "$f" "WorktreeCreate → ${cmd} — looks like a passive telemetry emitter; it returns no worktree path."
      else
        add_finding "INFO" "$f" "WorktreeCreate → ${cmd} — custom provider; ensure it creates the worktree and prints its path to stdout, synchronously."
      fi
    done < <(jq -r '
      (.hooks.WorktreeCreate // [])[]
      | .hooks[]?
      | select(.type=="command")
      | [((.async // false)|tostring), (.command // "")]
      | @tsv' "$f" 2>/dev/null)
  done
}

# ── run checks ────────────────────────────────────────────────────────
check_worktreecreate_provider
# (future checks go here)

ERR_COUNT=$(printf '%s' "$FINDINGS" | grep -c $'^ERROR\t' || true)
INFO_COUNT=$(printf '%s' "$FINDINGS" | grep -c $'^INFO\t' || true)

# ── hook mode: speak only on ERROR ──────────────────────────────────────
if [[ "$MODE" == "hook" ]]; then
  [[ "${ERR_COUNT:-0}" -gt 0 ]] || exit 0
  first_file=$(printf '%s' "$FINDINGS" | awk -F'\t' '$1=="ERROR"{print $2; exit}')
  msg="⚠️ sdlc doctor: a WorktreeCreate hook in ${first_file} is registered as a passive/async telemetry emitter. WorktreeCreate is a PROVIDER hook — it must create the worktree and print its path to stdout synchronously. As registered it returns no path and breaks every \`isolation:\"worktree\"\` Agent spawn (symptom: 'WorktreeCreate hook failed: hook succeeded but returned no worktree path'). Fix: remove the WorktreeCreate registration (keep WorktreeRemove, which is observer-safe). Run /sdlc:doctor for the full report."
  jq -cn --arg event "$EVENT" --arg ctx "$msg" \
    '{hookSpecificOutput:{hookEventName:$event, additionalContext:$ctx}}'
  exit 0
fi

# ── report mode ─────────────────────────────────────────────────────────
echo "sdlc doctor — config health"
echo
if [[ -z "$FINDINGS" ]]; then
  echo "  ✅ worktreecreate-provider — no WorktreeCreate provider-hook misconfiguration"
  echo
  echo "Result: all checks passed."
  exit 0
fi

printf '%s' "$FINDINGS" | while IFS=$'\t' read -r sev file detail; do
  [[ -z "$sev" ]] && continue
  case "$sev" in
    ERROR) icon="❌ ERROR";;
    INFO)  icon="ℹ️  INFO ";;
    *)     icon="   $sev ";;
  esac
  printf '  %s  %s\n            %s\n' "$icon" "$file" "$detail"
done
echo
echo "Result: ${ERR_COUNT:-0} error(s), ${INFO_COUNT:-0} info."
if [[ "${ERR_COUNT:-0}" -gt 0 ]]; then
  echo "Fix the WorktreeCreate error(s) above: remove the registration (keep WorktreeRemove)."
  exit 1
fi
exit 0
