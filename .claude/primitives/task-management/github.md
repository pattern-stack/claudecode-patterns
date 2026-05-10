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

Run once per repo to provision the gate labels documented in `README.md`:

```bash
gh label create state:awaiting-strategy-review --description "Strategy ready for human review" --color 0E8A16
gh label create state:strategy-approved        --description "Human approval to implement"    --color 0075CA
gh label create state:blocked                  --description "Blocked on external input"      --color B60205
```

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
