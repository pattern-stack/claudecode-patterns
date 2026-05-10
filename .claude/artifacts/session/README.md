# Session canvas — workflow observability

Captures the shape of every workflow execution as a structured directory: status + artifacts produced + per-turn discourse + closing summary. Ports the v1 `commands/shared/session-logging.md` pattern (from `pattern-stack/claudecode-patterns`) into the v2 artifact-pattern system, so observability is a tunable canvas alongside `spec/` and `envelope/` rather than an inline command convention.

## Producer

Every workflow command:

| Command | Workflow name | When session opens |
|---|---|---|
| `/plan` | `plan` | User invokes decomposition |
| `/design` | `design` | User invokes spec generation for an issue |
| `/develop` | `develop` | User invokes Topology A flow for an issue |
| `/orchestrate` | `orchestrate` | User invokes Topology B parallel batch |
| `/sync-issues` | `sync-issues` | User syncs an approved plan to the tracker |

Each command:
1. Initializes a session directory (per `instructions.yaml.session_id.format`)
2. Writes `input.json` with the original request
3. Streams every phase agent's envelope to `execution.log` (JSONL)
4. Tracks artifacts in `session.json.artifacts.<key>` as they're produced
5. Finalizes with `summary.md` at workflow close (or on error)

When a sub-workflow is invoked (e.g. `/orchestrate` calling implementer subagents), the producer accepts `--parent-session-dir=<path>` and writes into a subdirectory of the parent rather than creating a new top-level session.

## Consumers

| Consumer | What they read | For |
|---|---|---|
| **Humans** browsing past sessions | `summary.md`, then drill into `execution.log` if needed | Forensics, retros, "why did this run go sideways?" |
| **Future render skill** (planned) | `session.json` + `execution.log` | Project per-surface (slack, tracker, pr, log) |
| **Analytics / dashboards** (planned) | `session.json` index across all sessions | Throughput, error rates, time-to-completion |
| **PR-summary generators** | `summary.md` | Auto-populate PR descriptions from session output |

## Two-tone observability

The canvas captures the same execution at two altitudes:

| Tone | File | What it owns |
|---|---|---|
| **Summary** (structured) | `session.json` | Workflow status, timestamps, artifact IDs, errors. Machine-indexable. |
| **Discourse** (per-turn) | `execution.log` | Every phase agent's envelope as JSONL. Human-skimmable, machine-replayable. |
| **Render** (closing) | `summary.md` | Markdown report — human-friendly final view. |
| **Provenance** | `input.json` | Original request. Immutable. |

The split is load-bearing: humans want skimmable narrative (`summary.md`), machines want indexable state (`session.json`), and forensics need replay (`execution.log`). One file would compromise all three.

## Connection to the envelope canvas

The envelope canvas owns the **format** every phase agent emits at end of run. The session canvas owns the **destination** those envelopes accumulate into. The forward reference in `envelope/instructions.yaml`:

```yaml
surfaces:
  log:
    show: ["*"]
    format: jsonl
```

…is realized when the active session writes those envelopes to `<session_dir>/execution.log`. The two canvases are intentionally split because they evolve at different cadences: the envelope shape changes when phase agents change; the session structure changes when observability needs change.

## Output paths

```
agent-logs/<session_id>/
├── session.json           # always present; updated incrementally
├── input.json             # always present; written once
├── execution.log          # always present; appended per turn
├── summary.md             # written at workflow close (or on error)
└── <subagent_workflow>/   # present only when this is a parent session
```

`agent-logs/sessions.json` (optional, per `instructions.yaml.paths.index_file`) is a flat index of all sessions for quick listing.

## Override semantics

Standard Claude Code overlay:

| Source | Path |
|---|---|
| Plugin defaults (when shipped) | `<plugin>/.claude/artifacts/session/…` |
| Project local | `.claude/artifacts/session/…` |

Edit `instructions.yaml` to tune (session ID format, retention, what's tracked); edit `template.md` to change the directory contract.

## Validation

`just verify-artifacts` validates this canvas's `instructions.yaml` against `instructions.schema.json` like every other canvas.

## Status

**Active.** Producers (workflow commands) write sessions; consumers (humans, future render skill) read. Subagent-mode (Topology B parent → child sessions) is supported but underexercised — when `/orchestrate` runs in production, that flow gets stress-tested.

## Disabling per-workflow

Short or read-only commands can opt out of session logging via `instructions.yaml.enabled: false`. Useful for read-only commands that don't materially change state. Default is `true` — observability on by default.

## Related

- [`spec/`](../spec/README.md) — the spec canvas (specifier produces; implementer / coordinator / validator consume)
- [`envelope/`](../envelope/README.md) — cross-surface output wrapper every phase agent emits at end of turn (source of `execution.log` lines)
- [`plan/`](../plan/README.md) — the plan canvas (planner produces; /sync-issues consumes)
- [`canvas-authoring`](../../skills/canvas-authoring/SKILL.md) — meta-skill for tuning / validating / extending canvases
