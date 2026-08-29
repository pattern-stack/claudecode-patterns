# Changelog

All notable user-facing changes to the `sdlc` Claude Code plugin.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version field lives in [`plugin/.claude-plugin/plugin.json`](plugin/.claude-plugin/plugin.json) — bumping it is what triggers Claude Code's `/plugin update` to actually refresh the cache for existing consumers.

## [0.2.26] — 2026-08-29

### Fixed — `/handoff` no longer clobbers a handoff it did not write

Step 2 said *"Overwrite the existing `handoff.md` if present. Previous version is in git history."*
Both halves fail in practice, and the failure is silent and unrecoverable:

- **`.ai-docs/` is commonly untracked**, so there is no git history to fall back on. The overwrite is
  permanent.
- **A project may keep its running state elsewhere** — a published artifact, a tracker epic, a shared
  doc — leaving `handoff.md` as a *pointer* to it. Found live: a project moved its handoff to a
  living artifact and left a pointer behind carrying the protocol, the local decision record, and the
  plan; the next `/handoff` following step 2 literally would have replaced all of it with a five-line
  stub, with nothing in git to restore.

`/handoff` now reads the file before replacing it, honors a declared "the handoff lives elsewhere"
pointer by updating that destination instead, and checks `git ls-files --error-unmatch` before
overwriting a file it did not write. The constraint is restated in **Constraints** so it survives a
skimming read.

| Changed | What |
|---|---|
| `plugin/skills/handoff/SKILL.md` | step 2 read-before-overwrite + the untracked caveat; frontmatter description; a new **Constraints** bullet |

## [0.2.25] — 2026-08-10

### Added — `driving-mode`: hands-free voice, one message at a time

A per-turn spoken-summary protocol for a user who **cannot look at the screen** — driving, walking, running Claude Code by voice from a phone. Every turn opens by speaking a 2–3 sentence summary aloud; the written response becomes an archive nobody reads until later. Ported from a project-local `tts` skill that ran live for several hours on 2026-08-10, and generalized so it works in every project.

| Added | What |
|---|---|
| `plugin/scripts/driving-mode.mjs` | the engine — OpenAI `tts-1`/`nova` → `afplay`, macOS `say` fallback, playback mutex |
| `plugin/scripts/driving-mode` | bash shim (prefers `bun`, falls back to `node`) for projects that vendor it locally |
| `plugin/skills/driving-mode/SKILL.md` | activation phrases, the per-turn protocol, summary rules, key resolution, known limits |
| `plugin/sdlc.justfile` | `just sdlc::say "…"` |

**Zero npm dependencies** — nothing outside `node:` builtins, same rule as `guided-tour`.

### The two rules the live session bought

**1. One message at a time — playback is serialized by a mutex.** The old guidance was "background it with `&`, never block": correct for one message per turn, wrong across rapid consecutive turns. **Three voice messages played simultaneously** and the listener understood none of them. Audio has no scrollback, so a message lost to overlap is lost for good.

The fix is not "stop backgrounding it" — blocking would stall the turn for the length of the audio. The script splits the job instead: **synthesis stays parallel** (it's the slow network half), **playback serializes**. Messages queue and play back-to-back with no dead air — three simultaneous fires measured 10s instead of ~4s, i.e. queued rather than stalled.

The lock is an atomic `mkdir` in the temp dir with a stale-lock reclaim (5 min — a killed process can't strand the queue), a hard wait ceiling (10 min — it can never deadlock), and `SIGINT`/`SIGTERM`/`SIGHUP` handlers that release on the way out. Escape hatches: `TTS_NO_QUEUE=1` skips the queue, `TTS_INTERRUPT=1` kills playback and jumps it. **The mutex is load-bearing and the script says so in a DO-NOT-REMOVE comment** — a future author "simplifying" it away reintroduces the exact bug.

**2. Announce, then wait.** The user listens to music while driving, so a long report that starts unannounced is half-missed before they realize it's for them. When there's something substantial, speak a short ping — *"I've got the review results ready, say when you're ready"* — then **stop and end the turn**, and deliver on the next one. Short acknowledgements and status lines still go immediately; only long reports need the handshake. This is a first-class section of the skill, not a footnote.

### Generalized out of its origin project

- **Key resolution carries no project path**: `OPENAI_API_KEY` → `TTS_KEY_FILE` → `~/.config/claude-tts/key`. The old project-named location keeps working via `TTS_KEY_FILE`; the skill documents both the copy and the point-at-it migration.
- **Lock file renamed** to a neutral `claude-driving-mode.lock`. Consequence, documented: a leftover project-local copy of the old script has its *own* lock and will talk over this one — delete it.
- `TTS_MODEL` / `TTS_VOICE` overrides preserved (defaults `tts-1` / `nova`), as is the `say -v Samantha -r 195` fallback for a machine with no key.
- **Path resolution is version-pinned, not globbed.** Several plugin versions coexist in the cache, so the skill resolves the newest `driving-mode.mjs` once at activation (`ls -d … | sort -V | tail -1`) and reuses the literal path — a bare `*` glob can pick a stale version, and extra matches would be *read aloud as text*.

### Carried over unchanged

Activation phrases ("driving mode", "tts on", "I'm driving", "walking", "read it to me", "hands-free"; exits on "tts off", "I'm parked"), **confirm activation by speaking it, not printing it**, and the summary rules: ≤75 words, 2–3 sentences, lead with the takeaway, no code/paths/URLs/markdown, `Heads up:` prefix for errors, decisions phrased as spoken questions. Plus the two operating facts: **never spawn a subagent per utterance** (~6–7s wake cost for no benefit — invoke directly via Bash), and **written prose is invisible while active**, so any question needing an answer must be asked aloud.

### Changed vs the script it was ported from

Behavior is otherwise identical. Three deliberate differences:

- `acquireLock()` is now **reentrant** — the fallback path can ask for a lock it already holds. Previously that would have spun for the full 10-minute ceiling in silence before recovering.
- `TTS_INTERRUPT=1` also `pkill`s `say`, not just `afplay` — the interrupt was a no-op when running on the fallback voice.
- Added a `--help`/no-arg usage line.

### Known limits (documented in the skill, not fixed here)

- **macOS only.** `afplay` for playback, `say` for fallback; no Linux/Windows path.
- The mutex is per-machine **per script copy** — a differently-named copy has its own lock.
- `TTS_INTERRUPT=1` is process-wide `pkill`; it stops unrelated `afplay`/`say` audio too.
- Stale-lock reclaim is time-based, not PID-based.
- **No text sanitation** — whatever is passed is spoken, markdown included. Keeping it clean is the summary rules' job, not the script's.
- Every utterance is a billed network call; a dead zone silently degrades to the system voice.
- **Nothing enforces the mode** — staying in it is model discipline across turns, with no hook to fail a turn that forgot to speak.

## [0.2.24] — 2026-08-09

### Added — `guided-tour`: one tour definition, a demo and a check

A frontend UI-validation capability. A tour is a plain data module describing a path through the app — go here, click that, expect this text — and it runs two ways:

- **narrate** — drives the user's **real** browser (Arc/Chrome) over raw CDP. A cursor glides to each target, a ring highlights it, a click leaves a ripple, a caption trails the pointer, and a banner narrates each step. For demos and human-watchable walkthroughs.
- **verify** — same steps, no theatre and no dwell time. Captures screenshots + console errors + failed/4xx requests, evaluates `expect` assertions, writes `report.json`, exits non-zero on failure.

Write it once for the demo, keep it as the check.

| Added | What |
|---|---|
| `plugin/scripts/guided-tour.mjs` | the engine — exports `runTour(tour, opts)`, plus a CLI entrypoint |
| `plugin/skills/guided-tour/SKILL.md` | both modes, tour authoring, step vocabulary, selector forms, known limits |
| `plugin/skills/guided-tour/examples/example-tour.mjs` | annotated reference tour (placeholder URLs only) |
| `plugin/sdlc.justfile` | `just sdlc::tour` / `just sdlc::tour-verify` |

**Step vocabulary:** `goto`, `say`, `click` (+`label`), `fill`, `expect`, `waitFor`, `shot`, `dwell`, `optional` — executed in that fixed order within a step. **Selectors:** `text=` (shortest leaf match), `css=`, or raw CSS.

**Tours live in the consuming project** at `.claude/tours/<name>.mjs` — the engine ships with the plugin, the tour ships with the app it describes. They are agent-authored, committed, and reviewed in PR like any other source file. Base URL resolves from `.claude/sdlc.yml → browser.frontend_url` and is passed as `--base-url`; no project URL or port is hardcoded anywhere in the skill or engine. No `tours_dir` config key — the path is a fixed convention, and a knob for it would only be a way for the two to disagree.

**Zero npm dependencies.** Node 22+ ships a global `WebSocket`, so the engine imports nothing outside `node:` builtins and needs no install in any project, in any language.

`browser-pilot` gains the skill and a "promote a settled path to a tour" operating pattern. `design-grader` was deliberately **not** wired — it grades static surfaces against a design reference; flows aren't its job.

### Added — the Arc + Playwright finding, recorded in the `browser` skill

`skills/browser/SKILL.md` recommended Playwright paths that **hang** against Arc. Its "Arc specifics (hard-won)" section now records the finding:

> Playwright's `chromium.connectOverCDP()` hangs against Arc — the websocket connects, then the handshake never completes and dies on the 30s timeout. Verified 2026-08-10 against Arc on Chrome/149.0.7827.156. Raw CDP against the *exact same endpoint* works perfectly (`Target.getTargets`, `Browser.getVersion`, `Target.createTarget`, `Input.dispatchMouseEvent`).

With the practical consequences spelled out: the `playwright` MCP server is unaffected (it runs `--headless --isolated` against its own browser — the hang only bites code that *attaches* Playwright to the user's Arc); to drive the user's Arc, use the `chrome-devtools` MCP server or speak CDP directly; not known to affect Chrome/Brave/Edge. This is why `guided-tour.mjs` is raw CDP rather than Playwright.

### Known limits (documented in the skill, not fixed here)

Ported faithfully from a v1 proven live — it passed 4/4 assertions against a real app and caught 4 real HTTP 404s the UI was swallowing. Shipping it now, iterating later. The honest inventory:

- **`verify` is not yet a CI gate.** Both modes need a CDP browser on :9222; verify is a local check today. Headless-in-CI (launch Chromium, point `--cdp` at it) is untested.
- `fill` goes through `HTMLInputElement.prototype`'s value setter — no `<textarea>`, `<select>` or contenteditable.
- `expect` only sees `document.body.innerText` — no attribute/count/style/shadow-DOM assertions.
- `text=` can match the wrong element on pages with repeated labels; use `css=` + `data-testid` when precision matters.
- Fixed timings (`waitFor` 15s, nav ~22s, CDP calls 30s), no iframe support.
- `consoleErrors` / `failedRequests` are reported but **do not** fail the run — promoting them is a per-project decision.

### Changed vs the v1 it was ported from

Behavior of every step, the overlay, the resolver and the report shape is unchanged. The differences:

- **CLI entrypoint added.** v1 duplicated the runner boilerplate (argv parsing, report printing, `process.exit`) in every tour file; it now lives in the engine and tour files are pure `export default { … }` data. `runTour` is still exported for programmatic use.
- **`--base-url` override**, so callers resolve the URL from `sdlc.yml` instead of a tour pinning one machine's ports.
- **Preflight guards**: a named error when the CDP endpoint is unreachable (v1 threw a bare `fetch failed`), and when `WebSocket` is missing (Node < 22).
- **Websocket-open no longer hangs on failure** — v1 awaited `ws.onopen` alone, so a socket error waited forever; it now rejects on error and after 15s.

## [0.2.23] — 2026-08-09

### Fixed — the plugin manifest declared everything under a field Claude Code ignores

`plugin.json` nested all of its component fields under a `"components": { … }` wrapper. **`components` is not a field in the plugin manifest schema** — `skills`, `commands`, `agents`, `outputStyles`, `hooks` and `mcpServers` are all *top-level* keys. Claude Code silently ignores unrecognized top-level fields, so everything inside the wrapper was a no-op. `claude plugin validate` says so plainly: `components: Unknown field 'components'. Claude Code ignores it at load time.`

**Why nobody noticed for 12 releases:** `skills/`, `commands/`, `agents/` and `output-styles/` are scanned by **default**. They loaded the whole time, wrapper or not. Only `mcpServers` has no default location — so it, alone, silently vanished.

**User-visible effect:** the three browser MCP servers this plugin ships — `chrome-devtools`, `playwright`, `lighthouse` — **never registered on any consuming session**, in any project, since they were introduced in 0.2.11. Confirmed on a live install: `claude mcp list` showed no trace of them with `sdlc@claudecode-patterns` enabled. Everything downstream of them was dead on arrival:

- `/browse` and `/verify` — no browser tools to drive
- `browser-pilot` — the 0.2.11 entry below claims its dead MCP config was *fixed* by moving the servers to plugin level. That fix never landed; it moved them into the ignored wrapper.
- `design-grader` / `design-builder` — the design loop's evidence-capture step could not run
- `browser` skill — its "The plugin ships the three MCP servers this skill drives… no per-project setup" was, until now, false

All three now sit at the top level with **pinned versions and args unchanged** (`chrome-devtools-mcp@1.1.1 --browserUrl http://127.0.0.1:9222`, `@playwright/mcp@0.0.75 --headless --isolated`, `@danielsogl/lighthouse-mcp@1.3.0`). After `/plugin update` + a session restart they register for real.

The four path fields were **dropped rather than hoisted**, because each named its own default location and buys nothing at the top level: `skills` *adds to* the default scan (redeclaring it scans `skills/` twice), `commands`/`agents`/`outputStyles` *replace* it with itself, and `agents` rejects a directory outright — the schema takes individual `.md` files there, so the honest top-level spelling would be an enumeration of every agent file that drifts the moment one is added. Component loading is unchanged; it was always the default scan doing the work.

### Fixed — three components were loading with all frontmatter silently dropped

`claude plugin validate` reported `YAML frontmatter failed to parse` on three files, meaning Claude Code loaded each with **empty metadata** — no `description`, no `allowed-tools`, no `argument-hint`:

- `commands/verify.md` and `commands/review.md` — `argument-hint: [url] [--perf]` parses as a YAML flow sequence followed by a second, unexpected flow sequence. Both hints are now quoted.
- `skills/claude-platform/SKILL.md` — the unquoted `description` contained `Managed Agents API: agents, …`; a colon-space inside a plain scalar ends the key. Now quoted.

Values are unchanged in all three — this is quoting only. Practical effect: `/sdlc:verify` and `/sdlc:review` recover their descriptions and argument hints, and the `claude-platform` skill recovers its `description`/`when_to_use` — which is what the model matches on to decide whether to load it, so the skill was effectively undiscoverable by description.

### Added — `claude plugin validate` runs in CI

`verify.yml` now installs the Claude Code CLI (pinned, `2.1.226`) and runs `claude plugin validate ./plugin` inside the existing required `invariants` job. It needs no credentials — a pure local parse. This is precisely the check that would have caught both bugs above on the day they shipped; the wrapper had been in the manifest since the plugin's first release.

### Fixed — the hook-existence CI check had been passing vacuously

`plugin-drift-test.yml`'s "hooks all reference existing scripts" step read `.components.hooks` from `plugin.json` and grepped for `${CLAUDE_PLUGIN_DIR}` — the wrong file *and* the wrong variable. Hooks live in `plugin/hooks/hooks.json` and reference `${CLAUDE_PLUGIN_ROOT}`. `jq` matched nothing, the un-`pipefail`'d pipeline swallowed the error, and the step printed its ✅ regardless. It now reads the right file, and asserts a non-zero extraction count so it can never again pass by matching nothing. It verifies 11 scripts.

### Changed — authoring docs no longer teach the bug

`skills/claude-platform` was the source of the wrong shape: its `templates/plugin-manifest.json` and `reference/plugins.md` both modeled the `components` wrapper. Both now show the flat schema, and `plugins.md` gains a per-field table covering the adds-to/replaces distinction, the `agents`-takes-files rule, the `./` path requirement, and an explicit warning that a wrapped manifest *looks* like it works because the default scans mask it. In-repo references to `plugin.json → components.mcpServers` (`browser-pilot`, `browser`, `browser-driver`) are corrected.

## [0.2.22] — 2026-07-26

### Changed — per-role model + effort baseline

Every SDLC phase agent now ships an explicit `model` **and** `effort` in its frontmatter. Previously only `model` was set, effort was never declared, and `implementer` — the role that writes the most code — ran on `sonnet`.

| role | model | effort | was |
|---|---|---|---|
| `understander` | `opus` | `xhigh` | `opus` |
| `coordinator` | `opus` | `high` | `opus` |
| `implementer` | `opus` | `low` | **`sonnet`** |
| `planner` | `fable` | `xhigh` | `opus` |
| `specifier` | `fable` | `xhigh` | `opus` |
| `reviewer` | `fable` | `xhigh` | `opus` |
| `validator` | `fable` | `medium` | `opus` |

The split: `opus` where judgment is open-ended (research, routing, code-writing), `fable` where the work is authoring/critique against a known frame, or mechanical gate-running.

- **`sdlc.example.yml`'s `phases:` sample now restates this baseline** rather than the old sonnet/opus split, so the documented override sample and the shipped defaults agree. It still ships commented → zero behavior change on its own.
- **`fable` confirmed as a model alias** — verified empirically to resolve to `claude-fable-5` through the spawn-argument path the `phase-tuning` hook writes to. `reference/subagents.md` listed only `sonnet`/`opus`/`haiku` and has been corrected.
- **Note on `/orchestrate`**: its *lead* is the operator's own main session, not a spawned agent. It has no role key and is unreachable by the hook — set it with `/model`.

### Known-unverified

- `effort` honoring remains **beta** (accepted at spawn 2026-07-03; honoring untested) — unchanged from 0.2.20.
- The `fable` alias is proven on the **spawn-argument** path (`sdlc.yml` → `phase-tuning` hook). Resolution of a `model:` alias declared in **frontmatter** could not be re-verified in-session, because the running plugin is served from `~/.claude/plugins/cache/` and the agent registry loads at session start. Confirm after a `/plugin update` + restart.
- `implementer` pairs `opus` with `effort: low` while `sdlc.example.yml` still suggests `max_turns: 60`. Low effort on the heaviest code-writing role may need more turns to converge; raise the cap if it under-converges.

## [0.2.20] — 2026-07-03

### Added — `phase-tuning` hook: per-phase spawn tuning becomes deterministic control flow

Supersedes the 0.2.17 `phase_models` design, which resolved model policy as **prose** — each command's markdown told the spawning model to read `phase_models` and pass `model:` at spawn. That was soft: a long-context spawner could forget, and the override silently wouldn't apply. This ships a hook that takes the model out of the loop.

- **New `plugin/hooks/phase-tuning.sh` (+ `phase-tuning.py`)** — a `PreToolUse` hook (matcher `Agent|TeamCreate`, registered in `hooks.json`) that reads `sdlc.yml` on every spawn and rewrites the tool arguments via `hookSpecificOutput.updatedInput`. Deterministic, per-project, resolved at the spawn boundary — the command prose no longer has to remember.
- **New grouped `phases:` schema** — every knob for a role lives together under `phases.<role>` (block or inline-map form):
  - `model` → `model`, `effort` → `effort` (`low`…`max`), `max_turns` → `maxTurns`, `worktree` → `isolation: "worktree"`.
  - Reads cleaner than four parallel by-knob maps: `phases: { coordinator: { model: opus, effort: high } }`.
  - The legacy global `worktree.enabled` is honored as an alias for `phases.implementer.worktree`, so all worktree policy resolves in one place.
- **Backward-compat**: the flat 0.2.17 keys `phase_models` / `phase_effort` / `phase_max_turns` / `phase_worktree` are still honored as a fallback; a grouped `phases.<role>.<knob>` wins over its flat twin. Existing configs keep working untouched.
- **Precedence preserved**: an argument the spawner set explicitly always wins; an unconfigured role is untouched, so its frontmatter default stands. Ships with the block commented → **zero behavior change**.
- **Fails open**: no python3, no `sdlc.yml`, unparseable input, or any error → the spawn runs exactly as issued. A tuning layer must never wedge a spawn. Covered by `phase-tuning.test.sh` (21 cases).
- **Command/agent prose simplified**: `/develop`, `/orchestrate` + `coordinator`, `/design`, `/plan`, `/critique`, `/review` no longer carry manual `phase_models` resolution steps — they point at the hook.
- **Verified vs experimental**: `model` proven; `effort` accepted at spawn (honoring test pending); `maxTurns` spawn-arg key best-effort; `isolation:"worktree"` proven.

### Added — active model in the shipped statusline

`plugin/scripts/statusline.sh` now leads its line with the active model's display name (from CC's statusline payload), falling back to the model id, and dropping out cleanly when absent.

## [0.2.19] — 2026-07-03

### Shipped — cc-viewer dashboard: project-tree sidebar + a release binary that's current

Release-only bump: cuts a fresh `cc-viewer` binary. The dashboard ships as a per-platform binary attached to the plugin's GitHub Release and version-pinned to `plugin.json`, but the last released binary was `v0.2.9` — so every cc-viewer change since late May (terminal composer, `/`-command palette, and the new sidebar) had merged to source but never reached an installed binary. The version-pinned download for the interim versions 404s and the SessionStart hook falls back to the newest *cached* binary, so `/plugin update` never refreshed the dashboard. Tagging `v0.2.19` rebuilds the binary from current `main` and republishes it; the next session self-upgrades onto it.

- **New: collapsible project-tree left sidebar.** Projects group their sessions; a swarm **lead expands to its teammates**; an **All activity** entry gives the global cross-project view; search filters by session title / first prompt / id.
- **Sessions are titled, not id'd.** A session now shows its teammate role name → swarm summary → first user prompt → worktree → short id, instead of a raw session id. Swarm leads and teammates render distinctly from ordinary chats.
- **One session index** (fetch-once + live SSE, hook-events only) feeds the sidebar, the activity list, and the per-session related-sessions navigator. Ordering is stable under live activity (`firstSeen`).
- To pick it up: `/plugin update`, then start a new Claude Code session — the `ensure-cc-viewer` hook downloads `cc-viewer-v0.2.19` and restarts the dashboard.

## [0.2.18] — 2026-07-03

### Documented — `phase_models` in the top-level config walkthroughs

Follow-up to 0.2.17, which shipped the knob but only documented it inline in `sdlc.example.yml`. The two hand-authored config walkthroughs now surface it where users actually look:

- **`README.md` § "Customize without editing fifteen markdown files"** and **`WORKFLOW.md` § "governed by `.claude/sdlc.yml`"** — both `sdlc.yml` knob snippets now include `phase_models`, framed as the canonical "stronger model for judgment-heavy phases, cheaper for mechanical ones — without forking an agent def" example. No behavior change; docs + version bump only.

## [0.2.17] — 2026-07-02

### Added — `phase_models`: per-phase model policy as project config

Model selection per SDLC phase is now a `sdlc.yml` decision, not a forked agent def. Same shape as `gate1_default` — declared in config, resolved at spawn time.

- **`sdlc.example.yml` → new optional `phase_models:` block.** Maps agent role names (`implementer`, `validator`, `specifier`, `reviewer`, `coordinator`, `planner`, `understander`) to a model alias (`opus` | `sonnet` | `haiku`) or full model ID. Ships **unset** — absent/all-commented means every agent keeps its shipped frontmatter default, so existing behavior is unchanged. The block documents the single resolution rule every spawn point obeys: key set → pass `model:` as the spawn-time override (same channel as `isolation`); key unset → omit it, frontmatter default stands.
- **Threaded into every spawn point**: `/develop` (roster teammates), `/orchestrate` (coordinator teammate) + `coordinator.md` (its implementer/validator subagents), `/design` (specifier), `/plan` (understander, planner), `/critique` + `/review` (reviewer). Each reads `phase_models` from `sdlc.yml` and applies the override at the `Agent(...)` / `TeamCreate` call.
- **Why spawn-time, not frontmatter**: agent frontmatter is static YAML with no interpolation — it can't read `sdlc.yml`. The spawn-time `model:` arg is the only channel that can, and the harness layers it over frontmatter. So no agent def is forked or mutated; policy lives in the repo, visible and per-project.

## [0.2.16] — 2026-06-13

### Added — CI invariant: the plugin's own `hooks.json` can't re-register `WorktreeCreate`

Companion to 0.2.15's `/sdlc:doctor`. `doctor` deliberately doesn't scan plugin-cache hooks (stale cached versions false-positive), so it can't catch the plugin re-shipping the 0.2.12 footgun. This closes that gap from the other side:

- **`plugin/scripts/verify-worktree-hooks.sh`** (+ `just sdlc::verify-worktree-hooks`, added to the `verify` aggregate and wired into the `verify.yml` invariants job). Fails CI if `hooks/hooks.json` registers any `WorktreeCreate` hook — the plugin's policy is *never* register it (worktrees stay harness-managed; `WorktreeRemove` is observer-safe and allowed). Exit `0`/`1`/`2`, `jq`-gated.

## [0.2.15] — 2026-06-13

### Added — `/sdlc:doctor` config health check (+ auto-guard for the WorktreeCreate footgun)

A diagnostic that catches the exact class of silent misconfiguration that 0.2.14 fixed — but in *consumer* projects, where it can't be fixed by editing the plugin.

- **`/sdlc:doctor` command + `plugin/scripts/doctor.sh`** (also `just sdlc::doctor`). Read-only; reports findings with fixes. Exit `0` clean / `1` error(s) / `2` env error. First check, `worktreecreate-provider`, scans the project's `.claude/settings.json`, `.claude/settings.local.json`, `hooks/hooks.json`, and `~/.claude/settings.json` for a `WorktreeCreate` hook registered as a passive provider — `async: true`, or a telemetry emitter (`emit.sh`/`emit.mjs`) that prints no path. Both flavors break every `isolation: "worktree"` Agent spawn with `WorktreeCreate hook failed: hook succeeded but returned no worktree path`. `async`/emitter → **ERROR**; a custom sync command → **INFO** (likely a real provider, just confirm it prints the path). Plugin-cache hooks are deliberately not scanned (stale cached versions would false-positive; each plugin validates its own `hooks.json` in CI). Bash-3.2 safe; requires `jq`.
- **`UserPromptSubmit` guard** — `doctor.sh --hook UserPromptSubmit` is wired into `hooks/hooks.json`, staying silent unless it finds an ERROR (with a fast `grep` pre-filter so it's near-free when clean). The footgun now self-surfaces instead of blocking mid-session. The check is extensible — add a `check_<name>` function in `doctor.sh`.

## [0.2.14] — 2026-06-07

### Fixed — WorktreeCreate telemetry hook broke `isolation: "worktree"` harness-wide

- **Removed the `WorktreeCreate` entry from `hooks/hooks.json`.** The harness gives `WorktreeCreate` PROVIDER semantics, not observer semantics: registering any hook delegates worktree creation to it and expects the created path back. The passive `emit.sh` telemetry shim therefore shadowed the default `git worktree add` — every `Agent` spawn with `isolation: "worktree"` in every plugin-consuming project failed with `WorktreeCreate hook failed: hook succeeded but returned no worktree path`. Reproduced and fix verified end-to-end in fresh sessions (spawn succeeds, temp worktree created + auto-cleaned). `WorktreeRemove` was tested the same way and is observer-safe — its telemetry stays. `hooks.json`'s `description` and `claude-platform/reference/settings.md` now document the provider contract so it can't sneak back in.

### Hardened — shared-tree branch switching (fallout of the isolation outage)

While isolation was broken, sdlc agents fell back to the main working tree — a specifier `git checkout`'d its spec branch under a mid-edit implementer. Defense-in-depth so that can't recur:

- `coordinator.md` spawn snippets now pass `isolation: "worktree"` (mandatory in Topology B) and use the namespaced `subagent_type`s.
- `specifier.md` § 4b and `implementer.md` § 4: never `git checkout`/`git switch` the main working tree — isolated-worktree agents proceed as before; agents that find themselves in the main tree do branch work in a private `git worktree add` (specifier) or halt and request isolation (implementer).

### Fixed — teammates spawned from allowlist agents were mute (broke `/orchestrate`)

Two platform behaviors, verified empirically with live probe teammates (and observed in a real `/orchestrate` run, where all three coordinators failed to report while the denylist-form implementer reported fine):

- **Explicit `tools:` allowlists suppress harness-injected team tools.** A teammate spawned from such an agent has no `SendMessage` — it can receive messages and emits idle notifications, but cannot report up, answer plan-approval, or complete the shutdown handshake (`"SendMessage exists but is not enabled in this context"`). All five allowlist agents (`coordinator`, `planner`, `understander`, `sdlc-author`, `claude-platform-drift-check`) now list `SendMessage` explicitly (verified to work).
- **`Agent(...)` scope args must be registry keys, which for plugin agents are namespaced.** `coordinator`'s `Agent(implementer, validator)` matched nothing — empty spawnable set, every `subagent_type` rejected. Now `Agent(sdlc:implementer, sdlc:validator)`.
- `coordinator.md` § Report up corrected: a teammate's final text is never delivered to the lead — `SendMessage` IS the report channel (the old text claimed the orchestrator polls completion).

### Added — `verify-teammate-tools` invariant check

- **`scripts/verify-teammate-tools.sh`** — catches both footguns at PR time: allowlist agents missing `SendMessage` (denylist agents denying it), and `Agent(...)` scope args that don't resolve (bare plugin-agent names get a "use `sdlc:<name>`" hint). Deliberate non-teammate agents opt out with a `# teammate: never` frontmatter comment. Wired into `just sdlc::verify` and CI (`verify.yml`).
- `verify-tool-groups.sh` now treats team-plumbing tools (`SendMessage`, `Task*`) as orthogonal to capability groups — agents can carry them without breaking canonical-group conformance.
- `claude-platform/reference/subagents.md` documents both behaviors (allowlist-teammate rule + namespaced registry keys).
## [0.2.13] — 2026-06-07

### Changed — delegate-or-author discretion (workflow judgment)

- **`sdlc-loop` skill** — new **"Delegate or author directly"** section. The agent each command names to *delegate to* (`planner`, `specifier`, …) is the **default, not a mandate**: whether to spin up a dedicated subagent or author the artifact in the main session is the primary agent's discretion, and the deciding factor is usually **context budget**, not artifact type. A two-column tradeoff table (spend main context vs conserve it) makes the call explicit — short-horizon/plan-then-stop and "you already hold the synthesis" favor authoring directly; long autonomous loops (`gate_mode: auto-all`, `/orchestrate`) favor delegating to keep the window clean. Adds the hybrid pattern (let the agent draft the format, take the pen for the human-gated iteration) and the dead-agent fallback (adopt a crashed agent's partial artifact and continue directly rather than re-delegating cold).
- **`/plan` + `/design` commands** — short pointer at the `Delegate to` step reframing the named agent as default-not-mandate, with the context-budget cue and a deep-link to the new `sdlc-loop` section. Scoped to the single-agent authoring commands; `/develop` + `/orchestrate` (which spawn teams) are unaffected.
## [0.2.12] — 2026-06-04

### Added — `project-documentation` skill

- **`project-documentation` skill** (`skills/project-documentation/`) — durable-docs discipline (ADRs, specs, RFCs), upstreamed from codegen-patterns and generalized for arbitrary consumers. **Detection-first**: learns the consumer repo's naming scheme, header style, and status vocabulary from its existing files before creating anything (the original hardcoded one repo's conventions — and had drifted even there: its ADR glob matched zero files). Bundled `templates/{adr,spec}.md` cover the greenfield case only. Codifies the **two-planes split** (durable `docs/` owned by this skill vs SDLC working artifacts owned by `sdlc.yml → artifact_paths` + canvases), append-only ADRs with number-collision checks, **status-in-place lifecycle** (no archive folders — files never move, so links never break), and the "specs are post-implementation truth" rule (update the spec in the same PR that implements it). Delegates bulk authorship to `sdlc-author`.

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
