#!/usr/bin/env bash
# ensure-browser-agent.sh — SessionStart hook that keeps the browser-pilot
# agent installed in ~/.claude/agents/, idempotently.
#
# Why it exists: the browser MCP servers live in browser-pilot's frontmatter
# (`mcpServers:`), so they start only while that agent runs. Plugin-shipped
# agents ignore `mcpServers:`, so the agent has to be a user-level file; this
# hook copies it there from plugin/user-agents/ and refreshes it on update.
#
# Policy: opt-out, like ensure-statusline.sh. We only touch a file that carries
# our managed-by line. Once a user deletes the file, a marker file ensures we
# never re-install it.
#
# Decision table:
#
#   ~/.claude/agents/browser-pilot.md          | marker | action
#   -------------------------------------------|--------|---------------------------
#   absent                                     | absent | INSTALL + write marker + log
#   absent                                     | exists | no-op (user removed it)
#   ours (managed-by line), differs from ours  |   *    | UPDATE + write marker + log
#   ours, identical                            |   *    | no-op (ensure marker present)
#   no managed-by line (user's own copy)       |   *    | no-op (don't touch)
#
# A newly installed agent is picked up by the NEXT session (agents load at
# startup). Always exits 0 — hook failures must not block session start.

set -uo pipefail

SRC="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/user-agents/browser-pilot.md"
DEST="${HOME}/.claude/agents/browser-pilot.md"
MARKER_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/claudecode-patterns"
MARKER="${MARKER_DIR}/browser-agent-installed"
OWNED_LINE='# managed-by: claudecode-patterns sdlc'

[[ -f "$SRC" ]] || exit 0

mark_installed() {
  mkdir -p "$MARKER_DIR" 2>/dev/null || return 0
  : > "$MARKER" 2>/dev/null || return 0
}

install_agent() {
  # Atomic via temp+mv so a concurrent session never reads a half-written file.
  local tmp
  mkdir -p "$(dirname "$DEST")" 2>/dev/null || return 1
  tmp="$(mktemp "${DEST}.XXXXXX")" || return 1
  cat "$SRC" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$DEST" || { rm -f "$tmp"; return 1; }
}

# Case 1: not installed.
if [[ ! -e "$DEST" ]]; then
  [[ -f "$MARKER" ]] && exit 0
  if install_agent; then
    mark_installed
    printf 'sdlc: installed the browser-pilot agent in ~/.claude/agents/ (its browser servers start only when it runs; delete the file to opt out)\n' >&2
  fi
  exit 0
fi

# Case 2: the user's own copy. Leave alone.
grep -qF "$OWNED_LINE" "$DEST" 2>/dev/null || exit 0

# Case 3: ours and out of date.
if ! cmp -s "$SRC" "$DEST"; then
  if install_agent; then
    mark_installed
    printf 'sdlc: updated the browser-pilot agent in ~/.claude/agents/\n' >&2
  fi
  exit 0
fi

# Case 4: ours and current. Ensure the marker exists so a later deletion reads
# as an opt-out, not as never-installed.
[[ -f "$MARKER" ]] || mark_installed
exit 0
