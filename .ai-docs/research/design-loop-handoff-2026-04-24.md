<!--
RESEARCH ARTIFACT — vendored from pattern-stack/sales-patterns-ts PR #74 (`docs/handoff-design-loop-2026-04-24.md`).

Origin: end-of-session handoff written by the lead during the issue #47 work that
informed this plugin's design-loop port. Project-specific and time-bound (2026-04-24).
Kept for historical context — the gaps and resume instructions it lists shaped
the design-loop SKILL.md choreography and the design-spec canvas knobs.

NOT THE CANONICAL HANDOFF for the ported version. For port-specific gaps and
resume instructions, see `plugin/skills/design-loop/HANDOFF.md`.
-->

# Handoff — Design Loop continuation (2026-04-24)

**Session wrapped:** 2026-04-24. This doc is the single entry-point for a fresh Claude Code session continuing the work.

## TL;DR

The frontend-mvp milestone is **shipped**. Five PRs merged (#40–#44) covering A1 scaffold + atoms + e2e harness, A2 events endpoint + page, A3 jobs endpoint + correlation drawer, A4 overview stats + gantt, + rootRunId propagation. Design pass 1 merged on top (typography, pool palette contrast, gantt labels, empty states, crm_sync pool token). Upstream codegen-patterns PR #219 filed (`tier: audit` event classification). Three concrete follow-ups open — see §4.

The user wants to continue **refining the design loop itself** — the pattern of spec → parallel specifier+validator review → patches → rebuild → designer audit → polish PR. Not re-ship the MVP; iterate on it.

## 1. What the "design loop" is

A repeatable cadence the user and Claude converged on this session:

1. **Spec.** Produce an implementation spec per discrete deliverable.
2. **Parallel review.** Spawn a specifier and a validator in parallel, independently, against the same spec. They find different classes of problem.
3. **Iterate.** Apply targeted fixes between rounds. Re-spawn both reviewers. Repeat until both say READY.
4. **Build.** Single builder implements the spec. Echo-back gate before first file write.
5. **Design audit.** Run the designer agent against the running app; capture screenshots; propose polish in a concrete follow-up PR.
6. **Merge + move on.** Don't rehash resolved findings.

See `memory/feedback_design_loop_pattern.md` for the reasoning behind this shape.

**Supporting tooling the user built mid-session (outside Claude's context):**

- `.claude/agents/designer.md` — designer agent definition.
- `.claude/skills/gh-attach-image/` + `scripts/gh-attach-image.mjs` — attaches screenshots to PRs.
- `screenshots/2026-04-24-observability-audit/` — screenshots captured per screen during pass 1 audit.

Pass 1 commits on main: `ee7bbf0 → e3989ee → b2877e2 → 090ebf4 → 61982ad`. Those established the pattern. Pass 2+ should build on it.

## 2. Where the repo is right now

**Branch:** `feat/a2-events-page` (stale — was checked out mid-session; main has since advanced with the merged PRs). Recommended first move: `git checkout main && git pull` in a fresh session.

**Merged into main** (in merge order, most recent first):
- `a800859` `feat(crm): propagate rootRunId through sync events for correlation drawer` (PR #44)
- `61982ad` `fix(observability): pass 1 polish — drawer width, crm_sync token, pool contrast, gantt labels, health alias`
- `090ebf4` `design(observability): pass 1 — typography, pool palette, empty states`
- `b2877e2` `docs(observability): pass 1 designer screenshots`
- `e3989ee` `docs(observability): pass 1 re-audit screenshots`
- `ee7bbf0` `docs(observability): pass 1 audit screenshots`
- `b2059be` `A4 — Overview page: stats + per-pool gantt (#43)`
- `6036dc9` `fix(frontend): make dev server + backend proxy port-flexible`
- `bf9bef2` `feat(observability): A4 — Overview page...`
- `a9ebc68` `A3 — Jobs endpoint + correlation drawer (#42)`
- `3c4c5e4` `feat(observability): A2 — GET /api/observability/events + EventsPage (#35)`
- `902b0a5` `A1 — Frontend scaffold + Chalky Primary theme + 7 atoms + e2e harness (#40)`

**Upstream codegen-patterns (sibling repo):**
- PR #219 filed, not merged: `feat(events): tier: audit — bridge-inert events for lifecycle/observability`. Design + skills docs. Ready for review.

**Running services (when `pts dev` is up):**
- Backend: `:9100` (moved off `:9000` because Docker Desktop squats it on macOS; see `.env` comment)
- Frontend: `:4000`
- Postgres: `:6432` / Redis: `:7379`

## 3. What the app does today

### Routes (all live on `http://localhost:4000`)
| Path | Status |
|---|---|
| `/overview` | Stats (jobs/hr, error rate, p95 duration, active correlations) + per-pool gantt. Click a gantt block → `/jobs?focus=<run_id>`. |
| `/events` | Paginated domain-event list, filterable by pool / direction / time / free-text. `?focus=<uuid>` highlights a row. |
| `/jobs` | Paginated `job_runs` list, same filter shape as events. |
| `/pools`, `/bridge` | `ComingSoonPage` placeholders — Stack A5 / v2 content. |

Correlation drawer mounts globally via `?corr=<rootRunId>` on any route. Opens when the URL param is a valid UUID; closes via Esc / backdrop / close-button (all clear the param). Paste a UUID into the topbar search → drawer opens without a navigation.

### Backend endpoints (all under `/api/observability/*`)
| Method + path | Purpose |
|---|---|
| `GET /events` | List `domain_events` with filters (rootRunId, poolId, direction, since, cursor, limit). |
| `GET /jobs` | List `job_runs`. Dedicated endpoint — the generated `collections/job.ts` is the wrong entity (codegen-patterns' build-orchestration `Job`, not our `job_run`). |
| `GET /correlations/:rootRunId` | Stitched timeline of events + jobs sharing a rootRunId. Empty arrays on unknown UUID (no 404). |

Wired into `src/shared/observability/dev-status.module.ts` (the module keeps its legacy name from `/dev/status`; still exports `StackStatusService` + three new services).

### Data model reminders
- `job_runs.root_run_id` is a **first-class indexed UUID column** (upstream codegen-patterns JOB-1 convention).
- `domain_events.metadata->>'rootRunId'` is the jsonb path events use. PR #44 wired propagation from `CrmSyncJob.run(ctx)` → `ctx.run.rootRunId` → use case → `TypedEventBus.publish(..., { metadata: { rootRunId } })`.
- `SEEDED_ROOT_RUN_ID = "7f8e9d2a-1111-2222-3333-444455556666"` is the pinned dev/test UUID. Two files keep this literal in sync: `scripts/seed-observability.ts` + `frontend/src/__fixtures__/seeded.ts`.

## 4. Open follow-ups (where to pick up)

### 4.1 CRM sync emits too many events on re-syncs (the big architectural one)

**Observed:** a re-sync with zero HubSpot-side changes fires ~80 events (55 `crm_entity_persisted` + 22 `opportunity.updated` + 2 `opportunity.field_changed` + 1 `crm_sync_completed`). Only 2 represent real domain change. Not idempotent at any layer.

**Root cause:** three independent layers compound.
1. **Read layer** — fetches all records, not a delta. HubSpot Search API's `hs_lastmodifieddate > $since` filter is viable under user-OAuth and is the biggest single lever.
2. **Write layer** — `ON CONFLICT DO UPDATE SET` without a `setWhere` clause. Row `updated_at` advances even when nothing changed.
3. **Emission layer** — base-service lifecycle hooks fire on every write; sync port also emits its own `crm_entity_persisted`. Redundant channels.

**Fix order (tackle in this sequence, each yields diminishing returns for the next):**
1. **Since-cursor on read** — per-integration `lastSyncedAt`; HubSpot Search filter. Biggest lever.
2. **Fingerprint diff at write** — `sync_fingerprint` column; Drizzle `onConflictDoUpdate({ setWhere: sql\`fingerprint IS DISTINCT FROM excluded.fingerprint\` })`. Postgres short-circuits. `.returning([...])` tells you whether a write happened.
3. **Sync-writer lifecycle suppression** — async-local-storage flag set by sync ports; base-service lifecycle hooks skip emission when a sync is the writer. Sync's `crm_entity_persisted` is authoritative.

**Spec status:** not yet written. The user requested this be thought-through deeply during the session and reached the "both architectures are wrong, tier: audit is one of the fixes" conclusion. Next step: draft a proper spec under `specs/2026-04-XX-crm-sync-change-detection.md`, run through design loop.

**Visibility-scope considerations:** this work also has to document the SFDC vs HubSpot per-user-OAuth visibility model — SFDC is always user-scoped under user OAuth, HubSpot is portal-wide on Starter/Pro but user-scoped on Enterprise + Advanced Permissions. Coverage model is per-integration. Multi-seat install + loopback fingerprint dedup is the pattern for org-wide coverage. See `memory/project_sync_emission_architecture.md` for the full framing.

### 4.2 Upstream codegen-patterns PR #219 (tier: audit)

Filed, waiting for review. Merges in order: design + skill docs now, generator implementation whenever the events-codegen work lands next, bridge-dispatcher guard whenever the bridge formalizes. After merge, **dealbrain-local follow-up:** update hand-rolled `src/shared/subsystems/events/generated/bus.ts` to honor `tier: audit` — skip stamping `pool` / `direction` when the YAML declares it. Then migrate the three CRM lifecycle events to `tier: audit`:
- `events/crm_sync_started.yaml`
- `events/crm_sync_completed.yaml`
- `events/crm_sync_failed.yaml`

Keep `events/crm_entity_persisted.yaml` on `tier: domain, direction: change` — it IS a real domain-change event (row was persisted). The lifecycle ones are NOT.

### 4.3 Design loop refinements (what the user specifically wants to iterate on)

**Pattern works; tooling can sharpen.** Things to explore in a fresh session:

- **Automate the designer-audit trigger.** Today the user runs the designer agent manually after a merge. A hook or a `/design-audit` skill that fires automatically post-merge on observability-touching PRs would cut the loop.
- **Tighter specifier↔validator round coordination.** The two reviewers ran independently this session; sometimes they raised overlapping findings. A small "consolidator" step between rounds (one pass to dedupe + prioritize) would reduce wasted cycles.
- **Screenshot baselining.** `screenshots/2026-04-24-observability-audit/` is per-pass; a `-baseline/` dir referenced in PR bodies would make visual regression obvious.
- **Polish PRs should honor the same parallel-review pattern.** Today pass 1 was a manual iteration; the specifier+validator structure likely applies to design polish too (specifier: "does this match the intent spec" / validator: "are the states falsifiable").

## 5. Useful commands on re-entry

```bash
# Refresh branch + services
cd /Users/dug/Downloads/dealbrain-v2
git checkout main && git pull
pts dev                                       # starts pg, redis, backend :9100, frontend :4000, workers

# Trigger a sync (HubSpot integration id is pinned)
curl -X POST http://localhost:9100/crm/integrations/76968350-56a8-4d61-9579-80e712031cb0/sync

# Inspect what the sync emitted (since T0=ISO)
curl -s "http://localhost:9100/api/observability/events?since=$(date -u -v-2M +%Y-%m-%dT%H:%M:%SZ)&limit=80" \
  | jq '.items | group_by(.type) | map({type: .[0].type, count: length})'

# Correlation drawer for a specific rootRunId
open "http://localhost:4000/jobs?corr=<rootRunId>"

# Seed the deterministic test data (for browser-gate / e2e)
bun scripts/seed-observability.ts
# --touch flag inserts one fresh event (polling probe)
bun scripts/seed-observability.ts --touch
```

## 6. Things Claude should NOT re-do in a fresh session

- Re-propose the frontend MVP. It's merged. The four stacks (A1–A4) are `frontend-mvp` milestone complete.
- Re-port v1's atomic component library. The foundation is `@pattern-stack/frontend-patterns@0.2.0-alpha.11` (pinned). See `memory/project_frontend_patterns_is_foundation.md`.
- Re-argue about whether `pool` / `direction` on lifecycle events is a lie. It is. The fix is upstream PR #219 (`tier: audit`). Don't relitigate.
- Touch the user's other project (referenced as "work") — they explicitly scoped this session to dealbrain-v2 only.

## 7. Memory index snapshot (as of session end)

See `~/.claude/projects/-Users-dug-Downloads-dealbrain-v2/memory/MEMORY.md`. New entries this session:
- `project_observability_mvp_complete.md`
- `project_sync_emission_architecture.md`
- `feedback_design_loop_pattern.md`

Prior relevant:
- `project_frontend_patterns_is_foundation.md` — substrate decision.
- `feedback_echo_back_guard.md` — builder discipline.
- `feedback_layer_rules.md` — where logic lives (services/repos/use-cases).

## 8. One line per PR, for context-resuming summary

- **#40** A1: scaffold + theme + 7 atoms + e2e harness — the foundation.
- **#41** A2: `/api/observability/events` + EventsPage + seed script + rootRunId infrastructure.
- **#42** A3: `/api/observability/jobs` + `/api/observability/correlations/:rootRunId` + drawer + JobsPage.
- **#43** A4: OverviewStats + OverviewGantt + page-level TimeRangePicker. MVP complete.
- **#44** rootRunId propagation: `CrmSyncJob.run(ctx) → ctx.run.rootRunId → use case → events metadata`.
- Pass 1 design polish (no PR — direct commits): typography, pool palette contrast, crm_sync pool, gantt lane labels, empty states.
- **codegen-patterns#219** (filed, open): `tier: audit` event classification. Bridge-inert lifecycle events.

Good luck, future-Claude. Pick up at §4.1 if Doug wants to tackle the sync architecture; pick up at §4.3 if he wants to keep refining the loop itself.
