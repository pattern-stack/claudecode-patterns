#!/usr/bin/env bash
#
# ensure-cc-bridge.sh — SessionStart hook: install + run cc-bridge, then
# register this session so the daemon starts tailing its transcript JSONL.
#
# Behavior:
#   - No-op when CC_BRIDGE_AUTOSTART=0.
#   - No-op silently when the binary can't be installed (no network, no
#     curl, no tarball for this platform). The chat view will be missing
#     content but logs (hook events) still flow via emit.sh.
#   - Spawns the bridge detached on $CC_BRIDGE_PORT if /health doesn't
#     answer yet, then waits up to ~6s for /health to come up and POSTs
#     a register call carrying session_id + transcript_path + cwd.
#
# Always exits 0 — telemetry-side failures must never block the user's
# Claude Code session.

set -u

# ---- Opt-out ----------------------------------------------------------------
if [[ "${CC_BRIDGE_AUTOSTART:-1}" = "0" ]]; then
  exit 0
fi

# ---- Resolve plugin root + sourced helpers ---------------------------------
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
export PLUGIN_ROOT

# shellcheck source=../lib/tools.sh
source "${PLUGIN_ROOT}/lib/tools.sh"

# ---- Capture stdin payload BEFORE doing anything blocking ------------------
PAYLOAD="$(cat 2>/dev/null || true)"

SESSION_ID=""
TRANSCRIPT_PATH=""
CWD=""
if [[ -n "$PAYLOAD" ]] && command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)"
  TRANSCRIPT_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)"
  CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)"
fi

# Without session_id or transcript_path there's nothing to register — bail.
[[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" ]] && exit 0

# ---- Resolve (and lazily install) the binary -------------------------------
BIN="$(ensure_tool cc-bridge)"
[[ -z "$BIN" || ! -x "$BIN" ]] && exit 0   # silent skip

# ---- State paths -----------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/cc-bridge"
mkdir -p "$STATE_DIR"
LOG_FILE="${STATE_DIR}/server.log"

PORT="${CC_BRIDGE_PORT:-3994}"
BRIDGE_URL="http://localhost:${PORT}"

# ---- Spawn (only if not already healthy) -----------------------------------
spawn_bridge() {
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup env CC_BRIDGE_PORT="$PORT" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
  else
    nohup env CC_BRIDGE_PORT="$PORT" "$BIN" >>"$LOG_FILE" 2>&1 < /dev/null &
  fi
  disown 2>/dev/null || true
}

if command -v curl >/dev/null 2>&1; then
  if ! curl -sS -m 0.3 "${BRIDGE_URL}/health" >/dev/null 2>&1; then
    spawn_bridge
  fi
else
  # No curl — register POST will silently fail too, nothing to do.
  exit 0
fi

# ---- Wait-for-health then register the session -----------------------------
(
  for _ in $(seq 1 30); do
    if curl -sS -m 0.3 "${BRIDGE_URL}/health" >/dev/null 2>&1; then
      curl -sS -m 1 -X POST "${BRIDGE_URL}/sessions/register" \
        -H "content-type: application/json" \
        --data "$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' \
                  "$SESSION_ID" "$TRANSCRIPT_PATH" "$CWD")" \
        >/dev/null 2>&1 || true
      exit 0
    fi
    sleep 0.2
  done
  printf '[ensure-cc-bridge] bridge did not bind within 6s; session %s not registered\n' \
    "$SESSION_ID" >>"$LOG_FILE"
) >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
