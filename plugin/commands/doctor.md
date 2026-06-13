---
description: Diagnose Claude Code / sdlc misconfigurations that silently break the harness — e.g. a WorktreeCreate provider-hook registered as passive telemetry. Read-only; reports findings and fixes.
argument-hint: (no arguments)
allowed-tools: Bash, Read
status: active
topology: none
---

# /sdlc:doctor — config health check

Surfaces Claude Code / sdlc misconfigurations that fail **silently** or with cryptic
mid-session errors, so they show up as named findings with a fix instead of blocking the
user later.

## Run it

Run the bundled script against the current project. Prefer the Justfile recipe when the
project has the sdlc module wired; otherwise call the installed script directly via the
version glob (the same pattern the statusline wiring uses — `${CLAUDE_PLUGIN_ROOT}` is
**not** substituted into command bodies, so don't write it here):

```bash
just sdlc::doctor 2>/dev/null \
  || bash ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/doctor.sh
```

In the plugin dev repo, run `bash plugin/scripts/doctor.sh` directly.

Then relay the output to the user. For each **❌ ERROR**, walk them through the fix below.
Exit codes: `0` clean · `1` error finding(s) · `2` environment error (e.g. `jq` missing).

## Checks

### worktreecreate-provider

`WorktreeCreate` is a **provider** hook: a registered hook *replaces* the built-in
`git worktree add` and must create the worktree and print its path to stdout,
**synchronously**. A passive registration — `async: true`, or a telemetry emitter
(`emit.sh` / `emit.mjs`) that prints nothing — returns no path and breaks **every**
`isolation: "worktree"` Agent spawn harness-wide, with:

> Error creating worktree: WorktreeCreate hook failed: hook succeeded but returned no worktree path

- **❌ ERROR** — `async: true`, or a known passive emitter. Definitively broken.
- **ℹ️ INFO** — a custom synchronous command. Likely a real provider; just confirm it
  prints the worktree path to stdout.

**Fix:** remove the `WorktreeCreate` entry from the offending file's `hooks` block (keep
`WorktreeRemove` — it's observer-safe). Worktrees are then harness-managed under
`.claude/worktrees/`. If you genuinely want to own creation, the hook must run
`git worktree add` itself and `echo` the absolute path, with no `async`.

## Notes

- **Read-only.** Scans the project's `.claude/settings.json`, `.claude/settings.local.json`,
  `hooks/hooks.json`, and `~/.claude/settings.json`. Plugin-cache hooks under
  `~/.claude/plugins/cache/**` are *not* scanned — multiple versions coexist and only the
  enabled one is live, so each plugin validates its own `hooks.json` in CI instead.
- Also runs automatically as a `UserPromptSubmit` guard (`doctor.sh --hook`), staying
  silent unless it finds an ERROR — so this footgun self-surfaces without anyone running
  the command.
- Requires `jq`.
- Extensible: each check is a `check_<name>` function in `scripts/doctor.sh`.
