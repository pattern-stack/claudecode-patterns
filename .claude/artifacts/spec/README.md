# Spec artifact

Per-issue implementation strategy. Detailed enough that an implementer can code without guessing; abstract enough that it isn't yet code.

## Producer

- `specifier` agent (`.claude/agents/specifier.md`) — runs via `/design <KEY>`

## Consumers

- `implementer` agent — reads the spec, validates required sections, executes
- `coordinator` agent — reads the spec to verify presence (Topology B)
- `validator` agent — reads PR body's spec link
- `sdlc-loop` skill — references `instructions.yaml.sections.required` in halt messages

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Pure structural skeleton with `{{token}}` placeholders. Renaming a section means editing this file *and* `instructions.yaml`. |
| `instructions.yaml` | Tunable knobs — section order, required sections, verbosity, diagrams, citations, tracker-comment shape. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Output paths

Per `.claude/sdlc.yml` `artifact_paths`:
- Stack-co-located (preferred): `.ai-docs/stacks/<slug>/specs/<issue-key>.md`
- Legacy fallback: `.ai-docs/specs/<issue-key>.md`

## How agents use these files

**Producer (specifier):**
1. Reads `template.md` and `instructions.yaml` at start.
2. Validates `instructions.yaml` against `instructions.schema.json` — halts on validation error.
3. Renders the template by substituting `{{tokens}}` per the verbosity / citation / diagram knobs in `instructions.yaml`.
4. Writes the populated document to the resolved spec path.
5. Posts the tracker comment per `instructions.yaml.tracker_comment` knobs (max chars, included sections, signature, files-list-inline flag).

**Consumers (implementer, coordinator, validator):**
1. Read the spec at the resolved path.
2. Read `instructions.yaml` `sections.required` to know which sections must be non-empty.
3. Halt with the missing-section name if any required section is empty or still contains a `{{token}}` placeholder.

## Override

Edit `instructions.yaml` to tune behavior (verbosity, diagram tool, citation strictness, comment shape). Edit `template.md` to change structure (section names, ordering, frontmatter shape).

When this project ships as a plugin, plugin defaults are overridden by project-local `.claude/artifacts/spec/` files via Claude Code's standard plugin overlay.

## Validation

Run `bash scripts/verify-artifacts.sh` (when implemented) — validates each `instructions.yaml` against its schema. Pre-commit / CI hook candidate.

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed knobs, changed enum values). Producers and consumers should fail loudly on unknown versions rather than degrade silently.
