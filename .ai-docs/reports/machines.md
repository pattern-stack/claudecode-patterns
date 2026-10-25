# Report: machines (sdlc)

Brief: `~/maplelog/hq/briefs/sdlc/20261025-machines.md` · ADR: `~/maplelog/hq/docs/adrs/009-machines.md`
Worktree: `/root/wt/claudecode-patterns/machines`, branch `dugshub/machines` (from origin/main 0711be6).

## State — 2026-10-25: plan written, WAITING ON DOUG (Gate 0 via HQ)

Plan: `.ai-docs/stacks/machines/plan.yaml` — 4 issues, one PR each:

| # | key | depends on |
|---|---|---|
| 1 | `machine-registry`: schema, loader, `sdlc machines list/check`, example file | — |
| 2 | `placement-resolver`: `phase_machines` / `agent_machines` / `default_machine` / `needs` + resolver | 1 |
| 3 | `phase-tuning-remote-hint`: hook tells the coordinator to start a remotely-placed phase as a herdr agent | 2 |
| 4 | `sdlc-delegate`: fit then load, start in `workdir`, clear first-start gates, print placement; live check on devbox-n2, refuses compute | 2 (parallel with 3) |

## Decisions for Gate 0

- **D1** `sdlc` CLI as `plugin/bin/sdlc` (Python) plus `just sdlc::machines` / `just sdlc::delegate`; resolver shared in `plugin/lib/machines.py`.
- **D2** YAML: PyYAML if importable, else `yq` (as `sync-github.py` does); no new hard dependency; the hook fails open.
- **D3** The hook *hints* (spawn still allowed), not a block.
- **D4** No registry file means the feature is inert. An unknown or unfit placement is a `check` error and falls back to `default_machine`, never to an `assignable: false` box.
- **D5** `gaming_sensitive` is generic as a per-machine `busy_flag` path (`gaming_flag` accepted as an alias).
- Live check job: a read-only reviewer pass on devbox-n2 that posts one PR comment.

## Shipped

Nothing yet. No issues have been filed and no PRs opened; this waits on Gate 0.

## Deviations

- I wrote the plan YAML directly instead of spawning the `planner` helper. `/sdlc:plan` allows this when the next stop is human review, and I already held the context.
- The plan lives at `.ai-docs/stacks/machines/plan.yaml`, the repo's `artifact_paths.plan`, not `.ai-docs/plans/`.
- The orchestra recipes in `to-compute.md` weren't read, because the brief said not to wait on them. Issue 4 cross-checks them if they've arrived.

## Waiting on Doug

Gate 0 on the plan and on D1–D5.
