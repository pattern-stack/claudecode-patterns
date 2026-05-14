#!/usr/bin/env bash
#
# deregister-cc-bridge-session.sh — SessionEnd hook: tell cc-bridge to stop
# tailing this session's transcript and drop its in-memory state. cc-bridge
# does a final flush before removing the watcher, so any tail content that
# landed between the last watch event and this call is still forwarded.
#
# Silent on every failure path — telemetry never blocks the user.

set -u

# Opt-out — symmetric with ensure-cc-bridge.sh.
[[ "${CC_BRIDGE_AUTOSTART:-1}" = "0" ]] && exit 0

# Parse stdin payload to get session_id. CC's SessionEnd payload always
# carries it; jq is the only dependency.
PAYLOAD="$(cat 2>/dev/null || true)"
[[ -z "$PAYLOAD" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)"
[[ -z "$SESSION_ID" ]] && exit 0

PORT="${CC_BRIDGE_PORT:-3994}"

curl -sS -m 0.5 -X POST "http://localhost:${PORT}/sessions/deregister" \
  -H "content-type: application/json" \
  --data "$(printf '{"session_id":"%s"}' "$SESSION_ID")" \
  >/dev/null 2>&1 || true

exit 0
