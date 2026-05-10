# Plan artifact

Per-stack issue decomposition. One YAML file per stack/epic, located at `.ai-docs/stacks/<slug>/plan.yaml`. Defines the parent epic + leaf issues + their dependencies + tracker metadata. Consumed by `/sync-issues` to materialize the stack as a tracker epic with sub-issues.

## Producer

- `planner` agent (`.claude/agents/planner.md`) — runs via `/plan <description>`

The planner iterates the YAML across chat turns based on human feedback, halting only on explicit approval (Gate 0 — synchronous, in-chat).

## Consumers

- `/sync-issues` command — reads the plan, creates the tracker epic + leaves, wires sub-issue parenting, applies blocking relations, sets project fields
- `specifier` agent — discovers stack slug by globbing `.ai-docs/stacks/*/plan.yaml` and matching the issue key
- `coordinator` agent — same discovery for Topology B
- `implementer` agent — same discovery for spec resolution
- `sdlc-loop` skill — references plan structure in cold-start primer

## Files in this directory

| File | Purpose |
|---|---|
| `template.md` | Pure structural skeleton with `{{token}}` placeholders. Renaming a field means editing this file *and* `instructions.yaml`. |
| `instructions.yaml` | Tunable knobs — required fields, sizing guidance, verbosity, idempotence markers. |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml`. |
| `README.md` | This file. |

## Output paths

Per `.claude/sdlc.yml` `artifact_paths`:
- Stack-co-located (preferred): `.ai-docs/stacks/<slug>/plan.yaml`
- Legacy: `.ai-docs/plans/<slug>.yaml` (pre-stack-convention)

## Key extensions (v1)

Beyond the original linear-only flat-issue list, the plan canvas v1 adds:
- **Epic shape** — `plan.epic_title` + `plan.epic_body` define the parent issue. `/sync-issues` creates this first, then chains `add-sub-issue` to wire each leaf as a child.
- **Stack topology** — `plan.stack.base` + `plan.stack.depends_on` (optional) record `st`-rooting and cross-stack ordering. Informational; doesn't gate sync.
- **Layer field** — `issue.layer` (L0–L7) sets the project's `Layer` custom field on the GitHub adapter (no-op on adapters without project field support).
- **Cross-repo** — `plan.repo` (optional) creates issues in a different repo than `sdlc.yml.repo`. Only adapters that support cross-repo (GitHub does; Linear's team-scoping doesn't) honor this.
- **Per-issue milestone override** — `issue.milestone` overrides `plan.milestone` for that one issue. Rare but useful when a single leaf needs to graduate ahead of the wave.

## Idempotence

Two markers — both written into issue bodies as footer lines:
- Epic marker: `[plan-epic:<plan.slug>]`
- Leaf marker: `[plan-key:<plan.slug>/<issue.key>]`

`/sync-issues` uses `find-by-marker` to detect existing issues and update rather than duplicate. The marker is stable across edits; renaming a `key:` in plan.yaml without first removing the marker from the existing issue creates an orphaned issue (the rename caveat — see `sdlc-loop`).

## Override semantics

Standard Claude Code overlay — project `.claude/canvases/plan/` overrides plugin `<plugin>/.claude/canvases/plan/`. Tune knobs by editing `instructions.yaml`; restructure by editing `template.md`.

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed fields in `template.md`, changed enum values in the schema). `/sync-issues` and the `planner` agent fail loudly on unknown versions.

## Related

- [`canvas-authoring`](../../skills/canvas-authoring/SKILL.md) — meta-knowledge for canvases
- [`/canvas tune plan`](../../commands/canvas.md) — adjust knobs
- [`sdlc-loop`](../../skills/sdlc-loop/SKILL.md) — workflow judgment that references plan section names
- [`/sync-issues`](../../commands/sync-issues.md) — consumer that materializes the plan to the tracker
- [`/plan`](../../commands/plan.md) — entry command that runs the planner producer
