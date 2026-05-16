---
name: critique
description: Structured critic discipline for SDLC artifacts — specs, plans, diffs, ADRs. Applies a verdict (PASS / PASS_WITH_NOTES / REVISE / BLOCK) with categorized findings (blockers / notes / nits) against a configurable lens (adherence / quality / logic / scope / mixed). Used by the reviewer agent at Gate 1.5 (spec critique) and Gate 2.5 (post-impl two-pass diff review). Loadable inline by any agent or the lead for ad-hoc review.
when_to_use: User asks "review this spec / plan / diff", "critique my design", "is this implementation faithful to the spec", "is this code well-built", or any SDLC phase agent is about to emit an artifact for human review and wants a structured second pass.
allowed-tools: Read, Glob, Grep
user-invocable: true
# tool_group: read_only (allowlist) — write access acquired via Edit when the
# reviewer agent loads this skill and appends to a spec phase section.

# === Project SDLC overlay ===
status: active
topology: none
consumes: [target, against]
produces: [verdict, findings, phase-section, envelope]
gates:
  enforces: []
  sets: []
---

# critique — the critic discipline

A reusable critic skill that can be applied to any written artifact in the SDLC loop. The discipline is constant; what changes is the **target** (what's being reviewed), **against** (what to compare it to), and **lens** (which axis of judgment dominates).

Loaded automatically by the [`reviewer`](../../agents/reviewer.md) agent. Loadable inline by any other agent or the lead for ad-hoc review (no spawn needed; the calling model applies the discipline in-context).

## Mission contract

Every invocation of this skill is parameterized by three values:

| Parameter | Type | Examples |
|---|---|---|
| `target` | path / URL / issue key / diff ref | `.ai-docs/stacks/foo/specs/abc-101.md`, `git diff main...HEAD`, `ABC-101`, `https://github.com/.../pull/42` |
| `against` | reference to compare to | path to cited code, prior art doc, spec file, quality canvas (`canvases/quality-checks/`), or `self` for internal-consistency review |
| `lens` | judgment axis | `adherence` / `quality` / `logic` / `scope` / `mixed` (default) |

When the reviewer agent loads this skill, it receives the mission as its spawn prompt. When the lead loads this skill inline, it applies the mission to the current conversation context (no spawn).

## Lens taxonomy

A lens is a primary axis of judgment. Multiple lenses can run in parallel against the same target — that's how the two-pass diff review works (one reviewer with `lens=adherence`, another with `lens=quality`, joined verdicts).

| Lens | Question being asked | What to read | Typical target+against |
|---|---|---|---|
| `adherence` | "Did we build what we said?" | target + against (the spec or plan) | diff vs spec, impl vs plan |
| `quality` | "Is this well-built?" | target alone (intentionally **blind** to the spec) | diff vs quality canvas |
| `logic` | "Is the reasoning sound?" | target + cited references | spec vs cited code, ADR vs cited RFCs |
| `scope` | "Are we doing the right amount?" | target + plan / charter | diff vs plan, spec vs issue body |
| `mixed` | "All of the above, weighted by what matters" | target + against | default for spec critique |

The `quality` lens is intentionally spec-blind — a reviewer using this lens reads the diff alone, with no access to the spec. This prevents the lens from collapsing into adherence-by-another-name. When the reviewer agent runs `lens=quality`, the spawning command MUST NOT include the spec path in its prompt; `against` is the quality canvas, not the spec.

## Verdict taxonomy

Every critique terminates in one of four verdicts:

| Verdict | Meaning | What unblocks |
|---|---|---|
| `PASS` | No findings. Implementation matches spec, or spec is sound, or diff is well-built. | Next gate fires automatically. |
| `PASS_WITH_NOTES` | Findings exist but none are blockers. Worth fixing, but ship-ready. | Next gate fires; notes tracked as follow-ups in the spec file or issue body. |
| `REVISE` | At least one blocker found. The artifact needs change before the next gate fires. | Producer agent (specifier / implementer) re-runs; reviewer re-checks. |
| `BLOCK` | A structural problem the producer can't resolve without human input (architectural conflict, contradicting prior decision, missing context). | Human reviews; reviewer halts. |

## Findings structure

Findings are categorized by severity. Every finding lives in exactly one category.

| Category | Definition | Required fields |
|---|---|---|
| `blockers` | Defects that prevent the artifact from being correct. Verdict shifts to `REVISE` (or `BLOCK` if humans must arbitrate) if any are present. | location, description, suggested fix |
| `notes` | Real issues worth addressing but not gate-blocking. Track as follow-ups. | location, description |
| `nits` | Style, naming, micro-optimization, taste-level. Author may close-as-wontfix. | location, description |

Each finding cites a concrete location: `path:line` for code/specs, `§ N.M` for documents, `<plan-key>` for plan items. Generic "this is unclear" comments are not findings — they're noise.

## Discipline — how to actually do the work

Apply this loop on every critique:

### 1. Read the target

Read the target artifact in full. If it's a path, use Read. If it's a diff, use `git diff` (or `git show <ref>` for a single commit). If it's an issue key, fetch the issue body via the configured tracker MCP.

### 2. Read against

Read the comparison reference. This varies by lens:

- `adherence`: read the spec or plan that the target is supposed to faithfully implement. Treat the spec as authoritative.
- `quality`: read the quality canvas (`canvases/quality-checks/categories.yaml` — see [`canvases/quality-checks`](../../canvases/quality-checks/README.md) when present). Treat each category as a checklist.
- `logic`: read every cited reference in the target. If a citation is missing or wrong, that's a blocker.
- `scope`: read the plan and the issue body. Compare what the target claims to do against what was scoped.
- `mixed`: read the spec (or plan, depending on phase) + the quality canvas + cited references. Synthesize across.

### 3. Verify claims against the actual code

Specs and diffs make claims about other files: "the existing `Foo.bar()` is called from three places," "this matches the pattern at `path/x.ts:42`." Verify every such claim with `Glob` / `Grep`. Wrong line numbers, stale call-site counts, and missed sites are common in first-pass specifier output — catching them is the highest-value thing this skill does.

### 4. Produce findings

For each finding, capture:

- `severity`: blocker / note / nit
- `location`: `path:line` or `§ section`
- `description`: what's wrong, in one or two sentences
- `suggested_fix`: concrete next action (blockers only; nits may omit)
- `category` (optional): name of a quality canvas category if `lens=quality` — e.g. `convenient_fallback`, `magic_constants`. Lets producers grep for repeat offenders.

### 5. Determine the verdict

Rules:
- Any blocker → `REVISE` (or `BLOCK` if it's a human-arbitrate issue)
- Notes only → `PASS_WITH_NOTES`
- Nits only or none → `PASS`

If there's tension between lenses in a `mixed` run (one says PASS, another says REVISE), the lower verdict wins. Surface the tension explicitly.

### 6. Write the result

**If the target is a phase-aware artifact** (i.e., a spec file with phase sections — see [`canvases/spec`](../../canvases/spec/README.md)):
- Locate the section owned by this critique (per the spec canvas's `phases:` block).
- Replace the placeholder line (`_Awaiting <agent>._`) with the verdict + findings via Edit.
- The static spec sections remain untouched. Other phase sections remain untouched.

**If the target is not a phase-aware artifact** (ad-hoc review of a plan, an ADR, a diff without a spec file):
- Return the verdict + findings inline as the response. The calling command decides where they go.

### 7. Post the status envelope

Per [`canvases/envelope`](../../canvases/envelope/README.md). The envelope is the cross-surface output wrapper; the chat / tracker / PR / log surfaces project from it. Required fields for critique phase:

- `phase: reviewer` (the agent that ran the skill)
- `target`, `against`, `lens` — captured under `mission:`
- `verdict` — top-level field
- `findings_count: { blockers, notes, nits }` — top-level field
- `artifact.path` — the spec phase section the critique was appended to, or `null` if ad-hoc
- `headline: "<verdict> on <target> (<lens>) — <N> blockers / <N> notes"`
- `next.command` — what should fire next (`/sdlc:review` if Gate 2.5 critique; `null` if the verdict was REVISE and the producer re-runs)

## Multi-lens runs (the two-pass diff review)

For the post-implementation review, two reviewers run concurrently with different lenses:

```
Reviewer A: target=<diff-ref>, against=<spec-path>,         lens=adherence
Reviewer B: target=<diff-ref>, against=<quality-canvas>,    lens=quality
```

Each writes to its own phase section (`Diff Review — Adherence` and `Diff Review — Quality` respectively). The calling command (`/sdlc:review`) waits for both, then joins the verdicts:

```
joined_verdict = min(adherence.verdict, quality.verdict)
                 # where verdict order: PASS > PASS_WITH_NOTES > REVISE > BLOCK
joined_findings = adherence.findings ∪ quality.findings
                  # de-duplicated by (location, description)
```

The combined envelope's `headline` cites the joined verdict; the body summarizes the worst N findings across both.

## Context isolation via subagent fork

When a critique needs to read 30+ files of cited code (typical for `lens=quality` against a non-trivial diff), running inline burns the calling model's context budget. Fork to a subagent:

The reviewer agent (`plugin/agents/reviewer.md`) is the canonical runtime for this skill — context-isolated, opus model, allowed to Edit the spec phase section and post tracker comments. Spawn it via:

```
Agent({
  subagent_type: "reviewer",
  prompt: "target: <ref>\nagainst: <ref>\nlens: <adherence|quality|...>",
  description: "Critique <target> with <lens> lens"
})
```

Inline use (no fork) is appropriate when:
- The target is small (≤200 lines)
- The lens doesn't require reading cited code (e.g. `scope` on a plan)
- The caller is the lead or another opus agent and context budget is healthy

When in doubt, fork. The cost of an extra subagent is small; the cost of a polluted lead context is large.

## Anti-patterns

Things this skill explicitly is NOT:

- A linter. Linters check syntactic invariants; critique checks semantic correctness against a referenced expectation.
- A test runner. Tests check runtime behavior; critique checks intent + craft.
- A LGTM stamp. A `PASS` verdict means the critic actively looked for findings and didn't find any — not "I didn't read it carefully."
- A style guide. Style preferences without a referenced rule belong in nits, not blockers.
- A re-derivation of the artifact. The critic reads what's there; they do not rewrite. If the artifact needs rewriting, the verdict is `REVISE` and the producer re-runs.

## Cross-references

- [`reviewer` agent](../../agents/reviewer.md) — the runtime that loads this skill
- [`canvases/spec`](../../canvases/spec/README.md) — phase sections this skill writes to
- [`canvases/envelope`](../../canvases/envelope/README.md) — output wrapper
- [`canvases/quality-checks`](../../canvases/quality-checks/README.md) — input to `lens=quality` runs (when present)
- [`sdlc-loop`](../sdlc-loop/SKILL.md) — Gate 1.5 (critique) and Gate 2.5 (review) workflow judgment
- [`/sdlc:critique`](../../commands/critique.md) — single-reviewer entrypoint (Gate 1.5)
- [`/sdlc:review`](../../commands/review.md) — paired-reviewer entrypoint (Gate 2.5)
