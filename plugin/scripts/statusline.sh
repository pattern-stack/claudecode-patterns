#!/usr/bin/env bash
# statusline.sh — full statusline for the sdlc plugin.
#
# Renders one centered line, in CC's default dim style:
#
#   <TEAM>-N  ·  branch  ·  st <stack>  ·  PR #N <state>  ·  CI <rollup>  ·  ● dashboard
#
# Every segment is independent — each drops out cleanly when its source
# is absent (no ticket in branch, no `st`, no `gh`, no `ap`, etc.).
#
# Constraints from the platform:
#   - Plugins cannot ship a `statusLine` setting (only `agent` and
#     `subagentStatusLine` are valid in plugin settings.json — see
#     reference/statusline.md). Users wire this script into their own
#     ~/.claude/settings.json:
#
#       {
#         "statusLine": {
#           "type": "command",
#           "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh",
#           "padding": 1,
#           "refreshInterval": 5
#         }
#       }
#
#     The `${CLAUDE_PLUGIN_ROOT}` token is substituted at config-parse time.
#     A version-pinned alternative for hand-rolled wiring:
#
#       "command": "bash ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/statusline.sh"
#
# Configuration:
#   - Ticket prefix is read from .claude/sdlc.yml `team_key` (e.g. `AP`,
#     `PSC`). When sdlc.yml is absent or unreadable the ticket segment
#     is suppressed silently.
#
# Slow probes (`st status`, `gh pr view`) are cached on disk so the UI
# never blocks. Caches live in $XDG_CACHE_HOME/ccp-statusline/.
#
# Always exits 0. Statusline scripts must be silent on failure.

set -uo pipefail

input="$(cat 2>/dev/null || true)"

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

jqr() {
  have jq || { printf ''; return; }
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null || true
}

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ccp-statusline"
mkdir -p "$cache_dir" 2>/dev/null || true

# cached_run <ttl-seconds> <cache-key> <cmd...>
# Echoes cached value if fresh; otherwise runs cmd, caches stdout, echoes it.
# Failures cache as empty so we don't hammer broken commands.
cached_run() {
  local ttl="$1" key="$2"; shift 2
  local file="$cache_dir/$key"
  if [[ -f "$file" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0) ))
    if (( age < ttl )); then
      cat "$file"
      return
    fi
  fi
  local out
  out="$("$@" 2>/dev/null || true)"
  printf '%s' "$out" >"$file" 2>/dev/null || true
  printf '%s' "$out"
}

# ----------------------------------------------------------------------------
# data sources
# ----------------------------------------------------------------------------

cwd="$(jqr '.workspace.current_dir')"
[[ -z "$cwd" ]] && cwd="$PWD"

branch="$(git -C "$cwd" branch --show-current 2>/dev/null || true)"

# Project's ticket prefix from sdlc.yml `team_key`. Empty when no sdlc.yml.
team_key=""
if [[ -f "$cwd/.claude/sdlc.yml" ]]; then
  if have yq; then
    team_key="$(yq -r '.team_key // ""' "$cwd/.claude/sdlc.yml" 2>/dev/null || true)"
  else
    # Tolerant fallback: a single `team_key:` line, unquoted value.
    team_key="$(grep -E '^team_key:' "$cwd/.claude/sdlc.yml" 2>/dev/null \
                 | head -1 | sed -E 's/^team_key:[[:space:]]*"?([A-Z][A-Z0-9_-]*)"?.*$/\1/' || true)"
  fi
fi

# Ticket from branch (case-insensitive). Pick the highest-numbered match.
ticket=""
if [[ -n "$branch" && -n "$team_key" ]]; then
  prefix_lc="$(printf '%s' "$team_key" | tr '[:upper:]' '[:lower:]')"
  ticket="$(printf '%s\n' "$branch" \
    | grep -oiE "${prefix_lc}-[0-9]+" \
    | sort -t- -k2 -n \
    | tail -1 \
    | tr '[:lower:]' '[:upper:]' || true)"
fi

# `st` stack info. Skip on main/master and when no tracked stack.
stack=""
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]] && have st; then
  st_raw="$(cached_run 5 "st-status-${branch//\//_}" st status)"
  if [[ -n "$st_raw" && "$st_raw" != *"No tracked stacks"* ]]; then
    stack_name="$(printf '%s\n' "$st_raw" | awk 'NF{print; exit}' | sed -E 's/[[:space:]]+/ /g')"
    [[ -n "$stack_name" ]] && stack="st ${stack_name}"
  fi
fi

# PR state + CI rollup via gh. Single call, cached 20s.
pr=""
ci=""
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]] && have gh && have jq; then
  gh_raw="$(cached_run 20 "gh-pr-${branch//\//_}" \
    gh -R "$(git -C "$cwd" remote get-url origin 2>/dev/null \
              | sed -E 's#.*github\.com[:/]##; s/\.git$//')" \
    pr view "$branch" --json number,state,statusCheckRollup)"
  if [[ -n "$gh_raw" ]]; then
    pr_num="$(jq -r '.number // empty' <<<"$gh_raw" 2>/dev/null)"
    pr_state="$(jq -r '.state // empty' <<<"$gh_raw" 2>/dev/null)"
    if [[ -n "$pr_num" ]]; then
      pr="PR #${pr_num}"
      [[ -n "$pr_state" && "$pr_state" != "OPEN" ]] && pr="${pr} ${pr_state,,}"
    fi
    ci_summary="$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .status // "")] as $c
      | {pass: ($c | map(select(. == "SUCCESS")) | length),
         fail: ($c | map(select(. == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED")) | length),
         run:  ($c | map(select(. == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "")) | length)}
      | if (.fail > 0) then "CI \(.fail) failing"
        elif (.run > 0) then "CI \(.run) running"
        elif (.pass > 0) then "CI \(.pass) ✓"
        else empty end
    ' <<<"$gh_raw" 2>/dev/null)"
    [[ -n "$ci_summary" ]] && ci="$ci_summary"
  fi
fi

# Optional ap-playground dashboard pill. Reuses dashboard-status.sh which
# emits an OSC 8 hyperlink. Composed here so users get the segment "free"
# when ap is installed and running.
dashboard=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$script_dir/dashboard-status.sh" ]] && have curl; then
  dashboard="$("$script_dir/dashboard-status.sh" 2>/dev/null || true)"
fi

# ----------------------------------------------------------------------------
# compose + center
# ----------------------------------------------------------------------------

segments=()
[[ -n "$ticket"    ]] && segments+=("$ticket")
[[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]] && segments+=("$branch")
[[ -n "$stack"     ]] && segments+=("$stack")
[[ -n "$pr"        ]] && segments+=("$pr")
[[ -n "$ci"        ]] && segments+=("$ci")
[[ -n "$dashboard" ]] && segments+=("$dashboard")

# Fallback: project name + branch so the line is never empty.
if (( ${#segments[@]} == 0 )); then
  fallback="$(basename "$cwd")"
  [[ -n "$branch" ]] && fallback="$fallback (${branch})"
  segments+=("$fallback")
fi

joined=""
for i in "${!segments[@]}"; do
  if (( i == 0 )); then
    joined="${segments[i]}"
  else
    joined="${joined} · ${segments[i]}"
  fi
done

DIM=$'\033[2m'
RESET=$'\033[0m'
line="${DIM}${joined}${RESET}"

# Strip ANSI / OSC 8 for width measurement.
visible="$(printf '%s' "$joined" \
  | sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g' \
  | sed -E $'s/\x1b\\]8;[^\x1b]*\x1b\\\\//g')"
visible_width=$(printf '%s' "$visible" | wc -m | tr -d ' ')

cols="${COLUMNS:-0}"
if (( cols == 0 )) && have tput; then
  cols="$(tput cols 2>/dev/null || echo 80)"
fi
(( cols < 1 )) && cols=80

pad=$(( (cols - visible_width) / 2 ))
(( pad < 0 )) && pad=0

printf '%*s%s' "$pad" "" "$line"
exit 0
