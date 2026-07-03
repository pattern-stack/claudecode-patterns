---
description: Gate 1.5 — single-reviewer spec critique. Spawns the reviewer agent with lens=mixed against cited code; writes verdict + findings to the spec's Spec Review phase section. Verdict PASS/PASS_WITH_NOTES clears Gate 1.5; REVISE triggers specifier re-run; BLOCK halts for human arbitration.
argument-hint: [issue-key]
allowed-tools: Read, Bash, Agent
primitives:
  required:
    - task_management
status: active
topology: none
consumes: [issue, spec]
produces: [verdict, phase-section, comment]
gates:
  enforces: []                # Gate 1.5 doesn't enforce a tracker label; it requires a spec file
  sets: []                    # the reviewer's verdict drives next-command branching, not a label
---

# /sdlc:critique

Gate 1.5 — pre-implementation spec critique. Spawns the [`reviewer`](../agents/reviewer.md) agent (which loads the [`critique`](../skills/critique/SKILL.md) skill) to read the spec against cited code, identify defects, and write a structured verdict to the spec's **Spec Review** phase section.

This gate sits between `/design` (specifier writes spec; sets `state:awaiting-strategy-review`) and human approval (sets `state:strategy-approved`). It catches the bugs a first-pass designer agent typically misses — wrong line numbers, miscounted call sites, missed constraints, citation drift — before the implementer runs and the cost compounds.

> **Workflow judgment** — for halt recovery from REVISE / BLOCK, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Working tree state (pre-rendered)

Branch: !`git branch --show-current`
Status: !`git status --short`

## Usage

```
/sdlc:critique <ISSUE-KEY>
```

`$1`: tracker issue key (e.g. `ABC-101`).

Optional second argument: `--lens=<lens>` to override the default `mixed` lens. Other lenses make sense for ad-hoc / non-spec critiques but are unusual at Gate 1.5.

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `task-management/{value}` | primitive | Issue resolution, envelope post routing |
| [`reviewer`](../agents/reviewer.md) | agent | Runs the critique mission in an isolated context |
| [`critique`](../skills/critique/SKILL.md) | skill | The discipline (loaded by reviewer) |
| [`canvases/spec`](../canvases/spec/README.md) | canvas | Defines the Spec Review phase section |

## Steps

### Step 1: Resolve config

Read `.claude/sdlc.yml`. Capture `task_management`, `quality_profile`, and `phase_models` (for the reviewer spawn override in Step 4).

### Step 2: Resolve issue + spec

Use the configured tracker's get-issue MCP to read `$1`. Capture title, description, labels.

Resolve the spec path per `.claude/sdlc.yml` `artifact_paths`:
- Stack-co-located (preferred): glob `.ai-docs/stacks/*/specs/<issue-key-lowercase>.md`
- Legacy fallback: `.ai-docs/specs/<issue-key-lowercase>.md`

If no spec file exists, halt:
> ⏸  No spec found for `$1`. Run `/design $1` first.

### Step 3: Detect re-run vs first-run

Read the spec file's `## Spec Review` section. Determine whether this is the first critique or a re-run after REVISE:

- If the section contains the placeholder line `_Awaiting spec critic._` → **first run**. `rerun = false`.
- If the section contains a prior verdict (look for `**Verdict:** ` line) → **re-run** (the specifier presumably wrote a Design Addendum in response to the prior REVISE; we're re-checking). `rerun = true`.

The reviewer halts on re-run unless explicitly told `rerun: true` — this command sets the flag automatically when it detects prior content.

### Step 4: Spawn the reviewer

```
Agent({
  subagent_type: "reviewer",          # plugin agent registered as bare name (no `sdlc:` prefix)
  description: "Critique <$1> spec (mixed lens)",
  model: <sdlc.yml phase_models.reviewer, if set — else OMIT this line>,
  prompt: "
target: <resolved-spec-path>
against: cited-code
lens: mixed
issue: $1
phase_section: Spec Review
rerun: <true if Step 3 detected prior content; false otherwise>
"
})
```

**Model policy**: include `model:` only when `sdlc.yml.phase_models.reviewer` is set; otherwise omit it and let `reviewer.md`'s frontmatter default stand.

Reviewer runs the critique discipline (`skills/critique/SKILL.md`), writes findings to the spec's Spec Review phase section (overwriting prior verdict on re-run), posts a tracker envelope, returns.

### Step 5: Surface the verdict

Parse the final fenced ` ```yaml ... ``` ` block from the reviewer's response (per the envelope canvas — every phase agent emits the envelope as the final block). Read:

```
Critique complete on <$1>: <verdict>
Spec phase section: <spec-path>#spec-review
Findings: <B> blockers / <N> notes / <K> nits
```

Branch on verdict:
- `PASS` / `PASS_WITH_NOTES` → print `Gate 1.5 cleared. Next: /sdlc:develop <$1>` (or human approval if Gate 1 is human-gated)
- `REVISE` → print `Spec needs revision. Next: /design <$1>` (specifier re-runs to write Design Addendum + correct static sections)
- `BLOCK` → print `Architectural conflict — human arbitration required. See spec phase section for details.`

### Step 6: Done

The reviewer has already posted the tracker envelope and written the spec phase section. This command exits.

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| Reviewer writes Spec Review section | Gate 1.5 (critique) | Verdict ≠ REVISE/BLOCK |
| (downstream) | Gate 1 (strategy approved) | Per `gate1_default` / `gate:*` label resolution |

Gate 1.5 fires automatically based on verdict; Gate 1 is the existing strict/auto resolution. Gate 1.5 PASS is a necessary-but-not-sufficient signal for Gate 1 in strict mode.

## Output

```
Critique complete on ABC-101: PASS_WITH_NOTES
Spec phase section: .ai-docs/stacks/foo/specs/abc-101.md#spec-review
Findings: 0 blockers / 3 notes / 2 nits

Gate 1.5 cleared. Next: /sdlc:develop ABC-101
```

## Error Handling

- **No spec file**: see Step 2.
- **Reviewer returns BLOCK**: print the verdict + cite the spec phase section; do not advance.
- **Reviewer halts with mission error** (missing required field, lens-target mismatch): surface the error and abort.

## When to use

- After `/design <KEY>` writes the initial spec.
- Before requesting human approval on Gate 1 (strict mode) — Gate 1.5 catches the bugs that would waste human review time.
- After a `REVISE` cycle, to re-check the addendum-corrected spec.

## When NOT to use

- For post-implementation review of a diff — use [`/sdlc:review`](./review.md) instead (Gate 2.5, paired lenses).
- For ad-hoc critique of a non-spec artifact (ADR, plan, RFC) — spawn the reviewer directly with a different `target` + `against` rather than going through this command, which assumes a spec phase section exists.
