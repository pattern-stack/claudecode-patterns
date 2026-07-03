#!/usr/bin/env bash
# phase-tuning.sh — PreToolUse hook that injects per-phase spawn tuning from
# .claude/sdlc.yml into `Agent` / `TeamCreate` calls, so model/effort/turn/worktree
# policy is ENFORCED CONTROL FLOW rather than prose the spawner might skip.
#
# This is the deterministic successor to the 0.2.17 `phase_models` design, where
# each command's markdown *told the model* to read `phase_models` and pass
# `model:` at spawn. That was soft — a long-context spawner could forget, and the
# override would silently not apply. This hook removes the model from the loop:
# it reads sdlc.yml itself and rewrites the spawn arguments before the tool runs.
#
# Config — preferred grouped schema, every knob for a role in one place:
#   phases:
#     <role>:
#       model:     opus | sonnet | haiku | <full-model-id>   → tool_input.model
#       effort:    low | medium | high | xhigh | max         → tool_input.effort
#       max_turns: <int>                                     → tool_input.maxTurns
#       worktree:  true                                      → tool_input.isolation="worktree"
# Backward-compat: the flat 0.2.17 keys `phase_models` / `phase_effort` /
# `phase_max_turns` / `phase_worktree` (each a `<role>: <value>` map) are still
# honored as a fallback; a grouped `phases.<role>.<knob>` wins over its flat twin.
# The legacy global `worktree.enabled: true` is honored as an alias for
# `phases.implementer.worktree: true`, so all worktree policy resolves here.
#
# Role resolution: the spawn's `subagent_type` (Agent) or `agent_type` (TeamCreate)
# with any `namespace:` prefix stripped — `sdlc:implementer` → `implementer`. A
# spawn whose role matches no configured key (e.g. `general-purpose`) passes through
# untouched.
#
# Precedence: an argument the spawner set EXPLICITLY always wins — the hook only
# fills a key the spawn left unset. So `Agent(model: "opus")` is never overridden;
# a bare `Agent()` gets sdlc.yml's value. Un-configured keys are omitted, leaving
# the agent's frontmatter default to stand — identical semantics to phase_models.
#
# Verified vs experimental (see also phase-tuning.py):
#   - model     — proven: the Agent tool accepts `model` and honors it.
#   - effort    — accepted at spawn (verified 2026-07-03); honoring not yet proven.
#   - maxTurns  — frontmatter field name; the spawn-arg key is a best-effort guess.
#   - isolation — proven for "worktree" (same channel /develop + coordinator use).
#
# Design contract:
# - FAILS OPEN. No python3, no sdlc.yml, unparseable JSON/YAML, or ANY error →
#   exit 0 with no stdout, i.e. the spawn runs exactly as the model issued it. A
#   tuning hook must never wedge a spawn — it is a policy layer, not a gate.
# - The Python does all logic and only prints on a real injection. Wired in
#   plugin/hooks/hooks.json, matcher "Agent|TeamCreate", async:false (input
#   rewrite must complete before the tool runs).

set -u

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -z "$DIR" ] && exit 0

# The .py always exits 0 and prints only on a real injection; the `|| true`
# is a belt-and-suspenders guarantee the wrapper never fails the spawn.
printf '%s' "$INPUT" | python3 "$DIR/phase-tuning.py" 2>/dev/null || true
exit 0
