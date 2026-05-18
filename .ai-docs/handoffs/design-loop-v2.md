# Handoff — design-loop v2 (reference-driven iteration)

This is the port-status doc for the v2 design-loop landing on `feat/design-loop-v2`. Read this before merging or before resuming in a new session.

**Status:** structurally validated, not yet exercised end-to-end against any of the three reference types inside this plugin's consumers.

## What v2 ships

```
plugin/
├── canvases/
│   ├── design-reference/                # NEW (replaces v1 design-spec)
│   │   ├── template.md
│   │   ├── instructions.yaml            # 3 knob blocks: types / grading / paths
│   │   ├── instructions.schema.json
│   │   └── README.md
│   └── proposal/                        # unchanged (PR #87)
├── primitives/
│   └── image-posting/                   # unchanged (PR #88 carry-over)
├── scripts/
│   └── gh-attach-image.mjs              # unchanged (PR #88 carry-over)
├── agents/
│   ├── browser-pilot.md                 # unchanged (PR #88 carry-over)
│   ├── design-builder.md                # NEW (replaces design-implementer)
│   └── design-grader.md                 # NEW (replaces design-auditor + design-specifier)
└── skills/
    ├── design-loop/
    │   ├── SKILL.md                     # leaner; --mode=loop|audit; 3 termination strategies
    │   └── examples/issue-47.md         # worked trace (vendored from source)
    └── design-audit/
        └── SKILL.md                     # thin wrapper (~25 lines)

.ai-docs/
├── proposals/design-loop-v2.md          # v2 architectural proposal
└── handoffs/design-loop-v2.md           # this file
```

## What's been validated

- All 6 canvases pass `bash plugin/scripts/verify-canvases.sh` (including new `design-reference`).
- All frontmatter blocks parse as valid YAML.
- Cross-references between agents ↔ skills ↔ canvas ↔ primitive point to real files.
- Reference-type-extension auto-detection logic is consistent across SKILL.md, agent prompts, and canvas knobs.
- `figma-dev-mode` MCP server availability documented (skill prereqs).

## What has NOT been validated

- **End-to-end loop run for any of the three reference types.** Needs a real reference + running surface.
- **Reference-type auto-detection from extension** — logic is correct per the canvas, but unverified at runtime.
- **`figma-dev-mode` MCP integration** — listed as a prereq, but `design-builder` and `design-grader` MCP calls have not been smoke-tested.
- **Composed mode via `/develop` + `needs:design`** — spec-only path documented; not exercised.
- **Image-posting primitive routing** — carried over from PR #88 unchanged but never exercised end-to-end there either.
- **Agent verdict envelopes** (`READY` / `FIXES` / `BLOCKED` + sub-codes for BLOCKED) — prompt-specified but real LLM responses may need tuning.

## Smoke test before first real use

For each reference type, in order:

### Spec
1. Author `.ai-docs/design/smoke-spec/reference.md` (1 locked decision, 1 atom with TS interface, 1 check, 1 theme).
2. Author `.ai-docs/design/smoke-spec/surface.txt` (one line: project's frontend path or `/` URL).
3. Run `/design-loop --reference=.ai-docs/design/smoke-spec/reference.md`. Spec-gate (grader's pre-grade validation) should pass; builder should ship the atom; grader should produce READY or FIXES.

### Figma
1. Author `.ai-docs/design/smoke-figma/reference.figma-url` (one line: a Figma frame URL on a project with `figma-dev-mode` MCP configured).
2. Author `.ai-docs/design/smoke-figma/surface.txt`.
3. Run `/design-loop --reference=.ai-docs/design/smoke-figma/reference.figma-url`. Watch for `figma_unreachable` / `frame_not_found` / `mcp_unavailable` BLOCKED sub-codes.

### Screenshot
1. Drop an image at `.ai-docs/design/smoke-shot/reference.png`.
2. Author `.ai-docs/design/smoke-shot/surface.txt`.
3. Run `/design-loop --reference=.ai-docs/design/smoke-shot/reference.png`. Vision-only comparison.

For all three: one-time `gh-attach-image` auth: `node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs --auth`.

## Deferred (post-v2)

| Item | Why deferred |
|---|---|
| Prose reference type | Needs more thought on grader source-of-truth |
| No-reference / "refine and polish" mode | Same — what does grader compare against |
| Multi-reference (spec + figma simultaneously) | Unclear semantics |
| Composed mode for figma/screenshot in `/develop` | v2 spec-only; v3 if use case materializes (Open Q #5) |
| `--dry-run` mode | Useful for spec iteration; not blocking |
| `local-folder` + `linear-comment` adapters for `image-posting` | v2 ships `gh` only (carry-over from PR #88) |
| `/review --lens=design` Gate 2.5 facade | v1.5 deferral still holds |
| Smoke fixture (`examples/smoke/`) | First real use exercises it instead |
| `sdlc.yml.design_loop` config block (defaults + max-loops) | Hardcoded in SKILL.md for v2; promote to config if multiple projects diverge |

## Open question decisions (tentative — flag for confirmation)

Captured in `.ai-docs/proposals/design-loop-v2.md` § Open questions. Summary:

1. Reference detection: extension only (override via `--reference-type=`)
2. Figma URL storage: single-line `reference.figma-url` file
3. Surface declaration: `surface.txt` (one line: path or URL)
4. BLOCKED sub-codes: enumerated per type
5. Composed mode: spec-only for v2

## Migration from PR #88 (v1)

PR #88 is held unmerged. v2 replaces it. The migration table in [`design-loop-v2.md`](../proposals/design-loop-v2.md) § Migration enumerates every v1 file's v2 disposition.

The v1 handoff doc at `.ai-docs/handoffs/design-loop-port.md` is preserved for history but marked superseded.

## Reference

- v2 proposal: `.ai-docs/proposals/design-loop-v2.md`
- v1 proposal (superseded): `.ai-docs/proposals/design-loop-port.md`
- Originating source: `pattern-stack/sales-patterns-ts` branch `feat/design-loop-skill` @ `cad9e74`
- Carry-over commit (foundations): PR #88 (held)
