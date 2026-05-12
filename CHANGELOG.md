# Changelog

All notable user-facing changes to the `sdlc` Claude Code plugin.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version field lives in [`plugin/.claude-plugin/plugin.json`](plugin/.claude-plugin/plugin.json) — bumping it is what triggers Claude Code's `/plugin update` to actually refresh the cache for existing consumers.

## [0.2.0] — 2026-05-12

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
