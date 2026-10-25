#!/usr/bin/env bash
# Tests for phase-tuning.sh — the PreToolUse per-phase spawn-tuning injector.
# Needs python3 + jq for building/reading JSON. The placement cases run once per YAML backend
# (PyYAML, and yq with PyYAML hidden); SDLC_REQUIRE_BOTH_BACKENDS=1 makes a missing one a failure.
# Run: bash plugin/hooks/phase-tuning.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/phase-tuning.sh"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

# Fixture project with a representative sdlc.yml.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Never read the developer's real registry or leave bytecode behind.
export HOME="$TMP/home"
mkdir -p "$HOME"
unset SDLC_MACHINES XDG_CONFIG_HOME
export PYTHONDONTWRITEBYTECODE=1
PY="$(command -v python3)"
HOOKPY="$(cd "$(dirname "$0")" && pwd)/phase-tuning.py"

# ── backends (mirrors plugin/lib/machines.test.sh) ───────────────────────────
HAVE_PYYAML=0; HAVE_YQ=0
"$PY" -c 'import yaml' 2>/dev/null && HAVE_PYYAML=1
command -v yq >/dev/null 2>&1 && HAVE_YQ=1
# Shadow package that hides PyYAML, so the yq path runs.
mkdir -p "$TMP/noyaml/yaml"; echo 'raise ImportError("hidden for the test")' > "$TMP/noyaml/yaml/__init__.py"
SLEEP="$(command -v sleep)"
# Restricted-PATH directories: the wrapper needs python3, cat and dirname.
mkpath() {  # mkpath DIR  (then add a yq of its own, if any)
  mkdir -p "$1"
  ln -sf "$PY" "$1/python3"; ln -sf "$(command -v cat)" "$1/cat"; ln -sf "$(command -v dirname)" "$1/dirname"
}
mkpath "$TMP/pyyq"; [ "$HAVE_YQ" = 1 ] && ln -sf "$(command -v yq)" "$TMP/pyyq/yq"
mkpath "$TMP/noyq"
mkpath "$TMP/slowyq"; printf '#!/bin/sh\nexec %s 5\n' "$SLEEP" > "$TMP/slowyq/yq"; chmod +x "$TMP/slowyq/yq"
mkpath "$TMP/slowsdlc"
printf '#!/bin/sh\nfor a in "$@"; do last="$a"; done\ncase "$last" in *sdlc.yml) exec %s 5 ;; esac\nexec %s "$@"\n' \
  "$SLEEP" "$(command -v yq 2>/dev/null || echo /bin/false)" > "$TMP/slowsdlc/yq"; chmod +x "$TMP/slowsdlc/yq"

if [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ]; then
  [ "$HAVE_PYYAML" = 1 ] && ok "required backend present: PyYAML" || bad "required backend missing: PyYAML"
  [ "$HAVE_YQ" = 1 ] && ok "required backend present: yq" || bad "required backend missing: yq"
fi
BACKENDS=()
TIMEOUT="$(command -v timeout || true)"
# tmo CMD...: run under `timeout 10` when it exists (a timeout then shows up as exit 124).
tmo() { if [ -n "$TIMEOUT" ]; then "$TIMEOUT" 10 "$@"; else "$@"; fi; }
[ "$HAVE_PYYAML" = 1 ] && BACKENDS+=(py)
[ "$HAVE_YQ" = 1 ] && BACKENDS+=(yq)
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


# ═══════════════════════════════════════════════════════════════════════════
# Placement hint, golden matrix, deadline and scanner fixes
# ═══════════════════════════════════════════════════════════════════════════
FIX="$TMP/f"; REGD="$TMP/reg"; mkdir -p "$FIX" "$REGD" "$TMP/ctxs"
B0="${BACKENDS[0]:-py}"
mkfix() { mkdir -p "$FIX/$1/.claude"; cat > "$FIX/$1/.claude/sdlc.yml"; }
mkreg() { cat > "$REGD/$1.yaml"; }
has() { case "$1" in *"$2"*) return 0;; esac; return 1; }
want() { local label=$1 c=$2 n miss=""; shift 2; for n in "$@"; do has "$c" "$n" || miss="$miss [$n]"; done
         [ -z "$miss" ] && ok "$label" || bad "$label (missing:$miss)"; }
unwant() { local label=$1 c=$2 n found=""; shift 2; for n in "$@"; do has "$c" "$n" && found="$found [$n]"; done
           [ -z "$found" ] && ok "$label" || bad "$label (unexpected:$found)"; }
# ctx OUT: the additionalContext (kept for the global checks at the end).
ctx() {
  local c f
  c="$(printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  if [ -n "$c" ]; then f="$(mktemp "$TMP/ctxs/c.XXXXXX")"; printf '%s' "$c" > "$f"; fi
  printf '%s' "$c"
}
hkeys() { printf '%s' "$1" | jq -r '.hookSpecificOutput | keys_unsorted | join(",")' 2>/dev/null; }
now() { date +%s.%N; }
under() { awk -v a="$1" -v b="$2" -v lim="$3" 'BEGIN{exit !((b-a) < lim)}'; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b-a}'; }

# runp FIXTURE REGISTRY|"" BACKEND tool_input [tool]
runp() {
  local fx=$1 rg=$2 be=$3 ti=$4 tool=${5:-Agent} regenv=()
  [ -n "$rg" ] && regenv=(SDLC_MACHINES="$REGD/$rg.yaml")
  if [ "$be" = yq ]; then
    payload "$ti" "$tool" | env PATH="$TMP/pyyq" PYTHONPATH="$TMP/noyaml" CLAUDE_PROJECT_DIR="$FIX/$fx" \
      ${regenv[@]+"${regenv[@]}"} "$BASH" "$HOOK" 2>/dev/null
  else
    payload "$ti" "$tool" | env CLAUDE_PROJECT_DIR="$FIX/$fx" ${regenv[@]+"${regenv[@]}"} "$BASH" "$HOOK" 2>/dev/null
  fi
}
VAL='{"subagent_type":"sdlc:validator","prompt":"x"}'

# ── registries ───────────────────────────────────────────────────────────────
REGBASE='machines:
  here:
    transport: local
    caps: [edit, test]
    keeps: [checkouts]
    secrets: dev
  worker-1:
    transport: { herdr: w1-label }
    workdir: WORKDIR
    caps: [edit, test, browser, full-suite]
    first_start: [trust-prompt, fullscreen-notice]
  worker-2:
    transport: { herdr: worker-2 }
    caps: [edit, test, browser]
  control:
    assignable: false'
printf '%s\n' "${REGBASE/WORKDIR//srv/work}" | mkreg REG
printf '%s\n' "${REGBASE/WORKDIR//srv/$(printf 'a%.0s' $(seq 1 300))}" | mkreg REG_LONG
{ printf '%s\n' "${REGBASE/WORKDIR//srv/work}" | sed 's/^    transport: { herdr: w1-label }/    transport: local/'; } | mkreg REG_BAD
{ printf '%s\n' "${REGBASE/WORKDIR//srv/work}"
  for n in 3 4 5; do printf '  worker-%s:\n    transport: { herdr: worker-%s }\n    caps: [edit, test, browser]\n' "$n" "$n"; done
} | mkreg REG_MANY
HROLE="r$(printf 'a%.0s' $(seq 1 189))"
"$PY" -B - "$REGD/REG_HUGE.yaml" "$FIX" "$HROLE" <<'PYEOF'
import os, sys
reg, fix, role = sys.argv[1:4]
def name(c):
    return c * 190
lines = ["machines:", "  %s:" % name("l"), "    transport: local", "    caps: [edit]"]
for c in "xyz":
    lines += ["  %s:" % name(c), "    transport: { herdr: %s }" % name(c), "    caps: [edit, browser]"]
open(reg, "w").write("\n".join(lines) + "\n")
os.makedirs(os.path.join(fix, "hugep", ".claude"), exist_ok=True)
open(os.path.join(fix, "hugep", ".claude", "sdlc.yml"), "w").write(
    "phase_machines:\n  %s: any\nneeds:\n  %s: [browser]\n" % (role, role))
PYEOF

# ── sdlc.yml fixtures ────────────────────────────────────────────────────────
mkdir -p "$FIX/base/.claude"; cp "$TMP/.claude/sdlc.yml" "$FIX/base/.claude/sdlc.yml"
mkfix p <<'YML'
phases:
  implementer:
    model: opus
  validator:
    model: sonnet
    machine: worker-1
phase_machines:
  implementer: local
  reviewer: worker-2
  checker: any
  tester: worker-2
agent_machines:
  browser-pilot: worker-1
needs:
  validator: [full-suite]
  checker: [browser]
  tester: { keeps: [datasets] }
  lonely: [gpu]
YML
mkfix p2 <<'YML'
phase_machines: {reviewer: control}
default_machine: worker-2
YML
mkfix p3 <<'YML'
phase_machines: {reviewer: auto}
default_machine: worker-2
YML
sed 's/^agent_machines:$/agent_machines: [x]/; /^  browser-pilot: worker-1$/d' "$FIX/p/.claude/sdlc.yml" > "$TMP/pbad.yml"
mkfix pbad < "$TMP/pbad.yml"

G_IMPL_BASE='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {"subagent_type": "sdlc:implementer", "prompt": "x", "model": "sonnet", "maxTurns": 40, "isolation": "worktree"}}}'
G_SPEC_BASE='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {"subagent_type": "sdlc:specifier", "prompt": "x", "model": "claude-opus-4-8", "effort": "high"}}}'
G_IMPL_P='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {"subagent_type": "sdlc:implementer", "prompt": "x", "model": "opus"}}}'
G_VAL_P='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {"subagent_type": "sdlc:validator", "prompt": "x", "model": "sonnet"}}}'

echo "T0: no registry -> today's bytes:"
out="$(runp base "" $B0 '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
[ "$out" = "$G_IMPL_BASE" ] && ok "implementer on BASE is byte-identical" || bad "implementer on BASE differs: $out"
out="$(runp base "" $B0 '{"subagent_type":"sdlc:specifier","prompt":"x"}')"
[ "$out" = "$G_SPEC_BASE" ] && ok "specifier on BASE is byte-identical" || bad "specifier on BASE differs: $out"
out="$(runp p "" $B0 "$VAL")"
[ "$out" = "$G_VAL_P" ] && ok "validator on P (no registry) is byte-identical" || bad "validator on P differs: $out"
empty "$(runp p "" $B0 '{"subagent_type":"sdlc:reviewer","prompt":"x"}')" && ok "reviewer on P (no registry): no output" || bad "reviewer on P should be silent"

# ── T0b: the golden matrix (bytes captured on a6c7977's hook) ────────────────
mkfix tab < <(printf 'phases:\n\timplementer:\n\t\tmodel: sonnet\n\t\tmax_turns: 40\n\treviewer: { model: opus, effort: high }\n')
mkfix flat <<'YML'
phase_models:
  implementer: haiku
  validator: sonnet
phase_effort:
  implementer: low
phase_max_turns:
  validator: 30
phase_worktree:
  reviewer: true
phases:
  implementer:
    model: sonnet   # grouped wins
YML
mkfix nest <<'YML'
phases:
  validator:
    model: sonnet
    extra:
      model: haiku
YML
mkfix inl <<'YML'
phases:
  planner: { model: fable }
    effort: high
  validator:
    model: sonnet
YML
mkfix mlf <<'YML'
phases:
  specifier: {
    model: opus,
    effort: high }
  reviewer:
    model: fable
YML
mkfix ex <<'YML'
phases:
  understander:
    model:  opus
    effort: xhigh
  planner:   { model: fable, effort: xhigh }
  specifier: { model: fable, effort: xhigh }
  reviewer:  { model: fable, effort: xhigh }
  implementer:
    model:     opus
    effort:    low           # cheap-but-strong; raise max_turns if it under-converges
    max_turns: 60
    worktree:  true          # per-role isolation; ADDS only, explicit spawn arg wins
  validator:
    model:     fable
    effort:    medium
    max_turns: 40
  coordinator:
    model:  opus
    effort: high
YML
mkfix repo <<'YML'
# sdlc.yml — central SDLC configuration.
#
# All SDLC agents (planner, specifier, implementer, validator, coordinator,
# understander) and commands (/plan, /design, /develop, /orchestrate, /sync-issues)
# read from this file. Don't hardcode tracker / language / quality specifics in
# agents — declare them here.
#
# This file is also the canonical reference template for downstream projects
# adopting the v2 SDLC: copy to your project's `.claude/sdlc.yml` and adjust
# the primitives + team_key + topology values. The structural blocks (worktree,
# artifact_paths, tool_groups, canvases) are universal and rarely change.
#
# When agents land in PR 3, the empty `canvases:` registry below populates as
# canvases land in subsequent PRs (spec/envelope/plan in PR 6, session in PR 7).

# === Primitives ===
# Each value resolves to .claude/primitives/<category>/<value>.md, which agents
# read on demand. To add a new value, drop a new file in the matching directory.

language: typescript          # typescript | python | go
quality_profile: strict       # strict | fast
commit_style: conventional    # conventional | freeform
task_management: github       # linear | github | jira
repo: pattern-stack/claudecode-patterns  # GitHub repo for /sync-issues (when task_management: github)
# project_number: <n>         # OPTIONAL: GitHub Project v2 number (when task_management: github + Project linking is set up via /sdlc:link-project)
team_key: PSC                 # tracker team key — used in branch convention + sync filters (Linear-shaped; harmless under github)
gate1_default: strict         # strict | auto — default Gate-1 mode. Override per-stack (plan.yaml.auto_approve) or per-issue (gate:auto / gate:human label). Dormant until PR 2 of sdlc-plugin-distribution stack lands.

# === Topology A — /develop base roster ===
# Per-issue extras come from `needs:*` labels on the issue (e.g. needs:browser-pilot).
develop_team:
  - implementer
  - validator

# === Loop iteration caps + Gate-1 timeout ===
# Consumed by the coordinator-driven impl⇄val loop (issue #44 wires these in).
# Today they are dormant — no agent reads them yet — but they ship now so the
# coordinator PR is a pure-behavior change with no contract drift.

validator_max_iterations: 3
# Maximum impl⇄val loop iterations before coordinator halts with
# `status: halted`, `next.command: null`. Cap-hit is NOT a failure — it's
# a structured halt that surfaces full context to the human. See port
# README §"Cap-hit halts".

spec_critic_max_iterations: 3
# Placeholder for the spec-critic agent (out-of-scope, fast-follow). Same
# cap-hit semantics. Setting this today is a no-op.

coordinator_specifier_timeout_seconds: null
# How long coordinator polls for `state:strategy-approved` after spawning
# specifier in strict mode, before self-blocking with Status=Blocked.
# null = wait forever (current implicit behavior, preserved).
# Finite integer (e.g. 3600 = 1 hour) bounds the wait for unattended /orchestrate runs.

# === Topology B — /orchestrate concurrency ===
orchestrate_concurrency: 3

# === Worktree isolation ===
# When enabled, the spawning command (/develop or coordinator under /orchestrate)
# passes `isolation: "worktree"` to the Agent tool when spawning implementer.
# The worktree path is managed by Claude Code internally — cannot be overridden.
worktree:
  enabled: true

# === Artifact paths — single source of truth ===
# Stack-co-located is preferred for new work. Cross-cutting / legacy paths still valid.
# Agents MUST read paths from this block — do NOT hardcode them in agent prompts.
artifact_paths:
  # Stack-co-located (preferred for new work):
  stack_root:     .ai-docs/stacks/<slug>/
  plan:           .ai-docs/stacks/<slug>/plan.yaml
  stack_research: .ai-docs/stacks/<slug>/<topic>.md
  stack_spec:     .ai-docs/stacks/<slug>/specs/<issue-key>.md

  # Cross-cutting / legacy:
  cross_cutting_research: .ai-docs/research/<topic>.md
  legacy_spec:            .ai-docs/specs/<issue-key>.md

# === Tool groups — canonical tool bundles ===
# Claude Code's runtime does NOT substitute these names. Each agent enumerates
# its actual tools in frontmatter; a `# tool_group: <name>` comment declares
# which group expands. Verify with `bash scripts/verify-tool-groups.sh`.
tool_groups:
  # ALLOWLISTS — copy into `tools:` to restrict to exactly these (no MCP)
  read_only:        [Read, Glob, Grep]
  research:         [Read, Glob, Grep, WebFetch, WebSearch]
  research_writer:  [Read, Write, Glob, Grep, WebFetch, WebSearch]
  spec_writer:      [Read, Write, Edit, Glob, Grep]
  code_writer:      [Read, Write, Edit, Bash, Glob, Grep]
  validator:        [Read, Bash, Glob, Grep]

  # DENYLISTS — copy into `disallowedTools:` to inherit-all-minus (KEEPS MCP)
  # Use these for tracker-agnostic SDLC agents.
  no_egress:        [WebFetch, WebSearch]
  no_recursion:     [Agent]
  no_writes:        [Write, Edit]
  spec_writer_mcp:  [WebFetch, WebSearch, Agent]            # Bash kept — required by github adapter (`gh issue comment`, `gh issue edit`)
  code_writer_mcp:  [WebFetch, WebSearch, Agent]
  validator_mcp:    [Write, Edit, WebFetch, WebSearch, Agent]

# === Canvas registry ===
# Each canvas is a contract (template + instructions + schema + README) that
# governs the shape of one kind of artifact (the populated instance). Each
# name below maps to a directory under .claude/canvases/. Producer and consumer
# agents read template.md + instructions.yaml from the resolved path. Validate
# every canvas's instructions.yaml against its schema with `just verify-canvases`.
#
# Note: this registry names CANVASES (the contracts). Where the actual
# ARTIFACT INSTANCES land is governed by `artifact_paths:` above.
#
# Active canvases (v2 set):
canvases:
  spec:               .claude/canvases/spec/         # producer: specifier; consumers: implementer, coordinator, validator
  envelope:           .claude/canvases/envelope/     # cross-surface output wrapper; every phase agent emits
  plan:               .claude/canvases/plan/         # producer: planner; consumers: /sync-issues + downstream specifier
  session:            .claude/canvases/session/      # producers: every workflow command; two-tone observability (session.json + execution.log + summary.md)
YML

golden() {  # FIXTURE ROLE TOOL U
  local fx=$1 role=$2 tool=$3 u=$4 key=subagent_type exp reg out
  [ "$tool" = TeamCreate ] && key=agent_type
  if [ "$u" = "-" ]; then exp=""; else exp='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": '"$u"'}}'; fi
  for reg in "" REG; do
    out="$(runp "$fx" "$reg" $B0 "$(jq -nc --arg k "$key" --arg r "$role" '{($k):$r,prompt:"x"}')" "$tool")"
    [ "$out" = "$exp" ] && ok "golden $fx $role ($tool${reg:+, registry})" || bad "golden $fx $role ($tool${reg:+, registry}): got [$out]"
  done
}
echo "T0b: golden matrix:"
golden ex sdlc:understander Agent '{"subagent_type": "sdlc:understander", "prompt": "x", "model": "opus", "effort": "xhigh"}'
golden ex sdlc:planner Agent '{"subagent_type": "sdlc:planner", "prompt": "x", "model": "fable", "effort": "xhigh"}'
golden ex sdlc:specifier Agent '{"subagent_type": "sdlc:specifier", "prompt": "x", "model": "fable", "effort": "xhigh"}'
golden ex sdlc:reviewer Agent '{"subagent_type": "sdlc:reviewer", "prompt": "x", "model": "fable", "effort": "xhigh"}'
golden ex sdlc:implementer Agent '{"subagent_type": "sdlc:implementer", "prompt": "x", "model": "opus", "effort": "low", "maxTurns": 60, "isolation": "worktree"}'
golden ex sdlc:implementer TeamCreate '{"agent_type": "sdlc:implementer", "prompt": "x", "model": "opus", "effort": "low", "maxTurns": 60, "isolation": "worktree"}'
golden ex sdlc:validator Agent '{"subagent_type": "sdlc:validator", "prompt": "x", "model": "fable", "effort": "medium", "maxTurns": 40}'
golden ex sdlc:coordinator Agent '{"subagent_type": "sdlc:coordinator", "prompt": "x", "model": "opus", "effort": "high"}'
golden ex general-purpose Agent '-'
golden tab sdlc:implementer Agent '{"subagent_type": "sdlc:implementer", "prompt": "x", "model": "sonnet", "maxTurns": 40}'
golden tab reviewer Agent '{"subagent_type": "reviewer", "prompt": "x", "model": "opus", "effort": "high"}'
golden flat sdlc:implementer Agent '{"subagent_type": "sdlc:implementer", "prompt": "x", "model": "sonnet", "effort": "low"}'
golden flat sdlc:validator Agent '{"subagent_type": "sdlc:validator", "prompt": "x", "model": "sonnet", "maxTurns": 30}'
golden flat sdlc:reviewer Agent '{"subagent_type": "sdlc:reviewer", "prompt": "x", "isolation": "worktree"}'
golden repo sdlc:implementer Agent '{"subagent_type": "sdlc:implementer", "prompt": "x", "isolation": "worktree"}'
golden repo sdlc:validator Agent '-'
golden nest sdlc:validator Agent '{"subagent_type": "sdlc:validator", "prompt": "x", "model": "sonnet"}'
golden inl sdlc:planner Agent '{"subagent_type": "sdlc:planner", "prompt": "x", "model": "fable"}'
golden inl sdlc:validator Agent '{"subagent_type": "sdlc:validator", "prompt": "x", "model": "sonnet"}'
golden mlf sdlc:specifier Agent '-'
golden mlf sdlc:reviewer Agent '{"subagent_type": "sdlc:reviewer", "prompt": "x", "model": "fable"}'

echo "T1/T1b/T16: a remote role gets a hint, never a decision:"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  out="$(runp p REG $be "$VAL")"; c="$(ctx "$out")"
  [ "$(got "$out" model)" = sonnet ] && ok "[$be] T1 tuning kept (model=sonnet)" || bad "[$be] T1 model (got: $(got "$out" model))"
  [ -z "$(got "$out" machine)" ] && ok "[$be] T1 no machine key in updatedInput" || bad "[$be] T1 machine leaked into updatedInput"
  [ "$(hkeys "$out")" = "hookEventName,updatedInput,additionalContext" ] && ok "[$be] T1 keys and order" || bad "[$be] T1 keys: $(hkeys "$out")"
  case "$out" in '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {'*) ok "[$be] T1 output prefix";; *) bad "[$be] T1 output prefix: $out";; esac
  [ "$(printf '%s' "$out" | jq -cS .hookSpecificOutput.updatedInput)" = "$(printf '%s' "$G_VAL_P" | jq -cS .hookSpecificOutput.updatedInput)" ] \
    && ok "[$be] T1 updatedInput equals today's" || bad "[$be] T1 updatedInput differs"
  want "[$be] T1 ran hint text" "$c" "sdlc machines: phases.validator.machine places validator on 'worker-1'" \
    "already ran here, on this box ('here')" "Its result stands; don't run this call again" "start the next validator there" \
    "sdlc delegate validator --issue <n>" "herdr --machine w1-label tab create" "--cwd /srv/work" "-- --agent sdlc:validator" \
    "sdlc machines where validator" "GitHub"
  unwant "[$be] T1 ran hint omits" "$c" "is running here now" "stop it" "worker-1 tab create" "--permission-mode" "--model" "agent_not_ready"
  out="$(runp p REG $be '{"subagent_type":"sdlc:validator","prompt":"x","run_in_background":false}')"; c="$(ctx "$out")"
  want "[$be] T1 explicit false is still ran" "$c" "already ran here" "Its result stands"
  unwant "[$be] T1 explicit false omits running" "$c" "is running here now" "stop it"
  out="$(runp p REG $be '{"subagent_type":"sdlc:validator","prompt":"x","run_in_background":true}')"; c="$(ctx "$out")"
  [ "$(got "$out" model)" = sonnet ] && [ "$(got "$out" run_in_background)" = true ] \
    && ok "[$be] T1b tuning kept, run_in_background untouched" || bad "[$be] T1b updatedInput: $out"
  want "[$be] T1b running hint text" "$c" "is running here now, on this box ('here')" "let it finish and use its result" \
    "stop it and start this job on 'worker-1' instead" "Never both" "sdlc delegate validator --issue <n>"
  unwant "[$be] T1b running hint omits" "$c" "already ran" "don't run this call again"
  out="$(runp p REG $be '{"agent_type":"sdlc:validator"}' TeamCreate)"; c="$(ctx "$out")"
  want "[$be] T16 TeamCreate running hint" "$c" "as a TeamCreate teammate" "is running here now" "Never both"
  unwant "[$be] T16 omits ran" "$c" "already ran"
  [ "$(got "$out" model)" = sonnet ] && ok "[$be] T16 tuning kept" || bad "[$be] T16 model"
done

echo "T2-T9, T17: decisions:"
out="$(runp p REG $B0 '{"subagent_type":"sdlc:reviewer","prompt":"x"}')"; c="$(ctx "$out")"
[ "$(hkeys "$out")" = "hookEventName,additionalContext" ] && ok "T2 hint only: no updatedInput" || bad "T2 keys: $(hkeys "$out")"
want "T2 worker-2 hint" "$c" "on 'worker-2'" "herdr --machine worker-2 tab create --no-focus," "already ran"
unwant "T2 no workdir" "$c" "--cwd"
[ "$(runp p REG $B0 '{"subagent_type":"sdlc:implementer","prompt":"x"}')" = "$G_IMPL_P" ] && ok "T3 local role: byte-identical" || bad "T3 local role differs"
empty "$(runp p REG $B0 '{"subagent_type":"general-purpose","prompt":"x"}')" && ok "T4 general-purpose: silent" || bad "T4 general-purpose"
empty "$(runp p REG $B0 '{"subagent_type":"lonely","prompt":"x"}')" && ok "T4 unplaceable but unplaced: silent" || bad "T4 lonely"
empty "$(runp p2 REG $B0 '{"subagent_type":"tour","prompt":"x"}')" && ok "T4 unplaced under a remote default: silent" || bad "T4 tour"
c="$(ctx "$(runp p2 REG $B0 '{"subagent_type":"sdlc:reviewer","prompt":"x"}')")"
want "T5 fallback to a remote default" "$c" "was refused" "on 'worker-2'"; unwant "T5 no bold" "$c" '**'
c="$(ctx "$(runp p3 REG $B0 '{"subagent_type":"sdlc:reviewer","prompt":"x"}')")"
want "T5b auto reason arrives clean" "$c" "reserved for sdlc delegate --machine auto" "on 'worker-2'"; unwant "T5b no backtick" "$c" '`'
c="$(ctx "$(runp p REG $B0 '{"subagent_type":"checker","prompt":"x"}')")"
want "T6 any" "$c" "least loaded of worker-1, worker-2" "herdr --machine w1-label"
c="$(ctx "$(runp p REG_MANY $B0 '{"subagent_type":"checker","prompt":"x"}')")"
want "T6b any list capped" "$c" "least loaded of worker-1, worker-2, worker-3 and 2 more"; unwant "T6b omits the rest" "$c" "worker-4" "worker-5"
c="$(ctx "$(runp p REG $B0 '{"subagent_type":"sdlc:browser-pilot","prompt":"x"}')")"
want "T8 agent placement (kind=None)" "$c" "agent_machines.browser-pilot" "--agent sdlc:browser-pilot" "'worker-1'"
out="$(runp p REG $B0 '{"subagent_type":"sdlc:validator","model":"haiku","effort":"low"}')"
[ "$(hkeys "$out")" = "hookEventName,additionalContext" ] && has "$(ctx "$out")" "already ran" && ok "T9 explicit args: hint only" || bad "T9: $out"
c="$(ctx "$(runp p REG_LONG $B0 "$VAL")")"
want "T17 long command value" "$c" "sdlc delegate validator --issue <n>"; unwant "T17 herdr line dropped" "$c" "herdr --machine" "Without sdlc delegate"

echo "T7: nowhere hint:"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  out="$(runp p REG $be '{"subagent_type":"tester","prompt":"x"}')"; c="$(ctx "$out")"
  want "[$be] T7 nowhere hint" "$c" "has nowhere to run" "runs on this box anyway"
  unwant "[$be] T7 no delegate command, herdr or bold" "$c" '**' "sdlc delegate tester" "--issue" "herdr"
  [ "$(hkeys "$out")" = "hookEventName,additionalContext" ] && ok "[$be] T7 no updatedInput" || bad "[$be] T7 keys: $(hkeys "$out")"
done

echo "T10-T12: fail-open:"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  [ "$(runp p REG_BAD $be "$VAL")" = "$G_VAL_P" ] && ok "[$be] T10 broken registry: tuning only" || bad "[$be] T10 validator"
  empty "$(runp p REG_BAD $be '{"subagent_type":"sdlc:reviewer","prompt":"x"}')" && ok "[$be] T10 reviewer silent" || bad "[$be] T10 reviewer"
done
[ "$(runp pbad REG $B0 "$VAL")" = "$G_VAL_P" ] && ok "T11 broken placement block: tuning untouched" || bad "T11"
out="$(payload "$VAL" | env PATH="$TMP/noyq" PYTHONPATH="$TMP/noyaml" CLAUDE_PROJECT_DIR="$FIX/p" SDLC_MACHINES="$REGD/REG.yaml" "$BASH" "$HOOK" 2>/dev/null)"
[ "$out" = "$G_VAL_P" ] && ok "T12 no YAML backend: tuning only" || bad "T12: $out"

echo "T13/T15/T18: stub libs in a private copy of the plugin:"
FP="$TMP/fp"; mkdir -p "$FP/hooks" "$FP/lib"
cp "$HOOK" "$FP/hooks/phase-tuning.sh"; cp "$HOOKPY" "$FP/hooks/phase-tuning.py"
FPH="$FP/hooks/phase-tuning.sh"
runfp() {  # runfp FIXTURE REG [tool_input]
  payload "${3:-$VAL}" Agent | env CLAUDE_PROJECT_DIR="$FIX/$1" SDLC_MACHINES="$REGD/$2.yaml" "$BASH" "$FPH" 2>/dev/null
}
rm -rf "$FP/lib"
out="$(runfp p REG)"; rc=$?
[ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && printf '%s' "$out" | jq -e . >/dev/null && ok "T13a no lib/: tuning only" || bad "T13a: $out"
mkdir -p "$FP/lib"
printf 'print("garbage")\nraise RuntimeError("boom")\n' > "$FP/lib/machines.py"
out="$(runfp p REG)"; rc=$?
[ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && ok "T13b import raises: tuning only" || bad "T13b: $out"
printf 'LOOKUP_BUDGET = 1\ndef locate(*a, **k):\n    print("garbage")\n    return (object(), None, None)\n' > "$FP/lib/machines.py"
out="$(runfp p REG)"; rc=$?
[ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && printf '%s' "$out" | jq -e . >/dev/null && ok "T13c stray print swallowed, bad Placement: tuning only" || bad "T13c: $out"
printf 'raise SystemExit(3)\n' > "$FP/lib/machines.py"
out="$(runfp p REG)"; rc=$?
[ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && ok "T13d SystemExit at import: tuning only" || bad "T13d: $out (rc=$rc)"

printf 'open(%s, "w").close()\nraise RuntimeError("probe")\n' "'$TMP/imported'" > "$FP/lib/machines.py"
rm -f "$TMP/imported"
out="$(runfp base REG '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
{ [ ! -e "$TMP/imported" ] && [ "$out" = "$G_IMPL_BASE" ]; } && ok "T15 gate: no 'machine' in sdlc.yml, no import" || bad "T15 gate skipped wrongly"
out="$(runfp p REG)"
{ [ -e "$TMP/imported" ] && [ "$out" = "$G_VAL_P" ]; } && ok "T15 probe: a placing sdlc.yml does import" || bad "T15 probe"

# T18: the hook's own deadline. Each variant under `timeout 10`; a timeout is a failure.
DL="$(sed -n 's/^HOOK_DEADLINE = \([0-9.]*\).*/\1/p' "$HOOKPY")"
SLP="31.$$${RANDOM}"   # unique per run, so the orphan check and cleanup touch only our own child
dl_case() {  # label stub-body
  local label=$1 s e out rc
  printf 'LOOKUP_BUDGET = 2.5\n%s\n' "${2//@SLP@/$SLP}" > "$FP/lib/machines.py"
  s=$(now)
  out="$(payload "$VAL" Agent | tmo env CLAUDE_PROJECT_DIR="$FIX/p" SDLC_MACHINES="$REGD/REG.yaml" "$BASH" "$FPH" 2>/dev/null)"; rc=$?
  e=$(now)
  echo "    T18 $label: $(secs "$s" "$e")s, exit $rc"
  [ $rc -eq 124 ] && { bad "T18 $label hit the 10 s timeout (no working deadline)"; return; }
  [ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && under "$s" "$e" 5 && ! under "$s" "$e" "$(awk -v d="$DL" 'BEGIN{print d-0.2}')" \
    && ok "T18 $label: tuning only, between HOOK_DEADLINE-0.2 and 5 s" || bad "T18 $label: rc=$rc out=[$out]"
}
dl_case "(a) time.sleep(30)" 'import time
def locate(*a, **k):
    time.sleep(30)'
dl_case "(b) busy loop" 'def locate(*a, **k):
    while True:
        pass'
dl_case "(c) subprocess.run sleep" 'import subprocess
def locate(*a, **k):
    subprocess.run(["sleep", "@SLP@"], capture_output=True)'
dl_case "(d) swallows Exception in a loop" 'import time
def locate(*a, **k):
    while True:
        try:
            time.sleep(30)
        except Exception:
            pass'
orphans="$(ps -eo pid,args | awk -v a="$SLP" '$2=="sleep" && $3==a {print $1}')"
[ -z "$orphans" ] && ok "T18 (c) no child left behind" || { bad "T18 (c) orphan: $orphans"; kill $orphans 2>/dev/null; }

# T20: an alarm inside redirect_stdout leaves stdout alone, and arming is conditional.
cat > "$TMP/imp.py" <<'PYEOF'
import importlib.util, io, json, os, signal, sys, threading
spec = importlib.util.spec_from_file_location("pt", os.environ["HOOKPY"])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
proj = os.environ["CLAUDE_PROJECT_DIR"]
event = {"tool_name": "Agent", "tool_input": {"subagent_type": "sdlc:validator", "prompt": "x"}}
spawn = event["tool_input"]
mode = sys.argv[1]
if mode == "stdout":
    class Bad(object):
        def __init__(self, target): self.t = target
        def __enter__(self):
            sys.stdout = self.t
            raise mod._Deadline()
        def __exit__(self, *a): return False
    mod.contextlib.redirect_stdout = Bad
    r = mod.placement_hint("Agent", "sdlc:validator", "validator", proj, spawn)
    assert r is None, r
    assert sys.stdout is sys.__stdout__, "stdout left redirected"
    sys.stdin = io.StringIO(json.dumps(event))
    mod.main()
elif mode == "armed":
    # main thread: the timer is disarmed and the old handler is back after the call
    assert signal.getsignal(signal.SIGALRM) == signal.SIG_DFL
    r = mod.placement_hint("Agent", "sdlc:validator", "validator", proj, spawn)
    assert r and "already ran" in r, r
    assert signal.getsignal(signal.SIGALRM) == signal.SIG_DFL, "handler not restored"
    assert signal.getitimer(signal.ITIMER_REAL) == (0.0, 0.0), "timer left armed"
    # off the main thread: nothing is armed, so nothing is touched, and the hint still comes
    seen = {}
    def work():
        seen["r"] = mod.placement_hint("Agent", "sdlc:validator", "validator", proj, spawn)
    marker = lambda s, f: None
    signal.signal(signal.SIGALRM, marker)
    t = threading.Thread(target=work); t.start(); t.join()
    assert seen["r"] and "already ran" in seen["r"], seen
    assert signal.getsignal(signal.SIGALRM) is marker, "a thread must not touch the handler"
    assert signal.getitimer(signal.ITIMER_REAL) == (0.0, 0.0)
    print("armed-ok")
PYEOF
out="$(env HOOKPY="$HOOKPY" CLAUDE_PROJECT_DIR="$FIX/p" SDLC_MACHINES="$REGD/REG.yaml" "$PY" -I -B "$TMP/imp.py" stdout 2>"$TMP/imp.err")"; rc=$?
[ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && ok "T20 deadline inside redirect_stdout: stdout restored, tuning printed" || bad "T20 stdout: rc=$rc out=[$out] $(cat "$TMP/imp.err")"
out="$(env HOOKPY="$HOOKPY" CLAUDE_PROJECT_DIR="$FIX/p" SDLC_MACHINES="$REGD/REG.yaml" "$PY" -I -B "$TMP/imp.py" armed 2>"$TMP/imp.err")"; rc=$?
[ "$out" = "armed-ok" ] && [ $rc -eq 0 ] && ok "T20 disarms and restores only when it armed" || bad "T20 armed: rc=$rc out=[$out] $(cat "$TMP/imp.err")"

# T14/T14b: yq hangs; the hook must still finish well inside its 5 s kill.
echo "T14/T14b: a hanging yq:"
hang_case() {  # label PATHDIR
  local s e out rc
  s=$(now)
  out="$(payload "$VAL" Agent | tmo env PATH="$2" PYTHONPATH="$TMP/noyaml" CLAUDE_PROJECT_DIR="$FIX/p" SDLC_MACHINES="$REGD/REG.yaml" "$BASH" "$HOOK" 2>/dev/null)"; rc=$?
  e=$(now)
  echo "    $1: $(secs "$s" "$e")s, exit $rc"
  [ "$out" = "$G_VAL_P" ] && [ $rc -eq 0 ] && under "$s" "$e" 5 && ok "$1: tuning only, under 5 s" || bad "$1: rc=$rc out=[$out]"
}
hang_case "T14 yq hangs on every call" "$TMP/slowyq"
if [ "$HAVE_YQ" = 1 ]; then hang_case "T14b yq hangs only on sdlc.yml" "$TMP/slowsdlc"; else echo "  - T14b skipped (no yq)"; fi

echo "T19: still over 2000 characters -> no hint:"
out="$(runp hugep REG_HUGE $B0 "$(jq -nc --arg r "$HROLE" '{subagent_type:$r,prompt:"x"}')")"
[ -z "$(ctx "$out")" ] && ok "T19 over-long hint is dropped whole" || bad "T19 hint present: $(ctx "$out" | wc -c) chars"
chk="$(env SDLC_MACHINES="$REGD/REG_HUGE.yaml" "$PY" -I -B -c '
import sys; sys.path.insert(0, sys.argv[1])
import machines
p, r, _ = machines.locate(sys.argv[3], None, project_dir=sys.argv[2])
print(p.status, p.local, len(p.candidates))' "$(cd "$(dirname "$HOOK")/../lib" && pwd)" "$FIX/hugep" "$HROLE")"
[ "$chk" = "placed False 3" ] && ok "T19 sanity: the role is placed remotely on 3 candidates" || bad "T19 sanity: $chk"

echo "Q1-Q5: scanner fixes:"
mkfix q1 <<'YML'
phases:
  validator:
    machine:
    model: fable
YML
out="$(runp q1 "" $B0 "$VAL")"; [ "$(got "$out" model)" = fable ] && ok "Q1 bare knob does not eat the next knob" || bad "Q1 (got: $(got "$out" model))"
mkfix q2a <<'YML'
phases:
  validator:
    model: null
YML
empty "$(runp q2a "" $B0 "$VAL")" && ok "Q2a null model is unset" || bad "Q2a"
mkfix q2b <<'YML'
phases:
  validator:
    model: ~
phase_models:
  validator: sonnet
YML
out="$(runp q2b "" $B0 "$VAL")"; [ "$(got "$out" model)" = sonnet ] && ok "Q2b ~ falls back to the flat value" || bad "Q2b (got: $(got "$out" model))"
mkfix q2c <<'YML'
phases:
  validator:
    model: "null"
YML
out="$(runp q2c "" $B0 "$VAL")"; [ "$(got "$out" model)" = null ] && ok "Q2c quoted \"null\" stays a string" || bad "Q2c (got: $(got "$out" model))"
mkfix q3a <<'YML'
phases:
  implementer:
    model: sonnet
  sdlc:validator:
    model: haiku
    max_turns: 7
YML
mkfix q3b <<'YML'
phases:
  implementer:
    model: sonnet
  validator: sonnet
    model: haiku
    max_turns: 7
YML
for v in q3a q3b; do
  out="$(runp $v "" $B0 '{"subagent_type":"sdlc:implementer","prompt":"x"}')"
  { [ "$(got "$out" model)" = sonnet ] && [ -z "$(got "$out" maxTurns)" ]; } && ok "Q3 $v: no knobs leak upward" || bad "Q3 $v: $out"
done
empty "$(runp q3a "" $B0 "$VAL")" && ok "Q3 prefixed header still does not tune" || bad "Q3 prefixed"
mkfix q4a <<'YML'
phases:
  specifier: { model: opus,
    effort: high }
YML
mkfix q4b <<'YML'
phases:
  specifier: { model: opus,
    effort: high }
phase_models:
  specifier: sonnet
YML
empty "$(runp q4a "" $B0 '{"subagent_type":"sdlc:specifier","prompt":"x"}')" && ok "Q4a multi-line flow map fails closed" || bad "Q4a"
out="$(runp q4b "" $B0 '{"subagent_type":"sdlc:specifier","prompt":"x"}')"
{ [ "$(got "$out" model)" = sonnet ] && [ -z "$(got "$out" effort)" ]; } && ok "Q4b flat value still applies" || bad "Q4b: $out"
mkfix q5 <<'YML'
phases:
  validator:
    model: sonnet
    extra:
      model: haiku
    effort: low
YML
out="$(runp q5 "" $B0 "$VAL")"
{ [ "$(got "$out" model)" = sonnet ] && [ "$(got "$out" effort)" = low ]; } && ok "Q5 nested map ignored, later knob kept" || bad "Q5: $out"

echo "Deadline vs hooks.json, BOM, 2000-char first stage, nested flow maps:"
HJ="$(cd "$(dirname "$HOOK")" && pwd)/hooks.json"
HT="$(jq -r '[.. | objects | select((.command? // "") | contains("phase-tuning.sh")) | .timeout] | first' "$HJ" 2>/dev/null)"
awk -v d="$DL" -v t="$HT" 'BEGIN{exit !(t+0 > 0 && d+0 < t+0)}' && ok "HOOK_DEADLINE ($DL) is below the hooks.json timeout ($HT)" || bad "HOOK_DEADLINE ($DL) vs hooks.json timeout ($HT)"

mkdir -p "$FIX/bom/.claude"; { printf '\xef\xbb\xbf'; cat "$FIX/p/.claude/sdlc.yml"; } > "$FIX/bom/.claude/sdlc.yml"
out="$(runp bom REG $B0 "$VAL")"; c="$(ctx "$out")"
{ [ "$(got "$out" model)" = sonnet ] && has "$c" "already ran here"; } && ok "BOM: tuning and hint both read the file" || bad "BOM: $out"
mkdir -p "$FIX/bom2/.claude"; { printf '\xef\xbb\xbf'; printf 'phases:\n  validator:\n    model: fable\n'; } > "$FIX/bom2/.claude/sdlc.yml"
out="$(runp bom2 "" $B0 "$VAL")"; [ "$(got "$out" model)" = fable ] && ok "BOM on the first key does not hide the block" || bad "BOM2: $out"

"$PY" -B - "$REGD/REG_MID.yaml" "$FIX" <<'PYEOF'
import os, sys
reg, fix = sys.argv[1:3]
M, L, Z = "m" * 190, "y" * 190, "/" + "z" * 190
body = "machines:\n  here:\n    transport: local\n    caps: [edit]\n"
body += "  %s:\n    transport: { herdr: %s }\n    workdir: %s\n    caps: [edit, browser]\n" % (M, L, Z)
for c in "pq":
    body += "  %s:\n    transport: { herdr: %s }\n    caps: [edit, browser]\n" % (c * 190, c * 190)
open(reg, "w").write(body)
os.makedirs(os.path.join(fix, "midp", ".claude"), exist_ok=True)
open(os.path.join(fix, "midp", ".claude", "sdlc.yml"), "w").write("phase_machines:\n  validator: any\nneeds:\n  validator: [browser]\n")
PYEOF
out="$(runp midp REG_MID $B0 "$VAL")"; c="$(ctx "$out")"
want "T19b first stage: over 2000 with the herdr line, the hint stays without it" "$c" "sdlc delegate validator --issue <n>" "Its result stands"
unwant "T19b herdr line dropped" "$c" "herdr --machine" "Without sdlc delegate"
[ "${#c}" -gt 1000 ] && [ "${#c}" -le 2000 ] && ok "T19b length ${#c} is within 2000" || bad "T19b length ${#c}"

mkfix q4c <<'YML'
phases:
  specifier:
    model: {
    effort: high }
YML
empty "$(runp q4c "" $B0 '{"subagent_type":"sdlc:specifier","prompt":"x"}')" && ok "Q4c nested multi-line flow map fails closed" || bad "Q4c"

echo "Every hint context:"
nfiles="$(ls "$TMP/ctxs" | wc -l)"
[ "$nfiles" -gt 0 ] && ok "collected $nfiles contexts" || bad "no contexts collected"
badc=0; for f in "$TMP"/ctxs/c.*; do
  if LC_ALL=C grep -q '[^ -~]' <(tr -d '\n' < "$f"); then badc=$((badc+1)); echo "    non-ASCII in $f"; fi
  [ "$(wc -c < "$f")" -le 2000 ] || { badc=$((badc+1)); echo "    over 2000 chars: $f"; }
  if grep -qF '**' "$f" || grep -qF '`' "$f"; then badc=$((badc+1)); echo "    markdown in $f"; fi
done
[ $badc -eq 0 ] && ok "all contexts are ASCII, <= 2000 chars, with no ** or backtick" || bad "$badc context problems"

echo
printf 'phase-tuning: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
