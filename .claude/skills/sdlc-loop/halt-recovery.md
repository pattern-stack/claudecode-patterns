# Halt recovery catalog

Every halt message any phase agent emits, what it means, and the recovery move.

## Specifier halts

### `Issue is already state:strategy-approved`
**Means:** the spec was previously approved; re-running would regress.
**Recovery:** confirm with the human before overwriting. If they want a fresh spec, drop the label first or accept the overwrite. Previous spec is in git.

### `state:awaiting-strategy-review label not provisioned on team`
**Means:** the Linear team is missing the gate labels.
**Recovery:** `bash scripts/setup-linear-labels.sh`.

### `Linear MCP unavailable`
**Means:** the configured tracker MCP is disconnected.
**Recovery:** check `/mcp`, reconnect or reauthenticate. The spec is **not** partially written — re-run `/design <KEY>` after reconnect.

## Implementer halts

### `<KEY> is not state:strategy-approved`
**Means:** Gate 1 enforcement. Either `/design` hasn't run, or the human hasn't approved.
**Recovery:** if no spec → `/design <KEY>`. If spec exists, ask human to review the Linear comment and add the label.

### `<KEY> is state:blocked`
**Means:** explicit block flag set by an earlier agent or human.
**Recovery:** read the issue's most recent comment for the blocker. Resolve, remove `state:blocked`, re-run.

### `spec missing — specifier did not run`
**Means:** no `.ai-docs/stacks/<slug>/specs/<key>.md` (or legacy `.ai-docs/specs/<key>.md`).
**Recovery:** `/design <KEY>`.

### `spec is incomplete — <section> is empty`
**Means:** specifier ran but a required section (per `.claude/artifacts/spec/instructions.yaml` `sections.required`) is empty or still contains a `{{token}}` placeholder.
**Recovery:** re-run `/design <KEY>` to overwrite. If repeated, the issue is in one of three places — check in order:
1. `.claude/artifacts/spec/template.md` — placeholder token may not have been rendered.
2. `.claude/artifacts/spec/instructions.yaml` — `sections.required` may list a section the template doesn't have.
3. Specifier prompt — section-render logic may be wrong.

### `quality gate failed: <gate>`
**Means:** typecheck or other active gate failed mid-implementation.
**Recovery:** the implementer fixes the underlying issue (don't suppress it). It re-runs the gate. If you want to take over, halt the agent, read the failure, fix manually.

## Validator halts

### `branch not found locally or remotely`
**Means:** validator was invoked with a branch that doesn't exist.
**Recovery:** confirm the implementer pushed; re-run with the correct branch name.

### `<gate>: blocking failure`
**Means:** a configured active gate failed (typecheck, build).
**Recovery:** validator does **not** fix. The implementer takes over. Re-run validator after.

### `<gate>: skipped — deferred per primitive`
**Not** a halt — informational. Listed in the report for visibility. Activate the gate by editing the primitive when ready.

## Coordinator halts (Topology B)

### `awaiting human approval`
**Means:** the implementer subagent halted at Gate 1 (defense-in-depth check).
**Recovery:** see implementer halts above. Coordinator surfaces the halt verbatim.

### `spec missing — specifier did not run`
**Means:** coordinator's pre-spawn check found no spec on disk.
**Recovery:** `/design <KEY>`. Coordinator does not re-spawn automatically; you re-run `/orchestrate` against the issue once the spec exists.

### `state:blocked`
**Means:** explicit block.
**Recovery:** as for implementer.

### `topology mismatch — needs:<agent> requires Topology A`
**Means:** the issue carries `needs:browser-pilot` (or similar), which `/orchestrate` should have dropped. If you see this from the coordinator, `/orchestrate`'s filter missed it.
**Recovery:** run the issue via `/develop` instead.

## Planner halts

The planner does not halt — it iterates until human approval. If the plan looks wrong, give feedback in chat. Approval keywords: `ship it`, `looks good`, `approved`, `go ahead`. Anything ambiguous keeps the loop running.

## Understander halts

The understander does not halt — it produces both an artifact and a chat summary. If you need different scope, send a follow-up turn.

## /sync-issues halts

### `validation failed: <field> missing`
**Means:** the YAML doesn't conform — missing `plan.slug`, `plan.team_key`, `plan.summary`, or an issue's `key` / `title` / `description`.
**Recovery:** re-open the YAML, fix the field, re-run `/sync-issues`.

### `dependency cycle in YAML: <path>`
**Means:** `depends_on` chains form a cycle.
**Recovery:** edit YAML to break the cycle, re-run.

### `Linear API error mid-sync`
**Means:** partial sync; some issues created, some not.
**Recovery:** re-run `/sync-issues` — already-created issues are detected by the `[plan-key:...]` marker, idempotent. Failures will retry.

## When to escalate

If a halt repeats after recovery, the underlying agent prompt or primitive is likely wrong. Capture the halt verbatim, file an issue (or a stack), and address with `/design` against the agent file itself.
