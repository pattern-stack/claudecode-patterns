# Command selection

Decision criteria for picking the right command at any point in the SDLC loop.

## State machine

| Current state | Next command | Why |
|---|---|---|
| New request, nothing tracked yet | `/plan <description>` | Decompose into PR-sized issues; iterate via Gate 0 chat approval |
| Plan YAML exists at `.ai-docs/stacks/<slug>/plan.yaml`, approved in chat | `/sync-issues <path>` | Idempotent Linear filing |
| Issue exists in Linear, no spec on disk | `/design <KEY>` | Specifier writes durable spec + posts strategy comment + sets `state:awaiting-strategy-review` |
| Issue carries `state:awaiting-strategy-review` | (human in Linear) | Review comment, add `state:strategy-approved` |
| Issue carries `state:strategy-approved`, single issue, watching | `/develop <KEY>` | Topology A — flat team with split-pane visibility |
| Multiple `state:strategy-approved` issues, want AFK throughput | `/orchestrate <filter>` | Topology B — coordinator-per-issue, subagents headless |
| Cold-start a fresh session | `/prime` | Loads handoff, branch, ticket, recent commits |
| UI epic with locked decisions, multi-phase, theme-swap matters | `/design-loop <spec-path>` | Drives spec → implement → audit → fix → validate per phase. Standalone (no tracker issue required). |
| Audit a shipped/in-flight UI surface against a design spec | `/design-audit <pr-or-branch> <spec-path>` | Audit-only; posts findings with screenshots; no fixes dispatched |
| Per-issue design work on top of `/develop` | Add `needs:design` label to the issue; run `/develop <KEY>` | Composed mode — `/develop` adds `design-auditor` to the team after implementer commit |

## /develop vs /orchestrate

| Question | If yes → /develop | If yes → /orchestrate |
|---|---|---|
| Will I be at the keyboard for each step? | ✓ | — |
| Do I need UI verification (`needs:browser-pilot`, `needs:designer`, `needs:design`)? | ✓ — Topology B forbids these | — |
| Does the issue need data/log validation per step (`needs:tester`)? | ✓ | — |
| Are there many independent issues to grind through? | — | ✓ |
| Am I OK with halts surfacing only in coordinator reports? | — | ✓ |

If an issue carries any `needs:*` label that maps to a Topology-A agent (`browser-pilot`, `designer`, `design-auditor`, `tester`), `/orchestrate` will drop it automatically and recommend `/develop`. Don't try to override — these agents exist for split-pane co-presence and don't run headless.

## /develop (composed-design mode) vs /design-loop (standalone)

When the design work is one PR-sized phase, label the issue `needs:design` and run `/develop <KEY>` — the team picks up `design-auditor` between the implementer's commit and the validator's run. This composes cleanly with all existing gates (1.5, 2, 2.5, 3) and ships as a normal PR.

When the design work is multi-phase or pre-tracker (you're shaping a UI surface from scratch), use `/design-loop <spec-path>` standalone. The loop drives spec → implement → audit → fix → validate per phase with the termination strategy you pick (`user-gate` / `max-loops` / `critic-evaluated`). It can run before any tracker issues exist; spec lives at `.ai-docs/design/<slug>/spec.md`.

The two modes share the same agents, canvas, and primitive. See [`design-loop` SKILL.md § Composed mode](../design-loop/SKILL.md#composed-mode) for the full collapse-rules.

## /plan vs jumping straight to /design

`/plan` produces a multi-issue YAML. `/design` produces a single-issue spec. Skip `/plan` only when:

- The work is genuinely one issue (no decomposition needed).
- A Linear issue already exists and is the right size.
- You've manually verified there's no "this should be split" judgment to make.

When in doubt, `/plan` first. Even a single-issue plan is fine — `/sync-issues` files it idempotently.

## /design re-runs

Acceptable scenarios:
- Spec was written, human reviewed comment, requested changes → re-run `/design <KEY>`.
- Implementer halted because spec was wrong → re-run `/design <KEY>`.
- Issue scope changed in Linear → re-run `/design <KEY>`.

Specifier overwrites the spec on re-run. Previous version is in git history. The Linear strategy comment gets a new entry (specifier appends, doesn't edit prior).

If `state:strategy-approved` was already set, specifier asks before overwriting (regression-prevention).

## What you can skip

| Cannot skip | Reason |
|---|---|
| `/plan` for genuinely multi-issue work | You'll lose the dependency graph and end up filing issues by hand |
| `/design` before `/develop` | Implementer halts at Gate 1 |
| `/sync-issues` before `/design` | Specifier needs a Linear issue key as input |

| Can skip | When |
|---|---|
| `/prime` | Optional — only useful for context loading; not part of the SDLC loop itself |
| `/plan` for single-issue work | When the work is already a single PR-sized issue and you can file it manually |
| `/orchestrate` | Always — `/develop` works for any issue, just one at a time |

## Worked examples

**"I just got a new request for adding GitHub auth."**
→ `/plan add github oauth` (multi-issue: model + adapter + UI + tests)

**"ABC-101 is in Linear, I want to start working on it."**
→ Check labels. If no `state:strategy-approved`: `/design ABC-101`. Once approved by human: `/develop ABC-101`.

**"I have ABC-101, ABC-102, ABC-103 all approved overnight."**
→ `/orchestrate state:strategy-approved` (or pass explicit keys).

**"The implementer halted on ABC-101 saying the spec is wrong."**
→ `/design ABC-101` (re-run; specifier overwrites).

**"I'm starting a fresh session and don't remember where I left off."**
→ `/prime`

**"ABC-104 has `needs:browser-pilot`. Can I `/orchestrate` it with the others?"**
→ No. `/orchestrate` will drop it. Run `/develop ABC-104` separately.

**"I'm starting a UI epic — multi-phase, locked decisions, two themes."**
→ `/design-loop .ai-docs/design/<slug>/spec.md`. Standalone — no tracker issue required up front. Each phase user-gates by default.

**"ABC-105 is a UI polish issue, one phase. I want design audit in the loop."**
→ Add `needs:design` label. Run `/develop ABC-105`. The team adds `design-auditor` between implementer and validator.

**"I want to audit a PR's design without re-running the loop."**
→ `/design-audit <PR-number> .ai-docs/design/<slug>/spec.md`. Audit-only; posts findings; no fixes dispatched.
