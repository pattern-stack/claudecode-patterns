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

# verify all (canvases + tool groups + teammate tools + worktree hooks)
[group('verify')]
verify: verify-canvases verify-tool-groups verify-teammate-tools verify-worktree-hooks

# verify canvas instructions.yaml schemas
[group('verify')]
verify-canvases:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-canvases.sh"

# verify agent tool_group annotations
[group('verify')]
verify-tool-groups:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-tool-groups.sh"

# verify teammate footguns: allowlists carry SendMessage; Agent(...) scopes resolve
[group('verify')]
verify-teammate-tools:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-teammate-tools.sh"

# verify the plugin's own hooks.json never registers a WorktreeCreate provider hook
[group('verify')]
verify-worktree-hooks:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/verify-worktree-hooks.sh"

# ─── Doctor (harness/config health) ───────────────────────────────────

# diagnose Claude Code / sdlc misconfigurations (e.g. the WorktreeCreate provider-hook footgun)
[group('verify')]
doctor:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/doctor.sh"

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

# ─── Guided tours (UI walkthrough + verification) ─────────────────────
# Tour definitions live in THIS project at `.claude/tours/<name>.mjs`;
# the engine ships with the plugin. Both need a Chromium-based browser
# exposing CDP on :9222 — see the `browser` skill for launch commands.

# narrate a tour in the user's browser (cursor, highlights, captions)
[group('browser')]
tour tour_file *args:
    @cd .. && node "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/guided-tour.mjs" {{tour_file}} {{args}}

# run a tour as a check — screenshots + assertions + report.json, non-zero exit on failure
[group('browser')]
tour-verify tour_file *args:
    @cd .. && node "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/guided-tour.mjs" {{tour_file}} --verify {{args}}

# ─── Driving mode (hands-free spoken summaries) ───────────────────────
# Speaks a line aloud, one message at a time — the script holds a playback
# mutex so rapid consecutive messages queue instead of overlapping. See the
# `driving-mode` skill for the per-turn protocol. macOS only today.
#
# In driving mode itself, prefer calling scripts/driving-mode.mjs directly:
# this recipe adds just's startup to every utterance.

# speak a line aloud (backgrounded — queues behind anything already playing)
[group('voice')]
say text:
    @cd .. && node "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/driving-mode.mjs" {{quote(text)}} &

# ─── Canvas reconciliation ────────────────────────────────────────────

# list canvases vs sdlc.yml.canvases
[group('verify')]
canvases:
    @cd .. && bash "${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}/scripts/list-canvases.sh"

# print resolved plugin dir (debug)
[group('verify')]
where:
    @cd .. && echo "cwd: $(pwd)"; echo "plugin_dir: ${CLAUDE_PLUGIN_DIR:-$(dirname "$(realpath .claude/sdlc.justfile)")}"
