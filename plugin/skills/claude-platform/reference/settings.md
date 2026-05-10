# settings.json — reference

`.claude/settings.json` is the per-project config file (committed). `.claude/settings.local.json` is the personal-overrides equivalent (gitignored). `~/.claude/settings.json` is the user-level default.

## Precedence

1. Managed settings (highest)
2. CLI flags
3. `.claude/settings.local.json`
4. `.claude/settings.json`
5. `~/.claude/settings.json` (lowest)

**Scalar keys** (e.g. `model`, `outputStyle`): most specific wins.
**Array keys** (e.g. `permissions.allow`, `permissions.deny`): combine across all scopes.

## Top-level keys

| Key | Type | Purpose |
|---|---|---|
| `permissions` | object | `{allow, deny, ask}` arrays of tool patterns |
| `hooks` | object | Map of event-name → matchers + hook commands |
| `statusLine` | object | Customize the bottom status line |
| `model` | string | Default model alias / ID for this project |
| `env` | object | Environment variables set in every session |
| `outputStyle` | string | Active output style (filename without `.md`, or its `name` field) |
| `agent` | string | Run every session as this subagent (CLI flag overrides) |
| `skillOverrides` | object | Map of skill-name → `on` / `name-only` / `user-invocable-only` / `off` |
| `disableSkillShellExecution` | bool | Globally disable `!`...`` injection in skills/commands |
| `cleanupPeriodDays` | number | Default 30; subagent transcript retention |
| `autoMemoryEnabled` | bool | Toggle auto memory |

## Permissions

```json
{
  "permissions": {
    "allow": [
      "Bash(npm test *)",
      "Bash(npm run *)",
      "Read",
      "Skill(commit)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Agent(Explore)",
      "Skill(deploy *)"
    ],
    "ask": [
      "Bash(git push *)"
    ]
  }
}
```

Patterns:
- `Bash(<glob>)` — wildcard match against the command string.
- `Agent(<name>)` — block subagents by name (works for built-ins and custom).
- `Skill(<name>)` or `Skill(<name> *)` — exact name or arg-prefix match.
- Bare tool name (e.g. `Read`, `Skill`) — applies to all uses.

## Hooks

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write"
          }
        ]
      }
    ]
  }
}
```

### Hook events

| Event | Fires |
|---|---|
| `SessionStart` | New session created |
| `InstructionsLoaded` | CLAUDE.md / rules loaded |
| `UserPromptSubmit` | User submits a prompt |
| `PreToolUse` | Before any tool call |
| `PostToolUse` | After successful tool call |
| `PostToolUseFailure` | After failed tool call |
| `PermissionRequest` | Permission prompt shown |
| `PermissionDenied` | Permission denied |
| `Notification` | UI notification |
| `SubagentStart` | Subagent begins |
| `SubagentStop` | Subagent finishes |
| `TaskCreated` / `TaskCompleted` | Task list events |
| `Stop` / `StopFailure` | Main agent finishes |
| `TeammateIdle` | Agent-teams: peer signals idle |
| `ConfigChange` | Settings reloaded |
| `CwdChanged` | Working dir changed |
| `FileChanged` | Tracked file changed |
| `PreCompact` / `PostCompact` | Around auto-compaction |
| `Elicitation` / `ElicitationResult` | Around `AskUserQuestion` |
| `SessionEnd` | Session ended |
| `WorktreeCreate` | Worktree created (used to copy `.worktreeinclude` patterns) |

### Hook input

JSON via stdin. Common fields:
- `tool_name`
- `tool_input` (e.g. `tool_input.command` for Bash, `tool_input.file_path` for Edit/Write)
- `tool_response` (PostToolUse only)
- `cwd`, `session_id`, etc.

### Hook output (exit codes)

- `0` — succeed silently
- `2` — **block** the operation; stderr is fed back to Claude
- non-zero non-2 — log error, allow operation

JSON output on stdout (alternative to exit codes) can override behavior more granularly — see `/en/hooks` for the full schema.

### Hook entry fields

```json
{
  "type": "command",
  "command": "...",
  "shell": "powershell",
  "async": true,
  "timeout": 10
}
```

`async: true` means the hook fires-and-forgets; this project uses async on all `emit.mjs` hooks for the dashboard observability shim.

## statusLine

```json
{
  "statusLine": {
    "type": "command",
    "command": "echo \"$(git branch --show-current) | $(date +%H:%M)\""
  }
}
```

Other types: `prompt` (LLM-driven), `static`.

## Example: this project's settings.json (excerpted)

The project ships a fan-out hook setup that POSTs every lifecycle event to a local dashboard via `.claude/hooks/emit.mjs`. See `.claude/settings.json` for the full list — every event has an async command-type hook with a 10s timeout. This is a representative pattern for observability without affecting Claude's main loop (zero context cost).
