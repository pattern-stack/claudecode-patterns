#!/usr/bin/env bash
# emit.sh — zero-dependency hook shim. POSTs stdin to the local ap dashboard.
#
# Replaces emit.mjs so the plugin works on machines without node installed
# (Python / Go / Rust projects, asdf/mise/nvm pinning to a missing version).
#
# Fallback port 3456 mirrors DEFAULT_DASHBOARD_PORT in
# packages/agent-cli/src/constants.ts. Keep in sync.
#
# Always exits 0 — hooks must never block the session. Dashboard-absent is
# the silent no-op path: curl fails, we log to stderr, move on.

EVENT="${1:-Unknown}"
BASE="${AP_DASHBOARD_URL:-http://localhost:3456}"

BODY="$(cat)"
[ -z "$BODY" ] && BODY='{}'

CURL_ARGS=(-fsS -m 0.5 -X POST -H 'content-type: application/json' --data-binary "$BODY")
if [ -n "${AP_RUNNER_CORRELATION_ID:-}" ]; then
  CURL_ARGS+=(-H "x-ap-runner-correlation-id: ${AP_RUNNER_CORRELATION_ID}")
fi

ERR="$(curl "${CURL_ARGS[@]}" "${BASE}/hooks/${EVENT}" 2>&1 >/dev/null)" || \
  echo "[ap-hook] ${EVENT}: ${ERR:-request failed}" >&2

exit 0
