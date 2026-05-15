# Quality checks canvas

Registry of named **quality categories** that the [`reviewer`](../../agents/reviewer.md) agent uses as the input to the `quality` lens (Gate 2.5). Each category is a pattern the reviewer actively looks for in diffs — semantically meaningful issues that linters miss because they require reading intent, not syntax.

## Producer

- Plugin author (initial categories — see `categories.yaml`)
- Project authors (project-level overrides at `.claude/canvases/quality-checks/categories.yaml`, additive: extends the plugin set, never silently removes)

## Consumers

- [`reviewer`](../../agents/reviewer.md) agent with `lens=quality` — reads the categories file, treats each entry as a checklist item against the diff. Findings cite the category id (e.g. `category: convenient_fallback`).
- [`/sdlc:review`](../../commands/review.md) (paired mode) — passes this canvas as `against` to the quality reviewer (the spec-blind lens).

## Files in this directory

| File | Purpose |
|---|---|
| `categories.yaml` | The registry. Each entry has `id`, `name`, `description`, `patterns_to_flag`, `counter_examples`, `severity_hint`. |
| `categories.schema.json` | JSON Schema validating `categories.yaml`. |
| `README.md` | This file. |

## Why this canvas exists

The drive that surfaced this need (HubSpot CRM port, ENG-674..ENG-679) produced two-pass diff reviews on every PR. The quality lens consistently caught the same handful of patterns:

- **Convenient fallback values** — `list() returns []` unconditionally; `?? ''` coercing null into non-null domain fields; catch blocks that swallow errors. The bug is that the code lies about state: missing data looks like empty data, failures look like success.
- **Coding around your own framework** — subclass / wrapper / capturing-mechanism workarounds for the framework's public surface. Signal: fix the surface, not the symptom.
- **Repeated magic constants** — the same literal (page sizes, timeouts, retry counts) appearing 3+ times across files. The constant is looking for a name.

These categories aren't lintable in the syntactic sense — they require reading intent. They are, however, learnable: once a reviewer knows the category, it's recognized fast. Codifying the categories means every reviewer (human or agent) starts with the same checklist.

## How agents use this canvas

**Quality reviewer flow** (per `lens=quality`):

1. Read `categories.yaml` (project overrides over plugin defaults via the standard overlay).
2. Validate against `categories.schema.json` — halt on schema error.
3. For each category, scan the diff for matches. Use `patterns_to_flag` as heuristic prompts, not hard regex matches — a category match requires semantic judgment.
4. Skip false positives per `counter_examples`.
5. Emit findings with `category: <id>` on each. Severity defaults to the category's `severity_hint` but the reviewer can override per-finding.

## Override

Project authors who want to add categories or shift defaults create `.claude/canvases/quality-checks/categories.yaml` in the project. The overlay rule: project entries with the same `id` as a plugin entry **replace** that plugin entry; project entries with novel ids **extend** the registry. Removing a plugin category outright requires setting `disabled: true` on the project-level entry.

## Cross-references

- [`canvases/spec`](../spec/README.md) — phase sections the reviewer writes to (`Diff Review — Quality`)
- [`skills/critique`](../../skills/critique/SKILL.md) — the discipline; § "Lens taxonomy" explains why quality is spec-blind
- [`agents/reviewer`](../../agents/reviewer.md) — runtime that loads this canvas

## Versioning

`categories.yaml.version` increments on breaking changes (renamed/removed fields, changed `severity_hint` enum). Adding new categories or new fields is a non-breaking minor change.
