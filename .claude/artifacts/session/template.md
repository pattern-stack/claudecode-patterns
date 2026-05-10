# Session canvas — template

This canvas describes a **directory contract**, not a single document. Each workflow command produces a session directory at session start and finalizes it at close. Sub-workflows (Topology B coordinator → implementer / validator) write into a subdirectory of the parent session.

## Directory layout

```
{{paths.base}}{{session.id}}/
├── session.json           # structured summary — machine-readable state
├── input.json             # original request that started the workflow
├── execution.log          # per-turn details — JSONL envelopes streamed in
├── summary.md             # closing render — human-friendly final report
└── {{subagent_workflow}}/ # optional — present when this is a parent session
    ├── input.json
    ├── execution.log
    └── output.json        # subagent's structured handoff to parent
```

## Two-tone observability

The session canvas captures the same workflow execution at two altitudes:

| Tone | File | Audience |
|---|---|---|
| **Summary** | `session.json` | Machine state — workflow status, timestamps, artifacts created, errors. Programmatic indexing and analytics. |
| **Discourse** | `execution.log` | Per-turn detail — every phase agent's envelope appended as JSONL. Human skim or machine replay. |
| **Render** | `summary.md` | Closing report — markdown summary suitable for human review or PR description. |
| **Provenance** | `input.json` | What the user asked for. Useful for "why did this run?" forensics. |

The envelope canvas's `surfaces.log: { format: jsonl }` IS the source of `execution.log`. Per-turn envelopes from every phase agent stream in chronologically. The session canvas owns the **destination**; the envelope canvas owns the **payload format**.

## session.json schema

```json
{
  "session_id": "{{session.id}}",
  "workflow": "{{workflow.name}}",
  "started_at": "{{iso8601_timestamp}}",
  "completed_at": "{{iso8601_timestamp_or_null}}",
  "status": "in_progress | completed | failed",
  "user_request": "{{free_text}}",
  "parent_session": "{{parent_session_id_or_null}}",

  "artifacts": {
    "issues_created":   ["{{issue_key}}", ...],
    "specs_generated":  ["{{path}}", ...],
    "files_modified":   ["{{path}}", ...],
    "commits":          ["{{sha}}", ...]
  },

  "errors": [
    {
      "timestamp": "{{iso8601}}",
      "phase": "{{phase_agent_name}}",
      "message": "{{free_text}}"
    }
  ]
}
```

The `artifacts` keys are configurable via `instructions.yaml.artifacts_tracked`. Custom workflows can add domain-specific keys (e.g., `prs_opened`, `tests_added`).

## summary.md template

```markdown
# {{workflow.name}} — session summary

**Session:** {{session.id}}
**Status:** {{status}}
**Duration:** {{duration_human}}

## Request
{{user_request}}

## Artifacts produced
{{rendered_artifacts_list}}

## Errors
{{rendered_errors_list_or_none}}

## Follow-ups
{{rendered_follow_ups}}
```

## Subagent mode

When a workflow command is invoked with `--parent-session-dir=<path>`, it writes into a subdirectory of the parent rather than creating a new top-level session. The subdirectory name matches the sub-workflow's name (e.g., a `coordinator` calling `implementer` produces `<parent>/implementer/`).

The parent session's `session.json` records the subagent invocation in its own `subagents:` array (added when present):

```json
{
  ...
  "subagents": [
    {
      "workflow": "implementer",
      "started_at": "{{iso8601}}",
      "completed_at": "{{iso8601_or_null}}",
      "status": "{{status}}",
      "subdir": "implementer/"
    }
  ]
}
```

## Producer responsibilities

Each workflow command (`/plan`, `/design`, `/develop`, `/orchestrate`) is responsible for:

1. **Init** — at workflow start: create `session_dir` (per `instructions.yaml.session_id.format`), write `input.json`, initialize `session.json` with `status: in_progress`.
2. **Stream** — during execution: append every phase agent envelope to `execution.log` as a JSONL line.
3. **Track** — as artifacts are produced: append IDs / paths to the appropriate `session.json.artifacts.<key>` list.
4. **Finalize** — at workflow close: write `summary.md`, update `session.json` with `completed_at` + final `status`.
5. **Errors** — on failure: append to `session.json.errors`; set `status: failed`; write `summary.md` describing what went wrong.

## Consumer responsibilities

Anything reading sessions (analytics, future render skill, PR-summary generators) should:

1. Treat `session.json` as the authoritative summary.
2. Use `execution.log` (JSONL) for replay or detailed forensics.
3. Render `summary.md` directly when surfacing to humans.
4. Walk `subagents:` recursively for nested workflow trees.

## File-format cheat sheet

| File | Format | Created by | Updated by | Schema |
|---|---|---|---|---|
| `session.json` | JSON | producer at init | producer throughout | section schema (this file) |
| `input.json` | JSON | producer at init | never (immutable) | producer-defined |
| `execution.log` | JSONL | producer at first turn | every phase agent (append-only) | one envelope per line — see envelope canvas |
| `summary.md` | Markdown | producer at finalize | never (final write) | template above |
