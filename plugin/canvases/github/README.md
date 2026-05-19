# GitHub canvas family

Canvases here govern artifacts that live on **GitHub** — PR bodies, issue / epic / project bodies, PR review comments, epic synthesis comments, and (future) issue comments + PR comments. They share a set of parser-sensitive conventions (closing keywords, `[plan-key:]` markers, sub-issue rollup, Issue Types, Status field options) that don't apply to other surfaces.

The shared conventions live in **[`CONVENTIONS.md`](./CONVENTIONS.md)**. Every canvas in this family draws from it instead of restating the same enums and parser constraints. The `canvas-author` agent loads it as context whenever it's tuning, validating, or authoring a canvas in this family.

## What this family covers

```
github/
├── CONVENTIONS.md              ← shared anti-patterns + reference enums (THIS IS THE LOAD-BEARING DOC)
├── README.md                   ← (you are here) family overview + roadmap
│
├── pr-body/                    ← planned v1 — PR description authoring
├── issue-body/                 ← planned v1 — leaf-issue / task body authoring
├── epic-body/                  ← planned v1 — epic + project body authoring
│
├── pr-review-comment/          ← future migration from project-local
├── epic-review-synthesis/      ← future migration from project-local
│
└── (future)
    ├── pr-comment/             ← single-purpose conversational PR comments
    ├── pr-review/              ← formal review surface (different from pr-review-comment)
    ├── issue-comment/          ← status updates + closing-summary comments
    └── falsifier-diary-entry/  ← diary lines specs reference
```

## Why a subfolder

Canvases that share parser-sensitive syntax should share a conventions doc — otherwise the same rules (closing-keyword format, `[plan-key:]` markers, Layer enum) get restated across every canvas and drift independently. A family subfolder makes the shared context discoverable and locates the conventions doc next to the canvases that draw from it.

This is the first such family. If Linear-native artifact canvases ever ship, they'd sit in a peer `linear/` folder with their own `CONVENTIONS.md` (different parser rules: Linear's closing keywords are different, identifiers are key-shaped not numeric, no Issue Types). The pattern generalizes; the github family is the worked example.

The pre-existing canvases (`spec`, `plan`, `envelope`, `session`, `quality-checks`) stay flat — they're cross-cutting (every domain uses them, no shared parser surface). Subfolder when canvases share a **surface-specific** parser rule set; flat when they're cross-cutting.

## Canvas roadmap

### v1 (incremental)

| Canvas | Authoring path | Primary purpose |
|---|---|---|
| `pr-body` | `/sdlc:canvas new pr-body` | Producer = specifier / implementer / docs-author. Renders PR description with structured `closing_references` knob (eliminates the prose-between-keyword-and-reference bug class). Two orthogonal axes: `commit_type` (conventional commits enum) drives title prefix; `sdlc_role` (`spec / impl / followup / hotfix / release / docs / tooling`) drives section requirements. |
| `issue-body` | `/sdlc:canvas new issue-body` | Producer = `/sync-issues` + planner. Renders leaf-issue (task) body with structured `[plan-key:]` marker, typed `parent_epic_ref`, `layer` knob (L0..L7), `depends_on` list. |
| `epic-body` | `/sdlc:canvas new epic-body` | Producer = `/sync-issues` + planner. Renders epic + project body with `epic_kind: epic \| project`, structured `[plan-epic:]` marker, `child_stacks_block` (informational rollup). |

### v2 (later)

- `pr-comment` — single-purpose comments (the `Implementation: PR #N` backfill we use today)
- `pr-review` — formal review surface (line-anchored inline comments, GitHub review.event mapping)
- `issue-comment` — status updates + closing-summary comments (the `Closing — …` shape used when closing epics)
- `falsifier-diary-entry` — diary lines specs reference in falsifier-tracked issues

### Pending migration from project-local

`pr-review-comment` and `epic-review-synthesis` currently live as project-local canvases in `pattern-stack/dealbrain-integrations` `.claude/canvases/`. Moving them upstream into this family is a follow-up coordinated PR (delete from project-local + add here + update the `pr-reviewer` agent + `stack-review` skill references). Not bundled with v1 because it touches a second repo.

## How agents use the family

Same as any canvas (see top-level `plugin/canvases/README.md`):
1. Producer reads `template.md` + `instructions.yaml` for its canvas.
2. Validates `instructions.yaml` against `instructions.schema.json`.
3. Renders the template with typed knob inputs.
4. The `canvas-author` agent additionally loads `CONVENTIONS.md` to surface anti-patterns specific to this family.

The **typed-input principle** matters most here. The whole reason `pr-body`'s `closing_references` is a structured list rather than a freeform string is that producers should never construct parser-sensitive markdown by string concatenation. The canvas owns the rendering; the producer owns the data.

## Related

- [`CONVENTIONS.md`](./CONVENTIONS.md) — shared conventions + anti-pattern catalog
- [`plugin/canvases/README.md`](../README.md) — canvas system overview
- [`plugin/canvases/plan/instructions.yaml`](../plan/instructions.yaml) — plan canvas (source of `layer.enum`, `markers.{epic,leaf}`)
- [`plugin/primitives/task-management/github.md`](../../primitives/task-management/github.md) — GitHub adapter (source of label palette, Issue Type, Status options, branch + commit conventions)
- [`plugin/primitives/commit/conventional.md`](../../primitives/commit/conventional.md) — conventional commit types
- [`plugin/skills/canvas-authoring/SKILL.md`](../../skills/canvas-authoring/SKILL.md) — the `canvas-author` agent's preloaded knowledge
