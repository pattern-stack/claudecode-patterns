# claudecode-patterns

**A Claude Code distribution for autonomous development with human gates, tracker-agnostic primitives, and a canvas-based artifact system.**

This repository ships an opinionated `.claude/` configuration layer designed for teams running Claude Code in production. It encodes:

- **Gate-disciplined workflows** — explicit human checkpoints at strategy approval and PR review
- **Tracker-agnostic SDLC** — Linear / GitHub Issues / Jira via the task-management primitive
- **Two execution topologies** — flat team (`/develop`) and parallel batch (`/orchestrate`)
- **Canvas-based artifacts** — specs, plans, observability sessions governed by template + instructions canvases
- **Dual-voice authoring** — developer-facing and seller-facing UX through swappable output styles

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  .claude/                                                   │
│  ├── sdlc.yml                  central config              │
│  ├── primitives/               language / quality / commit  │
│  │                             / task-management            │
│  ├── agents/                   6 SDLC phase agents +        │
│  │                             canvas-author + drift-check  │
│  ├── commands/                 /plan /design /develop       │
│  │                             /orchestrate /sync-issues    │
│  │                             /canvas                      │
│  ├── skills/                   claude-platform, sdlc-loop,  │
│  │                             skill-authoring, handoff,    │
│  │                             prime, canvas-authoring      │
│  ├── output-styles/            canvas-flow-{developer,      │
│  │                             seller}                      │
│  ├── artifacts/                spec, envelope, plan,        │
│  │                             session canvases             │
│  └── hooks/                    lifecycle event fan-out      │
└─────────────────────────────────────────────────────────────┘
```

## The gate-disciplined loop

```
Decompose → Strategy (HUMAN GATE) → Implementation → PR Review (HUMAN GATE) → Merge
```

Two human gates, everything else automated:

1. **Gate 0 (synchronous, in-chat)** — `/plan` decomposes a request into a YAML plan; you approve in chat before anything reaches the tracker
2. **Gate 1 (async, tracker-native)** — `/design` posts the implementation strategy as a tracker comment with `state:awaiting-strategy-review`; you approve via label
3. **Gate 2 (async, PR-native)** — Validator posts a quality report on the PR; you review code and merge

The implementer agent **refuses** to start without `state:strategy-approved`. Gates aren't conventions — they're load-bearing.

## Two topologies

| Topology | Command | When |
|---|---|---|
| **A — flat team** | `/develop ABC-101` | One issue at a time; full attention; iterative |
| **B — parallel batch** | `/orchestrate ABC-101 ABC-102 ABC-103` | Multiple approved issues; AFK throughput; one coordinator per issue |

Topology B uses worktree isolation (`isolation: "worktree"` in agent spawning) so parallel implementers don't collide.

## Canvas system

Artifacts produced by SDLC agents (specs, plans, validator reports, …) are governed by **canvases** — `template.md` + `instructions.yaml` + `instructions.schema.json` + `README.md` quartets under `.claude/canvases/<name>/`. Each canvas separates structure (template) from behavior (knobs).

Canvases are authored, tuned, and validated through the `canvas-author` agent in two voices:

| Voice | Launcher | For |
|---|---|---|
| **Developer** | `just canvas-dev` | System-fluent users — knobs, schemas, unified diffs, four-block scaffold |
| **Seller** | `just canvas-seller` | Outcome-thinking users — samples, conversation, mechanism hidden by default |

Both voices apply progressive disclosure: terse headlines by default, detail surfaced only when the user pulls. See [`.claude/skills/canvas-authoring/SKILL.md`](.claude/skills/canvas-authoring/SKILL.md).

## Quick start

### 1. Copy `.claude/` to your project

```bash
git clone https://github.com/pattern-stack/claudecode-patterns
cp -r claudecode-patterns/.claude your-project/
cp claudecode-patterns/Justfile  your-project/   # optional — verifier recipes
cp -r claudecode-patterns/scripts your-project/  # verifier + canvases scripts
```

### 2. Customize `sdlc.yml`

Edit `your-project/.claude/sdlc.yml` to set:

```yaml
language: typescript           # or python, go
quality_profile: strict        # or fast
commit_style: conventional
task_management: linear        # or github
team_key: YOUR_TRACKER_KEY     # tracker team key — used in branch convention + sync filters
```

Each value resolves to `.claude/primitives/<category>/<value>.md`. Add new values by dropping new files in the matching directory.

### 3. Verify

```bash
cd your-project
just verify                    # invariants check: tool groups + canvas schemas
```

### 4. Run the loop

```bash
/plan "Add Redis caching to user service"     # Gate 0 — iterate YAML plan
# (approve in chat)
/sync-issues                                   # push approved plan to tracker
/design ABC-101                                # Gate 1 — post strategy
# (approve via state:strategy-approved label)
/develop ABC-101                               # Topology A — flat team
# OR
/orchestrate ABC-101 ABC-102 ABC-103           # Topology B — parallel batch
```

## Component layers

The components are organized in dependency layers:

| Layer | Owns | Examples |
|---|---|---|
| **Configuration** | What this project's SDLC looks like | `sdlc.yml`, `primitives/` |
| **Platform reference** | What Claude Code itself supports | `skills/claude-platform/` |
| **Project SDLC overlay** | How to author components for this stack | `skills/skill-authoring/`, `skills/sdlc-loop/`, `skills/handoff/`, `skills/prime/` |
| **Workflow agents** | The actual gate-disciplined work | `agents/{planner,specifier,implementer,validator,coordinator,understander}.md` |
| **Slash commands** | User-facing entry points | `commands/{plan,design,develop,orchestrate,sync-issues}.md` |
| **Artifact registry** | Canvas-governed structured outputs | `artifacts/{spec,envelope,plan,session}/` |
| **Canvas authoring** | Tooling for tuning canvases via dialog | `agents/canvas-author.md`, `skills/canvas-authoring/`, `commands/canvas.md`, `output-styles/canvas-flow-*` |
| **Observability** | Lifecycle event fan-out + invariant checks | `hooks/emit.mjs`, `scripts/verify-*.sh`, `scripts/list-canvases.sh` |

## What changed from v1

This is a near-total architectural rewrite. The skeleton (decompose → spec → implement → validate) is preserved; the implementation differs.

| Concept | v1 | v2 |
|---|---|---|
| **Decomposition** | `commands/plan/{1,2,3}-*.md` (3-step sequential) | `/plan` skill → `planner` agent → YAML → `/sync-issues` |
| **Spec generation** | `commands/spec-generation/feature.md` | `/design` → `specifier` agent → spec canvas → tracker comment |
| **Implementation** | `commands/implement.md` | `/develop` (Topology A) / `/orchestrate` (Topology B) → subagents |
| **Validation** | `commands/test.md`, `analyze-implementation.md` | `validator` agent + report |
| **Tracker** | Linear-specific bootstrap (`setup-linear-team.md`, `setup-linear-labels.sh`) | Tracker-agnostic via `primitives/task-management/{linear,github}.md` |
| **Worktree** | `worktree-manager-skill` | `sdlc.yml.worktree:` config block |
| **Quality** | `quality-gates` skill | `validator` agent + `tool_groups` invariant verifier |
| **Canvases** | (none) | `artifacts/` registry with spec / envelope / plan / session canvases |
| **Output styles** | (none) | `canvas-flow-{developer,seller}` for dual-voice canvas authoring |
| **Verifiers** | (none) | `verify-tool-groups.sh`, `verify-canvases.sh`, `list-canvases.sh` |
| **Hook fan-out** | (none) | `hooks/emit.mjs` shim — POSTs lifecycle events to dashboard |

v1's `BOOTSTRAP-PLAN.md` is archived at [`.claude/docs/archive/v1-bootstrap-plan.md`](.claude/docs/archive/v1-bootstrap-plan.md) for historical reference.

## Verification

```bash
just verify                # all invariants
just verify-tool-groups    # agents have valid tool groups per sdlc.yml.tool_groups
just verify-canvases      # every canvas's instructions.yaml validates against its schema
just canvases              # list canvases on disk reconciled against sdlc.yml.canvases
```

These are designed to run in CI; pre-commit hook candidates.

## Where to read next

| If you want to | Go to |
|---|---|
| Understand the workflow end-to-end | [`WORKFLOW.md`](WORKFLOW.md) |
| Author a new skill / agent / output-style | [`.claude/skills/skill-authoring/SKILL.md`](.claude/skills/skill-authoring/SKILL.md) |
| Understand Claude Code platform fundamentals | [`.claude/skills/claude-platform/SKILL.md`](.claude/skills/claude-platform/SKILL.md) |
| Operate the SDLC loop on a real issue | [`.claude/skills/sdlc-loop/SKILL.md`](.claude/skills/sdlc-loop/SKILL.md) |
| Tune a canvas | `just canvas-dev` (developer voice) or `just canvas-seller` (outcome-framed) |
| Configure your project | [`.claude/sdlc.yml`](.claude/sdlc.yml) + [`.claude/primitives/README.md`](.claude/primitives/README.md) |

## License

MIT.
