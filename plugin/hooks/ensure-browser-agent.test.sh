#!/usr/bin/env bash
# Tests for ensure-browser-agent.sh — install, refresh, opt-out, user copy.
# Runs against a throwaway HOME and XDG_CACHE_HOME. Run: bash plugin/hooks/ensure-browser-agent.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/ensure-browser-agent.sh"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PLUGIN_ROOT/user-agents/browser-pilot.md"
pass=0 fail=0

ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

fresh() {
  T="$(mktemp -d)"
  export HOME="$T/home" XDG_CACHE_HOME="$T/cache" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  mkdir -p "$HOME"
  DEST="$HOME/.claude/agents/browser-pilot.md"
  MARKER="$XDG_CACHE_HOME/claudecode-patterns/browser-agent-installed"
}
run() { bash "$HOOK" 2>/dev/null; echo $?; }

echo "install:"
fresh
[[ "$(run)" == 0 ]] && ok 'exits 0' || bad 'exits 0'
cmp -s "$SRC" "$DEST" && ok 'installs an exact copy' || bad 'installs an exact copy'
[[ -f "$MARKER" ]] && ok 'writes the marker' || bad 'writes the marker'

echo "refresh:"
printf '\nstale line\n' >> "$DEST"
run >/dev/null
cmp -s "$SRC" "$DEST" && ok 'replaces an out-of-date managed copy' || bad 'replaces an out-of-date managed copy'

echo "opt-out:"
rm -f "$DEST"
run >/dev/null
[[ ! -e "$DEST" ]] && ok 'does not reinstall after the user deletes it' || bad 'does not reinstall after the user deletes it'

echo "user copy:"
fresh
mkdir -p "$(dirname "$DEST")"
printf -- '---\nname: browser-pilot\n---\nmine\n' > "$DEST"
run >/dev/null
grep -q '^mine$' "$DEST" && ok 'leaves a copy without the managed-by line alone' || bad 'leaves a copy without the managed-by line alone'

echo "missing source:"
fresh
CLAUDE_PLUGIN_ROOT="$T/nowhere" bash "$HOOK" 2>/dev/null; rc=$?
[[ "$rc" == 0 && ! -e "$DEST" ]] && ok 'exits 0 and installs nothing without a source' || bad 'exits 0 and installs nothing without a source'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" == 0 ]]
