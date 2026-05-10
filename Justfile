# claudecode-patterns — task runner
# Convention: every recipe is a thin wrapper. Real logic lives in scripts/.

default:
    @just --list

# ─── Verify (SDLC config invariants) ──────────────────────────────────

# verify everything (artifacts + tool groups)
[group('verify')]
verify: verify-artifacts verify-tool-groups

# verify .claude/artifacts/<name>/instructions.yaml against its schema
[group('verify')]
verify-artifacts:
    @bash scripts/verify-artifacts.sh

# verify each agent's # tool_group: matches its tools/disallowedTools list
[group('verify')]
verify-tool-groups:
    @bash scripts/verify-tool-groups.sh

# ─── Claude Code agent launchers ──────────────────────────────────────
# Convention: one recipe per launchable Claude Code agent UX. Recipes pre-apply
# the right --output-style so users don't have to remember flag names.
# Launchers land as their underlying agents land in later PRs in the v2 stack.
# (Empty for now — populated in PR 7+ when canvas-author + canvas-flow output
# styles ship.)
