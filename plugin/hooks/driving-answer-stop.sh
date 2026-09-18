#!/usr/bin/env bash
# driving-answer-stop.sh — PostToolUse hook for the Driving output style.
#
# A working turn in driving mode ends by queuing `/sdlc:answer` on its own
# Herdr pane, so the answer arrives as a message of its own (the phone reads a
# whole turn aloud, working notes included). Left alone, the model then writes
# a closing summary in the working turn, and the listener hears the result
# twice. Wording did not stop that; ending the turn does. Once the queue
# command has run, this returns `{"continue": false}`: Claude Code shows the
# tool result and makes no further model call, and the queued command runs.
#
# Wired in hooks.json with `if: Bash(herdr pane send-text *)`, so it spawns
# only for that command; the check below keeps it to the answer queue alone.
# FAILS OPEN: unparseable input means no output, and the turn carries on.

set -u
input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
  cmd="$(printf '%s' "$input" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
fi

case "$cmd" in
  *"herdr pane send-text"*"/sdlc:answer"*) printf '{"continue": false}\n' ;;
esac
exit 0
