#!/usr/bin/env bash
# Verify the plugin's OWN hooks.json never registers a WorktreeCreate hook.
#
# WorktreeCreate has PROVIDER semantics: a registered hook REPLACES the built-in
# `git worktree add` and must create the worktree and return its path. The plugin's
# telemetry shim (emit.sh) returns nothing, so registering it here shadows the default
# and breaks EVERY `isolation:"worktree"` Agent spawn harness-wide — shipped that way in
# 0.2.12, removed in 0.2.13. This invariant stops it from sneaking back in on a future
# "emit on every event" edit.
#
# Plugin policy: never register WorktreeCreate — worktrees stay harness-managed under
# .claude/worktrees/. WorktreeRemove is observer-safe and allowed.
#
# (Consumer-project configs are checked at runtime by `/sdlc:doctor`; this guards the
# plugin's own shipped hooks, which doctor deliberately does not scan.)
#
# Usage:  just sdlc::verify-worktree-hooks   (or bash plugin/scripts/verify-worktree-hooks.sh)
# Exit:   0 = clean, 1 = WorktreeCreate registered, 2 = config error
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$PLUGIN_ROOT/hooks/hooks.json"

if [[ ! -f "$HOOKS" ]]; then
  echo "❌ Missing $HOOKS" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not installed (brew install jq)" >&2
  exit 2
fi

count=$(jq '(.hooks.WorktreeCreate // []) | length' "$HOOKS" 2>/dev/null) || {
  echo "❌ Could not parse $HOOKS" >&2
  exit 2
}

if [[ "$count" -gt 0 ]]; then
  {
    echo "❌ hooks/hooks.json registers a WorktreeCreate hook (${count} matcher group(s))."
    echo "   WorktreeCreate is a PROVIDER hook: the registered command replaces the built-in"
    echo "   \`git worktree add\` and must print the created worktree path to stdout. The plugin's"
    echo "   emit.sh telemetry shim returns no path → every isolation:\"worktree\" Agent spawn"
    echo "   breaks harness-wide (the 0.2.12 outage). Remove the WorktreeCreate entry."
    echo "   WorktreeRemove (observer-safe) is fine. See CHANGELOG 0.2.13 + the hooks.json"
    echo "   description carve-out + claude-platform/reference/settings.md."
  } >&2
  exit 1
fi

echo "✅ worktree-hooks: hooks.json registers no WorktreeCreate provider hook"
exit 0
