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

The loop depends on these three labels existing on the team. Provision via `scripts/setup-linear-labels.sh`.

| Label | Set by | Means |
|---|---|---|
| `state:awaiting-strategy-review` | `specifier` agent (after posting strategy comment) | Strategy is ready for human review. AFK gate. |
| `state:strategy-approved` | **Human** in Linear UI | Approval to proceed to implementation. `implementer` refuses to start without this label. |
| `state:blocked` | Any agent on hard stop | Blocked on external input or unrecoverable error. Halts the loop. |

Other claudecode-patterns label groups (`type:` / `stack:` / `work:` / `layer:` / priority) are deferred — not provisioned in v1.

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

- **Branch**: `dugshub/<issue-key-lowercase>-<slug>` (e.g. `dugshub/ap-12-add-pm-domain`). When stacked via `st`, use `dugshub/<stack>/<N>-<desc>`.
- **PR body** must include `Closes <ISSUE-KEY>` so Linear auto-links and auto-closes.
- **Commit scope** should be the issue key (e.g. `feat(ap-12): ...`) — the conventional-commits primitive covers this.

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

## `needs:*` labels (Topology A team composition)

Per-issue extras for `/develop`'s Topology A team are declared as `needs:*` labels:

| Label | Adds to develop_team |
|---|---|
| `needs:browser-pilot` | Spawns `browser-pilot` teammate (UI verification) |
| `needs:tester` | Spawns `tester` teammate (data/logs validation) |
| `needs:designer` | Spawns `designer` teammate (UI taste pass) |

These are read by `/develop` at dispatch time — added to the base `develop_team` from `sdlc.yml`. Unknown `needs:*` labels are warned but not fatal.

`needs:*` labels are not provisioned by `setup-linear-labels.sh` — they're created on demand when the corresponding agent file is vendored.
