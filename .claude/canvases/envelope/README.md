# envelope canvas

The **output envelope** every phase agent emits at end-of-phase. One schema, many surfaces — chat, tracker, slack, PR, log.

Distinct from other canvases (`spec`, `plan`, …) in two ways:
1. Output format is **YAML**, not markdown. Hence the unconventional fenced-YAML body inside `template.md`.
2. The artifact is **not written to disk** — it's emitted inline at the end of the agent's response, in a fenced YAML block.

## Producer

Every SDLC phase agent — `understander`, `planner`, `specifier`, `implementer`, `validator`, `coordinator`.

Each agent emits the envelope as the **last block** of its response on completion or halt (not on mid-iteration turns). The envelope sits below the human-readable summary the agent already prints.

Per-phase required fields and default attention surfaces are encoded in `instructions.yaml`.

## Consumers

| Consumer | What it reads | Status |
|---|---|---|
| **CLI (human reader)** | `headline`, `body`, `next.command` | Always rendered inline by the agent's response itself |
| **Dashboard log** | Full envelope as JSONL via `emit.mjs` `Stop`/`SubagentStop` hooks | Available now (envelope visible in transcript) |
| **Render skill** (planned) | Full envelope — projects to slack / tracker / pr surfaces | Planned post-v1 |
| **Other agents** | `next.command`, `gate_action`, `attention.dm` | When chained (e.g. coordinator reads child envelopes) |

## How a producer emits the envelope

1. At end-of-phase, gather the values for each field in `template.md`.
2. Validate against `instructions.yaml` `required_per_phase[<phase>]` — halt if any required field is null or still contains a `{{token}}` placeholder.
3. Validate length budgets per `instructions.yaml.length`.
4. Substitute tokens in `template.md` and emit the rendered YAML inside a ```` ```yaml ```` fence as the final block of the response.

Example (specifier completing ABC-101):

```yaml
phase: specifier
issue: ABC-101
stack: pm-toolbox-bridge
status: complete
artifact:
  path: .ai-docs/stacks/pm-toolbox-bridge/specs/ap-12.md
  type: spec
  size: 4203
gate_action:
  enforces: []
  sets: [awaiting-strategy-review]
headline: "Strategy posted for ABC-101 — awaiting human review"
body: |
  Files: create 4, modify 2.
  Approach: extract LinearProvider into ports/task-management.
  Open questions: should we batch comment writes? (see Open questions section in spec)
attention:
  surfaces: [chat, tracker, log]
  dm: []
next:
  command: null
  reason: "human approves via state:strategy-approved label"
metadata:
  duration_seconds: 47
  model: claude-opus-4-7
  cost_usd: 0.18
```

## How a consumer reads the envelope

The render skill (planned) reads the envelope, looks up the surface in `instructions.yaml.surfaces`, and projects per-rule. Until the render skill exists, consumers (dashboard, log scrapers) parse the YAML directly from the agent's transcript.

## Override semantics

Standard Claude Code overlay — project `.claude/canvases/envelope/` overrides plugin `<plugin>/.claude/canvases/envelope/`. Edit `instructions.yaml` to tune; edit `template.md` to add or remove fields (also update the schema).

## Versioning

`instructions.yaml.version` increments on breaking changes (renamed/removed fields in `template.md`, changed enum values in the schema). Producers and consumers fail loudly on unknown versions.

## Path

The envelope is **not written to disk** — it's emitted inline. `sdlc.yml` `artifacts.envelope` points to this canvas directory (the contract); not to an output path.

## Related

- [`canvas-authoring`](../../skills/canvas-authoring/SKILL.md) — meta-knowledge for canvases
- [`/canvas tune envelope`](../../commands/canvas.md) — adjust knobs
- [`sdlc-loop`](../../skills/sdlc-loop/SKILL.md) — workflow judgment that interprets envelopes' `next.command` and `gate_action`
