# Design-spec artifact

A versioned, falsifiable contract for design-loop work. Ports the spec format from `pattern-stack/sales-patterns-ts` (`.claude/skills/_design-shared/spec-format.md` v1) into SDLC canvas form.

A design-spec captures: **locked decisions** (binding constraints the auditor grades verbatim), **themes declared** (the universe the auditor screenshots under), **phases** (each is one PR / one user-gate boundary), and per-phase **deliverables** (tokens / atoms with TS interfaces / showcase entries) + **acceptance criteria** (universal + spec-declared).

## When to use

A design-spec exists when a UI surface needs `/design-loop` or `/design-audit` to run against it — i.e., when the work is visual, multi-phase, and the audit step (screenshot-driven grading under each theme) earns its keep.

A design-spec does NOT replace the per-issue `spec/` canvas. They coexist:

- **`design-spec`** is the UI contract — what gets built, in what order, under what themes, against what locked decisions.
- **`spec/`** is the per-issue implementation strategy — wired into Gates 1.5 / 2.5 / 3 in the standard SDLC loop.

When a `needs:design` issue runs through `/develop` in composed mode, both canvases participate: the issue's `spec/` references the parent `design-spec`'s relevant phase.

## Producer

Either:

- **Human author** — writes the design-spec directly (the canonical case; design specs predate any tracker issue).
- **`design-specifier` agent** (when shipped) — verifies an authored spec conforms to this canvas; returns `READY` / `GAPS`. Does not author from scratch.

## Consumers

- **`design-implementer`** — reads the canvas + spec; ships one phase or applies a fix list. Atom contracts must include TS interfaces (per `atom_contract.require_ts_interface`); implementer does not invent atoms.
- **`design-auditor`** — reads the canvas + spec + a head commit; drives `browser-pilot` to screenshot per theme; grades against `locked decisions` (verbatim) + universal AC + spec-declared AC. Returns `READY` / `FIXES` / `BLOCKED`.
- **`/design-loop` skill** — orchestrates the per-phase cadence using the canvas to validate the spec before each phase.
- **`/design-audit` skill** — runs the auditor against a shipped surface; same canvas, no implement step.

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Pure structural skeleton with `{{token}}` placeholders + scaffolded phase block. Renaming a section means editing this file *and* `instructions.yaml`. |
| `instructions.yaml` | Tunable knobs — section order, required sections, `spec_format_version`, `locked_decisions`, `atom_contract`, `themes`, `universal_ac`, `phase_mode`, authoring rules. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Output path

Per project convention (v1 — to be codified in `sdlc.yml` `artifact_paths.design_spec` once the port wires it):

```
.ai-docs/design/<surface-slug>/spec.md
```

Rationale (locked decision from the design-loop port proposal Open Q #3): design specs predate tracker issues; they get referenced *by* issue specs, not the other way around. Keeping them out of `.ai-docs/stacks/<slug>/specs/` preserves that.

## How agents (or humans) use these files

**Producer:**
1. Read `template.md` and `instructions.yaml`.
2. Validate `instructions.yaml` against `instructions.schema.json` (halt on validation error).
3. Set frontmatter `spec_format: <instructions.yaml.spec_format_version>`. Any consumer reading a spec with a different value refuses with: *"Spec format version mismatch: spec is vN, package is v1."*
4. Fill template tokens honoring the contract:
   - `Locked decisions`: numbered list, each item is assertion + justification per `locked_decisions.require_justification`. No "TBD". Minimum count per `locked_decisions.minimum`.
   - `Themes declared`: at least `themes.minimum`. If only 1 declared, the `theme_swap` universal AC is auto-disabled by the consumer (the auditor still notes the waiver in its report).
   - `Phases`: index at the top of the doc; one `## Phase N — name` block per phase below.
   - For each phase: `Tokens`, `Atoms` (with TS interfaces verbatim), `Showcase route` entries.
   - `#### Universal AC`: render every enabled item from `universal_ac` verbatim; mark the disabled ones with `(waived: <reason>)`.
   - `#### Spec-declared AC`: free-form, but each must be falsifiable (gradable by typecheck, lint, runtime, or visual diff).

**Consumer (design-specifier verifies):**
1. Read the spec at the resolved path.
2. Validate `spec_format` frontmatter matches `instructions.yaml.spec_format_version`. Halt on mismatch.
3. Validate `Locked decisions`, `Themes declared`, `Phases` non-empty (per `sections.required`).
4. For the phase being prepared, validate `Deliverables` (with required subsections Tokens / Atoms / Showcase route) and `Acceptance criteria` (universal + spec-declared) are non-empty.
5. Validate atom contracts include TS interfaces (per `atom_contract.require_ts_interface`).
6. Validate no phase-jumping (`authoring_rules.no_phase_jumping`).
7. Return `READY` or `GAPS` with findings.

**Consumer (design-implementer reads):**
1. Read the spec at the resolved path.
2. Locate the phase by number; read `Deliverables` and `Acceptance criteria`.
3. Add tokens, atoms (using TS interfaces verbatim), and showcase entries.
4. Atoms MUST use CSS variables only — no hex/rgb/font-family literals. Exception: data-density numerics (e.g., `11.5px` for mono grids). Flag the exception in the implementer report.
5. Commit with phase number in the message.

**Consumer (design-auditor reads):**
1. Read the spec at the resolved path.
2. Verify build at the passed commit SHA; check showcase route returns HTTP 200.
3. Capture screenshots per declared theme via `browser-pilot`.
4. Grade against `Locked decisions` (verbatim — any violation is `definitely broken`).
5. Grade against the phase's `#### Universal AC` (only enabled items) and `#### Spec-declared AC`.
6. Return `READY` / `FIXES` / `BLOCKED` with numbered findings (each: file:line + screenshot + recommended fix).

## Knob reference

| Knob | Allowed values | Purpose |
|---|---|---|
| `spec_format_version` | int | Version refused by consumers if spec frontmatter mismatches. Increment on breaking changes. |
| `locked_decisions.numbered` | bool | Numbered list for stable references. |
| `locked_decisions.minimum` | int | Producer halts if fewer locked decisions. Default 1. |
| `locked_decisions.require_justification` | bool | Each decision must include "Justification: ..." rationale. |
| `atom_contract.require_ts_interface` | bool | Each atom's contract MUST include its TS interface verbatim. |
| `atom_contract.require_behavior_note` | bool | 3-line max behavior note. |
| `atom_contract.require_file_path` | bool | Atom file path declared in the contract. |
| `themes.minimum` | int | At least N themes declared. |
| `themes.theme_swap_required_when_count_gte` | int | When themes count ≥ N, theme-swap AC mandatory. |
| `universal_ac[]` | array of {id, enabled, statement} | The non-negotiable AC inherited by every phase. Toggle `enabled` for AC that genuinely doesn't apply. |
| `phase_mode.default` | `standalone` / `composed` | Default orchestration: `/design-loop` runs all phases (standalone), or `/develop` runs one phase per `needs:design` issue (composed). |
| `phase_mode.allow_composed` | bool | Whether composed-mode dispatch via `/develop` is permitted. |
| `authoring_rules.no_phase_jumping` | bool | Phase N may not reference Phase N+1 atoms/tokens. |
| `authoring_rules.one_pr_per_phase` | bool | Phase boundaries are PR boundaries. |
| `authoring_rules.locked_decisions_are_binding` | bool | Auditor grades verbatim; re-opening = new spec. |
| `citations.file_paths` | `required` / `optional` / `none` | File-path rigor for code refs in the spec. v1 default `required`. |

## Override

Edit `instructions.yaml` to tune behavior. Edit `template.md` to change structure (section names, ordering, frontmatter shape).

When this project ships as a plugin, plugin defaults are overridden by project-local `.claude/canvases/design-spec/` files via Claude Code's standard plugin overlay.

## Versioning

Two version axes:

1. `instructions.yaml.version` — canvas version (renamed knobs, changed enums). Producers/consumers fail loudly on unknown versions.
2. `instructions.yaml.spec_format_version` — **spec contract** version. Specs declare this in their frontmatter; consumers refuse mismatches. Bumping the spec format is a breaking change for every existing design-spec.

- **canvas v1 / spec_format v1:** ports sales-patterns-ts spec-format v1. Includes locked decisions / themes / phases / per-phase deliverables (tokens/atoms/showcase) / per-phase AC (universal + spec-declared). Marked `status: beta`.

## Out of scope for v1

- **Phase-level locked decisions.** v1 has spec-level only. Per Open Q #7 in the port proposal, phase-level is a v2 extension if a real epic pressures it.
- **Animation / motion specs** beyond keyframe declarations in tokens.
- **Cross-browser AC.** Auditor runs in Chromium only.
- **Accessibility beyond WCAG AA contrast.** Keyboard nav, ARIA, etc. are organism-level concerns.
- **Performance budgets.**

These are documented as non-goals so the auditor doesn't surface them as findings.

## Related

- [`spec/`](../spec/README.md) — per-issue implementation strategy. Coexists with this canvas.
- [`/design-loop`](../../skills/design-loop/SKILL.md) — orchestrator (when shipped).
- [`/design-audit`](../../skills/design-audit/SKILL.md) — audit-only entrypoint (when shipped).
- [`design-specifier`](../../agents/design-specifier.md), [`design-implementer`](../../agents/design-implementer.md), [`design-auditor`](../../agents/design-auditor.md) — phase agents (when shipped).
- [Design-loop port proposal](../../../.ai-docs/proposals/design-loop-port.md) — the architectural decisions behind this canvas.
