---
status: draft-architecture
author: dug (with Claude)
date: 2026-05-17
related:
  - supersedes: .ai-docs/proposals/design-loop-port.md (v1 — PR #88, on hold)
  - source: pattern-stack/sales-patterns-ts @ cad9e74 (originating package)
  - conversation: 2026-05-17 v2 discussion
---

# Design-loop v2 — reference-driven iteration

## Context

PR #88 lands a v1 design-loop port — strict, spec-only, three agents, two skills, verbose. It works, but it overspecifies for the actual goal: an iterative refinement loop where an agent builds, a reviewer screenshots and grades, the builder fixes, the reviewer rechecks.

The "spec" form is one valid input among several. Real refinement work also runs against Figma frames and reference screenshots. v2 generalizes the loop to **three reference types** sharing one engine, and trims the v1 verbosity along the way.

PR #88 is held unmerged pending this redesign. The foundations (`image-posting` primitive, `gh-attach-image.mjs` script, `browser-pilot` agent, `proposal` canvas) carry over unchanged; the v1 contract layer (canvas + 3 agents + 2 skills) is replaced.

## Goal

One iteration loop. Three reference types: **spec / figma / screenshot**. One canvas with a `reference_type:` discriminator. Two agents (builder + grader). One core skill + one thin audit shortcut. ~50% less prose than v1.

## Locked decisions

1. **Three reference types: spec / figma / screenshot.** Prose / no-reference / multi-reference deferred. Justification: covers the named real cases (issue #47 pattern, Figma-driven UI, "match this screenshot"); other types defer until a real use case forces them.
2. **One canvas: `design-reference`** with `reference_type:` frontmatter discriminator. Type-specific section requirements via `instructions.yaml.types.<type>`. Replaces v1's `design-spec` canvas. Justification: shared structure between types is large; per-type canvases would mostly duplicate.
3. **Two agents: `design-builder` + `design-grader`.** v1's `design-specifier` is dropped — the grader does its own pre-grade reference validation. Justification: spec-format verification is one small step; doesn't need a dedicated agent.
4. **One skill of substance: `/design-loop` with `--mode=audit` option. `/design-audit` is a thin wrapper.** Justification: avoids two SKILL.md files duplicating prereqs / agent invocation / reporting format; menu discoverability preserved via the wrapper.
5. **Standardized paths: `.ai-docs/design/<slug>/{reference,surface,iterations/}`.** Reference at `reference.{md,png}` or `reference.figma-url`; surface declaration at `surface.<path-or-url>`; per-iteration screenshots at `iterations/<N>/`. Justification: convention enforced means agents can discover assets mechanically; no per-invocation flag for "where do screenshots go".
6. **Figma reference uses `figma-dev-mode` MCP directly.** `get_design_context` + `get_metadata` + `get_variable_defs` for the builder; `get_screenshot` for the grader's reference image. Visual comparison is the fallback when MCP can't structurally express something. Justification: MCP is already available; no need to roll our own Figma client.
7. **Screenshot reference uses visual comparison only.** Image alone has no structural intent. Grader takes a build screenshot, compares to the reference image, asks the LLM what differs. Justification: simplest workable strategy; anything more requires extra metadata the user shouldn't have to author.
8. **Carry over from PR #88:** `image-posting` primitive, `gh-attach-image.mjs`, `browser-pilot` agent (already generalized), `proposal` canvas, the 8 Open Q decisions from v1 still hold. Justification: those parts don't change.
9. **No "AC" jargon.** v2 calls them **checks** (what the grader runs). The strict spec contract's "acceptance criteria" remains the term inside spec-mode references (because that's what users authoring specs would call them), but the canvas + skill + agent docs use "checks" externally.
10. **Verbosity targets:** agent prompts ≤80 lines each (v1 averaged ~110); canvas knobs grouped into 3 blocks max (v1 had 7); per-component README ≤80 lines (v1 averaged ~130).

## Architecture

### Component map

```
plugin/
├── canvases/
│   ├── design-reference/              # NEW (replaces v1's design-spec)
│   │   ├── template.md                # one template; reference_type discriminator + per-type sections
│   │   ├── instructions.yaml          # 3 knob blocks: types / grading / paths
│   │   ├── instructions.schema.json
│   │   └── README.md
│   └── proposal/                      # unchanged (PR #87)
├── primitives/
│   └── image-posting/                 # unchanged (PR #88 foundations)
├── scripts/
│   └── gh-attach-image.mjs            # unchanged (PR #88 foundations)
├── agents/
│   ├── browser-pilot.md               # unchanged (PR #88 foundations)
│   ├── design-builder.md              # NEW (replaces design-implementer; ~80 lines)
│   └── design-grader.md               # NEW (replaces design-auditor + design-specifier; ~80 lines)
└── skills/
    ├── design-loop/SKILL.md           # canonical; --mode=loop|audit, --reference=<path-or-url>
    └── design-audit/SKILL.md          # thin wrapper (~20 lines)

.ai-docs/
├── design/<slug>/                     # consumer convention
│   ├── reference.md|.png|.figma-url
│   ├── surface.{txt|json}             # where to build/audit (path/url)
│   └── iterations/<N>/                # per-iteration screenshots
└── handoffs/design-loop-v2.md         # v2 status doc
```

### Reference-type matrix

| Type | Reference shape | Builder reads | Grader compares against |
|---|---|---|---|
| `spec` | `reference.md` (a design-spec markdown — locked decisions, phases, atoms, checks) | The spec | Spec's enumerated checks + locked decisions verbatim |
| `figma` | `reference.figma-url` (one URL of a Figma frame) | Figma MCP: `get_design_context` (component tree), `get_metadata` (style rules), `get_variable_defs` (tokens) | Build screenshot vs Figma `get_screenshot` (visual diff) + structural deltas from MCP node tree |
| `screenshot` | `reference.png` (or `.jpg`) | The image (LLM multimodal Read) | Build screenshot vs reference image (visual diff, LLM-judged) |

The matrix collapses to: **builder takes a source-of-truth and produces a surface; grader takes evidence of the surface and compares to the source-of-truth.** The reference type changes how each end reads "source-of-truth" but doesn't change the loop's choreography.

### Skill choreography

```
/design-loop --reference=.ai-docs/design/<slug>/reference.* \
             --surface=.ai-docs/design/<slug>/surface.* \
             [--termination=user-gate|max-loops|grader-good] \
             [--max-loops=N] \
             [--mode=loop|audit]

Auto-detect reference_type from file extension / URL pattern:
  *.md          → spec
  *.figma-url   → figma   (file content is the frame URL)
  *.png|*.jpg   → screenshot

Engine:
  round = 1
  while True:
    if mode == loop:
      builder.run(reference, surface)            # phase mode (first round) or fix mode (round 2+)
    grader_verdict = grader.run(reference, surface, round)
    post_findings()
    if grader_verdict == READY:           termination check (per strategy)
    if grader_verdict == BLOCKED:         halt
    if grader_verdict == FIXES:
      if round >= max_loops:              halt
      round += 1
      continue
```

### Agent boundaries

| | `design-builder` | `design-grader` |
|---|---|---|
| Tools | Read, Write, Edit, Bash, Glob, Grep (+ MCP via inheritance) | Read, Glob, Grep, Bash + browser-pilot subagent + image-posting + figma-dev-mode MCP |
| Reads | Reference (type-aware), surface state, optional findings list | Reference, surface URL, declared themes (spec mode) |
| Writes | Source code in the surface scope; one commit per round | Findings via image-posting primitive; never edits code |
| Returns | `COMMIT: <sha>` + report | `READY` / `FIXES` / `BLOCKED` |
| Pre-grade validation | n/a | Verifies reference is well-formed for its type (folds in v1's design-specifier) |

### Canvas — `design-reference`

Template skeleton:

```markdown
---
reference_type: spec | figma | screenshot
status: draft | accepted | superseded
related: ...
---

# {{surface_name}} — reference

## Reference
{{reference_body}}              <!-- type-conditional rendering -->

## Surface
{{surface_target}}              <!-- path or URL where the build lives -->

## Checks
{{checks}}                      <!-- empty/optional for figma + screenshot -->

## Themes
{{themes}}                      <!-- spec mode only -->
```

Knob blocks (3, down from v1's 7):

```yaml
types:
  spec:
    required_sections: [Reference, Surface, Checks]
    require_locked_decisions: true
    require_atoms_with_ts_interfaces: true
  figma:
    required_sections: [Reference, Surface]
    mcp_server: figma-dev-mode
    mcp_ops: [get_design_context, get_metadata, get_variable_defs, get_screenshot]
  screenshot:
    required_sections: [Reference, Surface]
    comparison: visual_only

grading:
  termination_default: user-gate            # user-gate | max-loops | grader-good
  max_loops_default: 3
  findings_ceiling: 7                       # grader returns BLOCKED if more

paths:
  design_root: .ai-docs/design/<slug>/
  reference: reference.{md,png,jpg,figma-url}
  surface: surface.txt
  iterations: iterations/<N>/
```

## Open questions

_(Tentative answers locked 2026-05-17 by Claude — **flagged for human confirmation before merge.** Code on `feat/design-loop-v2` follows these defaults; flip any of them and the implementation adjusts.)_

1. **Reference detection — file extension only, or also content sniffing?**
   **Tentative answer:** Extension only.
   **Rationale:** Predictable; debuggable. If user wants override, `--reference-type=` flag wins. Content sniffing introduces ambiguity for no real benefit.

2. **Figma URLs — how stored?**
   **Tentative answer:** Single-line file `reference.figma-url` containing just the frame URL. Node ID is part of the URL itself (Figma URLs already encode `?node-id=...`).
   **Rationale:** Simpler than YAML; matches the "one path, one file" pattern of the other reference types.

3. **Surface declaration shape — `surface.txt` or `surface.json`?**
   **Tentative answer:** `surface.txt` for v2 — one line, either a filesystem path (where the code lives) or a URL (where the build runs).
   **Rationale:** Covers single-target cases (~95% of use). Upgrade to `surface.json` in v3 if multi-target ever forces it. Avoids over-structuring.

4. **What `BLOCKED` means in figma mode.**
   **Tentative answer:** Enumerate four failure modes:
   - `figma_unreachable` — MCP server not responding or auth missing
   - `frame_not_found` — URL valid but Figma returns 404 for the node
   - `mcp_unavailable` — `figma-dev-mode` MCP not configured on this project
   - `unsupported_node_type` — frame contains components the grader can't extract structural data from (e.g., embedded video)
   **Rationale:** Each maps to a different user fix (auth / URL correction / MCP install / spec-mode fallback). Generic "blocked" is unhelpful.

5. **Composed mode (`/develop` with `needs:design`) — figma/screenshot too?**
   **Tentative answer:** **Spec-only for v2.** Composed mode with figma/screenshot references deferred to v3.
   **Rationale:** Composed mode's primary value is "this tracker issue refines a parent design" — that pattern fits spec refs cleanest. Figma/screenshot composed mode is plausible but the use case hasn't materialized; defer until it does.

## Deferred

- **Prose reference** ("make this look like Linear") — needs more thought on what the grader actually compares.
- **No-reference / "refine and polish" mode** — what's the grader's source of truth?
- **Multi-reference** (spec + figma simultaneously) — unclear semantics.
- **`design-builder` MCP server selection per-type** — for v2, the agent's frontmatter declares all MCP servers it might use; runtime branches on `reference_type` to choose which to call.
- **Smoke fixture** — `examples/smoke/` with a fixture spec + fixture frontend.
- **`/review --lens=design`** — Gate 2.5 facade. v1.5 still deferred.
- **Verbosity audit pass on existing v1 SDLC skills/agents** (sdlc-loop SKILL, design-loop SKILL) — out of v2 scope.

## Next step

If this proposal lands as `accepted`, the decomposition is a smaller stack than v1's:

1. **`design-reference` canvas** (replaces v1's `design-spec`; ~3 hours)
2. **`design-builder` + `design-grader` agents** (replace v1's design-implementer / design-auditor / design-specifier; ~3 hours)
3. **`/design-loop` SKILL + `/design-audit` thin wrapper** (~2 hours)
4. **Integration + path conventions** (sdlc-loop, develop.md, sdlc.example.yml additions for `design_root`; ~1 hour)

Total ~9 hours. v1 (PR #88) gets closed in favor of v2 once landed; the carry-over foundations (image-posting, gh-attach-image, browser-pilot, proposal canvas) get split out of #88 into their own PR if needed, OR the v2 PR consumes them directly off PR #88's base.

## Migration from v1 (PR #88)

| v1 component | v2 disposition |
|---|---|
| `plugin/canvases/design-spec/` | Replaced by `design-reference/` |
| `plugin/agents/design-specifier.md` | Dropped; logic folds into `design-grader` |
| `plugin/agents/design-implementer.md` | Replaced by `design-builder` |
| `plugin/agents/design-auditor.md` | Replaced by `design-grader` |
| `plugin/skills/design-loop/SKILL.md` | Rewritten leaner |
| `plugin/skills/design-audit/SKILL.md` | Thin wrapper (~20 lines) |
| `plugin/agents/browser-pilot.md` | Kept |
| `plugin/primitives/image-posting/` | Kept |
| `plugin/scripts/gh-attach-image.mjs` | Kept |
| `plugin/canvases/proposal/` (PR #87) | Kept |
| `plugin/skills/sdlc-loop/SKILL.md` updates | Re-do for v2 shape |
| `plugin/commands/develop.md` updates | Re-do for v2 shape |
| `.ai-docs/handoffs/design-loop-port.md` | Archive; replaced by `design-loop-v2.md` |
| `.ai-docs/proposals/design-loop-port.md` | Mark `superseded`; link to v2 |

Recommended sequence: merge PR #87 (proposal canvas) → close PR #88 in favor of v2 → land v2 as a single PR on top of #87's base, including the carry-over foundations.
