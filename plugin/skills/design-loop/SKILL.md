---
name: design-loop
description: Run a structured design pass on a UI surface — spec → implement → audit (browser-pilot + design-auditor) → fix → validate, one phase at a time with a configurable termination strategy. Use when the user invokes `/design-loop` on a design spec, runs a design pass on a feature, or kicks off a UI epic with locked decisions. Composes into `/develop` for single-phase work when an issue carries `needs:design`.
disable-model-invocation: true
argument-hint: "[spec-path] [--strategy=<user-gate|max-loops|critic-evaluated>] [--max-loops=N] [--phase=N]"
arguments: [spec_path, strategy, max_loops, phase]
allowed-tools: Bash(git *) Bash(gh *) Bash(curl *) Read Write Edit Glob Grep Agent

# === Project SDLC overlay ===
status: beta
topology: [design-loop]
consumes: [design-spec]
produces: [commits, audit-comments]
gates:
  enforces: []
  sets: []
---

# Design Loop

Greenfield design loop. Drives a UI epic from spec to merged code, one phase at a time, with structured audit + configurable termination per phase.

For audit-only workflow on shipped code, see [`/design-audit`](../design-audit/SKILL.md) instead. For composing this into a tracker-issue workflow, see [Composed mode](#composed-mode) below.

## Spec contract

The spec must conform to the [`design-spec` canvas](../../canvases/design-spec/README.md). The canvas IS the contract — section structure, `spec_format_version`, locked-decisions rules, atom-contract rules, themes, universal AC. Read it once at the start of the loop to know what to enforce. Do NOT inline its contents.

Resolution chain for the canvas:

1. Project: `.claude/canvases/design-spec/instructions.yaml`
2. Plugin: `${CLAUDE_PLUGIN_DIR}/canvases/design-spec/instructions.yaml`

## Prerequisites

Before running, verify these are present. If any is missing, stop and tell the user with a one-line fix hint.

- `git` and `gh` CLI available (`gh auth status` exits 0).
- `image-posting` primitive's `verify-prereqs` op returns `ok: true`. For the `gh` adapter, this includes `~/.config/gh-attach/session.json` and Playwright resolvable.
- `browser-pilot` agent present (`ls ${CLAUDE_PLUGIN_DIR}/agents/browser-pilot.md` OR `.claude/agents/browser-pilot.md`).
- Three design-loop agents present:
  - `design-specifier`
  - `design-implementer`
  - `design-auditor`
- A generic `validator` agent (already shipped with the SDLC plugin) for the validation gate.
- Dev server running for the project under audit (the loop verifies `/_showcase` returns HTTP 200 in step 5).

Path resolution: agents and skills are found via Claude Code's standard plugin overlay — project's `.claude/agents/` overrides `${CLAUDE_PLUGIN_DIR}/agents/`.

## Inputs

| Arg | Required | Default | Meaning |
|---|---|---|---|
| `spec_path` | yes | — | Path to a design spec markdown file. Must conform to the `design-spec` canvas. |
| `--strategy` | no | `user-gate` | Termination strategy: `user-gate` / `max-loops` / `critic-evaluated`. See [Termination strategies](#termination-strategies). |
| `--max-loops` | no | `3` | Hard cap on audit→fix rounds per phase, regardless of strategy. Mirrors `validator_max_iterations` in `sdlc.yml`. |
| `--phase` | no | _resume_ | Run a specific phase number. Default: resume at the next un-passed phase (or phase 1 if first run). |

Strategy default and max-loops default may be set project-wide via `sdlc.yml.design_loop.termination_strategy` and `sdlc.yml.design_loop.max_loops` (v1.1 — for now, defaults are hardcoded here and per-invocation flags override).

## Termination strategies

The loop runs until one of these fires. `max-loops` is always the hard upper bound regardless of which strategy is named:

| Strategy | Termination condition | Use case |
|---|---|---|
| `user-gate` (default) | After each phase passes validation, halt and wait for user resume | Novel work; highest control; matches the source's invariant. |
| `max-loops` | `--max-loops` audit→fix rounds exhausted, then halt regardless of verdict | Time-boxed exploration; final round emits whatever state exists. |
| `critic-evaluated` | `design-auditor` returns `READY` (no `Definitely broken` findings) → proceed automatically to next phase | Highest automation; agent decides. Still halts on `BLOCKED` and on `--max-loops` exhaustion. |

Per Open Q #6 of the [design-loop port proposal](../../../.ai-docs/proposals/design-loop-port.md): under `critic-evaluated`, the critic IS `design-auditor`. There is no separate `lens=design` reviewer in v1.

## Choreography

For each phase from `--phase` (or 1) through the last phase in the spec:

### 1. Spec gate

Spawn `design-specifier` agent with `spec_path` + `phase_number`. The specifier reads the canvas, verifies the spec conforms.

- If specifier returns `GAPS`: surface them to the user. Stop. Do not proceed.
- If specifier returns `READY`: continue.

### 2. Implement

Spawn `design-implementer` agent in phase mode with `spec_path` + `phase_number`. The implementer:
- Adds tokens to theme files
- Creates the atoms enumerated in the spec (TS interfaces verbatim)
- Adds entries to the `/_showcase` route
- Self-runs gates (typecheck, lint, console errors)
- Commits with phase number in the message
- Returns commit hash + showcase route URL + report

### 3. Audit (round 1)

Spawn `design-auditor` agent (`context: fork`). Pass:
- `spec_path`
- `phase_number`
- `commit_sha` from the implementer
- `showcase_url`
- `themes` (declared themes from the spec)
- `target` — PR number (if one exists yet) or `null` (print mode)

The auditor uses `browser-pilot` for screenshots and the `image-posting` primitive for posting findings.

### 4. Fix-loop

Track `round = 1`.

- `auditor.verdict == READY` → proceed to step 5 (validate).
- `auditor.verdict == FIXES` → dispatch `design-implementer` in fix mode with the findings list. Implementer commits a single fix commit. Increment `round`. Go back to step 3.
- `auditor.verdict == BLOCKED` → surface to user and stop.

Cap: `round > --max-loops` halts the fix-loop regardless of verdict. Surface a final status to the user.

### 5. Validate

Spawn the generic `validator` agent (already provided by the SDLC plugin). Quality-gate matrix uses the project's [quality primitive](../../primitives/quality/README.md) plus design-loop additions:
- Standard quality gates (typecheck, lint, tests per `quality_profile`)
- `/_showcase` route returns HTTP 200 under each declared theme
- 0 console errors on showcase route under each theme
- Working tree clean (no probe scripts left behind)
- Commit hygiene: phase number in commit message; only files declared in phase deliverables touched

`validator.verdict == PASS` → proceed to step 6.
`validator.verdict == FAIL` → surface to user and stop.

### 6. Phase summary + termination check

Post a phase summary as a comment via the `image-posting` primitive (target: PR if one exists; else print):
- Files changed (tree)
- Atoms shipped
- Audit findings resolved (count + summary of last round)
- Validator gate matrix
- Screenshot grid (all themes; embedded via the primitive)
- Next phase preview (name + atom count) — if any

Then apply the termination strategy:

- `user-gate` → **always halt** at phase boundary. User must invoke `/design-loop $spec_path` again to proceed (the loop resumes at the next phase automatically; pass `--phase=N` to override).
- `critic-evaluated` → if the last audit returned `READY` with no escalations, continue automatically to the next phase. Otherwise halt.
- `max-loops` → continue if loops remain in budget for the next phase. Otherwise halt.

If this was the last phase, post a final summary and stop. Epic complete.

## Composed mode

When invoked indirectly via `/develop` for an issue carrying `needs:design`, the loop runs as a **single-phase** dispatch:

- The issue's spec (in `.ai-docs/stacks/<slug>/specs/<key>.md`) references a parent design-spec at `.ai-docs/design/<slug>/spec.md`. The reference is by relative path in the spec's `related:` frontmatter.
- `/develop`'s team picks up `design-auditor` (and optionally `design-implementer`) as `needs:design` extras alongside the standard `implementer` + `validator`.
- The loop's choreography collapses to: implementer (already running) → audit → fix-loop → validator (already running).
- The "phase boundary user-gate" is replaced by the standard Gate 2/2.5/3 SDLC flow — the PR-review and validator-pass gates carry the user-gate role.

In composed mode, only step 3 (audit) and step 4 (fix-loop) of this skill's choreography fire. Steps 1, 2, 5, 6 are handled by `/develop`.

## Stopping conditions

The loop stops (does not auto-continue) on:

- Spec gate `GAPS`
- Auditor `BLOCKED`
- Validator `FAIL`
- `--max-loops` exhaustion within a phase
- End of phase under `user-gate` strategy (always)
- End of last phase (epic complete)

## Reporting

At every stop, surface to the caller:

- Where in the choreography you are (`phase N, step M, round R`)
- What the agent returned (verdict + envelope)
- What the user can do to resume (which command, which flag)

Never auto-resume across `user-gate` boundaries. Never skip the audit. Never accept `READY-WITH-FIXES` from the auditor — only `READY`, `FIXES`, or `BLOCKED`.

## Worked example

For a complete trace of this loop run on a real epic (sales-patterns-ts issue #47 — the originating use case), see [`examples/issue-47.md`](./examples/issue-47.md).

## Related

- [`design-spec` canvas](../../canvases/design-spec/README.md) — the contract
- [`image-posting` primitive](../../primitives/image-posting/README.md) — how screenshots get attached
- [`design-specifier`](../../agents/design-specifier.md), [`design-implementer`](../../agents/design-implementer.md), [`design-auditor`](../../agents/design-auditor.md), [`browser-pilot`](../../agents/browser-pilot.md) — phase agents
- [`/design-audit`](../design-audit/SKILL.md) — audit-only entrypoint
- [`/develop`](../../commands/develop.md) — composed-mode entrypoint via `needs:design`
- [Design-loop port proposal](../../../.ai-docs/proposals/design-loop-port.md) — architectural decisions
- [Port handoff](../../../.ai-docs/handoffs/design-loop-port.md) — known gaps from the first port + resume instructions
