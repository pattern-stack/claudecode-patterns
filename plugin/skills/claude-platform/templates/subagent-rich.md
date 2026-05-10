# Rich subagent template

Copy into `.claude/agents/<your-agent>.md`. Both `name` and `description` are required; everything else is optional.

```markdown
---
# === Identity (required) ===
name: my-agent                              # lowercase + hyphens, unique
description: When Claude should delegate. Be specific about the specialty. "Use proactively when..." encourages auto-delegation.

# === Tool surface ===
tools: Read, Grep, Glob, Bash               # allowlist (omit for inherit-all)
disallowedTools: Write, Edit                # denylist (applied first, then `tools` is intersected)
# Restrict subagent spawning when running as --agent:
# tools: Agent(worker, researcher), Read, Bash    → only these can be spawned
# tools: Agent, Read, Bash                        → any can be spawned
# (omit Agent entirely)                           → cannot spawn any

# === Model + effort ===
model: inherit                              # sonnet | opus | haiku | <full id> | inherit
effort: inherit
maxTurns: 50                                # hard cap on agentic turns

# === Permissions ===
permissionMode: default                     # default | acceptEdits | auto | dontAsk | bypassPermissions | plan
# Note: parent's bypassPermissions / acceptEdits / auto cannot be overridden by this field.

# === Preloaded knowledge ===
skills:
  - api-conventions                         # full content injected at startup (not just description)
  - error-handling-patterns

# === MCP scoping ===
mcpServers:
  - github                                  # string ref to already-configured server
  - playwright:                             # inline definition, scoped to this agent only
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest"]

# === Lifecycle hooks (frontmatter-scoped) ===
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-bash.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"

# === Persistent memory ===
memory: project                             # user | project | local

# === Execution flags ===
background: false                           # true → always run in background
isolation: worktree                         # spawn in temporary git worktree (cleaned up if no changes)
color: blue                                 # red | blue | green | yellow | purple | orange | pink | cyan

# === Main-session-mode behavior (when run via --agent) ===
initialPrompt: |
  Greet the user with the active issue and recent commits before doing anything else.
---

# {Role title}

## Expertise
{One paragraph. What makes this agent the right choice.}

## When invoked
1. {first step}
2. {second step}
3. {third step}

## Output format
{Be explicit about what to produce.}

## Constraints
- Do NOT {scope creep boundary}
- ONLY {focus boundary}

## Memory protocol  (if memory: enabled)
Read your `MEMORY.md` before starting. Update it with patterns and recurring issues you discover. Curate aggressively if it exceeds 25KB.
```

## Plugin subagent reminder

If this file ships in a plugin, the runtime **silently ignores**: `hooks`, `mcpServers`, `permissionMode`. If you need them, the user must copy the file into their `.claude/agents/` or `~/.claude/agents/`.
