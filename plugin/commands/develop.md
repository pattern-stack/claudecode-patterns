---
description: Topology A — work one issue end-to-end with a flat team of split-pane teammates. Composes the team from sdlc.yml develop_team plus the issue's needs:* labels.
argument-hint: [issue-key]
allowed-tools: Read, Bash, TeamCreate, SendMessage, mcp__plugin_linear_linear__get_issue
primitives:
  required:
    - task_management
    - language
    - quality_profile
status: active
topology: A
consumes: [issue, spec, label]
produces: [team]
gates:
  enforces: [strategy-approved]
  sets: []
---

# /develop

Single-issue execution in **Topology A**: implementer + validator (and any per-issue extras) run as peer split-pane teammates of the main session. Use when human eyes per step matter (UI verification, data validation, debugging).

For batched AFK throughput across many issues, use `/orchestrate` instead.

> **Workflow judgment** — for `/develop` vs `/orchestrate`, halt recovery from any teammate, or what to do when the validator fails, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Working tree state (pre-rendered)

Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`

## Usage

```
/develop <ISSUE-KEY>
```

`$1`: tracker issue key (e.g. `ABC-101`).

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `task-management/linear` | primitive | Issue resolution, gate label semantics |
| `implementer` | agent | Default member of `develop_team` |
| `validator` | agent | Default member of `develop_team` |
| `browser-pilot` / `tester` / `designer` | agent | Spawned per `needs:*` labels (`browser-pilot` ships with the plugin since the design-loop port; `tester` / `designer` are project-vendored) |
| `design-auditor` (+ `browser-pilot`) | agent (composed design mode) | Spawned when issue carries `needs:design` — runs between implementer commit and validator. See [`/design-loop` SKILL.md § Composed mode](../skills/design-loop/SKILL.md#composed-mode). |

## Steps

### Step 1: Resolve config

1. Read `.claude/sdlc.yml`. Capture:
   - `develop_team`: base roster
   - `task_management`, `language`, `quality_profile`: pass-through

### Step 2: Resolve issue

Use the configured tracker's get-issue MCP to read `$1` (Linear: `mcp__plugin_linear_linear__get_issue`). Capture:
- Title, description, link to spec at `.ai-docs/specs/<key>.md`
- All labels — particularly `state:*` and `needs:*`

### Step 3: Enforce Gate 1

If `state:strategy-approved` is **not** present:
- Print: `⏸  $1 is not state:strategy-approved. Run /design $1 first, or have the human approve in the tracker.`
- Halt. Do not spawn anything.

If `state:blocked`:
- Print: `⏸  $1 is state:blocked. Resolve the blocker before /develop.`
- Halt.

### Step 4: Compose roster

Roster = `sdlc.yml.develop_team` ∪ (issue's `needs:*` labels mapped to agents).

Mapping (extend in `.claude/primitives/task-management/linear.md` § needs:* labels):
- `needs:browser-pilot` → `browser-pilot`
- `needs:tester` → `tester`
- `needs:designer` → `designer`
- `needs:design` → `design-auditor` (composed-mode design loop; auditor slots between implementer commit and validator). Also implies `browser-pilot` — add it to the roster if not already present.

If a `needs:*` label maps to an agent file that does not yet exist, warn but do not fail — log "skipping <name>: agent not vendored" and continue.

### Step 4a: needs:design composed-mode wiring

When `needs:design` is present in the roster:

1. Verify the issue's spec references a parent `design-spec` (look for `related:` frontmatter or a `Design spec:` line pointing to `.ai-docs/design/<slug>/spec.md`). If absent, warn the user and proceed without the auditor — the auditor needs a design-spec to grade against.
2. After the implementer reports its commit + showcase URL, dispatch `design-auditor` (context: fork) with: spec path, phase number (default 1 in composed mode), commit SHA, showcase URL, declared themes, and the open PR's number for posting.
3. If auditor returns `FIXES`: dispatch `design-implementer` (fix mode) with the findings list, then re-spawn `design-auditor`. Cap at 3 rounds (matches `validator_max_iterations`). On exhaustion, surface and halt.
4. If auditor returns `BLOCKED`: halt and surface.
5. On `READY`, hand back to the standard validator gate. The auditor's verdict is visible in the PR comment; Gate 2.5 (`/sdlc:review`) and Gate 3 (validator) still fire normally.

Composed mode does NOT run the standalone loop's per-phase user-gate — the PR-review and validator-pass gates carry that role.

### Step 5: Spawn the team

`TeamCreate` with the resolved roster. Each agent becomes a teammate addressable via `SendMessage`. Hand off the issue key + spec path to `implementer` first; the rest are co-present for ad-hoc questions and per-step verification.

### Step 6: Return

Print the team handle and the addressable teammate names. The human and the orchestrator (this session) drive the loop from here — there is no further automation in this command.

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| (already enforced) | Gate 1 | Set on the issue in the tracker before calling `/develop` |
| Implementer opens PR | Gate 2 — PR review | Standard GitHub review |

## Output

```
Team spawned for <ISSUE-KEY>: <slug>
Spec: .ai-docs/specs/<key>.md
Roster: implementer, validator[, browser-pilot, ...]
Address teammates with: SendMessage to <name>
```

## Error Handling

- **Gate 1 missing**: see Step 3.
- **`needs:*` label maps to non-existent agent**: warn, skip, continue.
- **Spec file missing**: the implementer will halt on first contact; surface that in the team's first exchange rather than failing this command (the team is already useful for re-running `/design`).
