# Changelog

All notable user-facing changes to the `sdlc` Claude Code plugin.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version field lives in [`plugin/.claude-plugin/plugin.json`](plugin/.claude-plugin/plugin.json) — bumping it is what triggers Claude Code's `/plugin update` to actually refresh the cache for existing consumers.

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
