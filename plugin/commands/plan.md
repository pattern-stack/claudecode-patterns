---
description: Decompose a request into a PR-sized issue plan. Produces a YAML at .ai-docs/plans/<slug>.yaml; iterates against your feedback until you approve. Does NOT touch the tracker.
argument-hint: [description...]
allowed-tools: Read, Write, Edit, Glob, Grep, Agent
primitives:
  required:
    - task_management
  optional:
    - language
status: active
topology: none
consumes: [request, research]
produces: [plan]
gates:
  enforces: [chat-approval]
  sets: []
---

# /plan

Author or iterate a YAML issue plan via the `planner` agent. Implements **Gate 0** — synchronous, in-chat approval. Hands off to `/sync-issues` only when the human approves.

> **Workflow judgment** — for "should I `/plan` first or jump to `/design`", how to interpret a halt, or any other operating-the-loop question, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Usage

```
/plan <description...>
```

`$ARGUMENTS`: the work to plan, in your words.

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `planner` | agent | Owns the YAML; iterates across turns |
| `understander` | agent | (optional) Pre-step if no understanding artifact exists |

## Steps

### Step 1: (optional) Understanding

If no `.ai-docs/research/<slug>.md` exists for the topic and the request is non-trivial, delegate to `understander` first. Skip if the user's brief is already concrete or an artifact exists.

**Delegate to**: `understander` agent — when `sdlc.yml.phase_models.understander` is set, spawn with `model: <value>`; otherwise omit and let the agent's frontmatter default stand.

**Mission**:
- **Objective**: Produce understanding artifact + condensed summary for this request
- **Input**: `$ARGUMENTS`
- **Context**: `.claude/sdlc.yml`
- **Constraints**: Read-only on source; writes only to `.ai-docs/research/`
- **Output**: `.ai-docs/research/<slug>.md` + condensed summary in chat

### Step 2: Plan

> **Delegate, or author directly?** `planner` is the **default**, not a mandate. If you already hold the synthesis (e.g. you just ran the research) and the next stop is human review, authoring the YAML yourself is often faster and higher-fidelity — and a Gate-0 chat loop is easier to tune when you own the file. Delegate to conserve the main window when this is part of a long autonomous run. See [`sdlc-loop` § Delegate or author directly](../skills/sdlc-loop/SKILL.md#delegate-or-author-directly).

**Delegate to**: `planner` agent — when `sdlc.yml.phase_models.planner` is set, spawn with `model: <value>`; otherwise omit and let the agent's frontmatter default stand.

**Mission**:
- **Objective**: Decompose the request into PR-sized issues; iterate the YAML at `.ai-docs/plans/<slug>.yaml` against human feedback
- **Input**: `$ARGUMENTS` plus any existing research artifact at `.ai-docs/research/<slug>.md`
- **Context**: `.claude/sdlc.yml` (`team_key`, `task_management`)
- **Constraints**: No tracker writes; halt only on explicit approval keyword
- **Output**: `.ai-docs/plans/<slug>.yaml` + terse diff in chat each turn

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| Plan | Gate 0 — chat approval | "Are these the right work items, the right size, the right dependencies?" Approve via "ship it" / "looks good" / "approved" |

## Output

When approved, the planner prints:
```
.ai-docs/plans/<slug>.yaml ready.
Next: /sync-issues .ai-docs/plans/<slug>.yaml
```

## Error Handling

- **YAML conflict during iteration**: planner overwrites in full each turn; the previous version lives in git. Commit between substantive iterations if you want to compare.
- **Scope creep**: if the conversation drifts into implementation specifics, redirect — that's `specifier`'s job.
