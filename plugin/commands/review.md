---
description: Gate 2.5 — paired-lens post-implementation diff review. Spawns two reviewer agents in parallel (lens=adherence + lens=quality), each writing to its own spec phase section. Joins verdicts; the lower wins. Verdict PASS/PASS_WITH_NOTES clears Gate 2.5; REVISE triggers implementer fix.
argument-hint: "[issue-key] [--lens=<single>] [--against=<ref>]"
allowed-tools: Read, Bash, Agent
primitives:
  required:
    - task_management
status: active
topology: none
consumes: [issue, spec, branch, diff]
produces: [verdicts, phase-sections, comment]
gates:
  enforces: []
  sets: []
---

# /sdlc:review

Gate 2.5 — post-implementation diff review with two parallel lenses. Spawns the [`reviewer`](../agents/reviewer.md) agent twice in parallel:

- **Reviewer A:** `target=<diff>`, `against=<spec-path>`, `lens=adherence` → "Did we build what we said?"
- **Reviewer B:** `target=<diff>`, `against=<quality-canvas>`, `lens=quality` → "Is this well-built?" (spec-blind by construction)

Each writes verdict + findings to its own spec phase section (`Diff Review — Adherence` and `Diff Review — Quality` respectively). This command joins the two verdicts and emits the combined outcome.

The two-lens shape is load-bearing: a single reviewer with mixed lens systematically collapses one of these into the other. Real findings live in the *gap* between "what we said" and "what's well-built." See the [`critique`](../skills/critique/SKILL.md) skill § "Lens taxonomy" for the rationale.

> **Workflow judgment** — for halt recovery from REVISE, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Working tree state (pre-rendered)

Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`

## Usage

```
/sdlc:review <ISSUE-KEY> [--lens=<single>] [--against=<ref>]
```

`$1`: tracker issue key (e.g. `ABC-101`).

Flags:
- `--lens=<single>`: run a single reviewer (lens=adherence | quality | logic | scope | mixed) instead of the paired default. Use for spot checks.
- `--against=<ref>`: override the `against` reference for the single-lens form. Ignored under the paired default (paired runs always use spec + quality-canvas).

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `task-management/{value}` | primitive | Issue resolution, envelope post routing |
| [`reviewer`](../agents/reviewer.md) | agent | Spawned twice in parallel under paired mode |
| [`critique`](../skills/critique/SKILL.md) | skill | The discipline (loaded by each reviewer) |
| [`canvases/spec`](../canvases/spec/README.md) | canvas | Defines the Diff Review phase sections |
| [`canvases/quality-checks`](../canvases/quality-checks/README.md) | canvas | Input to the quality lens (when present) |

## Steps

### Step 1: Resolve config + issue + spec + diff

Read `.claude/sdlc.yml`. Resolve the spec path per `artifact_paths` (stack-co-located preferred). If no spec exists, halt. You do **not** need to read `phases` — the `phase-tuning` PreToolUse hook applies per-phase model/effort/turn tuning to both reviewer spawns in Step 3 automatically.

Resolve the diff ref:
- Default: `git diff main...HEAD` on the current branch
- If a PR is open against this branch, use the PR head commit as the explicit ref
- If the human passed a specific commit / range as part of the call, honor that

### Step 2: Detect mode + rerun

- If `--lens=<single>` is set → **single-lens mode** (one reviewer, no join).
- Otherwise → **paired mode** (two reviewers sequential, join verdicts).

For each phase section the run will write to (`Diff Review — Adherence` and/or `Diff Review — Quality`), detect first-run vs re-run by inspecting current content:
- Section contains placeholder (`_Awaiting adherence review._` / `_Awaiting quality review._`) → `rerun = false`.
- Section contains a prior `**Verdict:** ` line → `rerun = true`. The implementer presumably addressed prior findings; we're re-checking.

Pass `rerun: <true|false>` per-reviewer to the spawned agents in Steps 3a/3b.

### Step 3a (paired mode): Spawn two reviewers sequentially

Both reviewers Edit the same spec file (different sections, but same file). The Claude Code harness does not guarantee atomic Edit serialization across parallel subagents, so spawn **sequentially** to avoid TOCTOU races — Adherence first, then Quality:

**Per-phase tuning**: don't pass `model:` on either spawn — the `phase-tuning` PreToolUse hook injects `sdlc.yml`'s `phases.reviewer` tuning (model / effort / …) at the spawn boundary (frontmatter default stands when unset).

```
Agent A (first; await completion before spawning B):
  subagent_type: "reviewer"
  description: "Adherence review on <$1> diff"
  prompt: "
target: <diff-ref>
against: <resolved-spec-path>
lens: adherence
issue: $1
phase_section: Diff Review — Adherence
skip_tracker_post: true             # /sdlc:review posts the joined envelope
rerun: <per Step 2 detection for adherence section>
"

Agent B (after A returns):
  subagent_type: "reviewer"
  description: "Quality review on <$1> diff"
  prompt: "
target: <diff-ref>
against: quality-canvas             # symbolic; reviewer resolves to canvas file
lens: quality
issue: $1
phase_section: Diff Review — Quality
skip_tracker_post: true             # /sdlc:review posts the joined envelope
rerun: <per Step 2 detection for quality section>
"
```

**Critical invariant:** Reviewer B's prompt MUST NOT include the spec path. The quality lens is structurally spec-blind. The reviewer agent enforces this at parse-time (halts if `lens=quality` + `against` looks like a spec); this command pre-enforces it by passing `quality-canvas` symbolically (which the reviewer resolves to the canvas file).

**Why sequential, not parallel:** Both reviewers Edit `<spec-path>` — different sections, but same file. The Claude Code harness does not document atomic Edit serialization across concurrent subagents, so a TOCTOU race is possible. Sequential spawn costs ~1 extra minute of wall time and eliminates the race entirely. If the platform later guarantees Edit serialization, this command can switch to parallel — until then, A→B sequential is the contract.

### Step 3b (single-lens mode): Spawn one reviewer

```
Agent({
  subagent_type: "reviewer",
  description: "Review on <$1> diff (<lens>)",
  prompt: "
target: <diff-ref>
against: <--against value, or default for lens>
lens: <--lens value>
issue: $1
"
})
```

If `--against` was omitted, default per lens:
- `adherence` → spec path
- `quality` → quality canvas
- `logic` → spec path (cited references read from there)
- `scope` → plan.yaml for the stack
- `mixed` → spec path

### Step 4: Wait + join (paired mode only)

When both reviewers return, read both envelopes. Join:

```
joined_verdict = min(A.verdict, B.verdict)
                 # order: PASS > PASS_WITH_NOTES > REVISE > BLOCK
joined_findings = A.findings ∪ B.findings
                  # de-duplicated by (location, description) — same finding
                  # may surface under both lenses
```

### Step 5: Surface the joined verdict (paired) or the single verdict

Print:

```
Review complete on <$1>: <joined-verdict>
Adherence: <A.verdict> · <A.findings_count.blockers> blockers
Quality:   <B.verdict> · <B.findings_count.blockers> blockers
Spec phase sections written:
  - <spec-path>#diff-review-adherence
  - <spec-path>#diff-review-quality
```

Branch on joined verdict:
- `PASS` / `PASS_WITH_NOTES` → print `Gate 2.5 cleared. Next: validator (or merge under gate_mode: auto-all).`
- `REVISE` → print `Implementation needs revision. Next: /sdlc:develop <$1>.`
- `BLOCK` → print `Architectural conflict — human arbitration required.`

### Step 6: Post combined envelope

Emit a joined envelope (not the individual reviewer envelopes — those went to the phase sections). The joined envelope reuses the `reviewer` phase shape with an additional `joined: true` field rather than introducing a new phase mapping:

- `phase: reviewer`               (same as individual; envelope canvas doesn't need a new mapping)
- `joined: true`                  (top-level field — present means this is the multi-lens join, not a single reviewer's output)
- `verdict`: the joined verdict
- `findings_count`: summed across lenses (de-duplicated)
- `lenses_run`: [`adherence`, `quality`] (or [`<single>`] in single-lens mode)
- `artifact.paths`: array of both spec phase section paths (instead of singular `artifact.path`)

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| Joined verdict computed | Gate 2.5 (paired review) | Joined verdict ≠ REVISE/BLOCK |
| (downstream) | Gate 2 (PR review, if applicable) | Per `gate_mode`: human PR review under `interactive`, skipped under `auto-all` |

## Output (paired mode)

```
Review complete on ABC-101: PASS_WITH_NOTES
Adherence: PASS · 0 blockers
Quality:   PASS_WITH_NOTES · 0 blockers · 8 notes
Spec phase sections written:
  - .ai-docs/stacks/foo/specs/abc-101.md#diff-review-adherence
  - .ai-docs/stacks/foo/specs/abc-101.md#diff-review-quality

Gate 2.5 cleared. Next: validator (or merge under gate_mode: auto-all).
```

## Error Handling

- **No spec file**: halt — run `/design` first.
- **Empty diff**: halt — nothing to review.
- **Reviewer A or B returns mission error**: surface the error; do not join partial results.
- **One reviewer returns BLOCK, the other PASS**: joined verdict is BLOCK; do not proceed.

## When to use

- After the implementer commits but before validator runs (and before PR opens, under `gate_mode: auto-all`).
- After a `REVISE` cycle, to re-check the fixed implementation.
- Single-lens mode: spot checks during development (e.g., `--lens=quality` on a WIP commit to catch craft issues early).

## When NOT to use

- For pre-implementation spec critique — use [`/sdlc:critique`](./critique.md) (Gate 1.5).
- For automated style/lint checks — those belong to the [`validator`](../agents/validator.md), not the reviewer.
