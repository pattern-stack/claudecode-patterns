---
description: Onboarding flow that scaffolds a fresh project's `.claude/sdlc.yml` + Justfile module + symlink to the plugin's `sdlc.justfile`. Drives an interactive AskUserQuestion dialog (4 questions). Idempotent — re-runs safely with reconfigure prompt.
argument-hint: []
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
primitives:
  required: []
status: active
topology: none
consumes: []
produces: [config, justfile, symlink]
gates:
  enforces: []
  sets: []
---

# /sdlc:setup

Post-install onboarding for the `sdlc` plugin. Renders `.claude/sdlc.yml` from the bundled example, wires the project's Justfile into the plugin's recipes, and creates the `.claude/sdlc.justfile` symlink so `just sdlc::verify` works immediately.

> **Renamed from `/sdlc:init`** to avoid discoverability collision with Claude Code's native `/init` (which generates CLAUDE.md). Plugin commands are namespaced — invoke as `/sdlc:setup`.

## Usage

```
/sdlc:setup
```

No arguments. The flow is conversational.

## Resolution prerequisites

- **Plugin install path (`$PLUGIN_ROOT`)** — resolve at runtime from `~/.claude/plugins/installed_plugins.json` rather than relying on env-var substitution. Neither `${CLAUDE_PLUGIN_DIR}` nor `${CLAUDE_PLUGIN_ROOT}` is reliably exposed to skill-body shell calls: `${CLAUDE_PLUGIN_DIR}` is not a Claude Code token at all, and `${CLAUDE_PLUGIN_ROOT}` is only substituted into plugin-manifest files (e.g. `hooks/hooks.json`) at config-parse time — not into slash-command markdown bodies executed by the model.

  Resolve with a portable fallback chain — try `jq`, then `python3`, then `node`, then pure-shell grep/sed. The last branch has zero external deps, so the resolver works on Python / Go / Rust / etc. projects where `node` may not be installed or may be pinned to an unavailable version by a tool-version manager (asdf, mise, nvm):

  ```bash
  PLUGINS_FILE="$HOME/.claude/plugins/installed_plugins.json"
  PLUGIN_ROOT=""
  if command -v jq >/dev/null 2>&1; then
    PLUGIN_ROOT="$(jq -r '.plugins["sdlc@claudecode-patterns"][0].installPath // ""' "$PLUGINS_FILE" 2>/dev/null)"
  elif command -v python3 >/dev/null 2>&1; then
    PLUGIN_ROOT="$(python3 -c "import json; j=json.load(open('$PLUGINS_FILE')); e=j['plugins'].get('sdlc@claudecode-patterns',[{}]); print((e[0] if e else {}).get('installPath',''))" 2>/dev/null)"
  elif command -v node >/dev/null 2>&1; then
    PLUGIN_ROOT="$(node -e 'const j=require(require("os").homedir()+"/.claude/plugins/installed_plugins.json");const e=j.plugins["sdlc@claudecode-patterns"];process.stdout.write(e&&e[0]&&e[0].installPath||"")' 2>/dev/null)"
  else
    PLUGIN_ROOT="$(grep -A 5 '"sdlc@claudecode-patterns"' "$PLUGINS_FILE" 2>/dev/null | grep -m1 '"installPath"' | sed 's/.*"installPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  ```

  If `$PLUGIN_ROOT` is empty or `"$PLUGIN_ROOT/sdlc.example.yml"` doesn't exist, halt with: "sdlc plugin install not found at ~/.claude/plugins/installed_plugins.json (key `sdlc@claudecode-patterns`). Install via `/plugin install sdlc@claudecode-patterns` and retry."
- A project (`pwd`) — git repo not required, but warn if absent (worktree feature won't work).
- `just`: optional. Warn + skip the verify step if missing.

## Flow

### Step 1: Detect existing config

Check `.claude/sdlc.yml`:
- **Exists** → AskUserQuestion: "An `sdlc.yml` already exists at `.claude/sdlc.yml`. What now?"
  - `Quit (recommended)` — exit without changes.
  - `Reconfigure` — back up to `.claude/sdlc.yml.bak.<unix-timestamp>`; proceed to Step 2.
- **Missing** → proceed to Step 2.

### Step 2: AskUserQuestion × 3 (enums)

Three sequential questions; each picks one option (no preview pane needed for v1):

**Q1 — Language:**
- `typescript` (default) — TypeScript / JavaScript projects.
- `python` — Python projects.
- `go` — Go projects.
- `other` — handled with a follow-up text prompt for the language slug.

**Q2 — Quality profile:**
- `strict` (recommended) — full type-check + lint + test gates on every PR.
- `fast` — minimum gates; skips slow checks. Use for rapid prototyping.

**Q3 — Task management:**
- `github` — GitHub Issues. Most common; use `gh` CLI primitives.
- `linear` — Linear via MCP. Native workflow states + comments.
- `jira` — placeholder; primitive not yet authored. Pick another for now.

### Step 3: Text prompt — `team_key`

Free-text input. Validate against `^[A-Z][A-Z0-9]{1,9}$`. On invalid:
- Re-prompt with the exact rule.
- Examples: `ABC` (Linear team key), `PSC` (works for github too — used in branch convention `dugshub/<key>-<n>-<slug>`).

If `task_management: github`, `team_key` is informational (used in branch naming); not strictly required by the github primitive.

### Step 4: Render `.claude/sdlc.yml`

Read `$PLUGIN_ROOT/sdlc.example.yml` as the template. Substitute placeholders with answers:
- `language: <answer>`
- `quality_profile: <answer>`
- `task_management: <answer>`
- `team_key: <answer>`
- `repo: <owner>/<repo>` — when `task_management: github`, prompt for repo separately (or inline a 5th AskUserQuestion text input). Detect from `git remote get-url origin` if available; pre-fill the prompt.
- `gate1_default: strict` — leave at the example's default. Setup does NOT ask about this.

Write to `.claude/sdlc.yml` (create `.claude/` if missing). On reconfigure path, the old file is already backed up.

### Step 5: Create `.claude/sdlc.justfile` symlink

```bash
ln -s "$PLUGIN_ROOT/sdlc.justfile" .claude/sdlc.justfile
```

If `$PLUGIN_ROOT` is empty, halt with the resolution error from prerequisites.

If `.claude/sdlc.justfile` already exists (re-run case):
- If it's a symlink to the same target → no-op.
- If it's a different file or stale symlink → overwrite (no backup; this is plugin-shipped indirection, not user content).

### Step 6: Justfile detection + merge

Read repo-root `Justfile` (if exists):

| State | Action |
|---|---|
| **No Justfile** | Create one with: `default:\n    @just --list\n\nmod sdlc '.claude/sdlc.justfile'` |
| **Exists, no `mod sdlc` line** | AskUserQuestion: "Found existing `Justfile`. Add the `sdlc` module?" with options: `Add as module (recommended)` (prepends `mod sdlc '.claude/sdlc.justfile'` near top), `Add as import (top-level recipes)` (prepends `import '.claude/sdlc.justfile'`; pre-checks for collisions on recipe names, refuses if any), `Skip` (user wires manually later). |
| **Exists, already has `mod sdlc` or `import '.claude/sdlc.justfile'`** | No-op. Print "Justfile already wired." |

For the `import` collision check: parse existing recipe names from the Justfile (`grep '^[a-z][a-z0-9_-]*:' Justfile`), compare against plugin recipe names (`verify`, `verify-canvases`, `verify-tool-groups`, `canvas-dev`, `canvas-seller`, `canvases`, `where`). If any overlap, refuse import and recommend `mod` instead.

### Step 7: Provision tracker labels (github only)

If `task_management: github`:
```bash
bash "$PLUGIN_ROOT/primitives/task-management/bootstrap.sh" || echo "⚠️  Label provisioning failed — run manually later: bash plugin/primitives/task-management/bootstrap.sh"
```

Best-effort. Don't halt setup on failure.

### Step 8: Run verifiers

```bash
just sdlc::verify
```

If `just` not installed: print "⚠️  `just` not found — install via your package manager, then run `just sdlc::verify` to confirm. Skipping for now."

If verifiers fail: surface the output but don't undo the setup. The user can fix the config.

### Step 9: cc-viewer dashboard (offer install)

The plugin's hooks emit lifecycle events to a local dashboard — `cc-viewer`, a self-contained binary that ships *with* this plugin (one tarball per platform attached to each GH release). The runtime install primitive at `${PLUGIN_ROOT}/lib/tools.sh` handles downloading + caching under `~/.local/state/cc-viewer/bin/cc-viewer-v<plugin-version>-<platform>`. Telemetry hooks silently no-op when the binary is absent, so this step is genuinely optional — but offering it conversationally is way better UX than letting users discover later that the dashboard exists.

Probe the cache and the running dashboard. Use `tool_binary_path` from `tools.sh` to compute the expected path without triggering a download:

```bash
export PLUGIN_ROOT="$PLUGIN_ROOT"
source "${PLUGIN_ROOT}/lib/tools.sh"
EXPECTED_BIN="$(tool_binary_path cc-viewer)"
INSTALLED="no"; [[ -x "$EXPECTED_BIN" ]] && INSTALLED="yes"

PORT="${CC_VIEWER_PORT:-3993}"
DASHBOARD_UP="no"
if curl -sS -m 0.5 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
  DASHBOARD_UP="yes"
fi
```

Three outcomes:

**A — installed + running.** Print, do nothing else:
```
Dashboard:
  ❯ binary       <EXPECTED_BIN>              ✓
  ❯ running      http://localhost:<PORT>     ✓
```

**B — installed but not running.** Print and move on. The SessionStart hook will spawn it on next Claude Code session:
```
Dashboard:
  ❯ binary       <EXPECTED_BIN>              ✓
  ❯ running      (not yet)                   ⚠

Will auto-start on your next Claude Code session via
ensure-cc-viewer.sh. Or to launch right now:
  "$EXPECTED_BIN" &
```

**C — not installed.** AskUserQuestion: "Install the cc-viewer dashboard? Downloads ~25MB from the plugin's GitHub release. The plugin works fine without it — telemetry hooks silently no-op." Options: `Install (recommended)`, `Skip`.

On `Install`, call `ensure_tool` (the same code path the SessionStart hook uses), then surface the outcome:
```bash
BIN="$(ensure_tool cc-viewer)"
if [[ -n "$BIN" && -x "$BIN" ]]; then
  echo "Dashboard installed → $BIN"
  echo "Launch on your next session, or right now: $BIN &"
else
  cat <<EOF
Install did not complete. Common causes:

  - No matching tarball for $(uname -sm) at v<plugin-version>
  - Network unreachable / corporate proxy
  - GitHub rate limit (try again in a few minutes)

The plugin still works — telemetry hooks will silently no-op.
Inspect ~/.local/state/cc-viewer/install.log for the curl error,
or re-run /sdlc:setup later.
EOF
fi
```

On `Skip`, print "Dashboard skipped — re-run /sdlc:setup later if you change your mind."

This step is advisory in all three branches. **Never halt setup on a failed install** — the sdlc workflow is complete without telemetry.

### Step 10: Offer to wire the dashboard status line

The plugin ships `plugin/scripts/dashboard-status.sh` — a status-line component that renders a clickable colored dot pointing at the local cc-viewer dashboard (green when `/health` responds within 200ms, red otherwise). Status lines are session-wide UI, so the right home for the wiring is `~/.claude/settings.json` (user scope) rather than `.claude/settings.json` (this project only). Plugin-bundled `settings.json` cannot ship a top-level `statusLine` either — the plugin loader only honors `agent` and `subagentStatusLine` keys there — so user-scope is the only path that makes this apply to every session everywhere.

Read `~/.claude/settings.json` (treat a missing file as `{}`). Inspect its `statusLine` field:

| Current state | Action |
|---|---|
| **No `statusLine`** | AskUserQuestion: "Wire the SDLC dashboard status line into `~/.claude/settings.json`? Applies to every Claude Code session." Options: `Add (recommended)`, `Skip`. |
| **`statusLine` already references `dashboard-status.sh`** (substring match on `dashboard-status.sh`) | No-op. Print "Status line already wired." |
| **`statusLine` is set to something else** | AskUserQuestion: "Existing `statusLine` in `~/.claude/settings.json` does not point at the SDLC dashboard. Replace it?" Show the current command in the question body. Options: `Replace`, `Keep existing (skip)`. |

On `Add` or `Replace`, write:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/dashboard-status.sh 2>/dev/null"
  }
}
```

Merge into the existing JSON object — preserve all other keys. The glob (`sdlc/*/scripts/...`) auto-resolves to the latest installed version so `/plugin update sdlc` does not break the wiring. Do not write the literal `$PLUGIN_ROOT` path: that path includes the current version and would silently stop pointing at the latest after an update.

If the write fails (permissions, disk full), surface the OS error but do not halt setup — status line is optional polish.

### Step 11: Print next-steps

Three lines, always:

```
✅ Setup complete.

Default Gate-1 mode: strict. Override per-stack via `auto_approve: true` in
plan.yaml, or per-issue via `gate:auto` / `gate:human` labels.

Next: `/sdlc:plan "<your first request>"` to plan a stack.
```

If `task_management: github`, append a fourth line:
```
GitHub Project users: set `project_number: <n>` in `.claude/sdlc.yml` to enable
Status column auto-movement. The `discover` SessionStart hook (at
`plugin/primitives/task-management/discover.sh`) auto-loads
the project's field IDs on every session start (silent no-op when unset).
Otherwise specifier degrades to label-only.
```

## Halt and error handling

- `$PLUGIN_ROOT` unresolvable (missing entry in `installed_plugins.json`, or resolved path doesn't contain `sdlc.example.yml`) → halt before Step 4 with the resolution error from prerequisites.
- AskUserQuestion canceled mid-flow → print "Setup canceled — no files written" and exit. (Reconfigure backups stay; reverting them is on the user.)
- Symlink target missing (`$PLUGIN_ROOT/sdlc.justfile` doesn't exist) → halt: "Plugin install appears broken — sdlc.justfile not found at $PLUGIN_ROOT. Reinstall via `/plugin install sdlc@claudecode-patterns`."
- File write fails (permissions, disk full) → halt with the exact OS error and the path attempted.

## Acceptance

- End-to-end run in a fresh tmpdir produces a valid `.claude/sdlc.yml` (with `gate1_default: strict`) and a resolvable `.claude/sdlc.justfile` symlink.
- Verifiers (`just sdlc::verify`) pass post-setup (when `just` is installed).
- Reconfigure path on existing sdlc.yml is non-destructive by default (default-quit; reconfigure writes backup before overwrite).
- Next-steps output includes the gate-mode override-layers line; the `project_number:` hint line appears iff `task_management: github`.
- Command is named `/sdlc:setup` (not `/sdlc:init`) — does not collide with native `/init`.
- Dashboard offer (Step 9) runs in all three states without halting: installed + running, installed + idle, not installed. On `Install`, a failed download (no tarball / no network) prints the diagnostic without aborting setup. Setup is never blocked by the dashboard install.
- Status-line wiring (Step 10) is idempotent — re-run on a machine that already has the dashboard status line in `~/.claude/settings.json` is a no-op print. Other user-scope settings keys are preserved across the write. Skip path leaves the file untouched. Failure to write `~/.claude/settings.json` does not halt setup.
- `$PLUGIN_ROOT` resolver works without `node` installed (Python / Go / Rust projects pass through the `jq` / `python3` / pure-shell branches).

## Out of scope

- TUI/wizard. AskUserQuestion IS the v1 wizard.
- Asking about gate mode (defaults strict; documented in next-steps).
- Asking for a GitHub Project URL during setup. Project linkage is opt-in via `project_number:` in `sdlc.yml`; discovery happens automatically at every SessionStart.
- Multi-project setup (`extends:` sdlc.yml layering — deferred to v2).
