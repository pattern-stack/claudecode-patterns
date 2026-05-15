---
name: sdlc-loop
description: Workflow judgment for this project's SDLC loop — when to use /plan vs /design vs /develop vs /orchestrate, what each gate means, how to recover from a halt, how stacks and artifacts flow. Use when starting work on an issue, deciding the next command, interpreting a halt from any phase agent, or recovering from a failed gate.
when_to_use: User asks "what's next for ABC-NN", "should I /design or /develop", "the validator failed — now what", "the spec is wrong", "redo the strategy", "we need to re-plan", "halt", "blocked", "gate", or otherwise needs judgment about operating the SDLC loop.
allowed-tools: Read, Glob, Grep
user-invocable: true
# tool_group: read_only (allowlist)

# === Project SDLC overlay ===
status: active
topology: none
consumes: []
produces: []
gates:
  enforces: []
  sets: []
---

# sdlc-loop — workflow judgment

The human-side judgment layer for this project's SDLC loop. Commands (`/plan`, `/design`, `/develop`, `/orchestrate`, `/sync-issues`) are mechanical entrypoints. Agents (`planner`, `specifier`, `implementer`, `validator`, `understander`, `coordinator`) execute phases. This skill answers **why** and **when** — the questions with no other home.

For full platform reference (frontmatter semantics, etc.) see [`claude-platform`](../claude-platform/SKILL.md). For authoring new components see [`skill-authoring`](../skill-authoring/SKILL.md).

## The loop

```
request
  │
  ▼
/plan ─→ (understander?) ─→ planner ─→ (Gate 0: chat approval)
  │
  ▼
/sync-issues  →  Linear issues filed
  │
  ▼ per issue
/design  ─→  specifier  ─→  /sdlc:critique  ─→  reviewer (lens=mixed)
  │                              │
  │                              ▼
  │                          (Gate 1.5: PASS or PASS_WITH_NOTES)
  │                              │   ↑ REVISE → specifier re-runs (writes Design Addendum)
  │                              ▼
  │                       (Gate 1: state:strategy-approved)
  │
  ▼ per issue
/develop (Topology A)              OR              /orchestrate (Topology B)
  │                                                  │
  ▼                                                  ▼
team: implementer + validator                    coordinator (per issue)
      (+ needs:* extras)                              │
                                                     ▼
                                                  spawns implementer + validator
                                                     (subagents, headless)
  │                                                  │
  └──────────────────┬───────────────────────────────┘
                     ▼
              implementer commits + pushes
                     │
                     ▼
              /sdlc:review ─→ reviewer × 2 sequentially
                                 ├─ lens=adherence (against spec)         (first)
                                 └─ lens=quality   (against quality canvas) (after adherence)
                     │
                     ▼
              (Gate 2.5: joined verdict ≠ REVISE/BLOCK)
                     │   ↑ REVISE → implementer fixes
                     ▼
              validator runs gates (Gate 3)
                     │
                     ▼
              gate_mode: interactive ──→ PR opened ─→ (Gate 2: PR review) ─→ merge
              gate_mode: auto-all    ──→ tracker comment; human reviews batch async
```

## Layers (where each kind of knowledge lives)

| Layer | Captures | Read when |
|---|---|---|
| **CLAUDE.md** | Always-on facts (stack layout, conventions, ceremony) | Auto, every session |
| **Primitives** (`.claude/primitives/`) | Toolchains, gates, commit format, tracker bindings | Agents read on demand |
| **Commands** (`.claude/commands/`) | Mechanical orchestration entrypoints | User types `/<name>` |
| **Agents** (`.claude/agents/`) | How to execute one phase | Delegation |
| **This skill (`sdlc-loop`)** | **Judgment**: command selection, halt recovery, gate semantics, stack flow | Auto-loads on related questions |

When updating: facts → CLAUDE.md or primitive. Phase mechanics → agent. Workflow judgment → here.

## The gates

| Gate | Surface | Set by | Approves to |
|---|---|---|---|
| **Gate 0 — chat approval** | `/plan` chat turn | Human says "ship it" / "approved" | `/sync-issues` |
| **Gate 1.5 — spec critique verdict** | Spec phase section (`Spec Review`) + tracker envelope | `reviewer` agent via `/sdlc:critique` | Gate 1 (strict) or `/develop` directly (auto). REVISE → specifier re-runs. |
| **Gate 1 — `state:strategy-approved`** | Tracker label | Human (strict mode, after Gate 1.5 PASS) **OR** specifier (auto / "trust" mode) | `/develop` or `/orchestrate` |
| **Gate 2 — PR review** | GitHub PR | Human reviewer | merge (only fires under `gate_mode: interactive`) |
| **Gate 2.5 — paired diff review verdict** | Spec phase sections (`Diff Review — Adherence` + `Diff Review — Quality`) + tracker envelope | `reviewer` agent × 2 via `/sdlc:review` | validator (Gate 3) — or implementer re-run on REVISE |
| **Gate 3 — validator pass** | PR comment (interactive) or tracker comment (auto-all) | `validator` agent | merge / human review |

`implementer` halts without `state:strategy-approved` regardless of how it got set — the gate is structurally preserved. `coordinator` defers the check to implementer.

### Gate 1.5 — pre-implementation spec critique

A `reviewer` agent loads the `critique` skill with `lens=mixed`, reads the spec against cited code, and writes a verdict to the spec's `Spec Review` phase section. Catches the bugs a first-pass designer typically misses (wrong line numbers, miscounted call sites, missed constraints, citation drift) before the implementer runs and the cost compounds.

| Verdict | Effect |
|---|---|
| `PASS` / `PASS_WITH_NOTES` | Gate 1.5 cleared. Next: `/sdlc:develop` (or human Gate 1 approval if strict). |
| `REVISE` | Specifier re-runs `/design` — updates static spec sections in place, appends `Design Addendum` summarizing what changed. Reviewer re-checks. |
| `BLOCK` | Architectural conflict; human arbitrates. |

`spec_critic_max_iterations` (`sdlc.yml`) caps the design ↔ critique loop. Cap-hit is a halt, not a failure — surfaces full context.

### Gate 2.5 — paired post-implementation diff review

Two `reviewer` agents spawn sequentially via `/sdlc:review` (Adherence first, then Quality — sequential because both Edit the same spec file and the harness doesn't guarantee Edit serialization across concurrent subagents):

- Reviewer A: `target=diff`, `against=spec`, `lens=adherence` → "Did we build what we said?"
- Reviewer B: `target=diff`, `against=quality-canvas`, `lens=quality` → "Is this well-built?" (spec-blind by construction)

Each writes to its own spec phase section. Verdicts join: the worse of the two wins (BLOCK > REVISE > PASS_WITH_NOTES > PASS in severity order); findings union. The `quality` lens is structurally spec-blind — `/sdlc:review` enforces by passing the quality canvas (not the spec) as `against`, and the reviewer agent halts if `lens=quality` receives a spec-shaped `against`.

The two-lens shape is load-bearing. A single mixed reviewer systematically collapses one lens into the other; the real findings live in the gap.

### Gate-1 modes: strict vs auto ("trust mode")

Gate 1 is configurable per-issue via three override layers, most-specific wins:

```
sdlc.yml.gate1_default: strict          ← global floor (default; safest)
  └─ plan.yaml.auto_approve: true       ← stack-level override (planning time)
      └─ issue gate:auto / gate:human   ← per-issue override (always wins)
```

| Mode | Specifier sets | Halts | Use for |
|---|---|---|---|
| **strict** (default) | `state:awaiting-strategy-review` | yes | Novel work where human approval is load-bearing (port shapes, framework changes, first-of-kind) |
| **auto** ("trust mode") | `state:strategy-approved` | no | Mechanical work where human approval is theatre (RFC translation, YAML definitions, vendor adapter wirings) |

Resolution timing: `/sync-issues` reads `plan.auto_approve` and stamps `gate:auto` or `gate:human` on each leaf at issue-creation. Specifier reads only labels at runtime — never reads plan.yaml.

### Gate mode: interactive vs auto-all (cross-gate envelope)

`gate_mode` (in `sdlc.yml`) is the outer envelope that decides what happens **after** Gate 1. It governs Gate 2 (PR review) and where the validator posts. Compose with `gate1_default` to express the full matrix:

| `gate_mode` | `pr_required` | `validator_post_target` | Best for |
|---|---|---|---|
| **interactive** (default) | true (implementer opens a PR) | `pr` (validator posts to the PR) | Normal review flow — PR per issue, human reviews each |
| **auto-all** | false (implementer pushes; no PR) | `tracker` (validator posts to the issue) | AFK batch execution — human reviews many merged branches asynchronously |

Composition:

| `gate_mode` | `gate1_default` | Resulting flow |
|---|---|---|
| `interactive` | `strict` | Fully gated, conservative default. Human approves strategy + PR. |
| `interactive` | `auto` | Auto-strategy, human PR review. |
| `auto-all` | `strict` | Human-approved strategy, batch-merged branches without PR. |
| `auto-all` | `auto` | Fully autonomous loop; human reviews after the fact. |

Agents branch on the per-mode flags (`modes.<gate_mode>.pr_required`, `modes.<gate_mode>.validator_post_target`), not on `gate_mode` itself — so new modes can ship by extending `sdlc.yml.modes` without touching agents.

Gate 2.5 (paired diff review) fires under both modes — it's a pre-merge sanity check, not a PR gate.

## Status taxonomy (9 columns)

The outcome-driven Status field for the active task tracker. Outcome names age well as Gate 1 softens; no "Strategy review" column (label-only filter) and no "Specifying" sub-state (collapses to Planning).

```
Backlog → On-Deck → Planning → Ready → In Progress → In Review → Done       Blocked    Cancelled
```

| Column | Outcome | Mover |
|---|---|---|
| **Backlog** | Synced from plan; no commitment | `/sync-issues` default |
| **On-Deck** | Committed for this wave | human triage |
| **Planning** | Spec being written OR strategy posted, awaiting OK | `/sdlc:design` start |
| **Ready** | Spec is acceptable to start (Gate-1 satisfied) | specifier (auto mode) or human (strict mode) |
| **In Progress** | Branch + commits, no PR | implementer |
| **In Review** | PR open | implementer |
| **Done** | Merged | GitHub |
| **Blocked** | Parked | coordinator only (Gate-1 timeout in `/orchestrate`); humans set otherwise |
| **Cancelled** | Won't do | human |

Mover discipline keeps Status moves predictable. Implementer + validator halt with errors but do **not** self-block — only the coordinator does. See `plugin/primitives/task-management/{github,linear}.md` for adapter mapping.

## Decision tree: which command

For the full table see [command-selection.md](command-selection.md). Short version:

```
new request, no plan yet               → /plan
plan exists, ready to file in Linear   → /sync-issues <plan.yaml>
issue filed, no spec yet               → /design <KEY>
spec approved, single issue, watching  → /develop <KEY>           (Topology A)
many approved issues, AFK throughput   → /orchestrate <filter>    (Topology B)
cold-start session                     → /prime
```

## Halt recovery

When any agent halts, see [halt-recovery.md](halt-recovery.md) for the full catalog. The most common:

| Halt | What it means | Recovery |
|---|---|---|
| `awaiting human approval` (specifier strict mode) | Strategy is posted; Status=Planning; needs human OK | Human reviews tracker comment → adds `state:strategy-approved` (Status moves to Ready) |
| `not state:strategy-approved` (implementer halt) | Gate 1 not yet passed | Run `/design <KEY>` if no spec; else have human approve OR apply `gate:auto` to the issue + re-run `/design` to auto-approve |
| `spec missing — specifier did not run` | No spec on disk | `/design <KEY>` |
| `state:blocked` | Explicit block | Resolve blocker, remove label, re-run |
| `validator: blocking failure` | Gate failed on PR | Implementer fixes; re-run validator |

## Stack anatomy

Multi-issue plans define a **stack**. All artifacts live at `.ai-docs/stacks/<slug>/`. See [stack-anatomy.md](stack-anatomy.md) for the layout, artifact-flow diagram, and discovery rules.

Key idea: `<slug>` is set once by the planner; downstream agents discover it by globbing `.ai-docs/stacks/*/plan.yaml` for the issue key. Don't rename mid-flight.

## Topology A vs B

| | Topology A (`/develop`) | Topology B (`/orchestrate`) |
|---|---|---|
| Issues at a time | 1 | many (capped by `orchestrate_concurrency`) |
| Pattern | Flat team via `TeamCreate` (split-pane teammates) | One coordinator teammate per issue; spawns implementer + validator as subagents |
| Best for | Human eyes per step (UI, debugging, data validation) | AFK throughput on pre-approved issues |
| Halt visibility | Immediate | Surfaces in coordinator's report |
| `needs:browser-pilot` etc. | Required path | Auto-dropped (forbidden in Topology B) |

The Topology B constraint is load-bearing: subagents cannot spawn other subagents. The coordinator's `tools: ..., Agent(implementer, validator)` enforces this at the framework level.

## Common pitfalls

1. **Skipping `/design` and going straight to `/develop`.** Gate 1 halts the implementer. Run `/design <KEY>` first.
2. **Hand-editing the spec after approval.** The implementer reads the spec verbatim. If the spec is wrong, re-run `/design` (specifier overwrites; previous version in git).
3. **Running `/orchestrate` with `needs:*` issues that map to Topology-A agents.** `/orchestrate` drops these and recommends `/develop`. Don't override.
4. **Removing `state:strategy-approved` after implementation.** It's idempotent — leave it. Re-runs are fine.
5. **Trying to plan and design in one shot.** Two human gates exist for a reason. `/plan` produces work shape; `/design` produces strategy per work item. Don't fuse.
6. **Renaming a stack slug after `/sync-issues`.** Linear's `[plan-key:<slug>/<key>]` markers pin the slug. Rename means manual marker updates or duplicate issues on next sync.

## What this skill does NOT cover

- **Phase mechanics** — how to actually write a spec / write code / run gates → see the agent files.
- **Project conventions** — stack layout, package naming, ESM rules → see CLAUDE.md.
- **Toolchain** — which commands run typecheck/build → see `primitives/language/typescript.md`.
- **Tracker bindings** — Linear label IDs, branch convention → see `primitives/task-management/linear.md`.
- **Component authoring** — how to write a new skill/agent/command → see `skill-authoring`.
- **Platform reference** — every Claude Code field, every SDK primitive → see `claude-platform`.

## Cross-references

| Command | What |
|---|---|
| [`/plan`](../../commands/plan.md) | Decompose a request into PR-sized issues |
| [`/sync-issues`](../../commands/sync-issues.md) | Apply approved plan to Linear |
| [`/design`](../../commands/design.md) | Produce per-issue spec |
| [`/develop`](../../commands/develop.md) | Topology A execution |
| [`/orchestrate`](../../commands/orchestrate.md) | Topology B execution |
| [`/prime`](../prime/SKILL.md) | Session cold-start |
