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
# Bootstrap-event replay:
#   When this script HAS to spawn the dashboard (i.e. it was down), the
#   SessionStart event that's currently firing has already raced against an
#   unstarted server — the parallel emit.mjs hook POSTed before the server
#   bound the port and got connection-refused. To prevent the bootstrap
#   session from being invisible on the dashboard, we capture the SessionStart
#   payload from stdin, detach a small subshell that polls /health until the
#   dashboard is up, then re-POSTs the payload to /hooks/SessionStart. When
#   the dashboard is already up at probe time we skip this entirely (emit.mjs
#   in the parallel hook handles it normally and we'd cause a duplicate).
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

# ---- Capture stdin payload while the file descriptor is fresh ----------------
# Read everything CC piped to us so we can replay it after spawning. If stdin
# is empty (e.g. manual invocation), $PAYLOAD stays empty and the replay
# branch below becomes a no-op POST guarded by length check.
PAYLOAD="$(cat 2>/dev/null || true)"

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

# ---- Bootstrap-event replay --------------------------------------------------
# Wait for /health, then POST the captured SessionStart payload. Runs in a
# detached subshell so this script returns immediately (the hook is async
# with a 5s timeout; we can't afford to block on dashboard startup).
if [[ -n "${PAYLOAD}" ]]; then
  (
    # Poll /health up to ~6s (30 × 200ms). ap normally binds within 1–2s.
    for _ in $(seq 1 30); do
      if curl -sS -m 0.3 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
        # Server's up — replay the SessionStart event we got piped earlier.
        curl -sS -m 1 -X POST "http://localhost:${PORT}/hooks/SessionStart" \
          -H "content-type: application/json" \
          --data "${PAYLOAD}" >/dev/null 2>&1 || true
        exit 0
      fi
      sleep 0.2
    done
    # Health never came up in time. Log and give up silently.
    printf '[ensure-playground] dashboard did not bind within 6s; SessionStart replay skipped\n' \
      >>"${LOG_FILE}"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
