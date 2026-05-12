#!/usr/bin/env bash
# dashboard-status.sh — status-line component for the ap playground.
#
# Outputs a single OSC 8 hyperlink wrapping a colored dot + "dashboard" label,
# pointing at http://localhost:${AP_DASHBOARD_PORT:-3456}. Green = the
# dashboard's /health endpoint responds within 200ms; red = no response.
#
# Designed to be embedded in ~/.claude/settings.json `statusLine.command`.
# Always exits 0 (status-line scripts must be silent on failure).
#
# Wiring:
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/dashboard-status.sh"
#   }
#
# Glob picks the latest installed sdlc version automatically; survives
# `/plugin update sdlc` without manual rewiring.

PORT="${AP_DASHBOARD_PORT:-3456}"
URL="http://localhost:${PORT}"

if curl -fs -m 0.2 "${URL}/health" -o /dev/null 2>/dev/null; then
  COLOR='\033[32m'  # green
else
  COLOR='\033[31m'  # red
fi
RESET='\033[0m'

# OSC 8 hyperlink format:  ESC ]8;;URL ESC \  TEXT  ESC ]8;; ESC \
# iTerm2 and other modern terminals make TEXT clickable. Terminals without
# OSC 8 support degrade to printing TEXT plus the bracketing escapes (visible
# as garbage in legacy terms — Doug uses iTerm2 so this is fine).
printf '\033]8;;%s\033\\%b●%b dashboard\033]8;;\033\\' "$URL" "$COLOR" "$RESET"
