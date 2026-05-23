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

# verify all (canvases + tool groups)
[group('verify')]
verify: verify-canvases verify-tool-groups

# verify canvas instructions.yaml schemas
[group('verify')]
verify-canvases:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-canvases.sh"

# verify agent tool_group annotations
[group('verify')]
verify-tool-groups:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-tool-groups.sh"

# ─── Claude Code agent launchers ──────────────────────────────────────
# One recipe per launchable Claude Code agent UX. Recipes pre-apply the
# right --output-style so users don't have to remember flag names.

# canvas-author — developer voice
[group('claude')]
canvas-dev:
    claude --agent canvas-author --output-style canvas-flow-developer

# canvas-author — seller voice
[group('claude')]
canvas-seller:
    claude --agent canvas-author --output-style canvas-flow-seller

# ─── Canvas reconciliation ────────────────────────────────────────────

# list canvases vs sdlc.yml.canvases
[group('verify')]
canvases:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/list-canvases.sh"

# print resolved plugin dir (debug)
[group('verify')]
where:
    @cd .. && echo "cwd: $(pwd)"; echo "plugin_dir: ${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}"
