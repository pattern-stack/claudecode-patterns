# Upstream (Claude Code harness): failed teammate reported as `completed`

**Date:** 2026-05-24
**Status:** out-of-plugin-scope — file with the Claude Code team. Tracked here so the SDLC plugin's mitigation (below) has a referent.
**Source:** gap #4 in [`develop-workflow-gaps.md`](./develop-workflow-gaps.md).

## Symptom

A `validator` teammate spawned under `/develop` died on `API Error: Overloaded`. The task-completion notification surfaced it as **`status: completed`**. It was caught only because:

- the `result` field carried the error string, and
- the token count was implausibly low (~4k for what should have been a multi-gate run).

Had a human not been reading the result, an AFK `/orchestrate` run would have treated a broken/empty validation as a pass and advanced the gate.

## Why it matters

The notification's `status` conflates **"the process exited"** with **"the task succeeded."** Any consumer that branches on `status == completed` (a coordinator, an orchestrator loop, or a lead reconciling task state) will silently accept failed/empty work. This is most dangerous precisely where it's least observed — unattended batch runs.

## Requested upstream behavior

Surface a distinct terminal status for API/transport failures — e.g. `failed` / `errored` — separate from `completed`, so a consumer can distinguish "ran and finished" from "ran and produced a clean result." A transport error mid-stream should not normalize to `completed`.

Secondary: include a machine-readable error class on the notification (e.g. `error.type: overloaded`) so retries can be policy-driven (backoff vs. re-spawn vs. halt) instead of string-matching the result body.

## Plugin-side mitigation (already shipped — does not require the upstream fix)

Until the harness distinguishes the statuses, the SDLC plugin does not trust the completion notification as a success signal:

- **`/develop`** — "Trusting teammate results (harness caveat)" in `plugin/commands/develop.md`: the lead reads the teammate's **output envelope `status:` field** (and sanity-checks for an empty/implausibly-short result or an embedded error string) before treating any phase as done; re-spawns on `failed`/empty.
- **Phase agents** emit an explicit envelope `status:` (`complete` / `failed` / `halted`) as their last fenced block — a payload-level signal independent of the harness notification.
- **`validator`** envelope distinguishes `complete` (gates passed) / `failed` (blocking failure) / `halted` (config error), so a transport death (which produces no valid envelope at all) is distinguishable from a real pass.

The envelope is therefore the contract; the harness notification is advisory. The upstream fix would let consumers trust the notification directly and drop the sanity-check heuristic.
