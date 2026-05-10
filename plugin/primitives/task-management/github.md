---
type: primitive-adapter
category: task-management
value: github
status: active
description: GitHub adapter for the task-management port. Maps port operations to `gh` CLI commands. See README.md for the abstract contract.
port: README.md
d6_gaps: []
---

# GitHub Adapter (task-management)

Concrete binding of the [task-management port](./README.md) to the `gh` CLI. The port contract (operation list, gate semantics, conventions) lives in `README.md` — this file is operations → commands only.

## Configuration

Read from `.claude/sdlc.yml`:
- `repo: <owner>/<repo>` — required.
- `project_number: <n>` — optional; if set, `/sync-issues` adds new issues to the project.

Verify scopes once: `gh auth status`. The token needs `repo` and `project`. Add project scope: `gh auth refresh -s project`.

### Owner-type detection (drives Issue Types vs labels)

Issue Types is GitHub-native but **organization-only**. Personal-account repos don't have it. The adapter detects owner type at first use and chooses the `set-type` representation:

```bash
detect_owner_type() {
  local owner="$1"
  if gh api "orgs/$owner" >/dev/null 2>&1; then
    echo "Organization"
  else
    echo "User"
  fi
}
```

Cache the result for the session — owner-type doesn't change mid-session. If the repo gets transferred to an org during development, re-run `gh auth refresh -s repo,project` and re-detect.

## Operation bindings

| Port operation | gh CLI command |
|---|---|
| `read-issue(key)` | `gh issue view <key> --json number,title,body,labels,state,assignees,projectItems,url` (`<key>` is the issue number) |
| `list-issues(filter)` | `gh issue list --label <label> --state <state> --search <query> --json number,title,labels,url --limit 100` |
| `create-issue({title, body, labels})` | `gh issue create --title "<title>" --body "<body>" --label <l1> --label <l2> ...` (multiple `--label` flags). Capture the URL from stdout; the trailing path segment is the issue number. |
| `update-issue(key, patch)` | `gh issue edit <key> --title "..." --body "..." --add-label <l> --remove-label <l> ...` |
| `add-comment(key, body)` | `gh issue comment <key> --body "<body>"` (use heredoc for multi-line) |
| `set-blocking(blocked_by, blocks)` | Approximation: `gh issue edit <blocks> --body "$(gh issue view <blocks> --json body --jq .body)\n\nDepends on: #<blocked_by>"` (append). GitHub renders the cross-link automatically. |
| `find-by-marker(marker)` | `gh issue list --search "<marker> in:body" --state all --json number --limit 1 --jq '.[0].number'` (empty if none) |
| `add-sub-issue(parent, child)` | Two-step: resolve global node IDs (`gh issue view <n> --json id`), then GraphQL `mutation { addSubIssue(input: {issueId: $parent, subIssueId: $child}) { issue { id } } }` via `gh api graphql -f query=...`. The project automatically rolls up "Sub-issues progress" via the `Parent issue` and `Sub-issues progress` default fields. |
| `set-type(key, type)` | **Owner-type-dependent** — adapter detects via `detect_owner_type` (above): |
| ↳ User repo | `gh issue edit <n> --add-label "type:<type>"` (creates the label first if missing). Type-label palette: `type:project` (purple), `type:epic` (blue), `type:task` (gray). |
| ↳ Org repo | Two-step: ensure the IssueType exists at the org level (`gh api graphql ... createIssueType` if missing), then `gh api graphql -f query='mutation { updateIssueIssueType(input: {issueId: $issueId, issueTypeId: $typeId}) { issue { id } } }'`. Native Issue Type field surfaces in the GitHub UI and Project (v2) views. |

`<key>` for GitHub is always the issue **number** (no prefix).

## Issue identifier in branches and commits

- Branch: `<user>/<n>-<slug>` (e.g. `dug/12-add-pm-domain`)
- Commit scope: `feat(#<n>): ...`
- PR closing ref: `Closes #<n>`

`gh issue develop <n> --name <branch>` creates and checks out a branch already linked to the issue (use this when starting work).

## Label provisioning

Run `bash plugin/scripts/bootstrap-tracker.sh` once per repo to provision the SDLC label palette idempotently. The script creates two groups:

**`state:*` (lifecycle):**
- `state:planned` — synced from plan; not yet started
- `state:awaiting-strategy-review` (yellow) — strict-mode specifier posted strategy, awaiting human Gate-1 approval
- `state:strategy-approved` (green) — Gate-1 satisfied (human-set or auto-mode)
- `state:blocked` (red) — coordinator self-blocked on Gate-1 timeout

**`gate:*` (Gate-1 mode override):**
- `gate:auto` (green `#0E8A16`) — issue is in auto-approve mode; specifier posts strategy + sets `state:strategy-approved` directly without halting
- `gate:human` (red-ish `#B60205`) — issue requires human Gate-1 review; overrides plan auto_approve default

Resolution order at runtime (specifier reads issue labels only): `gate:auto` → auto; `gate:human` → strict; no `gate:*` → fall through to `sdlc.yml.gate1_default`.

`needs:*` labels (`needs:browser-pilot`, `needs:tester`, `needs:designer`) are created on demand the first time `/develop` encounters one.

### Type labels (user-repo fallback only)

When `detect_owner_type` returns `User`, the `set-type` operation creates these on demand:

```bash
gh label create type:project --description "Wave / release / top-level deliverable" --color 6F42C1
gh label create type:epic    --description "Stack / coherent surface area"           --color 0366D6
gh label create type:task    --description "PR-sized unit of work"                   --color 6E7681
```

When `detect_owner_type` returns `Organization`, these labels are NOT created — Issue Types are used instead, and the labels would only confuse the UI.

### Issue Type provisioning (org-repo only)

Run once per org to provision the canonical types:

```bash
# Get owner ID for the org
OWNER_ID=$(gh api graphql -f query='query($login:String!){organization(login:$login){id}}' -f login=<org> --jq .data.organization.id)

for type in project epic task; do
  gh api graphql -f query='mutation($ownerId:ID!,$name:String!){
    createIssueType(input:{ownerId:$ownerId,name:$name,description:""}){issueType{id name}}
  }' -F ownerId="$OWNER_ID" -f name="$(echo "$type" | sed 's/.*/\u&/')" || true  # ignore "already exists"
done
```

The default GitHub Issue Types (Bug, Feature, Task, Epic) exist on every org. We add `Project` as a custom type. `Epic` and `Task` are reused from defaults. The adapter resolves type IDs by name at first use.

## Project (v2) integration (optional)

If `sdlc.yml.project_number` is set, `create-issue` chains:

```bash
gh project item-add <project_number> --owner <owner from repo> --url <issue url>
```

`<owner>` is the part of `sdlc.yml.repo` before the slash.

### Recommended Status field options

The 9-option outcome-driven taxonomy (configure via the GitHub Project UI — `gh` CLI cannot create Status options programmatically):

| Status | Outcome boundary | Mover |
|---|---|---|
| **Backlog** | Synced from plan; no commitment yet | `/sync-issues` default |
| **On-Deck** | Committed for this wave; will be addressed | human triage |
| **Planning** | Spec being written OR strategy posted, awaiting OK | `/sdlc:design` start |
| **Ready** | Spec is acceptable to start (Gate-1 satisfied) | specifier (auto mode) or human (strict mode) |
| **In Progress** | Branch + commits, no PR | implementer |
| **In Review** | PR open | implementer |
| **Done** | Merged | GitHub |
| **Blocked** | Parked, can't progress | **only the coordinator self-blocks** (Gate-1 timeout in `/orchestrate`); humans set otherwise |
| **Cancelled** | Won't do, never merged | human |

**Intentional dropoffs:**
- No "Strategy review" column — `state:awaiting-strategy-review` stays as a *filter*, not a kanban swim lane.
- No "Specifying" sub-state — both spec-being-written and awaiting-review collapse to Planning.
- "Approved" → renamed "Ready" — outcome name, not gate name.

To wire Status moves at runtime, agents call `gh project item-edit --field-id <Status> --option <id>`. Field IDs are per-project and discovered + cached by `/sdlc:link-project <project-url>` (PR 5 of the sdlc-plugin-distribution stack). Without the cache, the specifier degrades to label-only (sets `state:*`; skips Status-field move).

### Coordinator self-block (load-bearing)

Only the **coordinator** self-applies `Status=Blocked`. Implementer + validator halt with errors but do **not** change Status — humans disposition. This keeps Status moves predictable across the four mover classes (`/sync-issues`, human, implementer, coordinator).

### Saved board views (recommended)

GitHub Projects v2 has no two-axis grouping; multiple saved views give the two-axis read:

| View | Group by | Filter | Question it answers |
|---|---|---|---|
| **Workflow** (default) | Status | none | "Where is each issue?" |
| **By Stack** | Parent epic | none | "How is each stack progressing?" |
| **By Layer** | Layer (L0–L7) | none | "Where in the architecture is the work?" |
| **Active only** | Status | `Status: On-Deck, Planning, Ready, In Progress, In Review` | working-session view |

`gh` CLI does not expose Projects v2 saved-view creation programmatically — configure these in the GitHub Project UI (`Settings → Views → New view`).
