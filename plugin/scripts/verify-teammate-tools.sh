#!/usr/bin/env bash
# Catch the two teammate footguns verified empirically on 2026-06-06
# (see CHANGELOG 0.2.13 / memory: allowlist-teammate-footgun):
#
# 1. TEAMMATE MUTE — an explicit `tools:` allowlist suppresses the team tools
#    the harness injects for teammates. Without `SendMessage` the agent can
#    receive messages but never report up, answer plan-approval, or complete
#    the shutdown handshake ("SendMessage exists but is not enabled in this
#    context"). Any agent can be spawned as a teammate, so:
#      - allowlist form  → MUST include SendMessage
#      - denylist form   → MUST NOT list SendMessage in disallowedTools
#    Deliberate exceptions opt out with a frontmatter comment: `# teammate: never`
#
# 2. BRICKED Agent(...) SCOPE — scope args must be REGISTRY keys. Plugin agents
#    register namespaced (`<plugin>:<name>`), so `Agent(implementer)` matches
#    nothing and yields an EMPTY spawnable set (every subagent_type fails,
#    including the default). Each scope arg must be either:
#      - `<plugin>:<name>` where agents/<name>.md exists in this plugin, or
#      - a known built-in type (general-purpose, Explore, Plan, claude)
#
# Reads agents from the plugin root (this script's parent dir).
#
# Usage:  just sdlc::verify-teammate-tools   (or bash plugin/scripts/verify-teammate-tools.sh)
# Exit:   0 = all OK, 1 = violation(s), 2 = config error
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$PLUGIN_ROOT/agents"
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "❌ Missing $MANIFEST" >&2
  exit 2
fi

# Plugin namespace — the registry prefixes shipped agents with "<name>:".
PLUGIN_NAME="$(sed -nE 's/^[[:space:]]*"name":[[:space:]]*"([^"]+)".*/\1/p' "$MANIFEST" | head -1)"
if [[ -z "$PLUGIN_NAME" ]]; then
  echo "❌ Could not read plugin name from $MANIFEST" >&2
  exit 2
fi

BUILTIN_TYPES="general-purpose Explore Plan claude"

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

  agent_errors=0

  # --- Check 1: SendMessage availability -----------------------------------
  if echo "$fm" | grep -qE '^# teammate:[[:space:]]*never'; then
    echo "ℹ️  $name: '# teammate: never' — SendMessage check skipped"
  elif echo "$fm" | grep -qE '^tools:'; then
    tools_line="$(echo "$fm" | grep -E '^tools:' | head -1 | sed -E 's/^tools:[[:space:]]*//')"
    if ! echo "$tools_line" | tr ',' '\n' | sed -E 's/\(.*\)//; s/^[[:space:]]+|[[:space:]]+$//g' \
        | grep -qx 'SendMessage'; then
      echo "❌ $name: allowlist \`tools:\` omits SendMessage — spawned as a teammate it cannot report up or answer the shutdown handshake. Add SendMessage (or mark '# teammate: never')."
      ((agent_errors+=1))
    fi
  elif echo "$fm" | grep -qE '^disallowedTools:'; then
    deny_line="$(echo "$fm" | grep -E '^disallowedTools:' | head -1 | sed -E 's/^disallowedTools:[[:space:]]*//')"
    if echo "$deny_line" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
        | grep -qx 'SendMessage'; then
      echo "❌ $name: disallowedTools lists SendMessage — spawned as a teammate it cannot report up. Remove it (or mark '# teammate: never')."
      ((agent_errors+=1))
    fi
  fi
  # No tools:/disallowedTools: → inherits everything incl. SendMessage. OK.

  # --- Check 2: Agent(...) scope args resolve in the registry ---------------
  # Scan both tools: and disallowedTools: lines for Agent(...) parentheticals.
  scope_args="$(echo "$fm" | grep -E '^(tools|disallowedTools):' \
    | grep -oE 'Agent\([^)]*\)' | sed -E 's/^Agent\(//; s/\)$//' \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' || true)"

  while IFS= read -r arg; do
    [[ -n "$arg" ]] || continue
    if [[ " $BUILTIN_TYPES " == *" $arg "* ]]; then
      continue
    fi
    if [[ "$arg" == "$PLUGIN_NAME":* ]]; then
      ref="${arg#"$PLUGIN_NAME":}"
      if [[ ! -f "$AGENTS_DIR/$ref.md" ]]; then
        echo "❌ $name: Agent($arg) — no agents/$ref.md in this plugin; scope arg won't resolve."
        ((agent_errors+=1))
      fi
    elif [[ -f "$AGENTS_DIR/$arg.md" ]]; then
      echo "❌ $name: Agent($arg) — plugin agents register NAMESPACED; use Agent($PLUGIN_NAME:$arg) or the scope resolves to an EMPTY registry."
      ((agent_errors+=1))
    else
      echo "❌ $name: Agent($arg) — unknown agent type (not a built-in, not $PLUGIN_NAME-namespaced, no agents/$arg.md)."
      ((agent_errors+=1))
    fi
  done <<< "$scope_args"

  if [[ "$agent_errors" -eq 0 ]]; then
    echo "✅ $name"
    ((checked+=1))
  else
    ((errors+=agent_errors))
  fi
done

echo ""
echo "Checked: $checked  Skipped: $skipped  Errors: $errors"
[[ "$errors" -eq 0 ]] || exit 1
