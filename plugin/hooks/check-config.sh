#!/usr/bin/env bash
# check-config.sh — UserPromptSubmit hook surfacing /sdlc:setup when sdlc.yml is missing.
#
# Replaces check-config.mjs to drop the node dependency.
#
# Returns a system-reminder block to the assistant on missing .claude/sdlc.yml,
# nudging it to suggest /sdlc:setup. Quiet otherwise. Wired into
# plugin/hooks/hooks.json under UserPromptSubmit.
#
# Hook protocol: write JSON to stdout. Schema:
#   { "hookSpecificOutput": { "hookEventName": "UserPromptSubmit", "additionalContext": "..." } }
# (See Claude Code hooks reference for full schema.)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -f "${PROJECT_DIR}/.claude/sdlc.yml" ]; then
  exit 0
fi

# Single-quoted heredoc — no shell expansion, backticks are literal.
# `\n` is emitted as the two-character escape sequence and JSON-decoded by
# the consumer into real newlines. Keep this text in sync with the
# source-of-truth in plugin/commands/setup.md if it changes.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"The sdlc plugin is installed but this project has no `.claude/sdlc.yml` configuration. The SDLC workflow commands (`/sdlc:plan`, `/sdlc:design`, `/sdlc:develop`, `/sdlc:orchestrate`, `/sdlc:sync-issues`, `/sdlc:canvas`) require it.\n\nSuggest the user run `/sdlc:setup` to scaffold the config interactively (4 questions: language, quality_profile, task_management, team_key). The setup command also wires the project's Justfile to the plugin's recipes and creates the `.claude/sdlc.justfile` symlink.\n\nIf the user is intentionally not using SDLC commands in this project (e.g. just using the plugin's skills/canvases), they can ignore this reminder — it appears once per prompt while `.claude/sdlc.yml` is absent and is silenced after `/sdlc:setup` completes."}}
JSON
