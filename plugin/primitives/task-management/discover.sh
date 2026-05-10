#!/usr/bin/env bash
# discover.sh — discover task-management adapter context and emit a markdown
# block agents `@`-mention from `.claude/.session/tracker-context.md`.
# Colocated with the task-management primitive (port + adapter docs).
#
# Pluggable dispatch by `task_management:` in `.claude/sdlc.yml`:
#   github → GitHub Project v2 field IDs (project ID, Status field, option IDs
#            for Backlog/Planning/Ready/...)
#   linear → Linear team workflow states + label palette  [TODO: stub]
#   jira   → not implemented
#
# Wired into plugin.json `components.hooks.SessionStart`. Writes output to
# `${CLAUDE_PROJECT_DIR}/.claude/.session/tracker-context.md`. Agents read that
# file via `@`-mention so they don't need to know about the discovery
# mechanism.
#
# Halts SILENTLY (exit 0, empty output) when:
#   - .claude/sdlc.yml missing
#   - task_management resolves to nothing or an unsupported vendor
#   - vendor adapter prerequisites missing (gh CLI, MCP, etc.)
#   - vendor-specific discovery fails (permissions, network, etc.)
#
# By design: an empty `tracker-context.md` makes `@`-mention in agent prompts
# a no-op. Agents degrade to label-only behavior.
set -euo pipefail


# ─── Adapter: GitHub Projects v2 ─────────────────────────────────────
# Emits project ID + Status field ID + option IDs for /sdlc:design's
# Status auto-movement. Silent no-op if no project_number or auth fails.
discover_github() {
  local sdlc="$1"
  command -v gh >/dev/null 2>&1 || return 0

  local repo project_number owner
  repo="$(yq -r '.repo // ""' "$sdlc" 2>/dev/null)"
  project_number="$(yq -r '.project_number // ""' "$sdlc" 2>/dev/null)"
  [[ -n "$repo" && -n "$project_number" ]] || return 0
  owner="${repo%%/*}"

  # Detect owner type (organization vs user)
  local root
  if gh api "orgs/$owner" >/dev/null 2>&1; then
    root="organization"
  elif gh api "users/$owner" >/dev/null 2>&1; then
    root="user"
  else
    return 0
  fi

  local query response
  query="query(\$owner:String!,\$n:Int!){
    $root(login:\$owner){
      projectV2(number:\$n){
        id title url
        fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}
      }
    }
  }"
  response="$(gh api graphql -f query="$query" -f owner="$owner" -F n="$project_number" 2>/dev/null)" || return 0

  local project_id project_title project_url status_field
  project_id="$(echo "$response" | yq -r ".data.$root.projectV2.id // \"\"")"
  project_title="$(echo "$response" | yq -r ".data.$root.projectV2.title // \"\"")"
  project_url="$(echo "$response" | yq -r ".data.$root.projectV2.url // \"\"")"
  [[ -n "$project_id" ]] || return 0

  status_field="$(echo "$response" | yq -o=json '.data.'"$root"'.projectV2.fields.nodes[] | select(.name == "Status")' 2>/dev/null)"

  cat <<EOF
## Tracker context (task_management: github)

- Project: [$project_title]($project_url)
- Project node ID: \`$project_id\`
- Owner type: $root ($owner)
EOF

  if [[ -z "$status_field" || "$status_field" == "null" ]]; then
    echo ""
    echo "**No Status field on this project.** Specifier degrades to label-only when setting Status (sets \`state:*\` labels; skips \`gh project item-edit\`)."
    echo ""
    return 0
  fi

  local status_field_id
  status_field_id="$(echo "$status_field" | yq -r '.id')"
  echo "- Status field ID: \`$status_field_id\`"
  echo ""
  echo "### Status options"
  echo ""
  echo "Use these IDs in \`gh project item-edit --field-id <Status field ID> --option <option id>\`:"
  echo ""
  echo "$status_field" | yq -r '.options[] | "- " + .name + " → `" + .id + "`"'
  echo ""
  echo "If a recommended option (Backlog / On-Deck / Planning / Ready / In Progress / In Review / Done / Blocked / Cancelled) is missing above, the user must add it via the GitHub Project UI — \`gh\` CLI cannot create Status options programmatically. Specifier degrades to label-only for missing options."
  echo ""
}


# ─── Adapter: Linear (stub) ──────────────────────────────────────────
# v1 placeholder. Linear's analogue would be: discover the team's workflow
# states (Backlog / Unstarted / Started / Completed / Canceled state types) +
# label palette IDs and emit a similar context block. Linear MCP exposes
# `list_issue_statuses` and `list_issue_labels` — wire those when needed.
discover_linear() {
  : # Silent no-op for v1.
  # When implemented:
  #   local sdlc="$1"
  #   local team_key="$(yq -r '.team_key // ""' "$sdlc")"
  #   [[ -n "$team_key" ]] || return 0
  #   ... call MCP via gh-equivalent or manual API ...
  #   ... emit ## Tracker context (task_management: linear) block ...
}


# ─── Dispatch ────────────────────────────────────────────────────────
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SDLC="$PROJECT_ROOT/.claude/sdlc.yml"

# Silent-exit on missing prerequisites
[[ -f "$SDLC" ]] || exit 0
command -v yq >/dev/null 2>&1 || exit 0

TM="$(yq -r '.task_management // ""' "$SDLC" 2>/dev/null)"

case "$TM" in
  github)  discover_github  "$SDLC"  ;;
  linear)  discover_linear  "$SDLC"  ;;
  jira)    : ;;  # not implemented; silent no-op
  *)       : ;;  # unknown / unset; silent no-op
esac
