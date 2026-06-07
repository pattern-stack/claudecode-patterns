#!/usr/bin/env bash
# Verify each agent's `# tool_group: <name>` comment matches its enumerated
# tools/disallowedTools list against the canonical groups in the project's
# .claude/sdlc.yml.
#
# Reads sdlc.yml from the project root (${CLAUDE_PROJECT_DIR} or cwd).
# Reads agents from the plugin root (this script's parent dir).
#
# Usage:  just sdlc::verify-tool-groups   (or bash plugin/scripts/verify-tool-groups.sh)
# Exit:   0 = all OK, 1 = mismatch(es), 2 = config error
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SDLC="$PROJECT_ROOT/.claude/sdlc.yml"
AGENTS_DIR="$PLUGIN_ROOT/agents"

if [[ ! -f "$SDLC" ]]; then
  echo "❌ Missing $SDLC" >&2
  exit 2
fi
if ! command -v yq >/dev/null 2>&1; then
  echo "❌ yq not installed (brew install yq)" >&2
  exit 2
fi

# Normalize a comma-separated tool list into sorted unique tokens.
# Strips whitespace and Agent(...) parenthetical args (compares the bare token).
# Also strips team-plumbing tools (SendMessage, Task*) — they're harness
# coordination channels, orthogonal to the capability groups in sdlc.yml.
# Allowlist agents MUST carry SendMessage (see verify-teammate-tools.sh), so
# excluding it here keeps both checks satisfiable at once.
normalize() {
  echo "$1" \
    | tr ',' '\n' \
    | sed -E 's/\(.*\)//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | grep -v '^$' \
    | grep -vE '^(SendMessage|TaskCreate|TaskGet|TaskList|TaskUpdate)$' \
    | sort -u
}

# Read a YAML array from sdlc.yml tool_groups.<name>
canonical() {
  yq -r ".tool_groups[\"$1\"] | .[]" "$SDLC" 2>/dev/null | sort -u || true
}

errors=0
checked=0
skipped=0

for file in "$AGENTS_DIR"/*.md; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file" .md)"

  # Extract first frontmatter block (between the first two `---` lines)
  fm="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print}' "$file")"
  if [[ -z "$fm" ]]; then
    echo "⚠️  $name: no frontmatter — skipping"
    ((skipped+=1))
    continue
  fi

  group="$(echo "$fm" | grep -E '^# tool_group:' | head -1 \
           | sed -E 's/^# tool_group:[[:space:]]*//' | awk '{print $1}')"

  if [[ -z "$group" ]]; then
    echo "⚠️  $name: no '# tool_group:' comment — skipping"
    ((skipped+=1))
    continue
  fi

  if [[ "$group" == "custom" ]]; then
    echo "ℹ️  $name: custom group — skipping verification"
    ((skipped+=1))
    continue
  fi

  # Determine form: denylist (preferred check first, since it's the SDLC default)
  if echo "$fm" | grep -qE '^disallowedTools:'; then
    actual_raw="$(echo "$fm" | grep -E '^disallowedTools:' \
                  | sed -E 's/^disallowedTools:[[:space:]]*//')"
    form="denylist"
  elif echo "$fm" | grep -qE '^tools:'; then
    actual_raw="$(echo "$fm" | grep -E '^tools:' \
                  | sed -E 's/^tools:[[:space:]]*//')"
    form="allowlist"
  else
    echo "❌ $name: tool_group=$group declared but no tools:/disallowedTools: line"
    ((errors+=1))
    continue
  fi

  expected="$(canonical "$group")"
  if [[ -z "$expected" ]]; then
    echo "❌ $name: tool_group=$group not found in sdlc.yml tool_groups"
    ((errors+=1))
    continue
  fi

  actual="$(normalize "$actual_raw")"

  if [[ "$actual" == "$expected" ]]; then
    echo "✅ $name ($group, $form)"
    ((checked+=1))
  else
    echo "❌ $name ($group, $form): mismatch"
    # diff returns 1 when files differ (expected here); pipefail would cause set -e to exit.
    # || true makes the pipeline succeed regardless so the loop continues to other agents.
    { diff <(echo "$expected") <(echo "$actual") | sed 's/^/     /' | head -20; } || true
    ((errors+=1)) || true
  fi
done

echo ""
echo "Checked: $checked  Skipped: $skipped  Errors: $errors"
[[ "$errors" -eq 0 ]] || exit 1
