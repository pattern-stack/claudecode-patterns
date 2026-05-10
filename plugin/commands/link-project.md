---
description: Discover and cache GitHub Project v2 field IDs (project ID, Status field ID, option IDs for the 9-option taxonomy). Pulls field-ID discovery out of specifier's hot path; agents read cached IDs at runtime. Github-only.
argument-hint: <project-url>
allowed-tools: Read, Write, Bash
primitives:
  required:
    - task_management
status: active
topology: none
consumes: [config]
produces: [project-cache]
gates:
  enforces: []
  sets: []
---

# /sdlc:link-project

Discover and cache GitHub Project v2 field IDs into `.claude/project.json`. Agents (specifier in PR 2) read this cache at runtime to set Status fields via `gh project item-edit`. Without the cache, agents degrade gracefully to label-only.

> **GitHub-only.** `task_management: github` is required. Linear and Jira have native equivalents — different setup paths.

## Usage

```
/sdlc:link-project <project-url>
```

`<project-url>` accepts both forms:
- User: `https://github.com/users/<user>/projects/<n>`
- Org:  `https://github.com/orgs/<org>/projects/<n>`

## Why this exists

GitHub Project v2 Status field setting requires per-repo runtime IDs (project ID, Status field ID, option IDs for `Backlog`/`Planning`/`Ready`/etc.) that **cannot be hardcoded** in the plugin — they're per-project state. Specifier could discover them at every design call via `gh api graphql`, but that adds latency to the hot path and runs the GraphQL query repeatedly. Caching once via this command keeps specifier fast.

## Flow

### Step 1: Validate prerequisites

- Read `.claude/sdlc.yml`. Halt if missing — point to `/sdlc:setup`.
- Halt if `task_management != github`. One-line: "/sdlc:link-project is github-only. Linear and Jira use native equivalents."
- Halt if `gh` CLI not installed. Point to install instructions.
- Verify `gh auth status` shows the `project` scope. If not: "Run `gh auth refresh -s project` and retry."

### Step 2: Parse the project URL

Accept both URL patterns:

```
https://github.com/users/<owner>/projects/<n>    → ownerType: user
https://github.com/orgs/<owner>/projects/<n>     → ownerType: organization
```

Extract `owner` (string) and `n` (project number, integer). Halt with a clear error if the URL doesn't match either pattern.

### Step 3: GraphQL discovery

Run a single GraphQL query to fetch the project ID + the Status field's field ID + every option ID:

```graphql
query($owner:String!,$n:Int!) {
  user(login:$owner) {
    projectV2(number:$n) {
      id
      fields(first:50) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
        }
      }
    }
  }
}
```

(Use `organization(login:$owner)` instead of `user(login:$owner)` when ownerType is organization.)

Find the field where `name == "Status"`. Capture:
- `project_id` (Project node ID)
- `status_field_id` (Status field ID)
- `status_options` (array of `{id, name}` for every Status option)

If the project has no field named "Status", halt: "Project has no field named 'Status'. Configure one in the GitHub Project UI before running /sdlc:link-project."

### Step 4: Match against the 9-option taxonomy

The 9 recommended Status options:

```
Backlog  On-Deck  Planning  Ready  In Progress  In Review  Done  Blocked  Cancelled
```

For each recommended option, look it up in `status_options` (case-insensitive substring match — tolerate "in progress" vs "In Progress" vs "In-Progress"). For each match:
- Record the option ID.

For each missing option:
- Log a warning naming it. Recommend adding it in the GitHub Project UI ("`gh` CLI does not expose Status option creation").

### Step 5: Write `.claude/project.json`

```json
{
  "project_url": "<full URL>",
  "owner": "<owner>",
  "owner_type": "user|organization",
  "project_number": <n>,
  "project_id": "<node id>",
  "status_field_id": "<node id>",
  "status_options": {
    "Backlog":     "<option id or null>",
    "On-Deck":     "...",
    "Planning":    "...",
    "Ready":       "...",
    "In Progress": "...",
    "In Review":   "...",
    "Done":        "...",
    "Blocked":     "...",
    "Cancelled":   "..."
  },
  "discovered_at": "<ISO 8601 timestamp>",
  "tool_version": "<plugin version from plugin.json>"
}
```

`null` values for missing options are fine — agents skip Status-set for missing names and fall back to label-only.

If `.claude/project.json` already exists, overwrite. Idempotent re-run.

The file is gitignored by default (per PR 1's `.gitignore` update). Teams that share the same project may opt to commit it; the cache is per-repo.

### Step 6: Optionally update sdlc.yml

If `sdlc.yml` doesn't have `project_number:` set, AskUserQuestion: "Set `project_number: <n>` in `.claude/sdlc.yml` so /sync-issues adds new issues to this project? (recommended)" → if yes, edit the file in place.

### Step 7: Print report

```
Linked: <project-url>
Project ID:        <id>
Status field ID:   <id>
Options matched:   <X>/9
Missing options:   <list> (add via GitHub Project UI)

Cache: .claude/project.json (gitignored by default)

Specifier will now move Status when /sdlc:design runs. To re-discover after
project changes, run /sdlc:link-project <url> again — idempotent.
```

## Specifier degrade behavior (referenced cross-PR)

Implemented in PR 2 (specifier.md), surfaced here for the contract:

- Cache present + all 9 options matched → set Status field via `gh project item-edit`.
- Cache present + some options missing → label-only for missing options; Status-set for matched.
- Cache absent → label-only for everything; one-line warning suggesting `/sdlc:link-project`.
- `gh project item-edit` failure → label-only fallback; specifier does NOT halt.

## Acceptance

- Discovery succeeds against a real GH-free user project AND a GH-org org project; cache is valid JSON.
- Re-run is idempotent (no duplicate keys; fresh option IDs after option renames).
- Halts cleanly when `task_management: github` is not set.
- Specifier integration: with cache present, `/sdlc:design` moves Status correctly; with cache absent, falls back to label-only without erroring.

## Out of scope

- Programmatic creation of the 9 Status options. `gh` CLI cannot create options on a Project v2 Status field — users add them via the GitHub Project UI. The command surfaces names; the user customizes.
- Linear or Jira analogues. `/sdlc:link-project` is github-only.
- Caching multiple projects per repo (rare; out of v1 scope).
- Auto-refresh on Status option rename (re-run the command — tradeoff for keeping cache simple).
