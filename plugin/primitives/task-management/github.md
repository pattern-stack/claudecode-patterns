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

- **Standalone branch**: `<user>/<n>-<slug>` (e.g. `dug/12-pm-domain`)
- **Stacked branch** (via `st`): `<user>/<stack-slug>/<N>-<slug>` (e.g. `dug/plugin-layout/2-gate-modes`). `<N>` is the stack position assigned by st; `<slug>` is terse (3 words max, kebab-case, noun-phrased, no `pr-N-` / `issue-NN` prefixes).
- **Commit scope**: `feat(#<n>): ...`
- **PR closing ref**: `Closes #<n>` (only auto-links when PR's base is the default branch — stacked PRs auto-link after upstream merges cascade)

`gh issue develop <n> --name <branch>` creates and checks out a branch already linked to the issue (use this when starting work; not used for stacked branches — let `st create` / `st branch insert` name them).

### Slug rules (terseness is load-bearing)

Anti-example (from a prior stack — too long, redundant with the directory + PR + issue):
```
dugshub/plugin-layout/2-pr-2-gate-mode-mechanism-status-taxonomy-issue-23   ❌
```

Right shape:
```
dugshub/plugin-layout/2-gate-modes                                          ✓
```

The issue key and PR number are durable identifiers — they live on the issue / PR forever. The branch name is for human skimmability (`st status`, `git branch -a`). Keep it short.

## Label provisioning

Run `bash plugin/primitives/task-management/bootstrap.sh` once per repo to provision the SDLC label palette idempotently. The script creates two groups:

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

## Epic status cascade

When the SDLC loop creates parent epic issues and child leaf issues (via `/sync-issues`), child-status transitions cascade to the parent. Identical contract to the Linear primitive — see [`linear.md` § Epic status cascade](./linear.md#epic-status-cascade) for the full rule table.

GitHub adapter binding for the cascade operations:

| Operation | Command |
|---|---|
| Resolve parent epic from child | `gh issue view <child> --json body --jq '.body' | grep -oE 'Parent epic: #[0-9]+'` (the sync-issues epic→child link is encoded both as a sub-issue relation and as a `Parent epic: #N` body line for grep-ability) |
| List children of an epic | `gh issue list --search 'parent:<epic-number>' --json number,labels,projectItems` (uses the `parent:` qualifier on GitHub Issues sub-issue relation) |
| Get child Status | Project field; resolved via the Project v2 GraphQL `projectItem.fieldValueByName(name: "Status")` |
| Set parent Status | `gh project item-edit --id <parent-item-id> --field-id <status-field-id> --project-id <project-id> --single-select-option-id <option-id>` |

Cache the parent Project item ID and the Status field's option IDs at session start (the `SessionStart` discover-tracker hook handles this). The cascade is a series of project-field updates, not issue updates per se — the issue's GraphQL `state` (open/closed) is independent.

Idempotence: the adapter compares the parent's current Status to the target before issuing an `item-edit` — skips when already at target.

Per-project enablement: `sdlc.yml.epic_cascade.enabled: false` disables the cascade for all SDLC-managed epics in this repo. Useful when the team uses GitHub Projects automations for status moves and doesn't want the loop double-dipping.

**Implementation status (v2 follow-up):** same as Linear — the cascade contract is defined here, but no SDLC phase agent performs the parent-status update yet. See [`linear.md` § Epic status cascade → Implementation status](./linear.md#epic-status-cascade) for the v2 wiring plan.

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

> Status moves are intentional but **soft**: agents check Status alongside labels and halt with one short reason rather than failing hard if the lane isn't what they expected. See port `README.md` §"Soft entry" for the convention.

To wire Status moves at runtime, agents call `gh project item-edit --field-id <Status> --option <id>`. Field IDs are per-project and auto-discovered at every SessionStart by `plugin/scripts/discover-tracker.sh` — output lands at `.claude/.session/tracker-context.md` and is `@`-mentioned by specifier. Set `project_number: <n>` in `sdlc.yml` to enable; discovery silent-no-ops otherwise. When the hook produces no context (no `project_number:`, missing GH auth, or discovery failure), specifier degrades to label-only (sets `state:*`; skips Status-field move).

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
