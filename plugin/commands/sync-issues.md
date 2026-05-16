---
description: Sync an approved YAML stack plan to the active task-management adapter. Creates the stack's epic parent + leaf issues + sub-issue rollup, idempotently by plan-key marker. Run after /plan ends with "approved". Does not run agents.
argument-hint: [plan-yaml-path]
allowed-tools: Read, Write, Bash, mcp__plugin_linear_linear__list_issues, mcp__plugin_linear_linear__save_issue, mcp__plugin_linear_linear__get_issue, mcp__plugin_linear_linear__list_issue_labels, mcp__plugin_linear_linear__save_comment
primitives:
  required:
    - task_management
status: active
topology: none
consumes: [plan]
produces: [issues, epic]
gates:
  enforces: []
  sets: []
---

# /sync-issues

Apply a YAML stack plan to the active tracker via the task-management port. **No agents involved** — this is a thin sync. Idempotent by plan-key marker (port operation `find-by-marker`).

> **Workflow judgment** — for stack anatomy, idempotence semantics, or rename caveats, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Usage

```
/sync-issues <path-to-plan-yaml>
```

`$1`: path to the plan YAML, typically `.ai-docs/stacks/<slug>/plan.yaml`.

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `task-management` (port + adapter) | primitive | Issue creation, label provisioning, sub-issue parenting, idempotence |

The active adapter file (`.claude/primitives/task-management/{task_management}.md`) provides concrete CLI/MCP commands for each port operation. This command never hardcodes Linear or GitHub specifics.

## Plan schema

```yaml
plan:
  slug: <kebab-slug>                # local stack key; appears in idempotence markers
  summary: <one-line>
  milestone: <milestone-name>       # default for all issues; overridable per-issue
  epic_title: <string>              # parent issue title
  epic_body: |                      # parent issue body (markdown)
    ...
  repo: <owner>/<repo>              # OPTIONAL cross-repo flag; defaults to sdlc.yml.repo
  stack:                            # OPTIONAL stack topology metadata
    base: main                      # branch base for `st`
    depends_on: [<other-stack-slug>] # informational; doesn't gate sync

issues:
  - key: <local-key>                # mapped to tracker key by sync
    title: <PR-sized title>
    description: |
      ...
    layer: L0..L7                   # OPTIONAL: sets project Layer custom field
    milestone: <override>           # OPTIONAL: overrides plan.milestone
    depends_on: [<other-key>]       # set as blocking relation via port op set-blocking
    parallel_with: [<other-key>]    # informational
    labels: []                      # extra labels (needs:* etc.); state:* NOT set here
```

## Steps

### Step 1: Resolve config & adapter

1. Read `.claude/sdlc.yml`. Capture `task_management` (e.g. `linear`, `github`) and any adapter-specific keys (Linear: `team_key`; GitHub: `repo`, `project_number`).
2. Read `.claude/primitives/task-management/README.md` (the port contract) and `.claude/primitives/task-management/{task_management}.md` (the active adapter binding).
3. If the adapter requires environment scopes, verify them. Halt with the missing-scope instruction from the adapter file if not.

### Step 2: Read the plan

1. Read `$1`. Validate shape per the schema above:
   - Top-level `plan.slug`, `plan.summary`, `plan.milestone`, `plan.epic_title`, `plan.epic_body` present.
   - `issues:` list non-empty; each has `key`, `title`, `description`.
2. If validation fails, print which field is missing and the issue index. Halt.
3. If `plan.repo` is set and differs from `sdlc.yml.repo`, the active adapter must support cross-repo. GitHub does (issues land in `plan.repo`). Linear does not (different teams need different `team_key`s). If cross-repo isn't supported by the adapter, halt with a clear error.

### Step 3: Find or create the parent epic

The epic is the parent issue that holds all leaves as sub-issues. It uses its own idempotence marker:

- Marker: `[plan-epic:<plan.slug>]`
- Body footer: append the marker on a separate line below `epic_body`.

1. Call `find-by-marker("[plan-epic:<plan.slug>]")`.
2. If found → capture as `epic_key`; this is the existing epic (idempotent re-run).
3. If not found → call `create-issue({ title: plan.epic_title, body: plan.epic_body + footer, labels: [] })`. Capture the returned key as `epic_key`.

If the plan has a `milestone:`, also assign the epic to that milestone via `update-issue(epic_key, { milestone: plan.milestone })` — adapters that don't support milestones (rare) treat this as a no-op.

### Step 4: Map local keys to existing leaf issues

For each issue in the YAML, build the leaf marker `[plan-key:<plan.slug>/<issue.key>]` and call `find-by-marker`:
- If found → update path (capture the existing tracker key).
- If not found → create path.

### Step 5: Create or update leaf issues

For each issue:

**Create** — call `create-issue` with:
- `title`: from YAML
- `body`: YAML description + footer line `[plan-key:<plan.slug>/<issue.key>]`. If `depends_on` is non-empty, also append `Depends on: <comma-separated-keys>` (the active adapter's `set-blocking` operation will translate this into the right native or approximated form in Step 7).
- `labels`: any extras from `issue.labels` (e.g. `needs:*`) **plus** the resolved `gate:*` label per Gate-mode resolution below.
- Apply `issue.milestone || plan.milestone` via `update-issue` after creation.

**Update** — call `update-issue(existing_key, { title, body, milestone })`. Preserve labels not mentioned (do not strip human-set labels).

Do NOT set `state:*` labels here — those are owned by agents and the human, not by sync.

**Gate-mode resolution at creation (auto_approve translation):**

`/sync-issues` is the **single integration point** that translates `plan.auto_approve` into per-issue labels. Specifier reads only labels at runtime — never reads plan.yaml.

For each leaf issue, decide which `gate:*` label to stamp:

```
plan.auto_approve == true   → stamp `gate:auto`
plan.auto_approve == false  → stamp `gate:human`
plan.auto_approve unset     → no `gate:*` label (specifier falls through to sdlc.yml.gate1_default)
```

Per-issue overrides take precedence: if `issue.labels` already includes `gate:auto` or `gate:human`, honor that instead of computing from `plan.auto_approve`.

The `gate:*` label is added alongside `needs:*` and any other extras during the `create-issue` call. On update of an existing issue (re-sync), do not strip `gate:*` if it was set manually by the user — only set it if it's missing AND `plan.auto_approve` resolves cleanly.

If the `gate:auto` / `gate:human` labels aren't provisioned on the tracker, halt with one line:
> Run `bash plugin/primitives/task-management/bootstrap.sh` to provision the SDLC label palette.

### Step 6: Wire sub-issues (epic → leaves)

For each leaf issue created or updated in Step 5, call `add-sub-issue(epic_key, leaf_key)`. The port's contract requires this to be idempotent — re-runs of the same parent/child pairing are a no-op.

This is what makes the stack visible as a tracked epic in the project (`Sub-issues progress` rolls up automatically once the adapter wires the relation).

### Step 7: Apply leaf depends_on

For each issue with non-empty `depends_on`:
- Resolve each dependency's local key to its tracker key (from Step 4–5 mapping).
- Call `set-blocking(blocked_by_key, blocks_key)` per the port's contract.
- Adapter handles native (Linear: BLOCKS relation) or approximated (GitHub: `Depends on: #N` body line) form.

### Step 8: Adapter-specific extras

Per the active adapter, runs after issue creation:

- **github**: if `sdlc.yml.project_number` is set, add the epic + each leaf to the project (`gh project item-add`). For each issue with a `layer:` field, set the project's `Layer` single-select field via `gh project item-edit`. The GitHub adapter file documents the exact commands.
- **linear**: ensure label IDs are resolved against the configured `team_key` before any `update-issue` call.

These are adapter-private bookkeeping. The port doesn't surface them; the adapter file documents them as adapter-specific Step 8.

### Step 9: Rewrite plan.yaml local keys → tracker keys

Local plan keys (`hcrm-1`, `port-2`, `foo-bar`) are useful for human authorship and intra-plan references, but they leak into downstream artifacts — branch names, spec filenames, chat shorthand — and require permanent translation tables when they diverge from tracker-assigned keys.

After Steps 3-7 successfully resolve every local key to a tracker key, rewrite the plan in place:

```yaml
# Before sync:
issues:
  - key: hcrm-1
    title: "Foo"
    depends_on: []
  - key: hcrm-2
    title: "Bar"
    depends_on: [hcrm-1]

# After Step 9:
issues:
  - key: eng-674                 # tracker-assigned key, lowercased
    key_original: hcrm-1         # preserved for trace
    title: "Foo"
    depends_on: []
  - key: eng-675
    key_original: hcrm-2
    title: "Bar"
    depends_on: [eng-674]        # all references rewritten
```

Rules:
- Set `key:` to the tracker-assigned key, lowercased (matches `gitBranchName` discipline).
- Preserve the original local key as `key_original:` for trace + handoff readability.
- Rewrite every `depends_on:` and `parallel_with:` reference to the new keys.
- If `epics:` is present (per_epic mode), rewrite each epic's `issues:` array and `stack_base:` (when set to a local key).
- Idempotence: if `key_original` is already set, this step is a no-op (re-sync case).

The plan file at `$1` is the only artifact rewritten. Everything else downstream (spec files, branches, commits) keys off the tracker-assigned keys from the start.

If the user has already started writing spec files under local-key names (`.ai-docs/stacks/<slug>/specs/hcrm-1.md`), this rewrite **does not** rename them — surface in the Step 11 report:

> ⚠  Plan keys rewritten. Existing spec files at `.ai-docs/stacks/<slug>/specs/hcrm-*.md` still use local keys — rename to match the new keys before running `/design`.

### Step 10: Emit st-create chain (per_epic mode only)

If `plan.stack_topology == "per_epic"`, the plan groups issues into epics that each get their own `st` stack. Emit (do **not** execute) the `st create` invocations needed to wire the chain.

**Forward-looking caveat:** branch names don't exist at `/sync-issues` time. The emitted commands reference branches that the implementer will cut later (per the `<user>/<issue-key-lowercase>-<slug>` convention from the task-management primitive). The chain is documentation the user runs incrementally as each epic's first branch comes online — the first epic's command typically runs immediately (its base is `main`), subsequent epics wait for the prior epic's last branch to be pushed.

```
For each epic in plan.epics (in order):
  stack_slug = "<plan.slug>-<epic.key>"

  if first epic:
    base = epic.stack_base  # defaults to "main"
  else:
    base = <previous-epic's-last-issue-branch>   # e.g. "doug/eng-676-hubspot-oauth"
    # branch name derived from the last issue.key in prior epic + slug rules

  first_branch = <first-issue-branch-in-this-epic>

  emit:
    st create <stack_slug> --base <base> --from <first_branch> --yes
```

The command does not execute these (`st` ops are side-effectful and require human review of cross-stack dependencies). Print them in the Step 11 report inside a fenced block labeled `st-create-chain`:

```
st-create-chain:
  st create hubspot-crm-foundations --base main --from doug/eng-674-strategy-registry --yes
  st create hubspot-crm-client-ports --base doug/eng-676-hubspot-oauth --from doug/eng-677-rest-client --yes
  st create hubspot-crm-sync --base doug/eng-679-adapter --from doug/eng-680-app-services --yes
```

Verification step (human runs after executing): `st stack graph` should render parent→child links between each stack.

If `stack_topology == "per_plan"` (default), skip this step entirely — one stack named `plan.slug` covers everything.

### Step 11: Report

```
Plan: <path>
Adapter: <task_management>
Repo: <plan.repo or sdlc.yml.repo>
Stack topology: <per_plan | per_epic>

Epic: <epic_key>  "<epic_title>"
  → status: created | existed
  → milestone: <plan.milestone>

Leaves: <N> issues
  Created: <count>
    - <KEY>  <title>  (key: <slug/key>)
    ...
  Updated: <count>
    - <KEY>  <title>  (key: <slug/key>)
    ...
  Sub-issues wired: <count>
  Blocking relations applied: <count>

Plan rewrite: <N> local keys → tracker keys
  Renamed: <count>  (key_original preserved)
  Plan written: <path>

Project items added: <count> (or skipped if no project_number)
Layer fields set: <count>

st-create-chain:                    # only when stack_topology: per_epic
  <emitted st create commands>
Run these manually, then `st stack graph` to verify links.

Next: /design <issue-key> to start strategy
```

## Human Gates

None. This command is post-Gate-0; the human already approved the YAML in `/plan`.

## Output

Tracker state created or updated. The local YAML at `$1` is **not** modified — it remains the source of truth for the next sync. Downstream agents reference issues via the `[plan-key:...]` marker (leaves) or `[plan-epic:...]` marker (epic).

## Error Handling

- **Missing adapter config** (no `team_key` for Linear, no `repo` for GitHub): halt with a one-line instruction to set the field in `sdlc.yml`. Do not partially sync.
- **Tracker API error mid-sync**: report which issues succeeded, which failed, which were not attempted. Re-running is safe — already-created issues are detected by the idempotence marker, and `add-sub-issue` is idempotent.
- **Dependency cycle in `issues[].depends_on`**: detect before any tracker call. Halt with the cycle path.
- **Adapter D6 gap on `set-blocking`** (e.g. tracker has no native blocks relation): log a warning per issue; the dependency is still encoded in the issue body via `Depends on:` text. Do not fail the whole sync.
- **Adapter D6 gap on `add-sub-issue`** (rare; trackers without native sub-issues): adapter approximates via tasklist body syntax. Document in the adapter's `d6_gaps:` frontmatter so consumers know rollup is approximate.
- **`epic_title` / `epic_body` missing** from plan: halt before any tracker call. The epic is required — every stack must have one parent issue.
