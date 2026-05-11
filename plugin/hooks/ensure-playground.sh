#!/usr/bin/env bash
#
# ensure-playground.sh — start `ap playground` in the background if it isn't
# already running. Wired as an async SessionStart hook so every Claude Code
# session has a live dashboard at http://localhost:${AP_DASHBOARD_PORT:-3456}
# without the user remembering to start it.
#
# Behavior:
#   - No-op when `AP_AUTO_START=0`.
#   - No-op when `ap` is not on PATH (silently — the rest of the plugin
#     works fine without telemetry, and we don't want hook noise in CI).
#   - No-op when the dashboard health endpoint already responds.
#   - Otherwise spawn `nohup ap playground --no-open` detached, logging to
#     ~/.local/state/ap/playground.log (XDG_STATE_HOME aware).
#
# Always exits 0 — a failure to start telemetry should never break the user's
# Claude Code session. Errors are appended to the log file for postmortem.

set -e

# ---- Opt-out via env ---------------------------------------------------------
if [[ "${AP_AUTO_START:-1}" = "0" ]]; then
  exit 0
fi

# ---- Required tooling --------------------------------------------------------
if ! command -v ap >/dev/null 2>&1; then
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  # No way to probe — bail rather than risk spawning duplicates.
  exit 0
fi

# ---- Already running? --------------------------------------------------------
PORT="${AP_DASHBOARD_PORT:-3456}"
if curl -sS -m 0.3 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
  exit 0
fi

# ---- Log location ------------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/ap"
mkdir -p "${STATE_DIR}"
LOG_FILE="${STATE_DIR}/playground.log"

# ---- Spawn detached ----------------------------------------------------------
# - `setsid` (Linux) / `nohup` (mac+linux) keeps the child alive after the
#   hook process exits.
# - `>>` so subsequent restarts append rather than truncate (easier debugging).
# - `&` + `disown` so this script doesn't wait for the child.
#
# Race condition note: if two CC sessions start within milliseconds of each
# other, both probes may return failure and both spawn `ap playground`. The
# second will fail to bind to PORT and exit; the first owns the dashboard.
# Harmless but visible in the log — left as v1 behavior.
if command -v setsid >/dev/null 2>&1; then
  setsid nohup ap playground --no-open >>"${LOG_FILE}" 2>&1 < /dev/null &
else
  nohup ap playground --no-open >>"${LOG_FILE}" 2>&1 < /dev/null &
fi
disown 2>/dev/null || true

exit 0
