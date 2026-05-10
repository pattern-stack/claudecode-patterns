# claudecode-patterns — task runner
# Convention: every recipe is a thin wrapper. Real logic lives in scripts/.

default:
    @just --list

# ─── Verify (SDLC config invariants) ──────────────────────────────────

# verify everything (canvases + tool groups)
[group('verify')]
verify: verify-canvases verify-tool-groups

# verify .claude/canvases/<name>/instructions.yaml against its schema
[group('verify')]
verify-canvases:
    @bash scripts/verify-canvases.sh

# verify each agent's # tool_group: matches its tools/disallowedTools list
[group('verify')]
verify-tool-groups:
    @bash scripts/verify-tool-groups.sh

# ─── Claude Code agent launchers ──────────────────────────────────────
# Convention: one recipe per launchable Claude Code agent UX. Recipes pre-apply
# the right --output-style so users don't have to remember flag names.

# canvas-author in developer voice (knobs, diffs, four-block scaffold)
[group('claude')]
canvas-dev:
    claude --agent canvas-author --output-style canvas-flow-developer

# canvas-author in seller voice (outcomes, samples, hides mechanism)
[group('claude')]
canvas-seller:
    claude --agent canvas-author --output-style canvas-flow-seller

# ─── Canvas reconciliation ────────────────────────────────────────────

# list canvases on disk reconciled against sdlc.yml.canvases
[group('verify')]
canvases:
    @bash scripts/list-canvases.sh
