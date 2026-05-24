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

# ---- State dir + expected version ------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/cc-viewer"
mkdir -p "$STATE_DIR"
LOG_FILE="${STATE_DIR}/server.log"
PORT="${CC_VIEWER_PORT:-3993}"

# The binary is version-pinned (cc-viewer-v<plugin-version>-<platform>); $BIN
# above already resolved to the installed plugin version. A running dashboard
# whose /health reports a different version — or none, i.e. an older binary
# predating the /health version field — is stale and gets restarted onto $BIN.
VERSION="$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)"

# Stop the running dashboard. Prefer the actual port listener (robust to
# setsid re-parenting); fall back to the recorded pid. TERM, brief wait, KILL.
stop_dashboard() {
  local pid="" rec
  if command -v lsof >/dev/null 2>&1; then
    pid="$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1)"
  fi
  if [[ -z "$pid" && -f "${STATE_DIR}/server.pid" ]]; then
    rec="$(cat "${STATE_DIR}/server.pid" 2>/dev/null)"
    [[ -n "$rec" ]] && kill -0 "$rec" 2>/dev/null && pid="$rec"
  fi
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "${STATE_DIR}/server.pid"
}

# ---- Already running? Current version → done; stale → self-upgrade ---------
if command -v curl >/dev/null 2>&1; then
  HEALTH="$(curl -sS -m 0.5 "http://localhost:${PORT}/health" 2>/dev/null)"
  if [[ -n "$HEALTH" ]]; then
    # Can't determine the expected version (no jq / missing plugin.json) —
    # don't second-guess a healthy server; leave it running.
    [[ -z "$VERSION" ]] && exit 0
    RUNNING_VERSION="$(printf '%s' "$HEALTH" | jq -r '.version // empty' 2>/dev/null)"
    if [[ "$RUNNING_VERSION" == "$VERSION" ]]; then
      exit 0   # up-to-date — nothing to do
    fi
    printf '[ensure-cc-viewer] running v%s, expected v%s — upgrading dashboard\n' \
      "${RUNNING_VERSION:-unknown}" "$VERSION" >>"$LOG_FILE"
    stop_dashboard
  fi
fi

# ---- Spawn detached --------------------------------------------------------
# Drop a warmup marker so the dashboard-status.sh statusline component can
# render yellow ("starting") during the bind window instead of red. The
# marker is cleared by dashboard-status.sh once /health responds, and
# treated as stale after WARMUP_SECONDS (see dashboard-status.sh).
date +%s > "${STATE_DIR}/warming-up" 2>/dev/null || true

# Race condition note: two CC sessions starting within milliseconds can
# both pass the /health probe and both spawn. The second will fail to
# bind PORT and exit; the first owns the dashboard. Harmless but visible
# in the log.
#
# CC_VIEWER_VERSION is echoed back by /health so the next session can tell
# whether the running dashboard matches the installed plugin version.
if command -v setsid >/dev/null 2>&1; then
  setsid nohup env PORT="$PORT" CC_VIEWER_VERSION="$VERSION" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
else
  nohup env PORT="$PORT" CC_VIEWER_VERSION="$VERSION" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
fi
echo $! > "${STATE_DIR}/server.pid" 2>/dev/null || true
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
