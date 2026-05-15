---
type: primitive
category: task-management
value: linear
status: active
description: Linear-specific implementation of the task-management contract — gate label semantics, branch/PR conventions, MCP tool routing.
---

# Linear Task Management Primitive

Linear-specific implementation of the task-management primitive. Defines the gate semantics that the SDLC loop depends on (see RFC-0004 § Gate contract).

> **Scope.** This file is intentionally Linear-specific. The *contract* (state labels, gate mechanics, idempotence) is generic — when a second backend lands (e.g. `task-management/github.md`), the contract section migrates to `task-management/README.md` and this file shrinks to just the Linear-specific bindings. Until then, treat the contract sections below as authoritative for Linear and forward-compatible with future backends.

## Team

Configured via `team_key` in `.claude/sdlc.yml`. dugs-agents uses team `AP` (AgentPatterns).

## State labels (the v1 gate API)

The loop depends on these labels existing on the team. Provision idempotently via `bash plugin/primitives/task-management/bootstrap.sh` (github-only today; for Linear, provision via the Linear UI or your own setup script).

| Label | Set by | Means |
|---|---|---|
| `state:awaiting-strategy-review` | `specifier` agent (strict mode, after posting strategy comment) | Strategy is ready for human review. AFK gate. |
| `state:strategy-approved` | **Human** in Linear UI **or** `specifier` agent (auto mode) | Gate-1 satisfied. `implementer` refuses to start without this label. |
| `state:blocked` | **Coordinator only** (Gate-1 timeout in `/orchestrate`) | Blocked on external input. Implementer + validator halt with errors but do NOT self-block — humans disposition. |

`gate:*` labels — `gate:auto` (auto-approve mode) and `gate:human` (force strict; overrides plan) — control specifier resolution. See `/sdlc:design` for the resolution chain.

Other claudecode-patterns label groups (`type:` / `stack:` / `work:` / `layer:` / priority) are deferred — not provisioned in v1.

## Status taxonomy mapping (working hypothesis)

The 9-option outcome-driven Status taxonomy (defined in `github.md`) maps to Linear's 5 native workflow-state types as follows. Linear's state-type model is coarser than GitHub Projects' Status field, so fine-grained columns ride on labels:

| 9-option Status | Linear workflow state type | Mechanism |
|---|---|---|
| **Backlog**     | `backlog`    | native state |
| **On-Deck**     | `unstarted`  | native state + `status:on-deck` label |
| **Planning**    | `unstarted`  | native state + `status:planning` label |
| **Ready**       | `unstarted`  | native state + `status:ready` label (or `state:strategy-approved` as proxy) |
| **In Progress** | `started`    | native state |
| **In Review**   | `started`    | native state + `status:in-review` label (or PR-open as proxy) |
| **Done**        | `completed`  | native state |
| **Blocked**     | `unstarted`  | native state + `status:blocked` label |
| **Cancelled**   | `canceled`   | native state |

This is a starting point. Specifier may propose a refined mapping per-stack. The `status:*` labels are not part of v1's required palette — they're an opt-in convention for Linear teams that want the GitHub-Projects-equivalent visualization.

## Gate mechanics

### Specifier — set `state:awaiting-strategy-review`

After posting the strategy as a Linear comment:
1. Read existing labels on the issue.
2. Add `state:awaiting-strategy-review`.
3. Halt. Do not proceed to implementation.

### Implementer — check `state:strategy-approved`

Before any code change:
1. Read labels on the assigned issue.
2. If `state:strategy-approved` is **not** present, write a one-line "waiting on approval" status and halt.
3. If present, proceed.
4. On successful PR creation, optionally remove `state:strategy-approved` (idempotent re-runs allowed; not required).

The gate is idempotent — any phase can be re-run.

## Branch and PR conventions

- **Standalone branch**: `<user>/<issue-key-lowercase>-<slug>` (e.g. `dugshub/ap-12-pm-domain`).
- **Stacked branch** (via `st`): `<user>/<stack-slug>/<N>-<slug>` (e.g. `dugshub/plugin-layout/2-gate-modes`). `<N>` is the stack position (1-based, assigned by st). `<slug>` is **terse** — see "Slug rules" below.
- **PR body** must include `Closes <ISSUE-KEY>` so Linear auto-links and auto-closes.
- **Commit scope** should be the issue key (e.g. `feat(ap-12): ...`) — the conventional-commits primitive covers this.

### Slug rules

The `<slug>` portion is the only free-form part. Keep it **succinct** — the issue key + commit history + PR description carry the full context.

- **Max 3 words**, kebab-case (`gate-modes`, `link-project`, `tracker-discovery`)
- **Prefer noun phrases** over action phrases (`docs` not `rewrite-docs`; `nag-hook` not `add-nag-hook`)
- **No issue keywords** (`pr-N-`, `issue-NN`, `feat-`) — the directory + PR + issue body already carry that
- **No verbose descriptions** (anti-example: `gate-mode-mechanism-and-status-taxonomy-v2-1-opinion`)

The branch name is for humans skimming `st status` or `git branch -a`; the durable identifiers are the issue key and PR number.

## CLI / tool reference

This repo uses the Linear MCP server for in-session reads/writes. Common operations:

| Operation | Tool |
|---|---|
| Read issue + labels | `linear.get_issue` |
| List issues by filter | `linear.list_issues` |
| Post strategy comment | `linear.save_comment` |
| Add/remove labels | `linear.save_issue` (with `labelIds`) or label-specific tools |
| List labels on team | `linear.list_issue_labels` |

Permissions: setting labels requires Linear write scope. The Linear MCP authenticated for this workspace already has it.

## Epic status cascade

When the SDLC loop creates parent epic issues (via `/sync-issues`) and child leaf issues, child-status transitions should cascade to the parent automatically. Manual epic-status moves are error-prone — easy to forget the first time the first child moves, easy to leave the epic at `In Progress` long after the last child reached `In Review`.

| Trigger | Cascade |
|---|---|
| **First child** transitions any state → `In Progress` | Move parent epic `Backlog` / `Ready` → `In Progress` |
| **Last child** transitions any state → `In Review` (i.e., all children are now `In Review` or `Done`) | Move parent epic `In Progress` → `In Review` |
| **All children** reach `Done` | Move parent epic `In Review` → `Done` |

Each cascade is idempotent — running twice is a no-op (the parent is already at the target state). Agents that move child status (implementer when starting a branch; validator when posting a pass; the lead on /done) must:

1. Resolve the parent epic via `linear.get_issue(child_key).parentId`.
2. If parent exists, query its children: `linear.list_issues({ parentId, includeArchived: false })`.
3. Apply the rule above based on the children's collective state.
4. Call `linear.save_issue(parent_key, { stateId: <resolved> })` only if the parent's current state differs from the target.

Cascade is governed by `sdlc.yml`:

```yaml
epic_cascade:
  enabled: true                       # default true; set false to manage epic status manually
  on_first_child_in_progress: true
  on_last_child_in_review: true
  on_all_children_done: true
```

When `enabled: false`, no agent performs cascade; humans manage epic status.

**Implementation status (v2 follow-up):** the cascade contract is defined here, but as of plugin v0.1.13 no SDLC phase agent (implementer / validator / reviewer / coordinator) actually performs the parent-status update. The "child status mover" in the loop today is mostly implicit (humans drag-and-drop in the tracker UI; GitHub auto-closes on PR merge). A follow-up PR will wire cascade execution into the validator (on `In Review` transitions) and into a new `/sdlc:done` command (on the final `Done` transition). Until then, this section documents intent; expect manual epic-status moves.

## `needs:*` labels (Topology A team composition)

Per-issue extras for `/develop`'s Topology A team are declared as `needs:*` labels:

| Label | Adds to develop_team |
|---|---|
| `needs:browser-pilot` | Spawns `browser-pilot` teammate (UI verification) |
| `needs:tester` | Spawns `tester` teammate (data/logs validation) |
| `needs:designer` | Spawns `designer` teammate (UI taste pass) |

These are read by `/develop` at dispatch time — added to the base `develop_team` from `sdlc.yml`. Unknown `needs:*` labels are warned but not fatal.

`needs:*` labels are not provisioned by `setup-linear-labels.sh` — they're created on demand when the corresponding agent file is vendored.
