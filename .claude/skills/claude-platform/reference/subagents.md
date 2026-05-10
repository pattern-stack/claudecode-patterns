# Subagents — full reference

Subagents are isolated workers with their own context window, system prompt, tool access, and optionally model. They live at `.claude/agents/<name>.md` (project), `~/.claude/agents/<name>.md` (user), or in a plugin's `agents/` directory.

## Scope and precedence

| Location | Scope | Priority |
|---|---|---|
| Managed settings | Org-wide | 1 (highest) |
| `--agents` CLI flag | Current session (JSON) | 2 |
| `.claude/agents/` | Project | 3 |
| `~/.claude/agents/` | User | 4 |
| Plugin `agents/` | Where plugin is enabled | 5 |

When the same name exists at multiple scopes, higher priority wins.

## Frontmatter (every supported field)

| Field | Required | Notes |
|---|:---:|---|
| `name` | yes | Lowercase + hyphens, unique |
| `description` | yes | When Claude should delegate to it |
| `tools` | no | Allowlist; comma-separated. Inherits all tools if omitted |
| `disallowedTools` | no | Denylist; applied first, then `tools` resolved against the remainder |
| `model` | no | `sonnet` / `opus` / `haiku` / full ID / `inherit`. Default `inherit` |
| `permissionMode` | no | `default` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` / `plan`. **Ignored for plugin subagents** |
| `maxTurns` | no | Hard cap on agentic turns |
| `skills` | no | Skills to **preload** (full content injected at startup, not just description) |
| `mcpServers` | no | List of strings (refs to configured servers) and/or inline definitions. **Ignored for plugin subagents** |
| `hooks` | no | Lifecycle hooks scoped to this subagent. **Ignored for plugin subagents** |
| `memory` | no | `user` / `project` / `local` — enables persistent memory directory |
| `background` | no | `true` to always run in background |
| `effort` | no | `low` / `medium` / `high` / `xhigh` / `max` |
| `isolation` | no | `worktree` to run in a temporary git worktree |
| `color` | no | `red` / `blue` / `green` / `yellow` / `purple` / `orange` / `pink` / `cyan` |
| `initialPrompt` | no | First user turn auto-submitted when this agent is the **main session** (`claude --agent`) |

The body is the system prompt. Subagents receive only this (plus working-directory context), not the default Claude Code system prompt.

## Tool access

```yaml
tools: Read, Grep, Glob, Bash         # allowlist
disallowedTools: Write, Edit          # denylist (preferred when you want "everything except X")
```

When both are set: `disallowedTools` is removed first, then `tools` is intersected against what remains. A tool in both is gone.

### Restrict subagent spawning (when this agent runs as `--agent`)

```yaml
tools: Agent(worker, researcher), Read, Bash    # only these subagents can be spawned
tools: Agent, Read, Bash                        # any subagent can be spawned
# Omit Agent entirely → cannot spawn any subagents
```

`Agent(...)` only matters when this agent is the main thread. **Subagents cannot spawn other subagents**, period.

To block named subagents at the session level:
```json
{ "permissions": { "deny": ["Agent(Explore)", "Agent(my-agent)"] } }
```

## Permission mode interaction

Subagents inherit the parent permission context and can override **except**:
- Parent on `bypassPermissions` or `acceptEdits` → child cannot override.
- Parent on `auto` → child inherits auto; any `permissionMode` in frontmatter is ignored.

## MCP scoping

```yaml
mcpServers:
  # Inline definition — scoped to this subagent only, connected at start, disconnected at end
  - playwright:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest"]
  # String reference — reuses parent session's connection
  - github
```

Inline servers use the same schema as `.mcp.json`. Defining inline keeps the server's tool descriptions out of the parent session's context.

## Persistent memory

```yaml
memory: project    # .claude/agent-memory/<name>/
# or
memory: user       # ~/.claude/agent-memory/<name>/
# or
memory: local      # .claude/agent-memory-local/<name>/  (gitignored)
```

When memory is enabled:
- The subagent's system prompt gets memory-management instructions.
- First 200 lines (or 25KB, whichever first) of `MEMORY.md` is injected.
- `Read` / `Write` / `Edit` are auto-enabled so the agent can curate its memory.

`project` is the recommended default — knowledge ships via git. Use `user` for cross-project knowledge, `local` for sensitive learnings that shouldn't be checked in.

## Hooks (frontmatter-scoped)

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"
```

Frontmatter hooks fire when the agent is invoked as a subagent **and** when it runs as the main session via `--agent`. `Stop` events are auto-converted to `SubagentStop` in subagent context.

## Foreground vs background

- **Foreground (default):** blocks main conversation; permission prompts and `AskUserQuestion` pass through to user.
- **Background (`background: true`, or Ctrl+B at runtime):** concurrent. Permissions are pre-approved before launch; anything outside the pre-approval auto-denies. Clarifying questions fail silently and the subagent continues.

When [fork mode](https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation) is enabled (`CLAUDE_CODE_FORK_SUBAGENT=1`), every subagent spawn runs in background regardless of the `background` field.

## Worktree isolation

```yaml
isolation: worktree
```

Subagent gets a temporary git worktree (its own copy of the checkout). Cleaned up automatically if no changes were made. Otherwise the worktree path + branch is returned in the result.

## Resumption

Each invocation creates a fresh agent. To **continue** an existing one (preserve history, tool calls, reasoning), use `SendMessage` with the agent's ID. This requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

Transcripts persist at `~/.claude/projects/<project>/<sessionId>/subagents/agent-<id>.jsonl`. Cleanup default: 30 days (`cleanupPeriodDays`).

## Plugin subagent restrictions

Plugin-shipped subagents **silently ignore**: `hooks`, `mcpServers`, `permissionMode`. If you need those, copy the file into `.claude/agents/` or `~/.claude/agents/`.

## Live reload

Subagents are loaded at session start. Edit on disk → restart session. Subagents created via `/agents` interface take effect immediately.

## Examples

### Read-only reviewer
```yaml
---
name: code-reviewer
description: Reviews code for correctness, security, and maintainability. Use proactively after code changes.
tools: Read, Grep, Glob, Bash
model: inherit
---

You are a senior reviewer. Run `git diff`, focus on modified files, organize feedback as Critical / Warning / Suggestion.
```

### Specialist with preloaded skills + project memory
```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
memory: project
---

Implement endpoints following the preloaded skills. Update memory with patterns you discover.
```

### Sandboxed DB query agent
```yaml
---
name: db-reader
description: Run read-only SQL via Bash, validated by hook
tools: Bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly-query.sh"
---

Execute SELECT-only queries. Refuse mutating statements.
```

### Worktree-isolated implementer
```yaml
---
name: implementer
description: Make code changes for an approved spec in an isolated worktree
tools: Read, Write, Edit, Bash, Glob, Grep
isolation: worktree
permissionMode: acceptEdits
---

Implement per the approved spec. Branch + PR via gh.
```
