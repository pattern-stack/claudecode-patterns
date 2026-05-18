---
name: design-loop
description: Iterate a UI surface against a design reference (spec / figma / screenshot). Loop is "agent builds → grader screenshots → gives feedback → agent fixes → grader rechecks." Termination configurable. `/design-audit` is a thin wrapper for audit-only runs. Composable into `/develop` for single-issue spec-mode work via `needs:design`.
disable-model-invocation: true
argument-hint: "[--reference=<path>] [--surface=<path-or-url>] [--mode=loop|audit] [--strategy=user-gate|max-loops|grader-good] [--max-loops=N]"
arguments: [reference, surface, mode, strategy, max_loops]
allowed-tools: Bash(git *) Bash(gh *) Bash(curl *) Read Write Edit Glob Grep Agent

# === Project SDLC overlay ===
status: beta
topology: [design-loop]
consumes: [design-reference, surface]
produces: [commits, audit-comments]
gates:
  enforces: []
  sets: []
---

# Design Loop

Iterative refinement loop for UI work. Reference can be a spec, a Figma frame URL, or a screenshot. Engine is the same across all three; only the builder's source-of-truth and the grader's comparison strategy change.

For audit-only runs (no builder dispatch), pass `--mode=audit` or use the [`/design-audit`](../design-audit/SKILL.md) thin wrapper.

## Reference contract

References conform to the [`design-reference`](../../canvases/design-reference/README.md) canvas. The canvas IS the contract — section structure, type-specific rules, grading config. Read it once at the start of the loop. Do NOT inline its contents.

## Inputs

| Arg | Required | Default | Notes |
|---|---|---|---|
| `--reference` | yes | — | Path to `.ai-docs/design/<slug>/reference.{md,figma-url,png,jpg}`. Reference type auto-detected from extension. Pass `--reference-type=<t>` to override. |
| `--surface` | yes | — | Path or URL where the build lives. Default discovered from `.ai-docs/design/<slug>/surface.txt`. |
| `--mode` | no | `loop` | `loop` (default) runs full build→grade→fix cycle. `audit` skips the builder — grader only, no fixes dispatched. |
| `--strategy` | no | `user-gate` | Termination: `user-gate` / `max-loops` / `grader-good`. See [Termination](#termination). |
| `--max-loops` | no | `3` | Hard cap on rounds regardless of strategy. |

## Prerequisites (auto-verified at skill start)

- `git` + `gh` (`gh auth status` exits 0)
- `image-posting` primitive's `verify-prereqs` → `ok: true` (only when `target` is provided)
- `design-builder` + `design-grader` agents present
- `bun ${CLAUDE_PLUGIN_DIR}/scripts/design.ts verify <surface-url>` (via `/browser-driver`) → `ok: true` (200 + non-stale auth + non-loading title)
- For `figma` mode: `.ai-docs/figma/<slug>/snapshot.yaml` exists and is fresh (else: run `/figma-snapshot <figma-url>` first; will block until done)
- If `/browser-driver` reports `authStale: true` → halt with "run `/auth-recover`"

The loop runs these checks automatically at start and halts with explicit recovery hints on failure. Each prereq lists which skill to invoke for fix.

## Termination

`max-loops` is always the hard upper bound. Within that:

| Strategy | Termination condition |
|---|---|
| `user-gate` (default) | After each round's grader verdict is posted, halt and wait for user resume. |
| `max-loops` | Run rounds until `--max-loops` exhausted, then halt regardless of verdict. |
| `grader-good` | If grader returns `READY`, terminate. Otherwise continue. |

All strategies halt immediately on `BLOCKED`. `--mode=audit` ignores `--strategy` (single grade pass, no loop).

## Choreography

```
# Pre-flight
verify_prereqs():
  /browser-driver verify-prereqs <surface-url>      # 200, non-stale auth, non-loading title
  if figma reference:
    /figma-snapshot <figma-url> --check-only        # snapshot exists + fresh
  halt-on-fail with explicit fix hint per finding

round = 1
loop:
  if mode == loop:
    builder.run(reference, surface, mode=phase|fix, round, findings?)
    capture builder.commit_sha
    # NEW (v2.1): builder must verify each ADDRESSED finding via
    # /browser-driver inspect with the grader's selectors JSON BEFORE reporting.

  grader.run(reference, surface, commit_sha, round, target)
    # NEW (v2.1): grader MUST run both /browser-driver capture (screenshot)
    # AND /browser-driver inspect (structural + interactive probe). The
    # verdict is gated on the inspection JSON, not just the screenshot.
    # READY requires: zero overflow, zero cursor mismatches, all interactive
    # elements have proper role+aria, plus visual match to the figma snapshot.

  post grader.verdict via image-posting (if target provided)

  switch grader.verdict:
    READY:
      apply termination strategy:
        user-gate     → halt; "/design-loop --reference=... again to continue"
        max-loops     → if round < max_loops, continue; else halt
        grader-good   → halt (epic complete)
    FIXES:
      if round >= max_loops: halt (cap-hit)
      else: round += 1; continue (builder runs in fix mode next iteration)
    BLOCKED:
      halt with sub-code (universal: `surface_unreachable_browser`,
      `surface_requires_auth`, `surface_evidence_missing`,
      `internal_contradiction`); surface to user with /skill-to-run hint
```

Spec mode adds one wrinkle: if the reference declares multiple phases, the loop runs phase-by-phase. Each phase has its own round counter; phase boundaries are user-gate boundaries under `user-gate` strategy. Phase semantics belong to the spec reference type only.

## Composed mode (`/develop` with `needs:design`)

When a tracker issue carries `needs:design`, `/develop` invokes the grader directly between the standard implementer's commit and the validator's run. v2 supports composed mode for **spec references only** — figma/screenshot composed mode deferred per Open Q #5.

In composed mode this skill's choreography collapses to: grader runs → fix-loop (up to `max-loops`) → standard validator gate. The per-phase user-gate is replaced by Gate 2/2.5/3.

## Stopping conditions

Halts (no auto-continue):
- Pre-grade validation failure (grader returns `BLOCKED`)
- Grader returns `BLOCKED` for any sub-code
- `--max-loops` exhaustion within a round
- End of round under `user-gate` strategy (always)
- Surface URL not reachable, or commit SHA mismatch

## Reporting

At every stop, surface to the caller:
- Position (`round N, verdict V`)
- Grader's verdict envelope (including BLOCKED sub-code if applicable)
- Posted-to URL (if any)
- Resume hint (which command, which flags)

## Worked example

For a complete trace of this loop run on a real epic (sales-patterns-ts issue #47 — the originating use case), see [`examples/issue-47.md`](./examples/issue-47.md). The example is from v1 (spec-only) but the choreography is the same in v2.

## Related

- [`design-reference` canvas](../../canvases/design-reference/README.md) — the contract
- [`design-builder`](../../agents/design-builder.md), [`design-grader`](../../agents/design-grader.md) — phase agents
- [`browser-pilot`](../../agents/browser-pilot.md), [`image-posting` primitive](../../primitives/image-posting/README.md) — substrate
- [`/design-audit`](../design-audit/SKILL.md) — thin audit-only wrapper
- [`/develop`](../../commands/develop.md) — composed-mode entrypoint
- [v2 proposal](../../../.ai-docs/proposals/design-loop-v2.md) — architecture
- [Port handoff](../../../.ai-docs/handoffs/design-loop-v2.md) — known gaps + resume instructions
