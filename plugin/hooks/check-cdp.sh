#!/usr/bin/env bash
# SessionStart nudge: if this dev uses the /browser skill's user-browser mode
# (signalled by BROWSER_PREFERENCE in .claude/settings.local.json) and CDP
# :9222 is dark, emit a one-shot reminder with their browser's relaunch
# command. Silent in every other case — devs who never set a preference are
# never nagged.
set -euo pipefail

SETTINGS="${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json"
[ -f "$SETTINGS" ] || exit 0

# Tolerate machines without jq.
if command -v jq >/dev/null 2>&1; then
  PREF=$(jq -r '.env.BROWSER_PREFERENCE // empty' "$SETTINGS" 2>/dev/null || true)
else
  PREF=$(grep -o '"BROWSER_PREFERENCE"[[:space:]]*:[[:space:]]*"[a-z]*"' "$SETTINGS" 2>/dev/null | sed 's/.*:[[:space:]]*"\([a-z]*\)"/\1/' || true)
fi
[ -n "${PREF:-}" ] || exit 0

# CDP reachable → nothing to say.
if curl -sS -m 1 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
  exit 0
fi

case "$PREF" in
  arc)      APP="Arc" ;;
  chrome)   APP="Google Chrome" ;;
  chromium) APP="Chromium" ;;
  brave)    APP="Brave Browser" ;;
  edge)     APP="Microsoft Edge" ;;
  vivaldi)  APP="Vivaldi" ;;
  opera)    APP="Opera" ;;
  *)        exit 0 ;;
esac

echo "browser-skill: CDP :9222 is not reachable, so /browser user-browser mode (your ${PREF} session) is unavailable this session."
if [ "$PREF" = "arc" ]; then
  echo "Relaunch (Arc drops the flag on every Cmd-Q): osascript -e 'quit app \"Arc\"' ; sleep 2 ; pkill -9 -f \"/Applications/Arc.app/\" 2>/dev/null ; sleep 1 ; open -a \"Arc\" --args --remote-debugging-port=9222"
  echo "Make it sticky: defaults write company.thebrowser.Browser EnableRemoteDebugging -bool true"
else
  echo "Relaunch after a full quit: open -a \"${APP}\" --args --remote-debugging-port=9222"
fi
echo "Ignore this if you don't need the browser this session — headless playwright + lighthouse still work."
exit 0
