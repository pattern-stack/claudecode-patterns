#!/usr/bin/env bash
# Tests for phase-tuning.sh — the PreToolUse per-phase spawn-tuning injector.
# Needs python3 (the hook's only dependency) + jq for building/reading JSON.
# Run: bash plugin/hooks/phase-tuning.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/phase-tuning.sh"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

# Fixture project with a representative sdlc.yml.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/sdlc.yml" <<'YML'
team_key: AP
task_management: linear

# Preferred grouped schema — all knobs for a role in one place.
phases:
  implementer:
    model: sonnet
    max_turns: 40
    worktree: true
  reviewer:
    model: opus
    effort: high
  specifier: { model: "claude-opus-4-8", effort: high }   # inline flow map
  understander:
    effort: low
  validator:
    worktree: false

# a trailing top-level key must not bleed into the last block
spec_storage: file
YML

# Build a PreToolUse stdin payload. $1 = tool_input JSON, $2 = tool (default Agent)
payload() { jq -nc --arg t "${2:-Agent}" --argjson ti "$1" '{tool_name:$t, tool_input:$ti, cwd:"IGNORED"}'; }
# Run hook against the fixture project.
run() { payload "$1" "${2:-Agent}" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null; }
# Read an injected value out of updatedInput ("" if absent/no output).
got() { printf '%s' "$1" | jq -r "(.hookSpecificOutput.updatedInput.$2) // empty" 2>/dev/null; }
# True when the hook produced no output (pure passthrough).
empty() { [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }

echo "Injection from config:"
out="$(run '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
[ "$(got "$out" model)" = "sonnet" ]   && ok "implementer → model=sonnet"        || bad "implementer model (got: $(got "$out" model))"
[ "$(got "$out" maxTurns)" = "40" ]    && ok "implementer → maxTurns=40"          || bad "implementer maxTurns (got: $(got "$out" maxTurns))"
[ "$(got "$out" isolation)" = "worktree" ] && ok "implementer → isolation=worktree" || bad "implementer worktree (got: $(got "$out" isolation))"

out="$(run '{"subagent_type":"reviewer","prompt":"x"}')"
[ "$(got "$out" model)" = "opus" ]  && ok "reviewer (bare role) → model=opus"    || bad "reviewer model (got: $(got "$out" model))"
[ "$(got "$out" effort)" = "high" ] && ok "reviewer → effort=high"               || bad "reviewer effort (got: $(got "$out" effort))"

out="$(run '{"subagent_type":"sdlc:specifier","prompt":"x"}')"
[ "$(got "$out" model)" = "claude-opus-4-8" ] && ok "specifier (inline map) → full quoted id"      || bad "specifier model (got: $(got "$out" model))"
[ "$(got "$out" effort)" = "high" ]           && ok "specifier (inline map) → effort=high"          || bad "specifier effort (got: $(got "$out" effort))"

echo "Preserved fields + precedence:"
out="$(run '{"subagent_type":"sdlc:implementer","prompt":"keepme"}')"
[ "$(got "$out" prompt)" = "keepme" ] && ok "original fields preserved in updatedInput" || bad "prompt preserved (got: $(got "$out" prompt))"
out="$(run '{"subagent_type":"sdlc:implementer","model":"haiku"}')"
[ "$(got "$out" model)" = "haiku" ] && ok "explicit model wins over config"        || bad "explicit model precedence (got: $(got "$out" model))"
out="$(run '{"subagent_type":"sdlc:implementer","isolation":"none"}')"
[ "$(got "$out" isolation)" = "none" ] && ok "explicit isolation wins over phase_worktree" || bad "explicit isolation precedence (got: $(got "$out" isolation))"

echo "No-op / passthrough cases:"
empty "$(run '{"subagent_type":"general-purpose","prompt":"x"}')"     && ok "unconfigured role → passthrough (no output)"  || bad "general-purpose should passthrough"
empty "$(run '{"subagent_type":"validator","prompt":"x"}')"          && ok "role only in worktree:false → passthrough"     || bad "validator(false) should passthrough"
empty "$(run '{"prompt":"x"}')"                                       && ok "no role → passthrough"                        || bad "no role should passthrough"
empty "$(run '{"subagent_type":"planner"}' Bash)"                    && ok "non-spawn tool (Bash) → passthrough"          || bad "Bash tool should passthrough"

echo "Fail-open safety:"
empty "$(printf 'not json' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null)" && ok "malformed JSON → fail open" || bad "malformed JSON should fail open"
empty "$(printf '' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" 2>/dev/null)"         && ok "empty stdin → fail open"   || bad "empty stdin should fail open"
missing="$(payload '{"subagent_type":"reviewer"}' | CLAUDE_PROJECT_DIR="/nonexistent-xyz-$$" bash "$HOOK" 2>/dev/null)"
empty "$missing" && ok "missing sdlc.yml → fail open" || bad "missing sdlc.yml should fail open"

echo "Legacy global worktree.enabled → implementer:"
TMP2="$(mktemp -d)"; mkdir -p "$TMP2/.claude"
cat > "$TMP2/.claude/sdlc.yml" <<'YML'
worktree:
  enabled: true
phase_models:
  validator: sonnet
YML
run2() { payload "$1" "${2:-Agent}" | CLAUDE_PROJECT_DIR="$TMP2" bash "$HOOK" 2>/dev/null; }
out="$(run2 '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
[ "$(got "$out" isolation)" = "worktree" ] && ok "implementer picks up global worktree.enabled" || bad "global worktree for implementer (got: $(got "$out" isolation))"
out="$(run2 '{"subagent_type":"validator","prompt":"x"}')"
[ -z "$(got "$out" isolation)" ] && ok "non-implementer role ignores global worktree.enabled" || bad "validator should not get global worktree (got: $(got "$out" isolation))"
rm -rf "$TMP2"

echo "Backward-compat flat phase_* keys (0.2.17 schema):"
TMP3="$(mktemp -d)"; mkdir -p "$TMP3/.claude"
cat > "$TMP3/.claude/sdlc.yml" <<'YML'
phase_models:
  implementer: haiku
phase_effort:
  implementer: low
phases:
  implementer:
    model: sonnet   # grouped wins over the flat phase_models above
YML
run3() { payload "$1" "${2:-Agent}" | CLAUDE_PROJECT_DIR="$TMP3" bash "$HOOK" 2>/dev/null; }
out="$(run3 '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
[ "$(got "$out" model)" = "sonnet" ] && ok "grouped phases.model wins over flat phase_models" || bad "grouped precedence (got: $(got "$out" model))"
[ "$(got "$out" effort)" = "low" ]   && ok "flat phase_effort still honored as fallback"     || bad "flat fallback (got: $(got "$out" effort))"
rm -rf "$TMP3"

echo
printf 'phase-tuning: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
