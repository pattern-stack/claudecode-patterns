# Design-reference artifact

The reference contract for `/design-loop` v2. One canvas, three reference types (`spec` / `figma` / `screenshot`). Replaces v1's `design-spec` canvas.

## When to use which type

| Type | When | Reference is |
|---|---|---|
| `spec` | UI epic with locked decisions, multi-phase, falsifiable checks. The original v1 use case. | A markdown spec (`reference.md`) — locked decisions, phases, atoms, checks. |
| `figma` | The design lives in Figma; you want the builder to read structural data and the grader to compare against the frame. | A single-line file (`reference.figma-url`) containing the Figma frame URL. |
| `screenshot` | "Make it look like this image." No structural intent encoded beyond what's visible. | An image file (`reference.png` / `.jpg`). |

A `design-reference` artifact lives at `.ai-docs/design/<surface-slug>/` with these conventions (overridable via `instructions.yaml.paths`):

```
.ai-docs/design/<surface-slug>/
├── reference.{md, figma-url, png, jpg}    # the source of truth (one file; type by extension)
├── surface.txt                            # one line: where to build (path or URL)
└── iterations/<N>/                        # per-round screenshots, written by the grader
```

## Producer / consumers

| Role | Who | What |
|---|---|---|
| Producer | Human author | Writes the reference. No agent for v2 — references are too varied to auto-author. |
| Consumer | `design-builder` | Reads reference (type-aware) to build or refine the surface. |
| Consumer | `design-grader` | Reads reference + surface evidence to grade. Validates the reference is well-formed before grading. |
| Consumer | `/design-loop`, `/design-audit` | Orchestrate; read the canvas to know the reference type's expectations. |

## How agents read each type

### spec

Builder reads the markdown spec. Honors `types.spec` knobs:
- `require_locked_decisions: true` — Reference body must contain a numbered "## Locked decisions" block; each item: assertion + justification.
- `require_atoms_with_ts_interfaces: true` — each atom in the spec has its TS interface verbatim.
- `require_falsifiable_checks: true` — each "## Checks" entry is gradable by typecheck / lint / runtime / visual diff.

Grader iterates the spec's checks + locked decisions; runs the check; accumulates findings. Per-check fail → `Definitely broken`.

### figma

Builder calls the `figma-dev-mode` MCP:
- `get_design_context` — component tree, layout structure
- `get_metadata` — style rules, applied tokens
- `get_variable_defs` — design tokens used in the frame

Builder synthesizes structure from MCP output, produces an implementation matching the frame.

Grader takes a build screenshot via `browser-pilot` + a reference screenshot via Figma `get_screenshot`. Compares: structural deltas from MCP metadata first (token mismatch, wrong layout primitive), then visual diff for things MCP doesn't surface. Per-mismatch → `Definitely broken` or `Visual polish` per severity.

### screenshot

Builder reads the image directly (multimodal). Visual intent only — no structural metadata.

Grader takes a build screenshot, compares to the reference image. LLM-judged visual delta only. Findings categorize as `Definitely broken` (obvious differences) or `Visual polish` (subjective).

## Verdicts

The grader always returns one of `READY` / `FIXES` / `BLOCKED`.

`BLOCKED` carries a sub-code per `grading.blocked_codes`:

| Universal | Spec | Figma | Screenshot |
|---|---|---|---|
| `internal_contradiction` | `missing_required_section`, `phase_jumping` | `figma_unreachable`, `frame_not_found`, `mcp_unavailable`, `unsupported_node_type` | `reference_image_missing`, `reference_image_unreadable` |

Each maps to a different user fix. The grader's verdict includes the sub-code; the loop surfaces it verbatim.

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Skeleton with `{{token}}` placeholders. Reference body is type-conditional — producer renders only the sections required by `types.<t>.required_sections`. |
| `instructions.yaml` | Three knob blocks: `types`, `grading`, `paths`. Plus a small `sections` block for verbosity. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Override

Edit `instructions.yaml` to tune. Project-local overrides at `.claude/canvases/design-reference/` override plugin defaults via Claude Code's standard overlay.

## Migration from v1's `design-spec` canvas

v1's `design-spec` canvas is replaced by this one. Specs that used the v1 contract become `reference_type: spec` artifacts in v2 with minor reshape:
- v1's `## Locked decisions` → v2's `## Reference` body (inside it: same `## Locked decisions` H3 block)
- v1's `## Phases` + per-phase `### Deliverables` / `### Acceptance criteria` → v2's `## Reference` body (phases as H3, checks as H3 under "## Checks")
- v1's `## Themes declared` → v2's `## Themes`
- v1's `spec_format: 1` frontmatter → v2's `reference_type: spec` frontmatter

The v2 canvas does not lock a `spec_format_version` — that role is filled by `instructions.yaml.version` (the canvas version itself, surfaced via canvas validation).

## Versioning

`instructions.yaml.version` increments on breaking changes. Marked `status: beta` until exercised end-to-end on a real reference of each type.

## Related

- [`/design-loop`](../../skills/design-loop/SKILL.md) — primary orchestrator
- [`/design-audit`](../../skills/design-audit/SKILL.md) — thin audit-only wrapper
- [`design-builder`](../../agents/design-builder.md), [`design-grader`](../../agents/design-grader.md) — phase agents
- [`browser-pilot`](../../agents/browser-pilot.md) — captures surface evidence
- [`image-posting` primitive](../../primitives/image-posting/README.md) — posts findings
- [v2 proposal](../../../.ai-docs/proposals/design-loop-v2.md) — architectural decisions
