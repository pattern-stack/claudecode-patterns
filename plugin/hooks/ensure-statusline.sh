#!/usr/bin/env bash
# ensure-statusline.sh — SessionStart hook that keeps the SDLC statusline
# wiring in ~/.claude/settings.json fresh, idempotently.
#
# Policy: opt-out. The plugin ships a statusline, so by default users get it.
# We only touch wiring the plugin itself owns (paths under
# claudecode-patterns/sdlc/). User-custom and third-party statusLines are
# left alone. Once a user removes our wiring, a marker file ensures we never
# re-install it.
#
# Decision table:
#
#   ~/.claude/settings.json .statusLine state    | marker | action
#   ---------------------------------------------|--------|----------------------------
#   absent / null                                | absent | INSTALL + write marker + log
#   absent / null                                | exists | no-op (user removed it)
#   ours, references dashboard-status.sh         |   *    | UPGRADE + write marker + log
#   ours, references statusline.sh               |   *    | no-op (ensure marker present)
#   third-party / user-custom                    |   *    | no-op (don't touch)
#
# Always exits 0 — hook failures must not block session start.
# Tolerates missing jq, malformed settings.json, and concurrent sessions.

set -uo pipefail

SETTINGS="${HOME}/.claude/settings.json"
MARKER_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/claudecode-patterns"
MARKER="${MARKER_DIR}/statusline-installed"
DESIRED_CMD='bash $HOME/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/statusline.sh 2>/dev/null'
OWNED_FRAGMENT='claudecode-patterns/sdlc/'
STALE_FRAGMENT='dashboard-status.sh'

# Hard dependency: jq. Without it we can't safely read/write JSON.
command -v jq >/dev/null 2>&1 || exit 0

mark_installed() {
  mkdir -p "$MARKER_DIR" 2>/dev/null || return 0
  : > "$MARKER" 2>/dev/null || return 0
}

write_settings() {
  # $1 = new full settings JSON on stdin (already validated). Atomic via temp+mv.
  local tmp
  tmp="$(mktemp "${SETTINGS}.XXXXXX")" || return 1
  cat > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$SETTINGS" || { rm -f "$tmp"; return 1; }
}

current_cmd=""
if [[ -f "$SETTINGS" ]]; then
  # If the file is malformed, bail without touching anything.
  if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
    exit 0
  fi
  current_cmd="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"
fi

# Case 1: nothing wired.
if [[ -z "$current_cmd" ]]; then
  if [[ -f "$MARKER" ]]; then
    exit 0
  fi
  # Install. If settings.json doesn't exist yet, start from `{}`.
  if [[ ! -f "$SETTINGS" ]]; then
    mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null
    echo '{}' > "$SETTINGS" 2>/dev/null || exit 0
  fi
  if jq --arg cmd "$DESIRED_CMD" \
        '.statusLine = {type: "command", command: $cmd}' \
        "$SETTINGS" 2>/dev/null \
       | write_settings; then
    mark_installed
    printf 'sdlc: installed statusline wiring in ~/.claude/settings.json (remove .statusLine to disable)\n' >&2
  fi
  exit 0
fi

# Case 2: wired, points at our stale dashboard-status.sh.
if [[ "$current_cmd" == *"$OWNED_FRAGMENT"* && "$current_cmd" == *"$STALE_FRAGMENT"* ]]; then
  if jq --arg cmd "$DESIRED_CMD" \
        '.statusLine.command = $cmd' \
        "$SETTINGS" 2>/dev/null \
       | write_settings; then
    mark_installed
    printf 'sdlc: upgraded statusline wiring (dashboard-status.sh → statusline.sh)\n' >&2
  fi
  exit 0
fi

# Case 3: wired, points at our current statusline.sh. Ensure marker exists
# so an absent-state next time (user-removal) is correctly distinguished
# from a never-installed state.
if [[ "$current_cmd" == *"$OWNED_FRAGMENT"*"statusline.sh"* ]]; then
  [[ -f "$MARKER" ]] || mark_installed
  exit 0
fi

# Case 4: third-party / user-custom. Leave alone.
exit 0
