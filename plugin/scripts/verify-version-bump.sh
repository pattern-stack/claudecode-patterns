#!/usr/bin/env bash
# Fails when files under plugin/ changed but plugin/.claude-plugin/plugin.json
# `version` did not. The version field is what triggers Claude Code's
# `/plugin update` to refresh the cache for existing consumers — merging
# plugin changes without a bump silently strands users.
#
# Plugin-dev only. No-op outside the plugin source tree, so it's safe even
# if a user's `just sdlc::verify` ever picks it up.
#
# Comparison base:
#   - In a PR run:    $GITHUB_BASE_REF (e.g. main) — set by GitHub Actions.
#   - Local default:  origin/main.
#   - Fallback:       HEAD~1 if neither base ref is fetchable.
#
# Exit codes:
#   0  no plugin/ changes, or version was bumped, or running outside plugin tree
#   1  plugin/ changed but version unchanged
#   2  unable to determine base ref (treated as warn-only on local; CI fails)

set -euo pipefail

if [ ! -f "plugin/.claude-plugin/plugin.json" ]; then
  echo "↷ not in plugin source tree (no plugin/.claude-plugin/plugin.json) — skipping"
  exit 0
fi

# Resolve base ref.
base_ref=""
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  base_ref="origin/${GITHUB_BASE_REF}"
fi
if [ -z "$base_ref" ] && git rev-parse --verify --quiet origin/main >/dev/null; then
  base_ref="origin/main"
fi
if [ -z "$base_ref" ] && git rev-parse --verify --quiet HEAD~1 >/dev/null; then
  echo "⚠ no origin/main and no GITHUB_BASE_REF — comparing against HEAD~1"
  base_ref="HEAD~1"
fi
if [ -z "$base_ref" ]; then
  echo "⚠ cannot determine base ref to compare against — skipping"
  if [ -n "${CI:-}" ]; then exit 2; else exit 0; fi
fi

# Verify base ref's plugin.json exists (it may not, on the first plugin commit).
if ! git cat-file -e "${base_ref}:plugin/.claude-plugin/plugin.json" 2>/dev/null; then
  echo "↷ base ref ${base_ref} has no plugin.json — skipping (first-commit case)"
  exit 0
fi

# Files changed in plugin/ between base and HEAD.
changed=$(git diff --name-only "${base_ref}...HEAD" -- plugin/ 2>/dev/null || true)

if [ -z "$changed" ]; then
  echo "✓ no plugin/ changes between ${base_ref} and HEAD — version bump not required"
  exit 0
fi

cur=$(jq -r '.version' plugin/.claude-plugin/plugin.json)
old=$(git show "${base_ref}:plugin/.claude-plugin/plugin.json" | jq -r '.version')

if [ "$cur" = "$old" ]; then
  cat <<EOF
✗ plugin/ files changed but version is still ${cur}

  base:    ${base_ref}
  changed:
$(printf '    %s\n' $changed)

  Without a version bump, /plugin update is a no-op for existing consumers
  even though main has new content. Bump plugin/.claude-plugin/plugin.json
  and add a CHANGELOG entry before merging.
EOF
  exit 1
fi

echo "✓ version bumped: ${old} → ${cur}"
