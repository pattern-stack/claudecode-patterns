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

- `${CLAUDE_PLUGIN_DIR}` env var: set by Claude Code when running plugin code. Resolves to `~/.claude/plugins/sdlc` (or wherever the marketplace installer placed the plugin). If absent, halt with: "Run /sdlc:setup from inside Claude Code (the env var ${CLAUDE_PLUGIN_DIR} must be set)."
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

Read `${CLAUDE_PLUGIN_DIR}/sdlc.example.yml` as the template. Substitute placeholders with answers:
- `language: <answer>`
- `quality_profile: <answer>`
- `task_management: <answer>`
- `team_key: <answer>`
- `repo: <owner>/<repo>` — when `task_management: github`, prompt for repo separately (or inline a 5th AskUserQuestion text input). Detect from `git remote get-url origin` if available; pre-fill the prompt.
- `gate1_default: strict` — leave at the example's default. Setup does NOT ask about this.

Write to `.claude/sdlc.yml` (create `.claude/` if missing). On reconfigure path, the old file is already backed up.

### Step 5: Create `.claude/sdlc.justfile` symlink

```bash
ln -s "${CLAUDE_PLUGIN_DIR}/sdlc.justfile" .claude/sdlc.justfile
```

If `${CLAUDE_PLUGIN_DIR}` is empty, halt with the resolution error from prerequisites.

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
bash "${CLAUDE_PLUGIN_DIR}/scripts/bootstrap-tracker.sh" || echo "⚠️  Label provisioning failed — run manually later: bash plugin/scripts/bootstrap-tracker.sh"
```

Best-effort. Don't halt setup on failure.

### Step 8: Run verifiers

```bash
just sdlc::verify
```

If `just` not installed: print "⚠️  `just` not found — install via your package manager, then run `just sdlc::verify` to confirm. Skipping for now."

If verifiers fail: surface the output but don't undo the setup. The user can fix the config.

### Step 9: Print next-steps

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
Status column auto-movement. The `discover-tracker` SessionStart hook auto-loads
the project's field IDs on every session start (silent no-op when unset).
Otherwise specifier degrades to label-only.
```

## Halt and error handling

- `${CLAUDE_PLUGIN_DIR}` unset → halt before Step 4 with clear instruction.
- AskUserQuestion canceled mid-flow → print "Setup canceled — no files written" and exit. (Reconfigure backups stay; reverting them is on the user.)
- Symlink target missing (`${CLAUDE_PLUGIN_DIR}/sdlc.justfile` doesn't exist) → halt: "Plugin install appears broken — sdlc.justfile not found at ${CLAUDE_PLUGIN_DIR}. Reinstall via `/plugin install sdlc`."
- File write fails (permissions, disk full) → halt with the exact OS error and the path attempted.

## Acceptance

- End-to-end run in a fresh tmpdir produces a valid `.claude/sdlc.yml` (with `gate1_default: strict`) and a resolvable `.claude/sdlc.justfile` symlink.
- Verifiers (`just sdlc::verify`) pass post-setup (when `just` is installed).
- Reconfigure path on existing sdlc.yml is non-destructive by default (default-quit; reconfigure writes backup before overwrite).
- Next-steps output includes the gate-mode override-layers line; the `project_number:` hint line appears iff `task_management: github`.
- Command is named `/sdlc:setup` (not `/sdlc:init`) — does not collide with native `/init`.

## Out of scope

- TUI/wizard. AskUserQuestion IS the v1 wizard.
- Asking about gate mode (defaults strict; documented in next-steps).
- Asking for a GitHub Project URL during setup. Project linkage is opt-in via `project_number:` in `sdlc.yml`; discovery happens automatically at every SessionStart.
- Multi-project setup (`extends:` sdlc.yml layering — deferred to v2).
