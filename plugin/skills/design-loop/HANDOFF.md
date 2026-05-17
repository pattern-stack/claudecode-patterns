# Handoff — design-loop skill package (port to SDLC plugin)

This file ships the v1-beta of the `/design-loop` + `/design-audit` skills inside the SDLC plugin. It is ported from `pattern-stack/sales-patterns-ts` branch `feat/design-loop-skill` (commit `cad9e74`) with adaptation to read the [`design-spec` canvas](../../canvases/design-spec/README.md) instead of inlining a flat-file contract, and to post through the [`image-posting` primitive](../../primitives/image-posting/README.md) instead of calling `gh-attach-image.mjs` directly.

**Status:** structurally validated, not yet exercised end-to-end against a real epic inside this plugin's consumers. Read this before merging or before resuming in a new session.

## What's shipped

```
plugin/
├── canvases/
│   └── design-spec/                    # the spec contract (replaces _design-shared/spec-format.md)
├── primitives/
│   └── image-posting/                  # how screenshots get attached
│       ├── README.md
│       └── gh.md                       # the gh-attach-image-based adapter
├── scripts/
│   └── gh-attach-image.mjs             # Playwright-driven uploads to GitHub's user-attachments CDN
├── agents/
│   ├── browser-pilot.md                # vendored from sales-patterns-ts; MCP-based browser teammate
│   ├── design-specifier.md             # spec-contract verifier (reads canvas)
│   ├── design-implementer.md           # phase-and-fix implementer
│   └── design-auditor.md               # browser-pilot-driven grader (posts via image-posting)
└── skills/
    ├── design-loop/
    │   ├── SKILL.md                    # greenfield orchestrator (user-invocable)
    │   ├── examples/
    │   │   └── issue-47.md             # worked trace (vendored from source)
    │   └── HANDOFF.md                  # this file
    └── design-audit/
        └── SKILL.md                    # audit-only orchestrator
```

## What's been validated

- All frontmatter blocks parse as valid YAML.
- `bash plugin/scripts/verify-canvases.sh` — passes for `design-spec` and `proposal` (the two canvases added by this port).
- Canvas resolution paths (`${CLAUDE_PLUGIN_DIR}/canvases/design-spec/` + project override) match the standard plugin overlay used by other canvases.
- Image-posting primitive layout mirrors `task-management/` (port README + per-value adapter file).
- All cross-references (agents ↔ skills ↔ canvas ↔ primitive) point to real files.

## What has NOT been validated

- **End-to-end loop run.** Needs a real spec, a running frontend with `/_showcase`, and a PR target. Not exercisable from this packaging session.
- **`image-posting` primitive at runtime.** The `gh` adapter's `--auth` flow has not been exercised against this plugin's path resolution. Should work — the script itself is unchanged from sales-patterns-ts where it's in active use.
- **Composed mode wiring through `/develop`.** `develop.md` now lists `design-auditor` as a `needs:design` extra, but the team-composition machinery hasn't been smoke-tested with a `needs:design` issue.
- **Agent return-format compliance.** Each agent's prompt specifies `READY` / `FIXES` / `BLOCKED` / `GAPS` envelopes; whether real LLM responses honor those strictly is empirical.
- **`disable-model-invocation: true` behavior** on the skills. Confirmed in docs but not test-driven here.
- **Cross-repo portability of `browser-pilot`'s MCP servers.** `chrome-devtools-mcp`, `@playwright/mcp`, and `@danielsogl/lighthouse-mcp` are listed as `npx` invocations. They install on first use; first use may be slow.

## Smoke test before first real use

1. In Claude Code with this plugin installed, type `/` and verify `/design-loop` and `/design-audit` appear in the menu (proves discovery).
2. Run `bash ${CLAUDE_PLUGIN_DIR}/scripts/verify-canvases.sh` — all canvases (including `design-spec`) should validate.
3. Type `/design-loop` (no args) — expect a usage message asking for `[spec-path]` (proves arg handling + render).
4. Author a tiny fixture spec at `.ai-docs/design/smoke/spec.md` (1 atom, 1 theme, 1 phase) and run `/design-loop .ai-docs/design/smoke/spec.md`. The spec gate (`design-specifier`) should either pass or return readable `GAPS`.
5. One-time auth for `gh` image posting: `node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs --auth`. Required before `design-auditor` can post to PR comments.

## Acceptance criteria deferred to follow-up

From the original sales-patterns-ts handoff + this port's open questions:

| Criterion | Status |
|---|---|
| **Self-test fixture** (`examples/smoke/`) | NOT SHIPPED — deferred. Add a tiny fixture spec + fixture frontend so the package can be smoke-tested in a clean repo. |
| **Versioned spec format** | SHIPPED — `spec_format_version: 1` in `canvases/design-spec/instructions.yaml`. Version-mismatch refusal in `design-specifier`. |
| **Explicit prerequisites section** | SHIPPED — both SKILL.md files have a `## Prerequisites` block. |
| **Dry-run mode** (`--dry-run`) | NOT SHIPPED — deferred. Useful for spec iteration; not blocking for v1. |
| **`local-folder` adapter** for `image-posting` | NOT SHIPPED — v1.1 deferred. Auditor's no-network fallback. |
| **`linear-comment` adapter** for `image-posting` | NOT SHIPPED — v2 deferred. |
| **`/review --lens=design`** | NOT SHIPPED — v1.5 deferred. Gate 2.5 facade over `design-auditor`. |
| **`canvas-author` support for `design-spec`** | NOT SHIPPED — v2 deferred. canvas-author dialog needs design-spec-specific question flows. |
| **`sdlc.yml.design_loop` block** for default strategy + max-loops | NOT SHIPPED — v1.1. For now, flags override; defaults are hardcoded in `/design-loop` SKILL.md. |
| **Phase-level locked decisions** | NOT SHIPPED — v2 if a real epic pressures it (Open Q #7). |

## Known open questions (tentative answers — flag for confirmation)

Captured in [the port proposal](../../../.ai-docs/proposals/design-loop-port.md) § Open questions. All 8 have tentative answers locked in this port; flip any of them and the relevant files adjust.

1. Termination default: `user-gate` + `max-loops: 3` ✓
2. Phase = intra-issue (composed) OR multi-phase (standalone) — both modes ✓
3. Design-spec path: `.ai-docs/design/<slug>/spec.md` ✓
4. browser-pilot: Playwright default, Anthropic-managed when detected ✓ (Playwright via `@playwright/mcp`; chrome-devtools-mcp is the "managed" path when user opts in)
5. `image_posting` + `validator_post_target` coexist ✓
6. `critic-evaluated` termination uses `design-auditor` verdict directly ✓
7. Locked decisions: spec-level only for v1 ✓
8. Universal AC: hardcoded list with `enabled` toggles ✓

## How to resume

If picking up in a new session to ship the deferred items:

1. **Smoke fixture** — create `plugin/skills/design-loop/examples/smoke/{spec.md,frontend/}` so `/design-loop` can run end-to-end in a clean checkout without depending on the source-repo project.
2. **`local-folder` image-posting adapter** — add `plugin/primitives/image-posting/local-folder.md`. Writes comment markdown + images to `<output_dir>/` instead of posting.
3. **`sdlc.yml.design_loop` block** — add to `sdlc.example.yml` and update `/design-loop` SKILL.md to read it for defaults.

If picking up to actually use the loop on a real epic:

1. Author a design spec at `.ai-docs/design/<slug>/spec.md` following the [`design-spec` canvas](../../canvases/design-spec/README.md).
2. Verify prereqs: `node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs --auth` (one-time), `bash ${CLAUDE_PLUGIN_DIR}/scripts/verify-canvases.sh`.
3. Invoke `/design-loop .ai-docs/design/<slug>/spec.md`.
4. The first phase will exercise everything. Watch for: spec gate refusing the spec, auditor returning malformed findings, implementer touching files outside scope. Tune prompts if any of these surface.

## Reference

- Originating source: `pattern-stack/sales-patterns-ts` branch `feat/design-loop-skill` @ `cad9e74` (unmerged there)
- Originating merged docs: `pattern-stack/sales-patterns-ts` PR #74 (`docs/multi-pass-loop-runbook.md`, `scripts/gh-attach-image.mjs`)
- Worked trace: `examples/issue-47.md`
- Architecture proposal: `.ai-docs/proposals/design-loop-port.md` (this plugin)
- Skill format docs: https://code.claude.com/docs/en/skills
