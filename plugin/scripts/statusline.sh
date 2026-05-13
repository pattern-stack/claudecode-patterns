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

project="$(basename "$cwd")"

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
# Output segments are pre-styled (OSC 8 link on PR, semantic color on CI)
# so they break out of the global dim wrap applied to other segments.
pr=""
ci=""
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" ]] && have gh && have jq; then
  repo_slug="$(git -C "$cwd" remote get-url origin 2>/dev/null \
                 | sed -E 's#.*github\.com[:/]##; s/\.git$//')"
  gh_raw="$(cached_run 20 "gh-pr-${branch//\//_}" \
    gh -R "$repo_slug" pr view "$branch" --json number,state,statusCheckRollup)"
  if [[ -n "$gh_raw" ]]; then
    pr_num="$(jq -r '.number // empty' <<<"$gh_raw" 2>/dev/null)"
    pr_state="$(jq -r '.state // empty' <<<"$gh_raw" 2>/dev/null)"
    if [[ -n "$pr_num" ]]; then
      pr_label="PR #${pr_num}"
      if [[ -n "$pr_state" && "$pr_state" != "OPEN" ]]; then
        pr_state_lc="$(printf '%s' "$pr_state" | tr '[:upper:]' '[:lower:]')"
        pr_label="${pr_label} ${pr_state_lc}"
      fi
      pr_url="https://github.com/${repo_slug}/pull/${pr_num}"
      # OSC 8 hyperlink + bold (no dim) so the PR pops out of the dim line.
      # Reset → bold → OSC8 open → label → OSC8 close → reset → dim (resume).
      printf -v pr '\033[0m\033[1m\033]8;;%s\033\\%s\033]8;;\033\\\033[0m\033[2m' \
        "$pr_url" "$pr_label"
    fi
    ci_kind="$(jq -r '
      [.statusCheckRollup[]? | (.conclusion // .status // "")] as $c
      | {pass: ($c | map(select(. == "SUCCESS")) | length),
         fail: ($c | map(select(. == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED")) | length),
         run:  ($c | map(select(. == "IN_PROGRESS" or . == "QUEUED" or . == "PENDING" or . == "")) | length)}
      | if (.fail > 0) then "fail \(.fail)"
        elif (.run > 0) then "run \(.run)"
        elif (.pass > 0) then "pass \(.pass)"
        else empty end
    ' <<<"$gh_raw" 2>/dev/null)"
    if [[ -n "$ci_kind" ]]; then
      kind="${ci_kind%% *}"
      count="${ci_kind##* }"
      case "$kind" in
        fail) ci_text="CI ${count} failing";  ci_color=$'\033[31m' ;;  # red
        run)  ci_text="CI ${count} running";  ci_color=$'\033[33m' ;;  # yellow
        pass) ci_text="CI ${count} ✓";        ci_color=$'\033[32m' ;;  # green
      esac
      # Break out of dim, apply color, then resume dim for the trailing separator.
      ci=$'\033[0m'"${ci_color}${ci_text}"$'\033[0m\033[2m'
    fi
  fi
fi

# Optional cc-viewer dashboard pill. Reuses dashboard-status.sh which
# emits an OSC 8 hyperlink. Composed here so users get the segment "free"
# whenever the bundled cc-viewer is running on :3993.
dashboard=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$script_dir/dashboard-status.sh" ]] && have curl; then
  dashboard="$("$script_dir/dashboard-status.sh" 2>/dev/null || true)"
fi

# ----------------------------------------------------------------------------
# compose + center
# ----------------------------------------------------------------------------

segments=()
# Show project name when there's no ticket — otherwise the ticket implies repo context.
[[ -z "$ticket" && -n "$project" ]] && segments+=("$project")
[[ -n "$ticket"    ]] && segments+=("$ticket")
[[ -n "$branch"    ]] && segments+=("$branch")
[[ -n "$stack"     ]] && segments+=("$stack")
[[ -n "$pr"        ]] && segments+=("$pr")
[[ -n "$ci"        ]] && segments+=("$ci")
[[ -n "$dashboard" ]] && segments+=("$dashboard")

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

# Pad with non-breaking spaces (U+00A0) — Claude Code's UI trims leading
# regular whitespace, which left-aligns the line. NBSPs render the same
# width but survive the trim, giving us actual visual centering.
NBSP=$'\xc2\xa0'
padding=""
for ((i=0; i<pad; i++)); do padding+="$NBSP"; done

printf '%s%s' "$padding" "$line"
exit 0
