# Project agent template (overlay on `claude-platform/templates/subagent-rich.md`)

**First**, copy the platform-rich template:
```
.claude/skills/claude-platform/templates/subagent-rich.md
```

That covers every modern Claude Code subagent field (`name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`).

**Then** layer this project's conventions on top:

```markdown
---
# Platform fields (from claude-platform/templates/subagent-rich.md)
name: <agent-name>                          # required, lowercase + hyphens
description: <when Claude should delegate>  # required

# Tool boundaries — use a canonical tool_group from sdlc.yml.
# DENYLIST form (preferred for tracker-agnostic SDLC agents — inherits MCP):
# tool_group: code_writer_mcp (denylist; inherits all configured MCP)
disallowedTools: WebFetch, WebSearch, Agent
# OR ALLOWLIST form (when scoping subagents or hard-sandboxing — no MCP):
# tool_group: spec_writer (allowlist)
# tools: Read, Write, Edit, Glob, Grep
# See .claude/sdlc.yml `tool_groups:` for the canonical list.

model: sonnet                               # opus for thinking phases, sonnet for execution
permissionMode: default                     # use `plan` for read-only intent

# Optional: persistent memory across sessions
memory: project                             # user | project | local

# === Project SDLC overlay ===
status: active                              # active | skeleton | deferred
topology: [A, B]                            # which topologies use this agent
consumes: [issue, spec]                     # artifact types read
produces: [branch, pr, comment]             # artifact types written
gates:
  enforces: [strategy-approved]             # halts if these labels missing/wrong
  sets: [awaiting-strategy-review]          # labels this sets
---

# {Agent Role}

## Expertise
{One paragraph. Why this agent is the right choice for this task.}

## Configuration
Read project config from @.claude/sdlc.yml.

Reference:
- `.claude/primitives/<category>/<value>.md` for each consumed primitive

## Primitives

| Primitive | Required | Purpose |
|---|---|---|
| `<name>` | yes/no | <why this agent needs it> |

## Instructions

### 1. {First step}
{Detailed: agents DO the work. Be thorough.}

### 2. {Second step}
...

## Output Format
{Explicit structure of what this agent produces.}

## Constraints
- Do NOT {scope creep boundary}
- ONLY {focus boundary}
- Do NOT bypass {gate name}
```

## Why `disallowedTools` over allowlist for SDLC roles

The older template recommended explicit tool allowlists (`tools: Read, Grep, Glob`). For SDLC roles that need tracker-MCP access (Linear today, GitHub Issues tomorrow), allowlists hardcode the tracker. Switching means editing every agent.

Use `disallowedTools` instead — the agent inherits all configured MCP servers, removes only the tools you've banned (web egress, recursive subagent spawning, etc.). The body of the agent specifies which tracker MCP to use via the primitive (`task-management/{value}.md`), and Claude resolves at runtime.

When to use allowlist (`tools:`):
- **Scoping subagent spawning**: `tools: ..., Agent(implementer, validator)` — must use allowlist form
- **True sandboxing**: an audit-only agent that should not have any MCP at all
- **Built-in agents** (`Explore`, `Plan`) inherently restrict — your custom agent doesn't need to

## `permissionMode` patterns

| Mode | When to use |
|---|---|
| `default` | Normal agent (interactive permission prompts) |
| `plan` | **Read-only enforcement** — `understander`, `validator`, audit agents. Hard guarantee, not just intent. |
| `acceptEdits` | Auto-accept file edits in worktrees — `implementer` running in `isolation: worktree` |

## Project metadata fields

`status`, `topology`, `consumes`, `produces`, `gates` are **documentation only** — Claude Code's runtime ignores them. Keep them: they make the SDLC roster grep-able and self-documenting.
