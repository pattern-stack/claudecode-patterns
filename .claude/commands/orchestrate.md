---
description: Topology B — parallel batch execution. Spawns one coordinator teammate per issue; each coordinator runs phase agents as headless subagents. Best for AFK throughput on pre-approved issues.
argument-hint: [issue-filter]
allowed-tools: Read, Bash, TeamCreate, SendMessage, mcp__plugin_linear_linear__list_issues, mcp__plugin_linear_linear__get_issue
primitives:
  required:
    - task_management
    - language
    - quality_profile
status: active
topology: B
consumes: [issue-list, spec, label]
produces: [team]
gates:
  enforces: [strategy-approved]
  sets: []
---

# /orchestrate

Multi-issue execution in **Topology B**: one `coordinator` teammate per issue, spawned in parallel. Each coordinator runs `implementer` + `validator` as **subagents** (Agent tool), not further teammates — the topology constraint is load-bearing (see RFC-0004 § Topology and `.claude/agents/coordinator.md`).

Use for AFK throughput across a batch of issues that are already through Gate 1. For single-issue work or work that needs human eyes per step, use `/develop` instead.

> **Workflow judgment** — for `/develop` vs `/orchestrate`, the Topology B constraint, or coordinator halt recovery, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Working tree state (pre-rendered)

Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`

## Usage

```
/orchestrate <issue-filter>
```

`$ARGUMENTS`: tracker issue filter — explicit list (`ABC-101 ABC-102 ABC-103`), label query (`state:strategy-approved`), or YAML plan path (issues from a single plan).

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `coordinator` | agent | Per-issue teammate; orchestrates one issue end-to-end |
| `task-management/linear` | primitive | Filter resolution, gate label semantics |

## Steps

### Step 1: Resolve config

Read `.claude/sdlc.yml`. Capture:
- `orchestrate_concurrency`: max parallel coordinators
- `quality_profile`, `language`, `task_management`: pass-through to coordinators

### Step 2: Resolve issue list

From `$ARGUMENTS`:
- If a YAML path: read it; resolve each `issues[].key` to its tracker issue via the `[plan-key:...]` marker.
- If a label query: use the configured tracker's list-issues MCP with the filter (Linear: `mcp__plugin_linear_linear__list_issues`).
- If explicit keys: `get_issue` for each.

### Step 3: Filter by Gate 1

Drop any issue not carrying `state:strategy-approved`. Print which were dropped and why. The orchestrator does not pre-approve issues — that's per-issue manual work in the tracker.

Drop any issue carrying `state:blocked`. Print which.

Drop any issue carrying a `needs:*` label that maps to a Topology-A-shaped agent (`browser-pilot`, `designer`, `tester`). These belong in `/develop`. Print which were dropped and recommend `/develop` for them.

### Step 4: Spawn coordinators

For up to `orchestrate_concurrency` issues at a time:
- `TeamCreate` one teammate per issue with the `coordinator` agent.
- Hand off issue key + relevant spec path.

Each coordinator runs end-to-end on its issue. Coordinators report back via the team result.

### Step 5: Return

Print the team handle and the per-issue coordinator names. The coordinators are working headless from here — the human can `SendMessage` to a coordinator to query status, but per-step interaction is not the point of this topology.

## Human Gates

| Before run | Gate 1 — set per issue | Already approved in the tracker before this command runs |
| Per coordinator | Gate 2 — PR review | Standard GitHub review per opened PR |

## Output

```
Orchestrating <N> issues (concurrency=<C>):
  ✓ ABC-101  → coordinator-ABC-101
  ✓ ABC-102  → coordinator-ABC-102
  ⏭ ABC-103  dropped: state:strategy-approved missing
  ⏭ ABC-104  dropped: needs:browser-pilot — use /develop
  ✓ ABC-105  → coordinator-ABC-105
  ⏳ ABC-106, ABC-107 queued (over concurrency limit)
```

## Error Handling

- **No issues pass filter**: report what was filtered and why; do not spawn an empty team.
- **`needs:*` to Topology-A agent on a candidate issue**: drop and recommend `/develop`. Do not let coordinators try to spawn these as subagents — they're explicitly forbidden by `coordinator.md`.
- **Coordinator failure**: surfaces in the team result; coordinator's own halt logic (gate, spec, blocker) handles its own halts.
