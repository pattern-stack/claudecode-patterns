#!/usr/bin/env bash
#
# ensure-cc-viewer.sh — SessionStart hook: make sure the bundled cc-viewer
# dashboard is installed and running.
#
# Replaces ensure-playground.sh. The dashboard is now shipped as a
# single-file binary attached to this plugin's GH release (one tarball per
# platform). `plugin/lib/tools.sh::ensure_tool` resolves the binary path,
# downloading on first use under ~/.local/state/cc-viewer/bin/.
#
# Behavior:
#   - No-op when CC_VIEWER_AUTOSTART=0.
#   - No-op silently when the binary couldn't be installed (no network,
#     no curl, no tarball for this platform, etc.). Telemetry is optional.
#   - No-op when the dashboard health endpoint already responds.
#   - Otherwise spawns the binary detached, logging to
#     ~/.local/state/cc-viewer/server.log, then re-POSTs the captured
#     SessionStart payload after /health comes up (so the bootstrap session
#     isn't invisible on the dashboard).
#
# Always exits 0 — failure to start telemetry must never break the user's
# Claude Code session.

set -u

# ---- Opt-out ----------------------------------------------------------------
if [[ "${CC_VIEWER_AUTOSTART:-1}" = "0" ]]; then
  exit 0
fi

# ---- Resolve plugin root + sourced helpers ---------------------------------
# Hook commands are template-expanded by CC, so $CLAUDE_PLUGIN_ROOT is set
# when this script is invoked from hooks.json.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]]; then
  # Last-ditch — script is co-located with hooks/ inside the plugin tree.
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
export PLUGIN_ROOT

# shellcheck source=../lib/tools.sh
source "${PLUGIN_ROOT}/lib/tools.sh"

# ---- Capture stdin payload BEFORE doing anything blocking ------------------
PAYLOAD="$(cat 2>/dev/null || true)"

# ---- Resolve (and lazily install) the binary -------------------------------
BIN="$(ensure_tool cc-viewer)"
[[ -z "$BIN" || ! -x "$BIN" ]] && exit 0   # silent skip

# ---- Already running? ------------------------------------------------------
PORT="${CC_VIEWER_PORT:-3993}"
if command -v curl >/dev/null 2>&1; then
  if curl -sS -m 0.3 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    exit 0
  fi
fi

# ---- Spawn detached --------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/cc-viewer"
mkdir -p "$STATE_DIR"
LOG_FILE="${STATE_DIR}/server.log"

# Race condition note: two CC sessions starting within milliseconds can
# both pass the /health probe and both spawn. The second will fail to
# bind PORT and exit; the first owns the dashboard. Harmless but visible
# in the log.
if command -v setsid >/dev/null 2>&1; then
  setsid nohup env PORT="$PORT" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
else
  nohup env PORT="$PORT" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
fi
disown 2>/dev/null || true

# ---- Bootstrap-event replay ------------------------------------------------
# The parallel emit.sh hook POSTed to /hooks/SessionStart before the server
# bound — connection refused. Re-POST the captured payload once the server
# is up so this session shows up on the dashboard.
if [[ -n "$PAYLOAD" ]] && command -v curl >/dev/null 2>&1; then
  (
    for _ in $(seq 1 30); do
      if curl -sS -m 0.3 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
        curl -sS -m 1 -X POST "http://localhost:${PORT}/hooks/SessionStart" \
          -H "content-type: application/json" \
          --data "$PAYLOAD" >/dev/null 2>&1 || true
        exit 0
      fi
      sleep 0.2
    done
    printf '[ensure-cc-viewer] dashboard did not bind within 6s; SessionStart replay skipped\n' \
      >>"$LOG_FILE"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
