---
description: Generate the implementation strategy for a tracker issue and post it. In strict mode (default) sets state:awaiting-strategy-review and halts; in auto mode (per gate:auto label) sets state:strategy-approved directly and completes. Resolution by gate:* label → sdlc.yml.gate1_default.
argument-hint: [issue-key]
allowed-tools: Read, Agent
primitives:
  required:
    - task_management
    - language
status: active
topology: none
consumes: [issue, research]
produces: [spec, comment, label, branch, commit]
gates:
  enforces: []
  sets: [awaiting-strategy-review, strategy-approved]  # strict / auto
---

# /design

Run the `specifier` agent for one tracker issue. Produces the durable spec + tracker comment + sets the gate label per resolved Gate-1 mode.

## Gate-1 modes (strict vs auto)

| Mode | Sets label | Halts | Used for |
|---|---|---|---|
| **strict** (default) | `state:awaiting-strategy-review` | yes | Novel work — port shapes, framework changes, first-of-kind decisions where human approval is load-bearing. |
| **auto** | `state:strategy-approved` | no | Mechanical work — RFC translation, YAML definitions, vendor adapter wirings against an established pattern, where human approval is theatre. Implementer's hard refusal-without-`state:strategy-approved` is preserved structurally; auto mode satisfies the gate via the agent. |

## Mode resolution (most-specific wins)

Specifier reads **only labels** on the issue. `/sync-issues` translates plan-level intent into labels at issue-creation time.

```
issue carries gate:auto label    → auto mode
issue carries gate:human label   → strict mode (always wins; explicit override)
no gate:* label                  → fall through to sdlc.yml.gate1_default
```

To override the resolved mode for a specific issue, apply `gate:auto` or `gate:human` directly in the tracker UI before running `/design`. To override at the stack level (planning time), set `auto_approve: true` (or `false`) in your plan YAML — `/sync-issues` translates that into per-leaf `gate:*` labels.

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
- **Objective**: Produce per-issue implementation strategy, commit it on the impl branch, and post a permalink-linked tracker comment for human review
- **Input**: `$1` (issue key) + any existing `.ai-docs/research/<slug>.md` for context
- **Context**: `.claude/sdlc.yml` + `.claude/primitives/{language,task-management}/...`
- **Constraints**: No code; no implementation; sets `state:awaiting-strategy-review` and halts
- **Output**: spec file + impl branch (pushed) + commit SHA + tracker comment with SHA permalink + gate label set

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| Strategize | Gate 1 — tracker label | "Is this the right approach? Files, interfaces, tests?" Approve via adding `state:strategy-approved` to the issue in the tracker |

## Output

```
Spec:      .ai-docs/specs/<key>.md   (or stack-co-located path)
Branch:    <user>/<key-lowercase>-<slug>   (pushed to origin with spec commit)
Permalink: https://github.com/<owner>/<repo>/blob/<full-sha>/<spec-path>
Tracker:   comment posted on <ISSUE-KEY> with permalink link
Gate:      state:awaiting-strategy-review

Next: human review in the tracker → add state:strategy-approved → /develop or /implement
```

## Error Handling

- **Issue already `state:strategy-approved`**: specifier asks before overwriting. Re-running would regress an approved spec.
- **Required state labels not provisioned**: specifier halts with `bash scripts/setup-linear-labels.sh` instruction.
- **Tracker MCP unavailable**: command fails with the missing-tool message; the spec is not partially written.
