# Handoff — 2026-05-11

**Branch:** `main` (clean after this commit). Doug also has WIP `dug/plugin-auto-launch-playground` with commits `71e1b04` (auto-launch ap playground SessionStart hook) + `d377c3e` (hooks.json migration); `experimental/teammate-fanout/` is also Doug's WIP. Both independent of the SDLC loop work.
**Last action:** Long architecture conversation collapsed the remote-control stack scope. Corrected a multi-turn misconception about `TeamCreate` (skills CAN compose teammates from within a session — `TeamCreate` is in /develop and /orchestrate's allowed-tools). Re-scoped remaining issues; plan below.
**Next action:** Restart with `just dev`, close obsolete tracker issues, file new ones per the corrected design, ship `/implement` skill (~120 lines) + envelope halt extension.
**Obstacles:**
- GraphQL rate limit recovered earlier; if exhausted again use REST endpoints (`gh api repos/.../issues` etc.)
- Doug enabled `/remote-control` on the prior session at end-of-conversation; if iPhone/web connections are active they may inherit.

## What shipped THIS session (already merged to main)

- **Wave A of remote-control:** #43 (sdlc.yml iteration-cap knobs + port-level soft-entry & cap-hit conventions) via PRs #54 + #55 + #56 + #57
- **Plugin marketplace cleanup train (parallel, mostly Doug):** #58, #59, #60, #61
- **#62 → #63:** Drop `.claude/{agents,commands,skills,primitives,canvases,hooks,output-styles}` dogfood symlinks; switch dev workflow to `--plugin-dir` + `/reload-plugins` via `just dev` recipe
- **#64:** Justfile 50-col comment wrap (Doug)
- **#65 → #66:** Gitignore `.claude/worktrees/` + `just clean-worktrees` recipe
- **Beyond my work** (parallel Doug PRs): #68 (justfile submodule recipes expanded), #69 (spec commits on impl branch + SHA permalink), #70 (specifier defaults to REST + accepts inline body)

## Corrected architectural understanding (load-bearing for next session)

The harness exposes **`TeamCreate`** as a first-class tool that slash commands can call. See `plugin/commands/{develop,orchestrate}.md` `allowed-tools` lists — both include `TeamCreate, SendMessage`. This means:

- **Main session CAN compose teammates** — via `TeamCreate` from any skill that lists it
- **Teammates CANNOT compose more teammates** — that's the actual constraint; `TeamCreate` doesn't nest. This is why `/orchestrate`'s coordinator-teammates fall back to subagents for phase work.

The asymmetry produces three patterns:

| Command | Main session role | Phase workers | Loop driver |
|---|---|---|---|
| `/develop` | skill orchestrator (no autoloop) | teammates via `TeamCreate` | human via `SendMessage` |
| `/implement` (new) | **skill IS the coordinator** (autoloop in skill prompt) | teammates via `TeamCreate` | skill prompt via `SendMessage` |
| `/orchestrate` | skill spawning N coordinator teammates | subagents *inside each coordinator* (forced) | each coordinator's prompt |

**Critical insight:** `/implement` for single-issue work does **NOT** need to spawn a coordinator teammate. The skill itself IS the coordinator. The coordinator agent (skeleton today) is ONLY needed for `/orchestrate`'s multi-issue case where nesting forces subagent fallback.

## Revised stack scope

| # | Status | New scope |
|---|---|---|
| #43 | ✓ merged | done |
| #44 | obsolete-as-scoped | **Defer entirely** (until you actually want /orchestrate batch). OR re-scope to "promote coordinator for /orchestrate-only use." Single-issue /implement does NOT need it. |
| #45 | re-scoped | `/implement <ISSUE>` skill: main-as-coordinator + teammates via `TeamCreate` + autoloop via `SendMessage` + cap-hit halt per #43. **~120 lines of skill prompt.** No new agent file. |
| #46 | keep | Envelope `status: halted` extension. ~5-10 lines canvas update. Useful for /implement halts + later coordinator. |
| #47 | obsolete | Close. Docs collapse to inline in /implement. |
| NEW | file | **Spawn primitive adapters** (`bash-nohup`, `tmux-detached`, `iterm-window`) — orthogonal to /implement; for use cases TeamCreate can't reach (externally-triggered runs, survival-after-session-crash, different auth/config). Fast-follow. |

**Minimal viable shipping order: #45 + #46 first.** Two PRs gets single-issue walk-away working. #44 and spawn-adapter deferred until needed.

## Concrete `/implement` skeleton (drop straight into the spec)

```
1. Resolve sdlc.yml: validator_max_iterations, gate1_default, develop_team, etc.
2. Resolve issue via tracker MCP. Capture labels (state:*, needs:*, gate:*).
3. Enforce Gate 1: if state:strategy-approved missing → halt
   (Auto-mode handling: if gate:auto AND no spec → first spawn specifier teammate
    which sets state:strategy-approved itself, then proceed.)
4. Resolve spec path. If missing → halt or spawn specifier first.
5. Compose roster: develop_team ∪ (needs:* labels → agent names).
6. TeamCreate the roster. Capture team handle.
7. Loop:
   a. SendMessage to implementer: "implement per <spec>; signal when ready for validation"
   b. Wait for implementer's envelope (status: complete | failed | halted)
   c. If failed/halted: halt with envelope citing implementer's error
   d. SendMessage to validator: "validate; emit envelope with findings"
   e. Wait for validator envelope
   f. If pass: break loop
   g. If fail AND iter < validator_max_iterations: SendMessage to implementer with findings; iter++; goto (a)
   h. If fail AND iter == cap: halt with envelope status:halted, next.reason: "cap-hit after N iterations"
8. On pass: open PR via Bash (st submit / gh pr create). Emit envelope status:complete with PR URL.
9. On halt: emit envelope status:halted with full context.
```

## Opening moves for next session

1. **`/prime`** to re-load context (this handoff lands first)
2. **Tracker cleanup** (REST API if GraphQL flaky):
   - Close #47 with comment pointing here
   - Close-or-defer #44 (your call — close clean and re-file later, or retitle in place to "deferred until /orchestrate batch")
   - Re-title #45: "Add /implement skill — single-issue autonomous loop (main-as-coordinator, teammates via TeamCreate)"
   - #46 keep as-is
   - File new issue: "Spawn primitive adapters (bash-nohup / tmux / iterm)"
3. **Ship #45**: `/design 45` → review spec → `/develop 45` (or just hand-code — the skeleton above is half the spec already)
4. **Ship #46**: tiny canvas update; one-shot `/develop 46` or hand-coded
5. **(Later)** spawn adapters + #44 promotion when you want /orchestrate batch

## Memory landed this session

- `feedback_teamcreate_asymmetry.md` — the no-nested-teammates constraint that shapes the topologies. Load-bearing for future skill/agent design decisions.
- `feedback_agent_tool_surface_adapter_alignment.md` (earlier) — cross-check agent denylist vs adapter operation table; lesson behind #56.
- `project_remote_control_stack.md` refreshed with corrected design.

## Notes for next-session-you

- The `just dev` recipe + `/reload-plugins` workflow is the supported dev pattern post-#63. `.claude/` no longer has agent/skill/primitive symlinks — use `--plugin-dir ./plugin` (via `just dev`).
- `just clean-worktrees` exists for stale agent worktrees; run periodically.
- Doug has WIP `dug/plugin-auto-launch-playground` + `experimental/teammate-fanout/` — DON'T conflate with SDLC loop work.
- Specifier got REST default in #70 (Doug-authored fast-follow to my #56/57). Test it on next `/design <N>` run.
- Cosmetic carryover: `plugin/primitives/task-management/github.md` line 151 still hard-codes "Gate-1 timeout" prose — same pattern as the fix in #55 coordinator.md §125-129. Batch into #45's PR if convenient.
