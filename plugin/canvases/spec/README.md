# Spec artifact

Per-issue implementation strategy plus an append-only phase execution log. The static spec is detailed enough that an implementer can code without guessing; the phase log captures critique → addendum → implementation → review → validation as gates fire.

## Producer

- `specifier` agent (`.claude/agents/specifier.md`) — runs via `/design <KEY>`; writes the static spec sections.

## Phase contributors (write append-only into the phase log)

| Phase | Agent | Section | Trigger |
|---|---|---|---|
| Gate 1.5 critique | `reviewer` (lens=mixed) | Spec Review | `/sdlc:critique` |
| Gate 1.5 response | `specifier` (re-run) | Design Addendum | `/design` re-run after REVISE |
| Gate 2 implement | `implementer` | Implementation notes | `/sdlc:develop` |
| Gate 2.5 review | `reviewer` (lens=adherence) | Diff Review — Adherence | `/sdlc:review` |
| Gate 2.5 review | `reviewer` (lens=quality) | Diff Review — Quality | `/sdlc:review` |
| Gate 3 validate | `validator` | Live Validate | `/sdlc:develop` validator phase |

Each phase agent owns exactly one section. Append-only: agents Edit their own section in place (replacing the placeholder line); they never overwrite another phase's section.

## Consumers

- `implementer` agent — reads the spec, validates required sections, executes. Honors `implementer_view: annotated | clean` (clean strips phase sections at spawn time).
- `coordinator` agent — reads the spec to verify presence (Topology B).
- `validator` agent — reads PR body's spec link (or, in `gate_mode: auto-all`, the tracker comment's spec-file link).
- `reviewer` agent — reads the spec (for adherence lens) or the diff (for quality lens), appends its verdict to the correct phase section.
- `sdlc-loop` skill — references `instructions.yaml.sections.required` in halt messages.

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Pure structural skeleton with `{{token}}` placeholders + scaffolded phase headings (`_Awaiting <agent>._` placeholder lines). Renaming a section means editing this file *and* `instructions.yaml`. |
| `instructions.yaml` | Tunable knobs — section order, required sections, verbosity, **phases ownership map**, **append_mode**, **implementer_view**, diagrams, citations, tracker-comment shape. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Output paths

Per `.claude/sdlc.yml` `artifact_paths`:
- Stack-co-located (preferred): `.ai-docs/stacks/<slug>/specs/<issue-key>.md`
- Legacy fallback: `.ai-docs/specs/<issue-key>.md`

## How agents use these files

**Producer (specifier, on initial /design):**
1. Reads `template.md` and `instructions.yaml` at start.
2. Validates `instructions.yaml` against `instructions.schema.json` — halts on validation error.
3. Renders the template by substituting `{{tokens}}` per the verbosity / citation / diagram knobs in `instructions.yaml`.
4. Writes the populated document to the resolved spec path. The phase log sections (`Spec Review`, `Design Addendum`, etc.) ship with placeholder text — they fill in as gates fire.
5. Posts the tracker comment per `instructions.yaml.tracker_comment` knobs.

**Producer (specifier, on /design re-run after REVISE):**
1. Reads the existing spec file.
2. Applies critic corrections directly into the static spec sections (Goal / Approach / File-level plan / Interfaces / Tests).
3. Appends a `Design Addendum` section summarizing what changed and why.
4. Other phase sections remain untouched.

**Phase contributors (reviewer, implementer, validator):**
1. Read the spec at the resolved path.
2. Locate their owned section (per `instructions.yaml.phases`).
3. Replace the placeholder line with real content via Edit. Other sections remain untouched.
4. Emit the envelope per the envelope canvas.

**Consumers (implementer reading the static spec):**
1. Read the spec at the resolved path.
2. If `implementer_view: clean`, strip phase sections before consuming.
3. Read `instructions.yaml.sections.required` to know which static sections must be non-empty.
4. Halt with the missing-section name if any required section is empty or still contains a `{{token}}` placeholder.

## Knob reference

| Knob | Allowed values | Purpose |
|---|---|---|
| `append_mode` | bool | When true, phase sections are append-only — agents Edit their own section in place. |
| `implementer_view` | `annotated` / `clean` | annotated = read full file; clean = strip phase sections at spawn. Default `annotated`. |
| `phases.*.section` | string | H2 heading the phase agent writes to. Must match `template.md` verbatim. |
| `phases.*.owner` | agent name | Phase agent that writes this section. |
| `phases.*.gate` | number | Position in the gate ordering (1.5 = pre-impl critique; 2.5 = post-impl review; etc.). |
| `tracker_comment.mode` | `status_envelope` / `full_content` | status_envelope = ≤15-line pointer to spec file (recommended). full_content = inline content (legacy). |
| `tracker_comment.spec_link` | `permalink` / `branch_relative` | permalink = SHA-pinned (resolves immediately, permanent). branch_relative = 404s until merge (use only for inline-content mode). |

## Override

Edit `instructions.yaml` to tune behavior. Edit `template.md` to change structure (section names, ordering, frontmatter shape, scaffolded phase headings).

When this project ships as a plugin, plugin defaults are overridden by project-local `.claude/canvases/spec/` files via Claude Code's standard plugin overlay.

## Validation

Run `bash scripts/verify-canvases.sh` (when implemented) — validates each `instructions.yaml` against its schema. Pre-commit / CI hook candidate.

## Status envelope templates

When `tracker_comment.mode: status_envelope` (the default under `spec_storage: file`), each phase posts a ≤15-line envelope to the tracker. The envelope is a projection of the agent's full YAML envelope (per the `envelope` canvas) onto the tracker surface — it cites the spec phase section permalink rather than inlining content.

These shapes are stable across agents. Agents may add fields but should not remove required ones.

### [Design] envelope — posted by `specifier` after writing the static spec

```markdown
## [Design] <ISSUE-KEY> — <issue title>

**Spec file:** [`<spec-path>`](<permalink>) (§ Goal / Approach / File-level plan populated)
**Strategy (one line):** <single sentence summary>
**Touches:** `path/a.ts`, `path/b.ts`
**Open decisions:** <bullets or "none">
**Status:** awaiting Gate 1.5 critique
```

### [Spec Review] envelope — posted by `reviewer` after Gate 1.5 critique

```markdown
## [Spec Review] <ISSUE-KEY>

**Spec file:** [`<spec-path>`](<permalink>) § Spec Review (appended)
**Verdict:** PASS / PASS_WITH_NOTES / REVISE / BLOCK
**Findings:** <B> blockers · <N> notes · <K> nits
**Status:** <cleared for /sdlc:develop | specifier revising design | escalated>
```

### [Implement] envelope — posted by `implementer` after commit + push

```markdown
## [Implement] <ISSUE-KEY>

**Branch:** `<branch>` (stack position M of N, or "no PR — gate_mode: auto-all")
**Commit:** `<short-SHA>` — <commit subject>
**Files changed:** <count>: `path/a.ts`, `path/b.ts`, …
**Lint/types/tests:** PASS / FAIL <one-line detail>
**Status:** ready for /sdlc:review (Gate 2.5) and validator (Gate 3)
```

### [Diff Review — Adherence] / [Diff Review — Quality] envelopes — posted by `reviewer` after Gate 2.5

Same shape as [Spec Review] above; the section title differs and the **Lens** line is explicit:

```markdown
## [Diff Review — Adherence] <ISSUE-KEY>

**Spec file:** [`<spec-path>`](<permalink>) § Diff Review — Adherence (appended)
**Lens:** adherence (against the spec)
**Verdict:** PASS / PASS_WITH_NOTES / REVISE / BLOCK
**Findings:** <B> blockers · <N> notes · <K> nits
**Status:** <cleared for validate | implementer fixing | escalated>
```

### [Validate] envelope — posted by `validator` after Gate 3

```markdown
## [Validate] <ISSUE-KEY> — LIVE

**Command:** `<the validation cmd from spec or quality primitive>`
**Result:** PASS / FAIL
**Evidence:**
\`\`\`
<terminal output, ≤30 lines; truncate middle if longer>
\`\`\`
**Posted to:** PR #<n> | tracker comment (gate_mode: auto-all)
**Next:** <ISSUE-KEY+1> <title> | hold for human review
```

### [Done] envelope — posted by the lead session when handing off to human review

```markdown
## [Done] <ISSUE-KEY>

Branch `<branch>` ready for human review. Tracker status → In Review.
Drive moves to <next-key>.
```

### [Blocked] envelope — posted by any phase agent that halts mid-flight

```markdown
## [Blocked] <ISSUE-KEY>

**Problem:** <one line>
**Action taken:** <one line>
**Decision needed:** <yes/no — what>
```

Each agent's full structured envelope (the YAML block) is the source of truth; the markdown projections above are what humans read in the tracker. Render skill compatibility: the future render skill projects the YAML envelope to chat / tracker / pr / slack / log surfaces per [`canvases/envelope/instructions.yaml`](../envelope/instructions.yaml) `surfaces.*`. The tracker projections above match `surfaces.tracker.use_canvas: tracker-comment` (forward-ref).

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed knobs, changed enum values). Producers and consumers should fail loudly on unknown versions rather than degrade silently.

- **v1 → v2:** added phase log (6 new sections), `phases:` ownership map, `append_mode`, `implementer_view`, `tracker_comment.mode`, `tracker_comment.spec_link`. Old v1 specs continue to render — v2 readers just see the phase-log sections as empty placeholders.
