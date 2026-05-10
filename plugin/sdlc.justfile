# sdlc plugin — task runner
#
# Imported into the user's project Justfile via `mod sdlc '.claude/sdlc.justfile'`.
# Invoke recipes as `just sdlc::<recipe>` (e.g. `just sdlc::verify`).
#
# `.claude/sdlc.justfile` is a symlink → `${CLAUDE_PLUGIN_DIR}/sdlc.justfile`
# (created by /sdlc:setup; committed in the dogfood repo). Plugin updates flow
# through automatically — the user's repo doesn't see this file change.

# Plugin location is resolved at recipe-runtime via shell, not just-parse-time:
#   1. ${CLAUDE_PLUGIN_DIR} if set (Claude Code sets this when running plugin code).
#   2. realpath of .claude/sdlc.justfile (a symlink → this file's dir,
#      created by /sdlc:setup or committed in the dogfood repo).
# Recipes shell out via "$(_plugin_dir)" inline since just doesn't allow shell
# evaluation inside variable substitution that respects cwd at recipe time.

default:
    @just --list

# ─── Verify (SDLC config invariants) ──────────────────────────────────

# verify everything (canvases + tool groups)
[group('verify')]
verify: verify-canvases verify-tool-groups

# verify each canvas's instructions.yaml against its schema
[group('verify')]
verify-canvases:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-canvases.sh"

# verify each agent's # tool_group: matches its tools/disallowedTools list
[group('verify')]
verify-tool-groups:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-tool-groups.sh"

# ─── Claude Code agent launchers ──────────────────────────────────────
# One recipe per launchable Claude Code agent UX. Recipes pre-apply the
# right --output-style so users don't have to remember flag names.

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
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/list-canvases.sh"

# Print the resolved plugin directory (debug aid — useful when recipes can't find scripts)
[group('verify')]
where:
    @cd .. && echo "cwd: $(pwd)"; echo "plugin_dir: ${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}"
