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
| UI work against a reference (spec / figma / screenshot) | `/design-loop --reference=<path>` | Iterative refinement loop. Standalone (no tracker issue required). Three termination strategies. |
| Audit a built UI surface against a reference | `/design-audit --reference=<path> --target=<PR>` | One grader pass; posts findings; no fixes dispatched. |
| Per-issue design audit composed into `/develop` | Label issue `needs:design` + run `/develop <KEY>` | Composed-mode (spec references only for v2). Grader slots between implementer and validator. |

## /develop vs /orchestrate

| Question | If yes → /develop | If yes → /orchestrate |
|---|---|---|
| Will I be at the keyboard for each step? | ✓ | — |
| Do I need UI verification (`needs:browser-pilot`, `needs:designer`, `needs:design`)? | ✓ — Topology B forbids these | — |
| Does the issue need data/log validation per step (`needs:tester`)? | ✓ | — |
| Are there many independent issues to grind through? | — | ✓ |
| Am I OK with halts surfacing only in coordinator reports? | — | ✓ |

If an issue carries any `needs:*` label that maps to a Topology-A agent (`browser-pilot`, `designer`, `design-grader`, `tester`), `/orchestrate` will drop it automatically and recommend `/develop`. Don't try to override — these agents exist for split-pane co-presence and don't run headless.

## /develop (composed-design mode) vs /design-loop (standalone)

When the design work is one PR-sized phase against a **spec** reference, label the issue `needs:design` and run `/develop <KEY>` — `design-grader` slots between the implementer's commit and the validator's run. Standard SDLC gates (1.5 / 2 / 2.5 / 3) carry the user-gate role.

For figma/screenshot references, or multi-phase spec work, use `/design-loop --reference=<path>` standalone. v2 supports composed mode only for spec references — figma/screenshot composed mode is deferred.

Both modes share agents (`design-builder` + `design-grader` + `browser-pilot`), the `design-reference` canvas, and the `image-posting` primitive. See [`/design-loop` SKILL.md § Composed mode](../design-loop/SKILL.md#composed-mode-develop-with-needsdesign).

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

**"I'm starting a UI epic from scratch with locked decisions across multiple phases."**
→ Author a spec at `.ai-docs/design/<slug>/reference.md`. Run `/design-loop --reference=.ai-docs/design/<slug>/reference.md`.

**"The designer handed me a Figma frame. I want to build it and iterate."**
→ Save the frame URL to `.ai-docs/design/<slug>/reference.figma-url`. Run `/design-loop --reference=.ai-docs/design/<slug>/reference.figma-url`.

**"I have a screenshot of what I want it to look like."**
→ Drop the image at `.ai-docs/design/<slug>/reference.png`. Run `/design-loop --reference=.ai-docs/design/<slug>/reference.png`.

**"I want to audit a teammate's PR for design quality."**
→ `/design-audit --reference=.ai-docs/design/<slug>/reference.* --target=<PR-number>`.

**"ABC-105 refines a parent design spec. I want the grader in the loop."**
→ Add `needs:design` label. Run `/develop ABC-105`. Composed mode adds `design-grader` between implementer and validator.
