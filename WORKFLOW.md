# Workflow Guide

A walkthrough of the gate-disciplined SDLC loop shipped by claudecode-patterns. Read this when you want to understand the end-to-end flow as a human operator. For Claude-side workflow judgment (when to use which command, how to recover from a halt), see [`.claude/skills/sdlc-loop/SKILL.md`](.claude/skills/sdlc-loop/SKILL.md).

## The two-gate model

The workflow has **three phases** and **two human gates**:

```
   Decompose → Strategy → Implement → Review → Merge
       │          │            │          │
       │          │            │          │
       ▼          ▼            ▼          ▼
   /plan      /design      /develop      PR
              + label    + branch +     review
              gate         commits +    gate
                             PR
```

Everything else — typecheck, lint, tests, commits, PR creation, validation reports — is automated.

## Gate 0 — Decomposition (synchronous, in chat)

**Command:** `/plan "<request>"`

You start with a request like *"Add Redis caching to the user service"*. The planner agent decomposes it into a YAML plan: an epic + sub-issues + dependencies + labels. You iterate in chat, refining scope and ordering, until you say "approved."

**Output:** `.ai-docs/plans/<slug>.yaml` (local file, NOT yet on your task management tool).

**Why this gate is synchronous:** Plans are negotiated. Task-management round-trips slow this down; chat is the right medium.

```bash
/plan "Add Redis caching to user service"
# (probing dialog — you respond with constraints, scope clarifications)
# (planner produces YAML)
# (you say "approved")
```

After approval:

```bash
/sync-issues
# pushes the YAML to your active task-management adapter (Linear / GitHub Issues / …)
# creates: epic + leaf issues + sub-issue parenting
# idempotent — re-runs apply diffs only
```

## Gate 1 — Strategy (strict by default; auto / "trust mode" available)

**Command:** `/design <ISSUE-KEY>`

For each issue from the plan, run `/design`. The specifier agent reads the issue, drafts an implementation strategy (Goal, Approach, File-level plan, Interfaces, Tests, Out of scope, Open questions — per the [spec canvas](plugin/canvases/spec/README.md)), and posts a condensed view as a tracker comment.

**Two paths from there**, selected per-issue by gate-mode resolution (sdlc.yml.gate1_default → plan.yaml.auto_approve → issue gate:* label, most-specific wins):

- **strict mode (default):** specifier sets `state:awaiting-strategy-review`, Status=Planning, halts. You review on the tracker; apply `state:strategy-approved` when satisfied (Status moves to Ready).
- **auto mode ("trust mode"):** specifier sets `state:strategy-approved`, Status=Ready, completes. No human Gate-1 review. Use for mechanical work (RFC translation, vendor adapter wirings, YAML definitions) where review is theatre.

**Why two paths:** real teams have a mix. Some stacks are novel (port shapes, framework changes) — keep the strict gate. Others are mechanical — let the agent self-approve and unlock parallel implementation. The implementer's hard refusal-without-`state:strategy-approved` is preserved structurally; auto mode just satisfies the gate via the agent.

```bash
/design ABC-101
# strict: specifier writes strategy → tracker comment → state:awaiting-strategy-review → halts
#   you review on the tracker → apply state:strategy-approved
# auto:   specifier writes strategy → tracker comment → state:strategy-approved → completes
```

## Implementation — Topology choice

Once an issue is `state:strategy-approved`, you have two execution paths:

### Topology A — `/develop <ISSUE-KEY>`

Flat team for one issue. Implementer + validator collaborate in this session. Best for:

- One-at-a-time work where you want full attention on the issue
- Iterative scope ("let me see how this lands then refine")
- Issues with `needs:*` labels that compose extra teammates (e.g. `needs:browser-pilot`)

```bash
/develop ABC-101
# implementer reads spec, branches <owner>/abc-101-feature-name
# writes code, commits per conventional format
# opens PR (draft) when complete
# validator runs the configured quality profile, posts report
```

### Topology B — `/orchestrate <FILTER>`

Parallel batch. One coordinator per issue, each spawning implementer + validator as headless subagents in worktree isolation. Best for:

- Multiple approved issues ready to work
- AFK throughput (you queue overnight, review PRs in the morning)
- Independent work (no cross-issue conflicts on shared files)

```bash
/orchestrate ABC-101 ABC-102 ABC-103       # explicit list
/orchestrate state:strategy-approved        # label-based query
/orchestrate plans/<slug>.yaml              # all issues from a plan
```

The coordinator agent wraps each issue: spawns implementer (writes code, opens PR), spawns validator (runs quality profile, posts report). Issues with `needs:*` labels that require non-default teammates get dropped — run those via `/develop` separately.

**Concurrency** is set by `sdlc.yml.orchestrate_concurrency` (default 3).

## Gate 2 — PR Review

The validator agent posts a report on each PR. Read the report, review the code, request changes via PR comments, merge when satisfied.

The validator never mutates source — it only reports. Source mutations stay with the implementer. This separation makes the validator's report trustworthy.

## End-to-end example

```bash
# Day 1 morning — Gate 0
/plan "Add Redis caching to user service with cache invalidation"
# (iterate; approve)
/sync-issues
# → creates epic ABC-100 + issues ABC-101, ABC-102, ABC-103, ABC-104

# Day 1 afternoon — Gate 1 (one at a time, careful review)
/design ABC-101    # cache adapter
# (review on Linear, label state:strategy-approved)
/design ABC-102    # invalidation hooks
# (review, approve)
/design ABC-103    # tests
/design ABC-104    # docs

# Day 2 — Implementation in parallel (Gate 2 happens async on each PR)
/orchestrate state:strategy-approved
# → 4 coordinators spawn, each handling one issue
# → 4 PRs open over the next ~hour
# → validator reports on each
# (review and merge each PR as it lands)
```

Total human time: ~30 minutes spread across two days. Total agent time: ~2 hours.

## Halt recovery

Any phase agent can halt at a gate. The most common halts:

| Halt | Why | What to do |
|---|---|---|
| Implementer halts: "issue not strategy-approved" | Gate 1 not passed | Run `/design <key>`; review; label `state:strategy-approved`; re-run `/develop` |
| Implementer halts: "spec is wrong" | Strategy doesn't match reality | Re-run `/design <key>` (specifier overwrites); review the new strategy; approve |
| Validator halts: typecheck / lint / tests fail | Quality gate failed | Read validator report on PR; fix in implementer; push; validator re-runs on push |
| Coordinator halts: subagent error | Topology B child agent failed | Read coordinator's halt message; usually retry the issue via `/develop <key>` (Topology A) for closer attention |

For full halt-recovery decision tree, see [`.claude/skills/sdlc-loop/halt-recovery.md`](.claude/skills/sdlc-loop/halt-recovery.md).

## Configuration

The workflow's behavior is governed by `.claude/sdlc.yml`:

```yaml
language: typescript           # primitives/language/typescript.md loaded
quality_profile: strict        # primitives/quality/strict.md loaded
commit_style: conventional     # primitives/commit/conventional.md loaded
task_management: linear        # primitives/task-management/linear.md loaded
team_key: ABC                  # task management tool team key — used in branch convention + sync filters

develop_team:                  # Topology A base roster
  - implementer
  - validator

orchestrate_concurrency: 3     # Topology B max parallel coordinators

worktree:
  enabled: true                # implementer subagents run in isolated worktrees
```

To swap a primitive (Linear → GitHub Issues), change one line in `sdlc.yml` and create the new primitive file. No agent edits required — agents use denylist tool inheritance and read task management tool calls through whichever MCP is connected.

## Artifacts produced

The workflow produces several structured artifacts, each governed by a canvas:

| Artifact | Producer | Canvas | Where it lands |
|---|---|---|---|
| Plan YAML | `planner` | [plan canvas](.claude/canvases/plan/README.md) | `.ai-docs/plans/<slug>.yaml` |
| Spec | `specifier` | [spec canvas](.claude/canvases/spec/README.md) | `.ai-docs/stacks/<slug>/specs/<issue>.md` + task management tool comment |
| Phase envelope | every phase agent | [envelope canvas](.claude/canvases/envelope/README.md) | end of every agent response |
| Session log | every workflow command | [session canvas](.claude/canvases/session/README.md) | `agent-logs/<session-id>/` |

Canvases govern these artifacts' shape. Tune them via `just canvas-dev` (knob-level control) or `just canvas-seller` (outcome-framed dialog). See [`.claude/skills/canvas-authoring/SKILL.md`](.claude/skills/canvas-authoring/SKILL.md).

## Observability

Every Claude Code lifecycle event (26 of them — SessionStart, PreToolUse, SubagentStart, …) gets POSTed to your dashboard via `.claude/hooks/emit.mjs`. The session canvas accumulates per-turn envelope JSONL into a session directory at `agent-logs/<session-id>/`.

Run `just canvases` to reconcile canvases on disk against the registry in `sdlc.yml.canvases`.

## Configuration verifiers

```bash
just verify                # all invariants
just verify-tool-groups    # agent frontmatter matches sdlc.yml.tool_groups
just verify-canvases      # every canvas's instructions.yaml validates against its schema
```

These should run in CI. They catch:

- Drift between an agent's declared `tool_group:` comment and its actual `tools:` / `disallowedTools:` list
- Schema violations in canvas configurations (e.g. unknown verbosity values, missing required fields)

## Migration from v1

If you ran the v1 workflow (3-step `commands/plan/` sequence, Linear-specific bootstrap, no canvases), see the README's "What changed from v1" table. The skeleton (decompose → spec → implement → validate) is preserved; everything underneath was rewritten. v1 is archived at [`.claude/docs/archive/v1-bootstrap-plan.md`](.claude/docs/archive/v1-bootstrap-plan.md).
