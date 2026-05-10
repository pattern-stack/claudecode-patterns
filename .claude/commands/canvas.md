---
description: Author / tune / validate / reverse-engineer / explain a canvas (a template + instructions pair under .claude/canvases/<name>/) via the canvas-author agent. Probing schema-aware dialog; never writes without confirmation. v1 ships tune + validate.
argument-hint: <mode> [name]
allowed-tools: Read, Glob, Grep, Agent

primitives:
  required: []
  optional: []

# === Project SDLC overlay ===
status: active
topology: none
consumes: [canvas, example]
produces: [canvas]
gates:
  enforces: []
  sets: []
---

# /canvas

Author / tune / validate / reverse-engineer / explain a canvas. Delegates to the [`canvas-author`](../agents/canvas-author.md) agent, which conducts a probing, schema-aware dialog and applies the [`canvas-authoring`](../skills/canvas-authoring/SKILL.md) skill's response scaffold on every turn.

> **What's a canvas?** A `template.md` + `instructions.yaml` + `instructions.schema.json` + `README.md` quartet under `.claude/canvases/<name>/` defining the contract for one kind of artifact. See [`artifacts/README.md`](../artifacts/README.md).

## Pre-rendered context

Existing canvases:
!`ls -1 .claude/canvases/*/README.md 2>/dev/null | sed 's|.claude/canvases/||; s|/README.md||' | sort`

## Launchers

This command is one of four entry points to canvas-authoring. Pick the right one for the situation:

| Entry point | Best for | Notes |
|---|---|---|
| **`/canvas <mode> [name]`** (this command) | One-shot canvas operations inside another session | Agent runs as subagent; no output-style applies; developer voice |
| **`just canvas-dev`** | Marathon canvas work in developer voice | Pre-applies `--output-style canvas-flow-developer`; full system access, four-block scaffold |
| **`just canvas-seller`** | Authoring with a non-technical user | Pre-applies `--output-style canvas-flow-seller`; outcome-framed, hides mechanism |
| **`claude --agent canvas-author`** (no flag) | When you don't know which voice yet | Agent auto-detects from your first message; asks once if ambiguous |

For voice-vs-disclosure detail see the [`canvas-authoring`](../skills/canvas-authoring/SKILL.md) skill.

## Usage

```
/canvas <mode> [name]
```

| `<mode>` | Status | What it does |
|---|---|---|
| `tune <name>` | v1 | Adjust an existing canvas to fix a felt problem |
| `validate <name>` | v1 | Health-check a canvas (schema, cross-knob, anti-patterns) |
| `new <name>` | v2 | Create a canvas from scratch |
| `reverse <name>` | v2 | Extract a canvas from an example artifact |
| `explain <name>` | v2 | Guided tour of an existing canvas |

`<name>` matches a directory under `.claude/canvases/` (or, for `new` / `reverse`, the directory to create).

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `canvas-author` | agent | Conducts the dialog; applies the response scaffold |
| `canvas-authoring` | skill | Meta-knowledge: modes, knob taxonomy, anti-patterns, reverse heuristics |
| `artifacts/<name>/` | data | The canvas being authored / tuned / validated |

## Steps

### Step 1: Resolve mode + canvas

Parse `$1` as the mode and `$2` as the canvas name. Validate:

- Mode must be one of `tune | validate | new | reverse | explain`. (If v2 modes are requested before they're activated, surface the v1 limitation and offer `tune` / `validate` instead.)
- For `tune | validate | explain`: canvas must exist at `.claude/canvases/<name>/`. If not, halt with the list of existing canvases.
- For `new | reverse`: canvas must NOT exist at `.claude/canvases/<name>/`. If it does, suggest `tune` instead.

If `$1` and `$2` are missing or unclear, hand off to the agent's mode-resolution prompt.

### Step 2: Pre-load context

Read these into context before delegating:

- `.claude/canvases/<name>/README.md` (if exists) — what the canvas is
- `.claude/canvases/<name>/instructions.yaml` (if exists) — current knob values
- `.claude/canvases/<name>/instructions.schema.json` (if exists) — type contract
- `.claude/canvases/<name>/template.md` (if exists) — current structure

The agent's session starts grounded in actual canvas state, not abstract knowledge.

### Step 3: Delegate to canvas-author

**Delegate to**: `canvas-author` agent

**Mission**:
- **Objective**: Conduct the canvas authoring conversation per the requested mode
- **Input**: mode (`$1`), canvas name (`$2`), pre-loaded canvas state
- **Context**: `canvas-authoring` skill (preloaded into the agent), `claude-platform` for any platform questions, `sdlc.yml.artifact_paths` for output-path resolution
- **Constraints**: never write without diff + confirmation; never modify agent files or `sdlc.yml`; surface schema violations and anti-patterns proactively
- **Output**: file writes to `.claude/canvases/<name>/...` on apply; session summary on close

The user drives the conversation from here. The agent applies the response scaffold and produces structured turns until the user signals close.

## Human Gates

| When | Gate | Approval Criteria |
|---|---|---|
| Before each apply | Implicit per-turn | User says `apply` / `go` / `ship it` etc. The agent shows the diff and waits |
| Before adding a new canvas to the registry | Out-of-band | After `new` or `reverse` mode closes, user adds `<name>:` to `sdlc.yml.canvases` themselves |
| Before migrating a consumer agent to read a new/changed canvas | Out-of-band | Separate explicit step; the canvas-author never edits agent files |

## Output

For `tune` / `new` / `reverse`: file writes to `.claude/canvases/<name>/`. The session summary at close lists what was applied.

For `validate`: a structured health report in chat — green/yellow/red findings, each citing an anti-pattern by name from [`canvas-authoring/anti-patterns.md`](../skills/canvas-authoring/anti-patterns.md).

For `explain`: a guided tour in chat. No file writes. Optionally pivots to `tune` if the user wants changes.

## Error handling

- **Mode unknown** → surface the mode list and halt.
- **Canvas not found (tune/validate/explain)** → list existing canvases and halt.
- **Canvas already exists (new/reverse)** → suggest `tune` and halt.
- **Schema validation fails on first read (validate mode)** → surface the violation and halt; don't pivot to other checks until schema is valid.
- **User signals close mid-pending-diff** → apply nothing; report the queued diff in the session summary so the user can resume later.

## See also

- [`canvas-authoring`](../skills/canvas-authoring/SKILL.md) — the meta-knowledge backing the agent
- [`canvas-author`](../agents/canvas-author.md) — the agent itself
- [`artifacts/README.md`](../artifacts/README.md) — registry layer
- [`canvas-flow-developer`](../output-styles/canvas-flow-developer.md) — output-style for `claude --agent canvas-author --output-style canvas-flow-developer` deep-dive sessions (rigid four-block scaffold, system vocabulary)
- [`canvas-flow-seller`](../output-styles/canvas-flow-seller.md) — output-style for `claude --agent canvas-author --output-style canvas-flow-seller` (three-move shape, progressive disclosure, artifact-as-proxy — for non-technical users)

> **Workflow judgment** — for the broader SDLC loop and how canvases plug into producer/consumer agents, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.
