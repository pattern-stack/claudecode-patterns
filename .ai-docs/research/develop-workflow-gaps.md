# `/develop` workflow gaps — field notes

**Date:** 2026-05-24
**Source:** observed running `/develop` end-to-end on codegen-patterns issue #374 (synced/junction sync-override lift). Code shipped clean and validated; the friction was in process plumbing, not output.
**Purpose:** actionable upstream backlog for the SDLC plugin (skills/commands/agents under `plugin/`).

---

## 1. No clean "spec already approved → implement" entry into `/develop`

**Observed:** a spec had already been produced and human-approved (via `/plan`). Invoking `/develop` with free-text args launched the **full loop from Phase 1 (Understand)**; the lead had to manually override to `--from=implement`. The skill documents `--from=` and "issue-ID with existing spec → resume from appropriate phase," but that detection keys off a tracker issue-ID arg, not a conversational "here is the approved spec file."

**Problem:** the most common real path — "we planned, now build" — fights the default. Re-running Understand/Plan/Spec wastes agent runs or forces manual intervention.

**Fix:** teach `/develop` input detection to accept a **spec path** and jump straight to Implement. Reconcile with #2.

**Component:** `plugin/commands/develop` (input detection), `plugin/skills/sdlc:develop`.

---

## 2. Spec-location + naming mismatch across `/plan`, `/develop`, `specifier`

**Observed:** `/plan` writes `ai-docs/specs/<date>-<kebab>.md`; `/develop`'s spec phase writes `ai-docs/specs/{issue-slug}.md`; the target repo also has `docs/specs/`; and the upstream contract spec lived in a **different repo** (`.ai-docs/specs/`). `/develop`'s auto-detect (`{issue-slug}.md`) would not find the spec `/plan` produced.

**Problem:** the planned-spec → develop handoff silently breaks because the two halves don't agree on where the artifact lives or how it's named.

**Fix:** one canonical spec path + naming convention shared by `/plan`, `/develop`, and `specifier`. Decide `docs/specs` vs `ai-docs/specs` (project CLAUDE.md files often say `docs/specs/*` while the commands emit `ai-docs/specs/`).

**Component:** `plugin/skills/sdlc:plan`, `plugin/commands/develop`, `plugin/agents/specifier`, `sdlc.example.yml` (`artifact_paths`).

---

## 3. Subagents don't update the shared task list

**Observed:** lead created 7 tasks, set the implementer as `owner`, and instructed it to mark in_progress/completed. The agent updated none — all stayed `pending`; the lead reconciled by hand after the agent reported done.

**Problem:** the task list is meant to be the live progress signal. If spawned agents can't/don't update it, it's decorative and the lead must babysit.

**Fix:** pick one model and enforce it — either (a) give `implementer`/`validator` the Task tools and *mandate* updates in their agent definitions, or (b) declare task state lead-owned and stop instructing subagents to touch it. Today it's ambiguous, so neither happens reliably.

**Component:** `plugin/agents/implementer`, `plugin/agents/validator`, tool grants.

---

## 4. Failed agent reported as `completed` (harness-level)

**Observed:** the first `validator` run died on `API Error: Overloaded` but the task-completion notification reported **`status: completed`**. It was only caught because the `result` field carried the error string and the token count was implausibly low (~4k). Had to re-run.

**Problem:** conflating "process exited" with "task succeeded" will silently pass broken/empty validations — dangerous in an AFK `/orchestrate` run where no one is reading results.

**Fix:** surface a distinct `failed`/`errored` status for API/transport errors so the lead doesn't trust an empty result. **This is Claude Code harness behavior, not a plugin file** — raise with the CC team / track separately from the plugin backlog.

**Component:** Claude Code harness (out of plugin scope) — file upstream.

---

## 5. `/develop` advertises tracker + logging guarantees it doesn't deliver

**Observed:** the skill describes Phase 5 creating PRs + updating issue status via a `task_management` primitive, and session logs committed to git. **None was wired** — the spawned agents are local subagents with no tracker write path; the lead scaffolded the `agent-logs/` session dir by hand. (This directly prompted the operator's "are the agents writing to the trackers?" question — the honest answer was no, but the skill implies yes.)

**Problem:** expectation gap. A reader trusting the doc assumes an audit trail + tracker sync that isn't happening.

**Fix:** either implement the tracker/logging hooks, or downgrade the skill text from "does X" to "the lead must do X" so it stops over-promising.

**Component:** `plugin/skills/sdlc:develop`, `plugin/commands/develop`, `plugin/primitives/session-logging`, `task_management` primitive.

---

## 6. `/develop` is prompt-expansion, so its gates are advisory

**Observed:** invoking the skill expanded the full command markdown into the lead's context; the orchestration (human gates, parallelization, logging, retries) is left to the lead to *interpret and honor* — not enforced by the runtime.

**Problem:** "human gate before merge" and "max 3 retries before human intervention" only hold if the lead chooses to honor them. Under load or a long loop they're skippable by accident.

**Fix:** for the guarantees that matter (gate before merge, fail-after-N-retries), encode them as actual control flow / hook checks rather than narrative instructions.

**Component:** `plugin/hooks`, `plugin/skills/sdlc:develop`.

---

## 7. No cross-repo / multi-agent coordination guardrail

**Observed:** the operator had to *manually* instruct isolation for a cross-repo validation step ("run it in a clone — another agent owns that tree"). Stray `worktrees/`, `.claude/worktrees/`, and a `.claude copy/` were present in the working repo, plus a named worktree with duplicate files in the sibling repo — signs of parallel-agent worktree churn.

**Problem:** nothing in the workflow prevents two agents from mutating the same working tree (especially across repos); correctness depends on a human remembering to isolate.

**Fix:** default cross-repo validation to a throwaway worktree/clone; consider a lightweight "who owns this tree" lock for multi-agent setups. (See existing `.claude/docs/dual-worktree-strategy.md` — extend it to cross-repo.)

**Component:** `plugin/skills` (validation steps), `.claude/docs/dual-worktree-strategy.md`.

---

## Adjacent (not `/develop` — project test-infra)

**`just test-baseline` covers only the `clean` architecture, giving false confidence on `clean-lite-ps` changes.** The #374 sync surface (a large emission change) produced **zero baseline diff** because baseline routes through `templates/entity/new/backend/`, not the clean-lite-ps templates. Coverage there rests entirely on template-emission unit tests. Not a plugin issue — a per-project testing gap worth a clean-lite-ps baseline fixture or a CLAUDE.md testing-section note. Logged here only because it surfaced during the same run and a `/develop` validator could be fooled by it.
