# Report: machines (sdlc)

Brief: `~/maplelog/hq/briefs/sdlc/20261025-machines.md` · ADR: `~/maplelog/hq/docs/adrs/009-machines.md`
Worktree: `/root/wt/claudecode-patterns/machines`, branch `dugshub/machines` (from origin/main 0711be6).

## State — 2026-10-26: all 4 PRs READY FOR HQ MERGE

Issues: epic #135; #136, #137, #138, #139 (all `gate:auto`).

**Merge order: #140 → #141 → #142 → #143.** Each PR after the first is stacked on the one before it. Retarget each to `main` after its parent merges, because `verify.yml` only runs on main/v2.

#142 and #143 both claim 0.2.42. Whichever merges second needs a bump to 0.2.43, plus a CHANGELOG heading.

| Issue | PR | Version | Head | Gates | Tests (all `nice -n 19`, exit 0) |
|---|---|---|---|---|---|
| #136 registry | [#140](https://github.com/pattern-stack/claudecode-patterns/pull/140) | 0.2.40 | 799621a | 1.5 PASS_WITH_NOTES · 2.5 both lenses PASS_WITH_NOTES · validator PASS · CI 4/4 | machines 334/0 |
| #137 placement | [#141](https://github.com/pattern-stack/claudecode-patterns/pull/141) | 0.2.41 | 67fe1c5 | 1.5 PASS_WITH_NOTES · 2.5 both PASS_WITH_NOTES · validator PASS | placement 392/0, machines 334/0 |
| #138 remote hint | [#142](https://github.com/pattern-stack/claudecode-patterns/pull/142) | 0.2.42 | 28ba196 | 1.5 PASS_WITH_NOTES · 2.5 both PASS_WITH_NOTES · validator PASS | hooks 165/0 |
| #139 delegate | [#143](https://github.com/pattern-stack/claudecode-patterns/pull/143) | 0.2.42 (see above) | 8a558f0 | 1.5 hit the critique cap (see Deviations) · 2.5 both PASS_WITH_NOTES at re-run 3 · validator PASS at cf2b6fa | delegate 358/0, placement 392/0, machines 334/0, hooks, verify, version bump, `claude plugin validate` |

Notes:
- **#136:** two holds on the way, both fixed: a `_Map` repr blowup, and a yq merge-key duplicate that failed open. A key repeated inside a merged mapping is now an error, with the restrictive value under both backends.
- **#138:** the hint goes out as `additionalContext`. The hook has a 3.5 s SIGALRM deadline and fails open.
- **#139, mutation testing:** adherence caught 55 of 61 mutants. Of the 6 survivors, 2 are expected, 3 are a name reservation dropped at one of its three sites (the other two still cover it), and 1 is the `ws_before` filter, which has since been replaced by a per-run workspace label (test D75).
- **#139, review fixes:** review added a per-machine lock, cleanup inside that lock, provisional records, and temporary tab and workspace labels. These handle concurrent delegations, which go beyond the original ask.
- **#139 live check (devbox-n2, through `herdr --machine` only, no ssh):**
  - run W at 955e40b posted [comment 6404938943](https://github.com/pattern-stack/claudecode-patterns/pull/143#issuecomment-6404938943);
  - run W again at cf2b6fa posted [comment 6408537493](https://github.com/pattern-stack/claudecode-patterns/pull/143#issuecomment-6408537493). It created a fresh workspace and renamed it after the cwd check;
  - `--machine compute` and an unknown machine both exited 1 with no herdr calls;
  - devbox-n2 was left exactly as found, with 13 agents.
  - **Run F was skipped:** `/root/work/sdlc-live` doesn't exist. So real first-start dialogs have **not** been seen live; the fake herdr is the only coverage.

### #136 detail (history)
- Gate 1.5:
  - first critique REVISE: an invalid `assignable` fell back to its default of `true`, which fails open;
  - addendum, then re-run PASS_WITH_NOTES.
- Lead decisions beyond the spec:
  - invalid, blank, duplicate or near-miss trust keys load the restrictive value;
  - `busy_flag` implies `gaming_sensitive` (D5 as approved);
  - `secrets` levels are `none < dev < prod`;
  - PyYAML and yq agree; a documented gap remains: yq-only `0x10`, `1_000`, `0o10`.
- Declined nits:
  - `list` marks only the columns it shows;
  - a bad-name local entry isn't counted toward the local count;
  - a duplicated `_first_line` helper.

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

Nothing merged yet. All four PRs are ready for HQ: #140, #141, #142, #143, in that order.

## Deviations

- I wrote the plan YAML directly instead of spawning the `planner` helper. `/sdlc:plan` allows this when the next stop is human review, and I already held the context.
- The plan lives at `.ai-docs/stacks/machines/plan.yaml`, the repo's `artifact_paths.plan`, not `.ai-docs/plans/`.
- The orchestra recipes in `to-compute.md` weren't read, because the brief said not to wait on them. Issue 4 cross-checks them if they've arrived.

## Waiting on Doug

No decisions are pending. Two actions on devbox-n2 are open:
- create an empty, untrusted `/root/work/sdlc-live`, so run F can see the real first-start dialogs;
- fix the `agents` limit (see the follow-ups below).

## Deviations (continued)
- **#139 spec drift:** spec rev 4 (bd9cb3b) and the final-round edits synced the main sections to the code. Adherence found no D1-D5 or ADR conflicts.
- **#139 Gate 1.5 stopped at the critique cap.** It ran 3 critiques (`spec_critic_max_iterations: 3`): REVISE, then REVISE, then REVISE. The third found 1 blocker (a dialog loop that never hits its deadline when it can't read the selection) and 4 small local notes. The lead had them folded into spec revision 3 without a fourth critique. Gate 2.5 reviews check those items in the code instead. This is the lead's call; HQ may want to see it.

## Inputs from HQ (2026-10-25)
- **Prior art for #139:** compute's `~/orchestra/justfile` is in `~/maplelog/hq/.ai-docs/to-compute.md`, under "compute → HQ" §1 (line 27 on). Lessons from it:
  - the justfile doesn't handle the first-start gates;
  - `agent get` returns `agent_not_found` while an agent is starting up, even though `agent start` says `agent_name_taken`, so fall back to `pane close` using `agent list`;
  - fetching results over ssh is a fallback only.
- **devbox-n2:** the guard is installed there, so tests may run on it.

## Follow-ups for HQ / Doug (not in this brief's scope)
- **Coordinator check before spawning (from the #138 Gate 1.5 review, N6).** Under D3 the hook can only hint, and the hint reaches the coordinator after a foreground subagent has already run locally. So the first local run of a placed role can't be prevented. The real fix is prose in the coordinator, `/develop` and `/orchestrate`: check `sdlc machines where <role>` before spawning, and use `sdlc delegate` when the result isn't local. A deny mode (a D3 escalation) is the alternative.
- **Trust entries on devbox-n2 (from the #139 live check).** `/root/work` was already trusted, so neither run W added anything. A future run F would leave `/root/work/sdlc-live` on Claude Code's trusted-folder list on devbox-n2. Nothing else persists: the clone and the `sdlc-delegate` workspace are removed.
- **devbox-n2's `agents` limit (from the #143 live check).** The hand-written `~/.config/sdlc/machines.yaml` sets `agents: 10` for devbox-n2, but the box had 13 live agents, all idle or done, during the check. `delegate` counts finished agents until they're stopped, so today it would treat devbox-n2 as full. HQ/Doug should either raise the limit or stop the finished workers. The live check used a temporary registry with `agents: 30`.
