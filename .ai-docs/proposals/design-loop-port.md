---
status: draft-architecture
author: dug (with Claude)
date: 2026-05-16
related:
  - source: pattern-stack/sales-patterns-ts @ cad9e74 (branch feat/design-loop-skill, unmerged)
  - source-merged: pattern-stack/sales-patterns-ts PR #74 (docs+tooling: multi-pass-loop-runbook, gh-attach-image skill)
  - dogfood-conversation: 2026-05-16 review session
---

# Port: `design-loop` into the SDLC plugin

## Context

A `/design-loop` + `/design-audit` skill package was extracted from a real UI epic in `sales-patterns-ts` (issue #47, vocabulary refactor). It lives on an unmerged branch there. This proposal captures the architecture for porting it into the SDLC plugin (`claudecode-patterns/plugin/`) so all consumers inherit it.

### What the source ships

Eight files on `feat/design-loop-skill`:

- `skills/design-loop/SKILL.md` — greenfield orchestrator. Drives a UI epic phase-by-phase: spec gate → implement → audit → fix-loop ≤3 → validate → user-gate. Stops at every phase boundary.
- `skills/design-audit/SKILL.md` — audit-only projection. Grades a shipped PR/branch, posts findings + screenshots.
- `skills/_design-shared/spec-format.md` — versioned canonical spec contract (`spec_format: 1`). Both skills inline it via `!`cat ${CLAUDE_SKILL_DIR}/../_design-shared/spec-format.md``.
- `agents/design-specifier.md` — verifies a spec follows the contract; returns `READY` / `GAPS`.
- `agents/design-implementer.md` — ships one phase or applies a numbered fix list.
- `agents/design-auditor.md` — drives `browser-pilot` to screenshot per declared theme; grades against locked decisions + AC + theme-swap + WCAG-AA contrast; returns `READY` / `FIXES` / `BLOCKED`.
- `skills/design-loop/examples/issue-47.md` — worked trace from the source epic.
- `skills/design-loop/HANDOFF.md` — deferred items (smoke fixture, dry-run mode, browser-pilot portability).

Key invariants in the source: locked decisions are binding (auditor grades verbatim), AC must be falsifiable, atom contracts include TS interfaces, theme-swap is universal AC, mandatory user-gate per phase, 3-round fix-cap.

Dependencies the source assumes: `browser-pilot` (Anthropic-managed), `gh-attach-image` (project-local skill), generic `validator` agent.

## Goal

Adopt the discipline (versioned contract, falsifiable AC, visual audit) without forking SDLC into two parallel workflows. The port is **canvas-adapted, plugin-resident, gate-composable**.

## Locked decisions

_(Decisions reached in the 2026-05-16 dogfood-review conversation. Future agents grade against these verbatim.)_


1. **Spec contract becomes a canvas.** `_design-shared/spec-format.md` → `plugin/canvases/design-spec/{template.md, instructions.yaml, instructions.schema.json, README.md}`. Skills and agents read the canvas; no shell-injected flat-file contract.
2. **Plugin-resident, not per-project.** Lands in `claudecode-patterns/plugin/`. All SDLC consumers inherit; per-project override via standard `.claude/canvases/design-spec/` overlay.
3. **`browser-pilot` ships with the skill.** Vendored into `plugin/agents/browser-pilot.md`. Not a runtime prereq the consumer has to wire up.
4. **Image posting is a new primitive type.** Sibling to `task-management/`. Configurable in `sdlc.yml`. Values: `gh`, `linear-comment` (future), `local-folder` (future). May be 1:1 with the tracker or standalone.
5. **One parametrized loop, three termination strategies.** Not two skills. The loop runs until: (a) `max-loops` exhausted, (b) `user-gate` fires at phase boundary, or (c) `critic-evaluated` verdict passes. Composable into `/develop` (`needs:design`) AND runnable standalone via `/design-loop`.

## Architecture

### Component map

```
plugin/
├── canvases/
│   └── design-spec/                    # NEW
│       ├── template.md
│       ├── instructions.yaml
│       ├── instructions.schema.json
│       └── README.md
├── primitives/
│   └── image-posting/                  # NEW primitive type
│       ├── README.md
│       ├── gh.md                       # gh-attach-image vendored as a primitive value
│       └── (linear-comment.md, local-folder.md — deferred)
├── skills/
│   ├── design-loop/                    # NEW (user-invocable)
│   │   ├── SKILL.md
│   │   └── examples/issue-47.md
│   └── design-audit/                   # NEW (user-invocable)
│       └── SKILL.md
.ai-docs/
└── handoffs/
    └── design-loop-port.md             # NEW — port-status doc (was inadvertently inside skill dir on first port; moved here)
├── agents/
│   ├── design-specifier.md             # NEW
│   ├── design-implementer.md           # NEW
│   ├── design-auditor.md               # NEW
│   └── browser-pilot.md                # NEW (vendored, ships with plugin)
├── scripts/
│   └── gh-attach-image.mjs             # NEW (consumed by primitives/image-posting/gh.md)
└── sdlc.example.yml                    # MODIFIED — add image_posting key + design-loop knobs
```

### Hybrid loop model

`/design-loop` accepts a termination strategy (declared per-spec or per-invocation, default from `sdlc.yml`):

| Strategy | Termination condition | Use case |
|---|---|---|
| `max-loops` | N audit→fix rounds, then halt regardless of verdict | Time-boxed exploration; final round emits whatever state exists |
| `user-gate` | After each phase, halt and wait for user resume | Default. Matches the source's invariant. Highest control. |
| `critic-evaluated` | Reviewer (lens=design) returns PASS or PASS_WITH_NOTES | Highest automation; agent decides when to stop |

The strategies are not mutually exclusive — `max-loops` always acts as a hard upper bound regardless of the other two. The default config is `user-gate` with `max-loops: 3` as a safety.

**Composable into `/develop`.** When an issue carries `needs:design`, `/develop` adds the `design-auditor` agent (and optionally `design-implementer` if the issue is design-led) to its Topology A team. The auditor runs after the implementer's commit, before the validator. Its verdict participates in Gate 2.5 alongside the standard adherence + quality lenses.

**Standalone via `/design-loop`.** Runs the full multi-phase cadence end-to-end against a spec. Not tied to a tracker issue (the spec is the source of truth). Emits its own session artifact under `.ai-docs/design-loop-sessions/<slug>/`.

### Image-posting primitive

Sibling to `task-management/`. Read by any agent that wants to attach an image to a comment surface — today, `design-auditor`; tomorrow, possibly `validator` (visual regression reports).

`sdlc.yml` shape:

```yaml
task_management: github
image_posting: gh           # gh | linear-comment | local-folder
```

Resolution: `plugin/primitives/image-posting/<value>.md` (override-able via project's `.claude/primitives/image-posting/<value>.md`).

The `gh` value wraps `scripts/gh-attach-image.mjs`. The `local-folder` value writes to `.ai-docs/audit-images/<session>/` and prints paths instead of posting. Default value: matches `task_management` when they align (github → gh), else `local-folder`.

**Open question:** does `image_posting` *replace* `validator_post_target` (currently in `sdlc.yml.modes.<mode>.validator_post_target: pr | tracker`)? They're related but not the same — `validator_post_target` chooses between PR and tracker; `image_posting` chooses how to attach images regardless of which surface. Probably they coexist for v1.

### `design-spec` canvas

Stands alone (does not extend `spec/`). Different producer (`design-specifier` verifies; humans author), different consumers (`design-implementer`, `design-auditor`), different lifecycle (multi-phase, locked decisions).

`template.md` outline:

```markdown
# {{surface_name}} — design spec

spec_format: {{version}}

## Locked decisions
{{locked_decisions}}

## Phases
{{phase_index}}

## Phase {{N}} — {{phase_name}}

### Deliverables
#### Tokens
{{tokens}}
#### Atoms
{{atoms_with_ts_interfaces}}
#### Showcase route
{{showcase_entries}}

### Acceptance criteria
{{falsifiable_ac_list}}

### Themes declared
{{themes}}
```

`instructions.yaml` knobs (sketch):

- `spec_format_version` — required; refuse mismatched specs
- `themes_minimum` — default 2; waive theme-swap AC if 1 declared
- `atom_contract.require_ts_interface` — default true
- `ac.universal` — list of universal AC (typecheck, lint, contrast, theme-swap, showcase-200)
- `locked_decisions.require_justification` — default true

### Agents

| Agent | Reads | Returns | Tools |
|---|---|---|---|
| `design-specifier` | `design-spec` canvas, spec file, phase number | `READY` / `GAPS` | Read, Glob, Grep |
| `design-implementer` | canvas, spec, phase or fix-list | commit hash + showcase URL | Read, Write, Edit, Bash, Glob, Grep |
| `design-auditor` | spec, phase, commit, showcase URL, themes | `READY` / `FIXES` / `BLOCKED` + findings | Read, Glob, Grep, Bash + `browser-pilot` subagent |
| `browser-pilot` (vendored) | URL, theme, viewport | screenshots | Bash + (Anthropic browser tooling if available, fallback otherwise) |

`design-specifier` is **not** a duplicate of `reviewer` lens=mixed at Gate 1.5. The roles are different: `reviewer` grades a *strategy spec* against cited code; `design-specifier` grades a *design spec* against the canvas contract. They could collapse into a shared discipline ("contract verifier with pluggable canvases") in v2 but that's premature.

### Integration with existing SDLC loop

**`skills/sdlc-loop/SKILL.md`** — add `/design-loop` to the loop diagram and to the command-selection table. Explain when to use `/design-loop` standalone vs. `needs:design` composed into `/develop`.

**`commands/develop.md`** — add `design-auditor` and `design-implementer` to the `needs:*` table (already lists `browser-pilot`, `tester`, `designer` as "when vendored" — these are now vendored).

**`commands/review.md`** — add `lens=design` as an option that spawns `design-auditor` instead of `reviewer`. This is the bridge between design-loop's audit and the standard `/review` Gate 2.5. Deferred to v1.5 — not required for first cut.

**`sdlc.example.yml`** — document `image_posting:` key, plus an optional `design_loop:` block with `termination_strategy: user-gate | max-loops | critic-evaluated`, `max_loops: 3`, `themes_required_minimum: 2`.

## Open questions

_(Tentative answers locked 2026-05-16 by Claude — **flagged for human confirmation before the port lands**. Code on `feat/design-loop-port` follows these defaults; flip any of them and the port adjusts.)_

1. **Termination strategy default at the plugin level.**
   **Tentative answer:** `user-gate` with `max-loops: 3` hard cap.
   **Rationale:** Matches the source's invariant; user-gate is the conservative default for novel work; max-loops at 3 mirrors `validator_max_iterations` + `spec_critic_max_iterations` already in `sdlc.yml`.

2. **Phase = SDLC issue, or intra-issue?**
   **Tentative answer:** Intra-issue when composed into `/develop` (a `needs:design` issue runs one design phase); multi-phase when standalone (`/design-loop` against a spec spans phases without tracker issues).
   **Rationale:** Preserves PR-sized-issue convention for tracker-integrated work, preserves source-loop cadence for greenfield UI epics. Documents the dual nature explicitly in `sdlc-loop` SKILL.md.

3. **Does `/design-loop` produce a spec at SDLC's `stack_spec` path?**
   **Tentative answer:** Separate path — `.ai-docs/design/<slug>/spec.md`. Add a new `design_spec` entry to `artifact_paths`.
   **Rationale:** Design specs predate any tracker issue and are referenced *by* issue specs (not the other way around). Conflating with `stack_spec` would force every design-loop run to have a tracker issue.

4. **`browser-pilot` portability.**
   **Tentative answer:** Vendor a Playwright-based implementation as the default. If Anthropic's managed browser tooling is detected at runtime, prefer it; else fall back to Playwright. Document Playwright as a hard dependency for design-audit; soft for design-loop (spec-only runs don't need a browser).
   **Rationale:** Anthropic-managed is convenient but not portable; Playwright is universal. The fallback gives us both.

5. **Image-posting vs. `validator_post_target`.**
   **Tentative answer:** Coexist for v1. `validator_post_target: pr | tracker` keeps choosing the surface; `image_posting: gh | local-folder` chooses *how* to attach images to whichever surface was chosen. Unify into a generic `output_target` primitive in v2 once `linear-comment` and `local-folder` values exist to pressure the design.
   **Rationale:** They solve different problems; collapsing now is premature. Document the eventual unification as a v2 deferred item.

6. **Critic-evaluated termination — which critic?**
   **Tentative answer:** `design-auditor` is the critic. Its verdict (`READY` / `FIXES` / `BLOCKED`) drives `critic-evaluated` termination. `/review --lens=design` (deferred to v1.5) becomes the Gate-2.5 facade over the same agent — same critic, different framing.
   **Rationale:** One critic, two entrypoints. Avoids a parallel `lens=design` reviewer-implementation in v1.

7. **Locked decisions: spec-level or phase-level?**
   **Tentative answer:** Spec-level only for v1. Phase-level locked decisions are a v2 extension if a real epic pressures them.
   **Rationale:** Source had spec-level only and it worked for issue #47. Adding phase-level adds canvas complexity without a forcing case.

8. **Acceptance criteria taxonomy in `instructions.yaml`.**
   **Tentative answer:** Hardcoded universal AC list (`typecheck`, `lint`, `contrast`, `theme-swap`, `showcase-200`) with `enabled: bool` toggle per item. Spec-declared AC are free-form.
   **Rationale:** Universal AC are the few non-negotiables; making them fully configurable invites accidental quality dropouts. Toggles give the escape hatch when an AC genuinely doesn't apply (e.g., `theme-swap` with one theme).

## Deferred

_(Post-v1. Captured here so the spec phase doesn't accidentally pull these in.)_


- **Smoke fixture** — `examples/smoke/` with a tiny spec + fixture surface so the package can be smoke-tested in a clean repo.
- **Dry-run mode** — `--dry-run` flag prints the phase plan without spawning agents.
- **`/review --lens=design`** — Gate 2.5 lens that spawns `design-auditor`. v1 keeps `/design-audit` as the standalone audit surface.
- **`linear-comment` + `local-folder` image-posting values** — v1 ships `gh` only.
- **Canvas-author support for `design-spec`** — the canvas-author dialog needs design-spec-specific question flows (locked decisions, themes, AC matrix).

## Next step

If this proposal lands as-is, the natural decomposition is a 5–6 issue stack:

1. `design-spec` canvas (template + instructions + schema + README)
2. `image-posting` primitive (README + `gh.md` value + `gh-attach-image.mjs` script)
3. `browser-pilot` agent (vendored)
4. `design-specifier` + `design-implementer` + `design-auditor` agents
5. `design-loop` + `design-audit` skills (canvas-aware)
6. Integration: `sdlc-loop` SKILL.md updates, `develop.md` teammate slot, `sdlc.example.yml`

Each issue is PR-sized. Stack via the standard `/plan` → `/sync-issues` flow once the open questions above are resolved.
