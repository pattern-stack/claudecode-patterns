#!/bin/bash
# Example take script — the thing record-desktop-demo.sh drives while recording.
#
# This one proves a CLI and a web app agree: a terminal command changes who the
# browser is logged in as. That claim needs both windows and real app switching,
# which is why it is a desktop capture and not a guided tour.
#
# Focus-stealing by design. Only run while a recording is rolling.
set -uo pipefail

# Defaults are the two apps every mac already has. Override for your own setup —
# the process name is not always the app name (Ghostty reports lowercase
# `ghostty`), which is why they are separate knobs:
#
#   TERM_APP=Ghostty TERM_PROC=ghostty BROWSER_APP=Arc BROWSER_PROC=Arc ./take.sh
#
# Prefer Chrome over Arc whenever the take also drives CDP — see "Known limits":
# Playwright's connectOverCDP hangs against Arc.
TERM_APP=${TERM_APP:-Terminal}
TERM_PROC=${TERM_PROC:-Terminal}
BROWSER_APP=${BROWSER_APP:-Google Chrome}
BROWSER_PROC=${BROWSER_PROC:-Google Chrome}

front() { osascript -e 'tell application "System Events" to return name of first application process whose frontmost is true'; }

# Guard every focus change: activate, poll until frontmost matches, only then
# type. Without this a mistimed switch types into the wrong window silently.
focus() {
  osascript -e "tell application \"$1\" to activate" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.15
    [ "$(front)" = "$2" ] && return 0
  done
  echo "ABORT: could not focus $1 (frontmost=$(front))" >&2
  exit 1
}

say()    { osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null; }
enter()  { osascript -e 'tell application "System Events" to key code 36' >/dev/null; }
down()   { osascript -e 'tell application "System Events" to key code 125' >/dev/null; }
reload() { osascript -e 'tell application "System Events" to keystroke "r" using command down' >/dev/null; }

run_command() { # $1 = command, $2 = arrow-key presses into its picker
  focus "$TERM_APP" "$TERM_PROC"
  sleep 0.35
  say "$1"; enter
  sleep 0.85                     # picker is up almost at once — start moving
  for _ in $(seq 1 "$2"); do
    down
    sleep 0.18                   # arrows read better than a typed filter, and
  done                           # fuzzy input surprises: "sd" can select "sdr"
  sleep 0.3
  enter
  sleep 1.1                      # tab out nearly immediately after committing
}

show_browser() {
  # Tabbing out fast means the command is still finishing, so the wait lands
  # here — which reads as a person waiting to refresh, not as dead air.
  focus "$BROWSER_APP" "$BROWSER_PROC"
  sleep 2.9
  reload
  sleep 4.4                      # a Vite dev reload is white for ~4s
}

focus "$BROWSER_APP" "$BROWSER_PROC"; sleep 1.9   # open on the page under test
run_command "just login" 4
show_browser
run_command "just login" 2
show_browser
focus "$TERM_APP" "$TERM_PROC"
sleep 0.4
echo "take complete"
