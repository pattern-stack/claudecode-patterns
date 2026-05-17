# Proposal artifact

A hybrid ADR + RFC artifact: captures locked decisions (ADR-style) and open questions (RFC-style) about an architectural change before any spec phase begins. Pre-spec, pre-plan — sits upstream of `/plan` and feeds it.

v1 is **deliberately minimal and tuned to the `design-loop` port shape.** Future proposals may want stricter alternatives-considered blocks or separate ADR-only / RFC-only canvases; those are out of scope for v1 (see § Versioning).

## When to use

A proposal exists when:

1. The change touches multiple parts of the SDLC plugin and a one-issue spec is too small.
2. There are decisions to lock and questions to resolve before a stack of issues can be planned.
3. The work is large enough that an implementer would otherwise have to re-make architectural calls mid-flight.

A proposal does NOT exist for:

- Per-issue strategy — that's `spec/`.
- Plan-level decomposition into PR-sized issues — that's `plan/`.
- Single-decision capture with explicit alternatives — author a standalone ADR by hand for now; this canvas may grow ADR-mode in v2.

## Producer

Either:

- **Human author** — writes directly (this canvas's first real use was hand-authored).
- **`sdlc-author` agent** (`plugin/agents/sdlc-author.md`) — context-isolated SDLC-aware writer for spec-like artifacts. The agent description names ADRs / RFCs / ad-hoc design docs as in-scope; this canvas gives it the shape to render against.

## Consumers

- **The human reviewer** — reads to react, flag, lock, or reject.
- **`planner` agent** (downstream) — once the proposal is `accepted`, the planner reads `Locked decisions` + `Architecture` to decompose into PR-sized issues. The proposal's `Next step` section often sketches this decomposition.
- **`specifier` agent** (further downstream) — references the proposal for context when writing per-issue specs.

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Pure structural skeleton with `{{token}}` placeholders. Renaming a section means editing this file *and* `instructions.yaml`. |
| `instructions.yaml` | Tunable knobs — section order, required sections, verbosity, status lifecycle, locked-decisions / open-questions knobs, diagram tool. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Output path

Per project convention (not yet codified in `sdlc.yml` `artifact_paths` — v2 candidate):

```
.ai-docs/proposals/<slug>.md
```

The slug is short-kebab-case naming the change (e.g., `design-loop-port`).

## How agents (or humans) use these files

**Producer:**
1. Read `template.md` and `instructions.yaml`.
2. Validate `instructions.yaml` against `instructions.schema.json` (halt on validation error).
3. Fill the template tokens, honoring:
   - Section order from `sections.order`.
   - Verbosity hints per section from `sections.verbosity`.
   - Locked-decisions formatting from `locked_decisions.*` (numbered list, justification one-liner if `justification_required`).
   - Open-questions minimum from `open_questions.minimum` (default 1 — a proposal with zero open questions is probably a spec).
   - Diagrams in eligible sections per `diagrams.in_sections`.
4. Set frontmatter `status` to `status_lifecycle.initial` (default `draft-architecture`).

**Consumer:**
1. Read the proposal at `.ai-docs/proposals/<slug>.md`.
2. Read `instructions.yaml.sections.required` to know which sections must be non-empty.
3. Halt with the missing-section name if any required section is empty or still contains a `{{token}}` placeholder.
4. Trust frontmatter `status` for lifecycle position — only `accepted` proposals should feed `/plan`.

## Knob reference

| Knob | Allowed values | Purpose |
|---|---|---|
| `status_lifecycle.values` | array | Allowed values for frontmatter `status:`. Default: draft-architecture → under-review → accepted → superseded / rejected. |
| `status_lifecycle.initial` | string | Initial status when producer creates the doc. |
| `locked_decisions.numbered` | bool | Numbered list for stable references in later docs. |
| `locked_decisions.justification_required` | bool | Each decision must include a one-line rationale. v1 default false; tighten later. |
| `locked_decisions.minimum` | int | Producer halts if fewer than N decisions locked. |
| `open_questions.numbered` | bool | Numbered list. |
| `open_questions.minimum` | int | Producer halts if fewer than N questions. Default 1 — a proposal with zero open questions is a spec. |
| `architecture.subsections_allowed` | bool | Whether the Architecture section may contain H3s. |
| `architecture.prefer_tables_over_prose` | bool | Bias producer toward tabular comparisons (component maps, knob refs, etc.). |
| `diagrams.tool` | `mermaid` / `excalidraw` / `none` | Diagram tool for eligible sections. |
| `diagrams.in_sections` | array of strings | Sections where diagrams are encouraged. |
| `citations.file_paths` | `required` / `optional` / `none` | File-path rigor. Proposals are looser than specs — v1 default `optional`. |
| `citations.line_numbers` | bool | Whether file refs should include line numbers. v1 default false. |
| `related.shape` | `list_of_objects` / `list_of_strings` | Frontmatter `related:` array shape. v1 default `list_of_objects` with `{source,spec,supersedes,conversation}` keys. |

## Override

Edit `instructions.yaml` to tune behavior. Edit `template.md` to change structure (section names, ordering, frontmatter shape).

When this project ships as a plugin, plugin defaults are overridden by project-local `.claude/canvases/proposal/` files via Claude Code's standard plugin overlay.

## Validation

Run `bash scripts/verify-canvases.sh` (when implemented) — validates each `instructions.yaml` against its schema. Pre-commit / CI hook candidate.

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed knobs, changed enum values). Producers and consumers fail loudly on unknown versions rather than degrade silently.

- **v1:** initial shape — Context / Goal / Locked decisions / Architecture / Open questions / Deferred / Next step. Tuned to the design-loop port; deliberately minimal. Future ADR / RFC ambitions deferred — author standalone docs by hand or extend this canvas with new modes once a second proposal pressures the design.

## Out of scope for v1

- **Strict-ADR mode** with required "Alternatives Considered" + "Consequences" sections. Author by hand if needed; promote to a canvas mode if multiple proposals call for it.
- **RFC public-comment lifecycle** — Last Call windows, decision quorums, etc. Premature; the producer-reviewer loop for now is the lead session + the originator.
- **Sectioned templating** beyond H2 — no per-subsection token map yet.
- **Resolution tracking on Open questions** — `resolution_tracked: false` until v2; for now, questions get answered in conversation and the proposal is edited.
