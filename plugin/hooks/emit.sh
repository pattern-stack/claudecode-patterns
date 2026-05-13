#!/usr/bin/env bash
# emit.sh — zero-dependency hook shim. POSTs stdin to the local cc-viewer.
#
# Replaces emit.mjs so the plugin works on machines without node installed
# (Python / Go / Rust projects, asdf/mise/nvm pinning to a missing version).
#
# Default port 3993 mirrors `port_default` for `cc-viewer` in
# plugin/lib/tools.json. Override via CC_VIEWER_URL (full base URL) or
# CC_VIEWER_PORT (port only, localhost assumed).
#
# Backwards compat: also honors $AP_DASHBOARD_URL for users mid-upgrade
# (existing sessions started before 0.1.10 still emitting to the ap port).
#
# Always exits 0 — hooks must never block the session. Dashboard-absent is
# the silent no-op path: curl fails, we log to stderr, move on.

EVENT="${1:-Unknown}"

# Pick the base URL — explicit > legacy > computed-from-port > default.
if [ -n "${CC_VIEWER_URL:-}" ]; then
  BASE="$CC_VIEWER_URL"
elif [ -n "${AP_DASHBOARD_URL:-}" ]; then
  BASE="$AP_DASHBOARD_URL"
elif [ -n "${CC_VIEWER_PORT:-}" ]; then
  BASE="http://localhost:${CC_VIEWER_PORT}"
else
  BASE="http://localhost:3993"
fi

BODY="$(cat)"
[ -z "$BODY" ] && BODY='{}'

CURL_ARGS=(-fsS -m 0.5 -X POST -H 'content-type: application/json' --data-binary "$BODY")
if [ -n "${AP_RUNNER_CORRELATION_ID:-}" ]; then
  CURL_ARGS+=(-H "x-ap-runner-correlation-id: ${AP_RUNNER_CORRELATION_ID}")
fi

ERR="$(curl "${CURL_ARGS[@]}" "${BASE}/hooks/${EVENT}" 2>&1 >/dev/null)" || \
  echo "[cc-viewer-hook] ${EVENT}: ${ERR:-request failed}" >&2

exit 0
