---
type: primitive-port
category: task-management
status: active
description: The task-management port — abstract operations and conventions consumed by agents and commands. Adapters (linear.md, github.md) provide concrete CLI/MCP bindings. The active adapter is selected by `task_management:` in `.claude/sdlc.yml`.
---

# Task Management Port

The abstract contract that agents and commands depend on. Concrete bindings live in sibling adapter files (`linear.md`, `github.md`). When you write or edit an agent prompt, **reference operations from this file, never concrete CLI/MCP commands**. The adapter file is consulted only at runtime by the agent.

## Operation contract

All operations are documented adapter-neutrally. Adapter files (`{task_management}.md`) provide a one-to-one binding table.

| Operation | Inputs | Output | Notes |
|---|---|---|---|
| `read-issue` | `key` | `{ key, title, body, labels[], state, url, assignees[], project_items[] }` | `key` is opaque to the port — Linear: `AP-12`; GitHub: `12`. |
| `list-issues` | `filter` | `issue[]` | `filter` shape: `{ labels?: string[], state?: 'open' \| 'closed' \| 'all', query?: string }`. Adapter may not honor every field. |
| `create-issue` | `{ title, body, labels[] }` | `{ key, url }` | Idempotent only when caller pre-checks via `find-by-marker`. |
| `update-issue` | `key`, `{ title?, body?, addLabels?, removeLabels? }` | `void` | Preserves labels not mentioned. |
| `add-comment` | `key`, `body` | `void` | Used for posting strategy comments and progress notes. |
| `set-blocking` | `blocked_by_key`, `blocks_key` | `void` | Adapter may approximate (e.g. GitHub uses `Depends on: #N` body line; Linear uses native blocks relation). |
| `find-by-marker` | `marker_string` | `key \| null` | Locates an issue whose body contains the given idempotence marker. Used by `/sync-issues`. |
| `add-sub-issue` | `parent_key`, `child_key` | `void` | Creates a parent → child issue relationship. Used by `/sync-issues` to wire epic parents to leaf issues. Adapter MAY approximate (e.g. tracker without native sub-issues uses tasklist syntax in body). |
| `set-type` | `key`, `type: 'project' \| 'epic' \| 'task'` | `void` | Tags an issue with its hierarchical type. Adapter chooses representation: native Issue Types (where supported) or `type:*` labels as a fallback. The three port-level type names are canonical; adapters MAY add more. |

Operations not in this table belong to the adapter, not the port. If you find yourself wanting one, propose adding it here first.

## Issue hierarchy (project / epic / task)

Three canonical types form a 3-level tree consumed by `/sync-issues`:

| Type | Scope | Example | Children |
|---|---|---|---|
| `project` | One wave / release / deliverable | "Wave 1 — HubSpot CRM end-to-end" | Epics |
| `epic` | One stack / coherent surface area | "Foundation — monorepo + L1 markers + CI" | Tasks |
| `task` | One PR-sized unit of work | "Bootstrap monorepo (bun workspaces, biome, justfile, postgres compose)" | (leaf) |

Hierarchy is convention enforced by `/sync-issues`, not by the tracker. Adapters representation differs:
- Native Issue Types where supported (GitHub orgs, Linear's project entity)
- Labels (`type:project` / `type:epic` / `type:task`) where not (GitHub user repos)

The `set-type` operation hides the difference from agents and commands.

## State labels (the gate API)

The loop depends on three state labels existing on the tracker. Provision them once when setting up the project; the active adapter file documents how.

| Label | Set by | Means |
|---|---|---|
| `state:awaiting-strategy-review` | `specifier` agent (after posting strategy comment) | Strategy ready for human review. AFK gate. |
| `state:strategy-approved` | **Human** (in tracker UI) | Approval to proceed to implementation. `implementer` refuses to start without this label. |
| `state:blocked` | Any agent on hard stop | Blocked on external input or unrecoverable error. Halts the loop. |

These names are **port-level** — every adapter must surface labels with these exact names. Adapters do not rename them.

## `needs:*` labels (Topology A team composition)

Per-issue extras for `/develop`'s Topology A team. Created on demand.

| Label | Adds to develop_team |
|---|---|
| `needs:browser-pilot` | Spawns `browser-pilot` teammate (UI verification) |
| `needs:tester` | Spawns `tester` teammate (data/logs validation) |
| `needs:designer` | Spawns `designer` teammate (UI taste pass) |

## Branch and PR conventions

- **Branch**: `<user>/<issue-identifier>-<slug>`
  - `<issue-identifier>` is whatever the active adapter calls the issue: Linear key lowercased (`ap-12`), GitHub issue number (`12`).
  - `<slug>` is a 3-4 word kebab summary derived from the issue title.
  - Example: `dug/ap-12-add-pm-domain` (Linear) · `dug/12-add-pm-domain` (GitHub)
- **PR body** must include the adapter's closing reference syntax (Linear: `Closes <KEY>`; GitHub: `Closes #<n>`) so the tracker auto-links/auto-closes.
- **Commit scope** is the issue identifier (Linear: `feat(ap-12): ...`; GitHub: `feat(#12): ...`). Conventional-commits primitive covers this.

The adapter file documents the exact closing-reference syntax.

## Idempotence marker convention

`/sync-issues` writes a footer line into each issue body:

```
[plan-key:<plan.slug>/<issue.key>]
```

`find-by-marker` searches issue bodies for this marker. The marker is stable across edits because it lives in the issue body, not in labels or titles. **All adapters must implement `find-by-marker` against this marker format.**

## Gate mechanics (port-level, adapter-neutral)

### Specifier — set `state:awaiting-strategy-review`

After posting the strategy as an issue comment via `add-comment`:
1. Call `update-issue(key, { addLabels: ['state:awaiting-strategy-review'] })`.
2. Halt. Do not proceed to implementation.

### Implementer — check `state:strategy-approved`

Before any code change:
1. Call `read-issue(key)`.
2. If `state:strategy-approved` is **not** in the labels, write a one-line "waiting on approval" status and halt.
3. If `state:blocked` is present, halt with the blocker.
4. Else proceed.

The gate is idempotent — any phase can be re-run.

## How agents consume this

1. The agent prompt references operations from the table above (e.g. "use `read-issue` to fetch the issue context").
2. At runtime, the agent reads `.claude/sdlc.yml` to discover the active adapter (`task_management:` field).
3. The agent reads `.claude/primitives/task-management/{task_management}.md` for the concrete binding (which CLI/MCP command to invoke).
4. Agent invokes the concrete command via its allowed tools.

The agent never hardcodes Linear or GitHub. Switching adapters is a one-line edit in `sdlc.yml`.

## Adding a new adapter

To add a third adapter (e.g. `jira.md`, `notion.md`):

1. Create `primitives/task-management/<name>.md` following the shape of `linear.md` / `github.md` — one binding row per operation in this README.
2. Document any port operations the adapter cannot satisfy as `D6 gaps` in the adapter's frontmatter (`d6_gaps: [set-blocking]`). Agents check `d6_gaps` and degrade gracefully.
3. Add label-provisioning instructions to the adapter file.
4. Update `sdlc.yml` to allow `task_management: <name>`.

No agent or command file changes if the operations are satisfied. That's the point of the port.
