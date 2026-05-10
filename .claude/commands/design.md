---
description: Generate the implementation strategy for a tracker issue and post it for human review. Implements Gate 1 setup — writes spec, posts comment, sets state:awaiting-strategy-review.
argument-hint: [issue-key]
allowed-tools: Read, Agent
primitives:
  required:
    - task_management
    - language
status: active
topology: none
consumes: [issue, research]
produces: [spec, comment, label]
gates:
  enforces: []
  sets: [awaiting-strategy-review]
---

# /design

Run the `specifier` agent for one tracker issue. Produces the durable spec + tracker comment + sets the `state:awaiting-strategy-review` gate label. **Halts** there — the human approves via the `state:strategy-approved` label in the tracker.

> **Workflow judgment** — for re-run scenarios, halt recovery, or what to do if the spec turns out wrong, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Usage

```
/design <ISSUE-KEY>
```

`$1`: tracker issue key (e.g. `ABC-101`).

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `specifier` | agent | Writes spec + posts strategy comment + sets gate label |

## Steps

### Step 1: Resolve config

Read `.claude/sdlc.yml` for `language`, `task_management`, `team_key`. No decisions here — pass through.

### Step 2: Strategize

**Delegate to**: `specifier` agent

**Mission**:
- **Objective**: Produce per-issue implementation strategy and post for human review
- **Input**: `$1` (issue key) + any existing `.ai-docs/research/<slug>.md` for context
- **Context**: `.claude/sdlc.yml` + `.claude/primitives/{language,task-management}/...`
- **Constraints**: No code; no implementation; sets `state:awaiting-strategy-review` and halts
- **Output**: `.ai-docs/specs/<key>.md` + tracker comment + label set

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| Strategize | Gate 1 — tracker label | "Is this the right approach? Files, interfaces, tests?" Approve via adding `state:strategy-approved` to the issue in the tracker |

## Output

```
Spec: .ai-docs/specs/<key>.md
Tracker: comment posted on <ISSUE-KEY>
Gate: state:awaiting-strategy-review

Next: human review in the tracker → add state:strategy-approved → /develop or /implement
```

## Error Handling

- **Issue already `state:strategy-approved`**: specifier asks before overwriting. Re-running would regress an approved spec.
- **Required state labels not provisioned**: specifier halts with `bash scripts/setup-linear-labels.sh` instruction.
- **Tracker MCP unavailable**: command fails with the missing-tool message; the spec is not partially written.
