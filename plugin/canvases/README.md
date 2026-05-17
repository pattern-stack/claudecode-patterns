# Artifact registry

Each subdirectory under `.claude/canvases/` defines one **canvas** — the contract for one kind of document the SDLC produces (specs, plans, validator reports, PR bodies, …). A canvas separates the artifact's **structure** (template) from its **behavior** (instructions), so each can evolve at its own cadence.

## What lives in each canvas

```
<name>/
├── README.md                  # what this artifact is, who produces, who consumes, paths
├── template.md                # pure structural skeleton with {{token}} placeholders
├── instructions.yaml          # tunable knobs (verbosity, diagrams, citations, length, …)
└── instructions.schema.json   # JSON Schema validating instructions.yaml
```

The four files are co-located so a canvas is a complete, self-describing unit. Renaming, reordering, or extending the structure means editing `template.md` AND `instructions.yaml`. Behavioral knobs (verbosity, diagram tool, citation strictness) are tuned by editing `instructions.yaml` only.

## Why split structure from behavior

- **Different change cadence.** Section order rarely changes; verbosity changes often.
- **Tuning becomes mechanical.** "Add Mermaid diagrams to the Approach section" is a one-line YAML knob, not a system-prompt revision in an agent.
- **Multiple consumers see the same canonical shape.** Producer and consumers all read the same files; no schema drift.
- **Plugin-friendly.** When this project ships as a plugin, plugin defaults are overridden by project-local files via standard Claude Code overlay. No new mechanism.

## Layer position

The artifact registry is **a parallel layer to `primitives/`**:

| Layer | Captures | Read by |
|---|---|---|
| `primitives/<category>/<value>.md` | Project conventions (language, quality, commit, tracker) | Agents, on demand |
| `artifacts/<name>/{template,instructions,schema,README}` | Document schemas (spec, plan, …) | Agents (producers + consumers), on demand |

Both are configuration data for the SDLC. Neither belongs inside an agent's prompt.

## How agents use a canvas

**Producer:**
1. Read `template.md` and `instructions.yaml` at start of work.
2. Validate `instructions.yaml` against `instructions.schema.json` (halt on validation error).
3. Render the template by substituting `{{tokens}}` per the verbosity / citation / diagram knobs.
4. Write the populated artifact to the resolved path (per `sdlc.yml.artifact_paths`).
5. Honor any auxiliary knobs (e.g. tracker-comment shape).

**Consumer:**
1. Read the artifact at the resolved path.
2. Read `instructions.yaml` `sections.required` to know which sections must be non-empty.
3. Halt with the missing-section name if any required section is empty or still contains a `{{token}}` placeholder.

## Override semantics

Filesystem overlay, no special mechanism:

| Source | Path |
|---|---|
| Plugin defaults (when shipped) | `<plugin>/.claude/canvases/<name>/…` |
| Project local | `.claude/canvases/<name>/…` |

Project-local files override plugin defaults via Claude Code's standard plugin overlay. Edit `instructions.yaml` to tune; edit `template.md` to restructure.

## Authoring canvases

Don't author canvases by hand — use the [`canvas-authoring`](../skills/canvas-authoring/SKILL.md) skill and the [`canvas-author`](../agents/canvas-author.md) agent. They guide creation, tuning, validation, reverse-modeling from examples, and explanation through a probing dialog with full schema awareness. Entry point: `/canvas <mode> [name]`.

## Validation

`scripts/verify-canvases.sh` validates every `instructions.yaml` against its sibling `instructions.schema.json` (auto-detects the JSON Schema draft from each schema's `$schema` URI). Run via `just verify-canvases` (or `just verify` to also run `verify-tool-groups`). Pre-commit / CI hook candidate.

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed knobs, changed enum values). Producers and consumers fail loudly on unknown versions rather than degrade silently.

## Family subfolders

Most canvases live flat under `canvases/<name>/` — they're cross-cutting (every domain uses them, no surface-specific parser rules). Canvases that share **parser-sensitive syntax** for a specific surface get grouped into a family subfolder with a `CONVENTIONS.md` next to them:

| Family | Surface | Shared conventions |
|---|---|---|
| [`github/`](github/README.md) | GitHub PRs + issues + Projects | Closing keywords, `[plan-key:]` markers, sub-issue rollup, Issue Types, Status field options |

The pattern: subfolder when canvases share a surface-specific parser rule set (otherwise the same rules drift across each canvas's README independently); flat when they're cross-cutting. If Linear-native artifact canvases ever ship, they'd sit in a peer `linear/` folder with their own `CONVENTIONS.md` (different keywords, key-shaped identifiers, no Issue Types).

## Current canvases

| Name | Producer | Consumers | Status |
|---|---|---|---|
| [`spec/`](spec/README.md) | `specifier` | `implementer`, `coordinator`, `validator` | Active (proving ground) |
| [`envelope/`](envelope/README.md) | every phase agent | CLI (always); render skill (planned) → slack / tracker / pr / log | Active |
| [`plan/`](plan/README.md) | `planner` | `/sync-issues`, `specifier`, `coordinator`, `implementer`, `sdlc-loop` | Active |
| [`session/`](session/README.md) | every workflow command (`/plan`, `/design`, `/develop`, `/orchestrate`, `/sync-issues`) | humans browsing past sessions; future render skill; analytics | Active (two-tone observability — `session.json` + `execution.log` + `summary.md`) |
| [`proposal/`](proposal/README.md) | human author / `sdlc-author` | human reviewer; downstream `planner` once `accepted` | **Beta** (v1 — tuned to design-loop port; deliberately minimal ADR+RFC hybrid; shipped without full review) |
| `understanding/` | `understander` | `planner`, `specifier`, `coordinator` | Planned |
| `validator-report/` | `validator` | PR review | Planned |
| [`github/`](github/README.md) | — (family folder) | — | Active (CONVENTIONS.md + family README; member canvases authored in follow-up PRs) |
| `github/pr-body/` | `implementer`, `specifier`, docs-author | GitHub | Planned (v1 of family) |
| `github/issue-body/` | `/sync-issues`, `planner` | GitHub | Planned (v1 of family) |
| `github/epic-body/` | `/sync-issues`, `planner` | GitHub | Planned (v1 of family) |
| `tracker-comment/` | `specifier`, `validator` | Tracker UI | Currently embedded in spec/ |
| `coordinator-status/` | `coordinator` | Orchestrator | Planned |

## Related

- [`canvas-authoring`](../skills/canvas-authoring/SKILL.md) — the skill teaching how to author canvases
- [`canvas-author`](../agents/canvas-author.md) — the agent running the authoring conversation
- [`/canvas`](../commands/canvas.md) — the entry command
- [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) — workflow judgment that references artifact section names
