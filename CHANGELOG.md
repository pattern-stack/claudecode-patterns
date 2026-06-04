# Changelog

All notable user-facing changes to the `sdlc` Claude Code plugin.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version field lives in [`plugin/.claude-plugin/plugin.json`](plugin/.claude-plugin/plugin.json) — bumping it is what triggers Claude Code's `/plugin update` to actually refresh the cache for existing consumers.

## [0.2.11] — 2026-06-04

### Added — `browser` skill + plugin-shipped MCP servers

- **`/browser` skill** (`skills/browser/`) — unified browser interaction, promoted from the per-project copies that had drifted across ~19 checkouts (several still carrying another project's ports). User-browser mode over CDP :9222 (launch table for all Chromium browsers + the hard-won Arc recipes: flag lost on Cmd-Q, force-quit relaunch one-liner, `EnableRemoteDebugging` defaults fallback), headless mode via the playwright server, audits via lighthouse. Project URLs resolve from `sdlc.yml → browser:` (frontend_url / api_url / prod_url) instead of being hardcoded — the drift that plagued the old copies.
- **`/browse` + `/verify` commands** — ported from the legacy skill, de-project-ified.
- **Plugin-shipped MCP servers** (`plugin.json → components.mcpServers`): `chrome-devtools` (pinned, `--browserUrl http://127.0.0.1:9222`), `playwright` (pinned, `--headless --isolated`), `lighthouse` (pinned). Every consuming project gets the deps with the plugin — no per-project `.mcp.json` setup. Note: plugin servers are namespaced (`mcp__plugin_sdlc_<server>__…`), so they coexist with same-named project-level servers (at the cost of a duplicate process — projects can drop their own entries).
- **`scripts/auth-capture.mjs`** — generic headed-once auth bootstrap: visible browser at a login URL, user authenticates by hand, storage state saved to `.playwright/auth.json` (shared with `browser-driver`), headless thereafter. Projects with their own credential plumbing point `sdlc.yml → browser.auth_script` at it instead.

- **`check-cdp` SessionStart hook** — when (and only when) a dev has set `BROWSER_PREFERENCE` in `.claude/settings.local.json` and CDP :9222 is dark, the session opens with a one-shot nudge carrying that browser's relaunch command (Arc gets the force-quit one-liner + the sticky `EnableRemoteDebugging` tip). Devs without a preference are never nagged.

### Fixed — `browser-pilot` agent had dead MCP config

- The agent declared `chrome-devtools`/`playwright`/`lighthouse` under `mcpServers:` in its frontmatter — **silently ignored for plugin-shipped agents** (platform security rule), so the agent has been running without its browser tools whenever consumed via the plugin. Servers now ship at plugin level (above) and the agent's `tools:` allowlist (which also blocked MCP tools) became a denylist so the session's browser tools are reachable.
- `browser-driver`'s "user-browser mode: not yet wrapped" now points at the `browser` skill.

## [0.2.8] — 2026-05-27

### Fixed — gate-guard hook precision

- **`gate-guard` no longer false-positives on prose.** Rules 1 & 2 grepped the entire command string, so a command that merely *mentioned* a blocked pattern (the admin merge-bypass flag, or a default-branch name) inside a quoted argument — a PR body, a `git commit -m` message, a heredoc, a doc edit — was wrongly denied. The verb matches (`gh pr merge`, `git push`) are now anchored to a *command position* (start of command, or right after a shell separator / newline), so the rules fire on real invocations, not text. Added `plugin/hooks/gate-guard.test.sh` (17 cases; `jq` or `python3`).

### Added — agent-governance showcase

- **`docs/AGENT-GOVERNANCE.md`** + a README "Agent governance" section: positions the framework's governance as the *workflow layer* (deterministic policy hooks, least-privilege agent roles, staged human gates, git-native auditability), with an honest OWASP Agentic Top 10 map and code-linked, **reproducible** controls. Complementary to infra-layer toolkits.

## [0.2.7] — 2026-05-24

### Added — design-loop (v2 + v2.1)

Consolidated bump for the design-loop port (PRs #95/v2 and #90/v2.1; the v1 port #88 was superseded and closed). An iterative "build → grade → fix" loop for UI work, runnable standalone or composed into `/develop` via `needs:design`.

- **`design-reference` canvas** — one engine, three reference types (`spec` / `figma` / `screenshot`) via a `reference_type:` discriminator.
- **Agents** — `design-builder` (builds/fixes a surface; component-discovery + verify-in-DOM steps) and `design-grader` (captures screenshot **and** inspection JSON, grades against the reference, returns `READY` / `FIXES` / `BLOCKED`). Both `tool_group: custom`. Plus vendored `browser-pilot` (browser teammate over chrome-devtools + playwright MCP).
- **`image-posting` primitive** (beta) — sibling to `task-management`; v1 `gh` adapter (Playwright + GitHub composer) with vendored `gh-attach-image.mjs`.
- **Skills** — `design-loop` (orchestrator; standalone + composed modes), `design-audit` (audit-only), `browser-driver` (Playwright substrate: `capture` / `inspect` / `verify`, auth-aware + cert-bypassing), `figma-snapshot` (extract a Figma frame once per change to `.ai-docs/figma/<slug>/`; downstream reads the cache, not the MCP each round).
- **`/develop` composed mode** — `needs:design` wires `design-grader` between the implementer commit and the validator (Step 4a), preserving the standard gates.
- **v2.1 hardening** — grading requires both a screenshot and an inspection JSON (cursor / ARIA / overflow / interaction probes), closing the v2 failure where the grader passed `READY` while real bugs (wrong cursor, overflowing chips, missing ARIA) remained invisible in a screenshot alone.

## [0.2.6] — 2026-05-24

### Added

- **`proposal` canvas (beta)** at `plugin/canvases/proposal/` — a minimal ADR + RFC hybrid for pre-spec architecture docs. Sections: `Context` / `Goal` / `Locked decisions` / `Architecture` / `Open questions` / `Deferred` / `Next step` (all required except `Deferred`). Knobs: `status_lifecycle` (draft-architecture → under-review → accepted → superseded/rejected), numbered `locked_decisions` (min 1) + `open_questions` (min 1 — a proposal with zero open questions is a spec), `architecture` (tables-over-prose), mermaid `diagrams`, looser `citations` than `spec/`. Shipped `status: beta` pending a second consumer.
- **`.ai-docs/proposals/design-loop-port.md`** — first proposal authored against the canvas: the architecture plan for porting `/design-loop` + `/design-audit` from `pattern-stack/sales-patterns-ts` (5 locked decisions, 8 open questions). Proposal artifact only — no agents/commands/skills/runtime touched here.

## [0.2.5] — 2026-05-24

### Added

- **GitHub canvas family** — new subfolder `plugin/canvases/github/` introduces the family-grouping pattern for canvases sharing surface-specific parser conventions.
  - [`plugin/canvases/github/CONVENTIONS.md`](plugin/canvases/github/CONVENTIONS.md) — the load-bearing reference doc. Captures the 9 closing keywords + format constraint (parser ignores `Closes <prose> X#N`; canonicalized to `Closes` immediately followed by the bare reference, one per line), cross-repo `owner/repo#N` form, URL-everywhere policy, REST-for-tracker-writes, permalink-with-SHA, the Layer enum (L0..L7), `state:*` + `gate:*` label palette, conventional commit types (9), Issue Type enum (`project | epic | task`), 9-option Status taxonomy, plan markers (`[plan-epic:]` / `[plan-key:]`), branch + commit conventions, and an 8-entry anti-pattern catalog. All grounded in existing primitives + plan canvas (no fresh design — consolidation).
  - [`plugin/canvases/github/README.md`](plugin/canvases/github/README.md) — family overview, member canvas roadmap, pattern rationale (subfolder when artifacts share a surface-specific parser rule set; flat when cross-cutting).
- **`plugin/canvases/README.md`** — new "Family subfolders" section documents the pattern + when to use it. Registry table extended with the github family + planned member rows (`github/pr-body`, `github/issue-body`, `github/epic-body`).
- **`plugin/sdlc.example.yml`** — `canvases:` registry block documents family-prefixed registration form + commented placeholders for the planned github-family members.

### Notes

- Foundational PR: ships the family folder, conventions, and registration form only. Member canvases (`github/pr-body`, `github/issue-body`, `github/epic-body`) are authored via `/sdlc:canvas new` in subsequent PRs — the canvas-author dialog is the right surface for the design decisions involved (knob enums, section requirements, verbosity defaults), not an upfront draft.
- `pr-review-comment` and `epic-review-synthesis` continue to live as project-local canvases in `pattern-stack/dealbrain-integrations` for now. Migrating them into `plugin/canvases/github/` is a follow-up coordinated PR (delete from project-local + add here + update the `pr-reviewer` agent + `stack-review` skill references) — not bundled here because it touches a second repo.
- `just verify-canvases` continues to pass (no new `instructions.yaml` added; this PR is docs + registry only).

## [0.2.4] — 2026-05-24

### Changed

- **cc-viewer chat UI polish** — turn grouping, project list, and a refactor onto atoms (`Text`, `Timestamp`, `Truncate`, `StatusDot`, `CodeBlock`), `WaitingIndicator`, and reworked `TurnCard` / `ChatPanel` / thinking + tool-call parts. Viewer-only (no server/contract change). Version-bumped so the rebuilt dashboard binary ships to consumers on `/plugin update` (the `tools/` change alone doesn't trip the version-bump gate).

## [0.2.3] — 2026-05-24

### Added

- **Dashboard self-upgrade on session start** — the `cc-viewer` dashboard now updates itself to match the installed plugin version with no manual step. `/health` reports the running version (the launcher injects `CC_VIEWER_VERSION`), and the `SessionStart` hook (`ensure-cc-viewer.sh`) compares it to the installed plugin version: a match is a no-op (unchanged behavior); a mismatch — or an older binary with no `version` field — triggers a graceful restart onto the new version-pinned binary. This makes every future upgrade self-healing (including the 0.2.2 → 0.2.3 transition, since this hook ships in 0.2.3 and runs right after `/plugin update`). Replaces the prior `pkill -f cc-viewer` workaround.
- Stale-restart targets the actual port listener (`lsof -ti tcp:$PORT`, robust to `setsid` re-parenting) with a recorded-pid fallback — TERM, brief wait, then KILL — instead of `pkill`-by-name.

### Changed

- `/health` response gains a `version` field (`{status, version}`); the `status: "ok"` shape is preserved for existing consumers.

## [0.2.2] — 2026-05-24

### Fixed (dogfood pass on the `/develop` workflow gaps)

Resolves the actionable items in `.ai-docs/research/develop-workflow-gaps.md` (field notes from running `/develop` end-to-end). Notably, gap #1 fired on turn one of *this* fix-session — invoking `/develop` from an approved spec couldn't start.

- **`/develop` spec-location mismatch (gap #2)** — `develop.md` hardcoded `.ai-docs/specs/<key>.md`, ignoring `artifact_paths`. Now resolves stack-co-located → legacy like the phase agents, so the planned-spec → develop handoff doesn't silently break. (The `/plan`-writes-specs half of the original note is stale — `plan.md` writes `plans/`, not `specs/`.)
- **`/develop` was Linear-hardcoded (bonus)** — resolved get-issue via the Linear MCP despite `task_management: github`. Now adapter-agnostic, matching the phase agents.
- **Over-promised automation (gap #5)** — added an explicit "What this command automates — and what it does not" table: tracker writes are agent-conditional (no `gh`/MCP ⇒ no write), session logs are not auto-committed.
- **Ambiguous shared-task-list ownership (gap #3)** — declared **lead-owned**. `implementer` and `validator` now carry a hard constraint: do not touch the shared Task list; report progress only via the output envelope `status:` field.

### Added

- **Spec-path entry into `/develop` (gap #1)** — `/develop <spec-path>` jumps straight to Implement (the "we planned, now build" path), skipping Understand/Plan/Spec; Gate 1 is satisfied by the approved-spec handoff. Step 0 disambiguates issue-key vs spec-path.
- **Enforced merge gate via hook (gap #6)** — new `plugin/hooks/gate-guard.sh` `PreToolUse` hook **hard-blocks** `git push` to `main`/`master` and `gh pr merge --admin` (override: `SDLC_GATE_OVERRIDE=1`). Converts the narrative "human gate before merge" into actual control flow that survives a long autonomous loop. **Behavior change for consumers:** pushing to the default branch is now denied by default.
- **Cross-repo isolation guardrail (gap #7)** — new "Cross-repo isolation" section in `dual-worktree-strategy.md` (throwaway worktree/clone for cross-repo work; never mutate a tree another agent owns) + `isolation: "worktree"` wired into `/develop` Step 5.

### Internal

- Filed upstream note `.ai-docs/research/upstream-cc-completed-vs-failed.md` (gap #4 — harness reports a failed teammate as `completed`; out of plugin scope, mitigated plugin-side by trusting the envelope `status:` over the completion notification).

## [0.1.14] — 2026-05-15

### Fixed (live-execution dogfood pass on 0.1.13)

A second agent ran the full SDLC loop end-to-end against a throwaway scratch repo (4 issues × 2 epics × 5 gates each = 20 gate decisions, ~75 min wall time). The loop flowed first-try with 0 blockers in artifacts, but 3 structural blockers surfaced in plugin scaffolding. All fixed in this patch:

- **`/sdlc:critique` and `/sdlc:review` referenced `subagent_type: "sdlc:reviewer"`** — but the plugin's `reviewer` agent is registered as a bare name in the subagent registry, not under the `sdlc:` namespace prefix. Other SDLC agents are double-listed (both forms work); reviewer was the lone exception. Changed both commands to `subagent_type: "reviewer"`. Works in both filesystem-overlay (dogfood) and installed-plugin contexts.
- **`validator` agent's `disallowedTools: Write, Edit` contradicted spec canvas v2** — the validator owns `## Live Validate` per `phases.live_validate.owner: validator` but couldn't write it. The validator worked around via `Bash → python3` mutations, which technically bypasses the constraint and undermines its purpose. Removed `Edit` from the denylist (same shape as `reviewer`); added explicit Step 6 ("Write to spec phase section") with a `git add && git commit` follow-up to isolate the phase-log write. Validator constraints updated to allow Edit only against the `## Live Validate` section, not other spec content.
- **Agent Bash writes to tracked spec files accumulated as uncommitted mutations** — and were nearly lost via a `git stash drop` during a cross-branch `gate_mode` switch. Recovery only worked via `git fsck --unreachable` dangling-object hunt. Reviewer + validator now require an immediate `git add && git commit` after each phase-section write (matches implementer's existing chore-commit convention). Added to constraints + Step 6 of both agents.

### Added

- **`reviewer` phase** entry to envelope canvas `required_per_phase` + `default_attention`. Schema bumped to accept new fields (`mission`, `verdict`, `findings_count`) on reviewer envelopes. Joined output from `/sdlc:review` paired mode reuses `phase: reviewer` with `joined: true` + `lenses_run: [...]` + `artifact.paths: [...]` (array) — no separate `reviewer-joined` phase mapping needed.
- **Tightened "spec-blind" definition** in reviewer's Step 1 — distinguishes "do not Read the spec's prose sections" (forbidden under `lens=quality`) from "MAY Read the spec file for phase-section markup discovery" (allowed; needed for Edit precision). The previous wording could be misread to forbid all file access, which would have prevented the reviewer from writing its own phase section.

### Internal

- Envelope canvas schema regex extended to accept `reviewer` alongside other phase names in `required_per_phase` and `default_attention`.
- All four canvases (spec, plan, quality-checks, envelope) validate against their schemas via ajv.
- Dogfood findings doc archived at `/tmp/sdlc-dogfood-2026-05-15/dogfood-findings.md` (~479 lines, 9 phase blocks + final verdict).

## [0.1.13] — 2026-05-15

### Added

- **`critique` skill** at `plugin/skills/critique/` — generic critic discipline applicable to any SDLC artifact (spec, plan, diff, ADR). Defines verdict taxonomy (`PASS` / `PASS_WITH_NOTES` / `REVISE` / `BLOCK`), finding categories (blockers / notes / nits), lens taxonomy (`adherence` / `quality` / `logic` / `scope` / `mixed`), and join semantics for multi-lens runs. The `quality` lens is structurally spec-blind by construction. Loadable inline by any agent or the lead; forks to subagent for context isolation.
- **`reviewer` agent** at `plugin/agents/reviewer.md` — runtime role that loads the `critique` skill. One reviewer per (target, lens) pair. Reads mission from spawn prompt, applies discipline, writes verdict to spec phase section via Edit, posts tracker envelope. Used at Gate 1.5 and Gate 2.5; supports REVISE re-runs via explicit `rerun: true` flag.
- **`/sdlc:critique <ISSUE-KEY>`** command — Gate 1.5 single-reviewer entrypoint (`lens=mixed` against cited code). Catches spec defects (wrong line numbers, miscounted call sites, missed constraints, citation drift) before the implementer cycle wastes the cost. Detects re-runs after REVISE automatically and passes `rerun: true`.
- **`/sdlc:review <ISSUE-KEY>`** command — Gate 2.5 paired-lens entrypoint. Spawns two reviewers sequentially (`lens=adherence` against the spec, then `lens=quality` against the quality canvas). Joins verdicts: the worse of the two wins; findings union. Sequential (not parallel) because both reviewers Edit the same spec file and harness doesn't guarantee Edit serialization across concurrent subagents.
- **Spec canvas v2** (`plugin/canvases/spec/`) — adds a 6-section phase execution log (`Spec Review`, `Design Addendum`, `Implementation notes`, `Diff Review — Adherence`, `Diff Review — Quality`, `Live Validate`) appended to the static spec. Each phase section owned by exactly one agent + gate (declared in `instructions.yaml.phases.*` with `triggered_by: { command, lens, target, against }` for mechanical resolution). New top-level knobs: `append_mode: true`, `implementer_view: annotated | clean`, `tracker_comment.mode: status_envelope | full_content`, `tracker_comment.spec_link: permalink | branch_relative`. Schema bumped v1 → v2; old v1 specs render unchanged (new phase sections appear as empty placeholders).
- **`quality-checks` canvas** at `plugin/canvases/quality-checks/` — registry of named quality categories consumed by the reviewer's `quality` lens. Ships with three starter categories: `convenient_fallback` (the AGENTS.md "missing-data-looks-like-empty-data" rule), `convention_workaround` ("coding around your own framework"), and `magic_constants` (3+-repeat literals looking for a name). Each entry carries `patterns_to_flag`, `counter_examples`, and a `severity_hint`. Project authors override at `.claude/canvases/quality-checks/categories.yaml` (entries with matching `id` replace; novel `id`s extend).
- **`sdlc-author` agent** at `plugin/agents/sdlc-author.md` — narrow file-author subagent for SDLC artifacts that don't have a dedicated phase agent (ADRs, RFCs, ad-hoc design docs, handoff notes, batch spec drafts). Tools: `Read, Write, Edit, Glob, Grep` only — no Bash, no tracker MCP, no recursion. Sits between `specifier` (full phase workflow) and `general-purpose` (too broad).
- **`gate_mode: interactive | auto-all`** in `sdlc.example.yml` — cross-gate envelope governing Gate 2 (PR review) + Gate 3 (validate). `interactive` (default): implementer opens a PR, validator posts to it. `auto-all`: implementer pushes branch and posts a tracker comment, validator posts to the tracker, no PR. Composes with existing `gate1_default` (strict / auto) to express the full matrix. Agents branch on `modes.<gate_mode>.{pr_required, validator_post_target}` rather than on `gate_mode` directly so new modes ship by extending `sdlc.yml.modes` without touching agents.
- **`spec_storage: file | inline | both`** in `sdlc.example.yml` — controls whether spec content lives in the spec file (default) with tracker comments as ≤15-line status envelopes pointing to it, or inline in tracker comments (legacy). Spec canvas's `tracker_comment.mode` defaults track this value.
- **`stack_topology: per_plan | per_epic`** in the plan canvas — when `per_epic`, `/sync-issues` emits one `st create --base` command per epic in the report, chaining child stacks to the prior epic's last branch. Branches don't exist yet at sync time (forward-looking); the human runs them incrementally as each epic's first issue comes online.
- **Plan-key rewrite in `/sync-issues`** — after issues are filed, rewrite `plan.yaml` in place: replace each local `key:` with the tracker-assigned key (lowercased; matches `gitBranchName` convention), preserve the original as `key_original:`, and update all `depends_on:` / `parallel_with:` / epic `issues:` references. Eliminates the permanent translation table that drives accumulate between local plan keys and tracker keys.
- **Epic status cascade contract** in `plugin/primitives/task-management/{linear,github}.md` — defines automatic parent-epic status moves on child transitions (`Backlog → In Progress` on first child; `In Progress → In Review` when all children are `In Review`/`Done`; `In Review → Done` when all children are `Done`). Governed by `sdlc.yml.epic_cascade.*` knobs. **Contract is defined; v2 follow-up wires the actual execution into validator + a new `/sdlc:done` command.**
- **`/sdlc:critique` / `/sdlc:review` chain from implementer envelope** — under `gate_mode: auto-all`, implementer sets `next.command: "/sdlc:review <ISSUE-KEY>"` so an orchestrator or lead session can fire Gate 2.5 without manual lookup.

### Changed

- **`sdlc-loop` skill** — refreshed gates table with Gate 1.5 (spec critique) and Gate 2.5 (paired diff review), updated loop diagram with the new flow, added Gate 1.5 / Gate 2.5 / gate-mode sections. Ordering note: Gate 1.5 runs BEFORE Gate 1 (critique → human approval); previously implicit, now documented.
- **`specifier` agent** — `Tracker comment` section splits on `tracker_comment.mode`. Under `status_envelope` (default), emits a ≤15-line `[Design]` envelope with permalink. Under `full_content`, emits the legacy inline shape.
- **`implementer` agent** — Step 8 (Open the PR) branches on `modes.<gate_mode>.pr_required`. Under `interactive`, opens a draft PR. Under `auto-all`, skips PR and posts a tracker comment with branch + commit. Envelope `next.command` chains accordingly.
- **`validator` agent** — Step 5 (Post the report) branches on `modes.<gate_mode>.validator_post_target`. Under `pr`, posts to the open PR (existing behavior). Under `tracker`, posts to the tracker issue directly via the configured tracker MCP.
- **`spec_critic_max_iterations` knob** — was a placeholder; now actually caps the design ↔ critique loop. Cap-hit is a structured halt, not a failure.

### Internal

- Spec canvas `instructions.schema.json` extended to validate `phases.*.triggered_by`, `append_mode`, `implementer_view`, and `tracker_comment.{mode, max_lines, spec_link}`.
- Plan canvas `instructions.schema.json` extended to validate `stack_topology`, `epics` array shape, and `key_original` as an issue optional field.
- All new YAML/JSON files validated against schemas via `ajv` in dev; no runtime breakage on existing v1 plan / spec instances.

## [0.1.12] — 2026-05-14

### Added

- **Real-time chat view alongside the existing trace viewer.** The cc-viewer dashboard now has two pages: `/logs` (the existing hook-event trace viewer, renamed from `ClaudeCodePage`) and `/chat` (a session list + per-session chat thread). `/chat/:sessionId` renders the actual Claude Code conversation — user prompts, assistant text and thinking, tool calls and results, model + token usage — live as the session progresses. Root path redirects to `/chat`.
- **`tools/cc-bridge/` — new local daemon, sibling to cc-viewer.** Watches per-session JSONL transcripts under `~/.claude/projects/` and forwards new lines to cc-viewer as `TranscriptDelta` events. Polling-based with optional `fs.watch` for sub-second reaction, per-session position cursor persistence at `~/.local/state/cc-bridge/positions/<id>.pos`, idle-timeout reaper for crashed-CC sessions. Single-binary build via `bun build --compile`, shipped via the same release pipeline as cc-viewer (entry added to `plugin/lib/tools.json`). HTTP control surface on `localhost:3994` (`/health`, `/sessions/register`, `/sessions/deregister`, `/admin/state`).
- **`/hooks/TranscriptDelta` ingest endpoint on cc-viewer.** Accepts one POST per JSONL line from cc-bridge. Dedupes on `(session_id, line_uuid)` via UNIQUE constraint on the new `transcript_entries` SQLite table. Broadcasts to SSE clients on the `claude_code.transcript_delta` channel. `GET /admin/claude-code/sessions/:id/transcript` returns the full ordered transcript for cold-load on chat page open.
- **`plugin/hooks/ensure-cc-bridge.sh`** spawns + registers the active session at SessionStart (sibling of `ensure-cc-viewer.sh`). **`plugin/hooks/deregister-cc-bridge-session.sh`** on SessionEnd. Both fail silently — telemetry never blocks the user.
- **`react-router-dom` + sidebar `AppShell`** in the viewer SPA (`Logs` / `Chat` nav). Proper atomic layout: `atoms/Cursor`, `molecules/{Avatar,Markdown,MessageFooter,WaitingIndicator}`, `organisms/{ChatPanel,MessageRow,parts/{TextPart,ThinkingPart,ToolCallPart,ErrorPart}}`, `templates/AppShell`.
- **Yellow "warming up" state on the statusline dashboard dot.** `ensure-cc-viewer.sh` drops a `~/.local/state/cc-viewer/warming-up` marker on spawn; the dashboard pill in `statusline.sh` renders yellow (`\033[33m`) instead of red while the marker is fresh (`< 15s`) and `/health` hasn't bound yet. Cleared automatically once `/health` answers; falls back to red once the warmup window expires.

### Fixed

- **SSE reconnection loop.** `Bun.serve`'s default `idleTimeout: 10` was closing `/admin/events/stream` every 10s, putting the dashboard's connection badge into permanent "reconnecting…". Now `idleTimeout: 0` plus a 15s `:keepalive` comment frame pushed by `SSEBroadcaster`.
- **EventSource `onopen` could lag up to 15s** on a freshly-loaded page because the broadcaster sent no initial bytes. `SSEBroadcaster.connect()` now emits an immediate `:keepalive` frame so the browser transitions out of `CONNECTING` state instantly.
- **`fs.watch` ENOENT at SessionStart.** cc-bridge previously gave up watching a transcript that didn't exist yet when register fired (CC hadn't written the JSONL). Replaced with a periodic poll-flush (every 1.5s) that opportunistically (re-)attaches `fs.watch` once the file exists.

## [0.1.11] — 2026-05-13

### Changed

- **Statusline is now installed opt-out, automatically.** New `SessionStart` hook `plugin/hooks/ensure-statusline.sh` writes the SDLC statusline wiring into `~/.claude/settings.json` on first session after `/plugin install sdlc`. Drops a marker at `~/.cache/claudecode-patterns/statusline-installed`; if the user later removes the `statusLine` block, the marker ensures the hook never re-installs (opt-out is non-recidivist). Only touches wiring whose path is under `claudecode-patterns/sdlc/` — third-party / user-custom `statusLine` values are left alone. Malformed `settings.json` is never clobbered.
- **Legacy `dashboard-status.sh` auto-upgrades to `statusline.sh`.** The same hook detects any `statusLine.command` still pointing at the old `dashboard-status.sh` script and rewrites it in place to `statusline.sh`. Other settings keys are preserved. One-line stderr log on the upgrade boot, silent thereafter.
- **`/sdlc:setup` Step 10 is now a reporter, not an installer.** The SessionStart hook owns install + upgrade. Setup only prompts on the third-party-`statusLine` branch where automatic action would be inappropriate.

### Removed

- **`plugin/scripts/dashboard-status.sh`** — the dashboard pill is now inlined directly into `statusline.sh`. The single-segment dot-only experience is no longer a separate wiring target. Existing wirings pointing at `dashboard-status.sh` are auto-upgraded by the SessionStart hook above; no manual action required.

## [0.1.10] — 2026-05-12

### Changed

- **Dashboard is now `cc-viewer`, bundled with the plugin.** Replaced the external `ap playground` (from `@agentic-patterns/cli`) with the in-monorepo `tools/cc-viewer/` binary. End users no longer need to `npm i -g` anything — the SessionStart hook lazily downloads a single ~25MB binary from the plugin's GH release on first session, caches it under `~/.local/state/cc-viewer/bin/cc-viewer-v<plugin-version>-<platform>`, then spawns it detached.
- **`plugin/lib/tools.sh` — runtime install primitive.** Exposes `ensure_tool <name>` and `tool_binary_path <name>`. Reads `plugin/lib/tools.json` for the platform list, the plugin's own `plugin.json` for the version, and the `homepage` field to derive the GH owner/repo. Verifies SHA256 from the release's `SHA256SUMS` when available. Silent no-op on missing curl / unsupported platform / network failure — telemetry never blocks a Claude Code session.
- **`plugin/hooks/ensure-cc-viewer.sh`** replaces `ensure-playground.sh`. Same payload-capture + health-poll + SessionStart-replay logic, now driven by `ensure_tool cc-viewer` instead of `command -v ap`.
- **`plugin/hooks/emit.sh`** retargeted from `AP_DASHBOARD_URL` / `:3456` to `CC_VIEWER_URL` / `:3993`. Backward-compatible: still honors `AP_DASHBOARD_URL` for users mid-upgrade.
- **`plugin/scripts/dashboard-status.sh`** + **`statusline.sh`** probe `:3993` by default (was `:3456`); `AP_DASHBOARD_PORT` still respected for transition.
- **`/sdlc:setup` Step 9** rewritten as a conversational install offer. Probes the cache via `tool_binary_path`; if absent, AskUserQuestion to download via `ensure_tool` (same code path the hook uses); explains failures (no tarball / no network / proxy) without halting setup.

### Migration notes

- Users on 0.1.8 with `ap` running will continue to see telemetry POST against `:3456` via the legacy env var until they restart Claude Code. After restart, the SessionStart hook downloads cc-viewer and the new port (`:3993`) takes over.
- The `ensure-playground.sh` file is deleted. Hook manifests outside this plugin that referenced it directly will need to switch to `ensure-cc-viewer.sh`.

## [0.1.9] — 2026-05-12

### Added

- **`tools/` workspace + cc-viewer dashboard inlined into the monorepo.** `tools/cc-viewer/` brings the self-contained Claude Code session viewer (Hono + bun:sqlite + embedded React SPA) into this repo so the plugin's version drives the viewer's version. `bun build --compile` produces a single ~60MB binary per platform with the SPA embedded via Bun's `with { type: "file" }` imports — no runtime dependency on `node` or `bun` for end users.
- **`plugin/lib/tools.json` — tool registry.** Declarative manifest of which binaries ship with the plugin and on which platforms. Single source of truth for both the release workflow's build matrix and the runtime install primitive (next release).
- **`.github/workflows/release.yml` — tag-triggered binary release.** On `v*` tags, derives a (tool × platform) matrix from `tools.json`, builds each cell on a native-arch runner, packages tarballs + SHA256SUMS, attaches to the GH Release. Asserts the tag matches `plugin.json` version so the runtime install path can key by plugin version directly.
- **`tools-typecheck` job in `verify.yml`.** Cheap PR feedback for every tool under `tools/` — loops over `tools.json` source_dirs and runs `bun run typecheck` on each. New tools picked up automatically.
- **`just viewer::*` recipes** (`build`, `dev`, `typecheck`, `clean`) for local dev against `tools/cc-viewer/`.

### Note

This release ships the build/release infrastructure but does NOT yet retarget the plugin's SessionStart hook from `ap playground` to the bundled cc-viewer binary. That swap (plus `plugin/lib/tools.sh` install primitive) lands in 0.1.10.

## [0.1.8] — 2026-05-13

### Changed

- **PR segment is a clickable hyperlink + CI segment is semantically colored.** The PR segment now renders bold (breaking out of the global dim wrap so it pops as the focal item) and wraps an OSC 8 hyperlink to `https://github.com/<owner>/<repo>/pull/<n>` — clickable in iTerm2 / Kitty / WezTerm. The CI segment is colored by state: red for `CI N failing`, yellow for `CI N running`, green for `CI N ✓`. Both segments re-enter the dim wrap immediately after their own escapes close, so the rest of the line stays uniformly muted. Built with `printf -v` to keep the OSC 8 byte sequence intact across bash versions (ANSI-C quote concatenated with double-quoted `${var}` was producing literal `\033` strings in some shells).

## [0.1.7] — 2026-05-13

### Changed

- **`statusline.sh` UX polish.** Two fixes after dogfooding on `main`:
  1. **Actual visual centering.** Previous version padded with regular spaces; Claude Code's UI trims leading whitespace and left-aligned the result. Now pads with U+00A0 (non-breaking spaces) which survive the trim and render the same width — the line is now centered as designed.
  2. **Always show branch + project when no ticket.** Previously, on `main`/`master`, every segment except the dashboard pill gated out, leaving a single-element line (`● dashboard`) with no context about which repo or branch you were on. New rules: always show branch (drop the main/master suppression for that segment); show the cwd basename as a "project" segment when no ticket was parsed. Result: `agent-patterns · main · ● dashboard` on main, `AP-16 · dugmcfarlane/ap-16-foo · ● dashboard` on a feature branch — both informative.

## [0.1.6] — 2026-05-13

### Added

- **Version-bump enforcement (`plugin/scripts/verify-version-bump.sh` + CI).** A new `version-bump` job in `.github/workflows/verify.yml` fails any PR that modifies files under `plugin/` without bumping `plugin/.claude-plugin/plugin.json` `version`. Closes the foot-gun where PRs merge to `main` but `/plugin update sdlc` is a no-op for existing consumers because the version string is unchanged. The script is no-op outside the plugin source tree, so it stays safe if it ever runs in a user project. Falls back from `$GITHUB_BASE_REF` → `origin/main` → `HEAD~1`; explicitly skips the first-commit edge case. Required-check name (`plugin/ changes require version bump`) is independent of the existing `invariants (canvases + tool groups)` check so branch protection can be configured incrementally.

- **Full SDLC status line (`plugin/scripts/statusline.sh`).** Companion to `dashboard-status.sh` — renders a centered, ANSI-dim line composed of independent segments: active ticket (parsed from branch using `team_key` from `.claude/sdlc.yml`), current branch, `st` stack name, PR number + state, CI rollup summary, and the dashboard pill (composed by calling `dashboard-status.sh`). Each segment auto-detects its source and drops out silently when absent — works on `main`, on non-AP branches, without `gh`, without `st`, without `jq`, etc. Slow probes are cached under `$XDG_CACHE_HOME/ccp-statusline/` (5s for `st`, 20s for `gh`) so the UI never blocks. Pure bash 3.2 compatible; no `node` required. Wired into `~/.claude/settings.json` by users who want more than the dashboard pill — README documents the snippet. Same plugin-distribution caveat as `dashboard-status.sh` (top-level `statusLine` only valid in user scope, not plugin manifest).

## [0.1.5] — 2026-05-12

### Added

- **`/sdlc:setup` now offers to wire the dashboard status line.** New Step 10 inspects `~/.claude/settings.json` and offers to add (or replace) the user-scope `statusLine` so the plugin's `dashboard-status.sh` (green/red clickable dot, OSC 8 hyperlink to the local `ap` dashboard) renders in **every** Claude Code session, not just this project. The wiring uses a glob (`~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/dashboard-status.sh`) so `/plugin update sdlc` does not break it. Idempotent — re-running on a machine that's already wired is a no-op. Skip path leaves the file untouched. Documented in the README's "Optional: dashboard status line" section. (Plugin-bundled `settings.json` cannot ship a top-level `statusLine` — the loader only honors `agent` and `subagentStatusLine` there — which is why this lives in user scope.)

### Changed

- **Telemetry hooks rewritten as pure-bash + curl (no node).** `plugin/hooks/emit.mjs` and `plugin/hooks/check-config.mjs` replaced by `emit.sh` and `check-config.sh`. The ~25 lifecycle hook commands in `plugin/hooks/hooks.json` now invoke `bash ${CLAUDE_PLUGIN_ROOT}/hooks/emit.sh <Event>` instead of `node ${CLAUDE_PLUGIN_ROOT}/hooks/emit.mjs <Event>`. Behavior is preserved 1:1: same `${AP_DASHBOARD_URL:-http://localhost:3456}/hooks/<Event>` endpoint, same 500ms timeout, same optional `x-ap-runner-correlation-id` header from `AP_RUNNER_CORRELATION_ID`, same stderr log format (`[ap-hook] <Event>: <msg>`), same `exit 0` discipline. `check-config.sh` emits the same UserPromptSubmit JSON when `.claude/sdlc.yml` is missing. The whole plugin — setup, telemetry, status line — now runs on machines without `node` installed (Python / Go / Rust projects, or asdf/mise/nvm pinning to an unavailable version). **Heads-up for `@agentic-patterns/cli` maintainers:** the previous `emit.mjs` header claimed `ap init --with-plugin` copied that file verbatim into user projects; if `ap` still does this, it needs to copy `emit.sh` now or grow its own embedded shim.

### Fixed

- **`$PLUGIN_ROOT` resolver in `/sdlc:setup` no longer assumes `node` is installed.** The setup skill previously shelled out to `node -e ...` to parse `installed_plugins.json`, which fails on Python / Go / Rust / etc. projects where `node` may be absent or pinned via asdf/mise/nvm to a version that isn't installed locally. Resolver now tries `jq` → `python3` → `node` → pure-shell `grep`/`sed` and uses the first one that succeeds. The pure-shell branch has zero external deps and works on every machine.

## [0.1.4] — 2026-05-12

### Fixed

- **`/sdlc:setup` no longer halts on a phantom env var.** The preflight check required `${CLAUDE_PLUGIN_DIR}`, which is not a real Claude Code token (PR #71 fixed the same bug in hook command strings but missed the setup skill body and the plugin-manifest template). Worse, even the canonical `${CLAUDE_PLUGIN_ROOT}` is only substituted into plugin-manifest files at config-parse time — not into slash-command markdown executed by the model. The skill now resolves the plugin install path at runtime from `~/.claude/plugins/installed_plugins.json` (key `sdlc@claudecode-patterns`) and uses it as `$PLUGIN_ROOT` throughout. Halt messages now point at the real failure mode (missing/corrupt install registry).
- **`skills/claude-platform/templates/plugin-manifest.json`** — same `${CLAUDE_PLUGIN_DIR}` → `${CLAUDE_PLUGIN_ROOT}` rename PR #71 applied to live hook configs, now also applied to the template developers copy when writing new plugins.

### Known follow-ups (not in this PR)

- Several docs and comments still mention `${CLAUDE_PLUGIN_DIR}` as if it were a meaningful token: `plugin/sdlc.example.yml`, `plugin/primitives/path-resolution.md`, `plugin/scripts/verify-canvases.sh`. These are explanatory prose; cleaning them up needs a separate decision about what name to canonicalize in narrative documentation (the answer differs by surface — plugin-manifest files use `${CLAUDE_PLUGIN_ROOT}`, skill bodies should resolve at runtime).

## [0.1.2] — 2026-05-11

### Fixed

- **Bootstrap session is no longer invisible on the dashboard.** When `ensure-playground.sh` has to spawn `ap playground` (i.e. the dashboard was down), the parallel `emit.mjs SessionStart` hook races against an unstarted server and gets connection-refused — the SessionStart event for the very session that bootstrapped the dashboard was being lost. The script now captures the hook's stdin payload, detaches a small subshell that polls `/health` until the dashboard is up, then re-POSTs the captured payload to `/hooks/SessionStart`. When the dashboard is already responding at probe time, replay is skipped (the parallel `emit.mjs` handles it normally — no duplicate fire).

## [0.1.1] — 2026-05-11

### Fixed

- **Hooks now actually fire.** Hook registrations were inlined under `components.hooks` in `plugin.json`; Claude Code's loader reads `hooks/hooks.json` instead. All 29 documented Claude Code lifecycle events are now captured. ([#71](https://github.com/pattern-stack/claudecode-patterns/pull/71))
- **Path expansion in hook commands.** Hook command strings used `${CLAUDE_PLUGIN_DIR}`, which is not a Claude Code template-substitution token. Swapped to the canonical `${CLAUDE_PLUGIN_ROOT}`. ([#71](https://github.com/pattern-stack/claudecode-patterns/pull/71))
- **`skills/claude-platform/reference/settings.md`** now lists all 29 canonical hook events. The previous count was 25 — missing `Setup`, `UserPromptExpansion`, `PostToolBatch`, `WorktreeRemove`. ([#71](https://github.com/pattern-stack/claudecode-patterns/pull/71))

### Added

- **Auto-launch dashboard on SessionStart.** New `plugin/hooks/ensure-playground.sh` probes `localhost:3456/health` and, when not responding, spawns `ap playground --no-open` in the background via `nohup`/`setsid`. Silent no-op when `ap` is not on PATH or `AP_AUTO_START=0`. ([#72](https://github.com/pattern-stack/claudecode-patterns/pull/72))
- **Telemetry probe in `/sdlc:setup`.** New advisory Step 9 detects the `ap` binary + dashboard state and prints one of three messages (both up / install present but down / not installed) without halting setup. ([#73](https://github.com/pattern-stack/claudecode-patterns/pull/73))
- **README** — new "Optional: live telemetry dashboard" subsection in Quickstart documenting the relationship between sdlc and the separately-installed `@agentic-patterns/cli`. ([#73](https://github.com/pattern-stack/claudecode-patterns/pull/73))

### Note for upgraders

Claude Code's `/plugin update` uses **version comparison** to decide whether to refresh the local cache from the marketplace clone. The 0.1.0→0.1.1 bump in this release is what makes the update actually take effect; otherwise the cache stays at the previously-installed version even though the marketplace tracks `main`.

After updating Claude Code's plugin cache (`/plugin update sdlc@claudecode-patterns`), a fresh Claude Code session is required for the new hook registrations to load.

## [0.1.0] — 2026-05-10

Initial Claude Code plugin release. See [`.ai-docs/stacks/sdlc-plugin-distribution/`](.ai-docs/stacks/sdlc-plugin-distribution/) for the planning + design history.
