# Project command template

Commands in this project remain in `.claude/commands/` (vs migrating to `.claude/skills/<name>/SKILL.md`) because they orchestrate phase agents via the **Mission format** — a project-specific delegation pattern. New workflows that don't need orchestration should be skills with bundled files (per `claude-platform/reference/plugins.md`).

For platform fundamentals (frontmatter fields, `!`...`` injection, `$ARGUMENTS` substitution), see `claude-platform/reference/skills.md` — commands and skills share most surface.

## Template

```markdown
---
description: {Brief description shown in /help}
argument-hint: {Expected arguments, e.g. [issue-key] or [description...]}
allowed-tools: {Pre-approved tools — see "Tool boundaries" below}

# Primitives consumed (project convention)
primitives:
  required:
    - <primitive>
  optional:
    - <primitive>

# === Project SDLC metadata ===
status: active                  # active | skeleton | deferred
topology: A | B | none
consumes: [issue, spec]
produces: [pr, team]
gates:
  enforces: [strategy-approved]
  sets: []
---

# /{command-name}

## Purpose
{One paragraph: what this workflow accomplishes end-to-end.}

## Working tree state (pre-rendered, optional)
Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`

## Usage
```
/{command-name} {arguments}
```

`$1` / `$ARGUMENTS`: {what the user provides}

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `<agent-name>` | agent | <what it does in this workflow> |
| `<primitive>` | primitive | <why> |

## Steps

### Step 1: {Step Name}

**Delegate to**: `<agent-name>` agent

**Mission**:
- **Objective**: {what to accomplish}
- **Input**: {data/artifacts being passed}
- **Context**: {relevant info — typically sdlc.yml + primitive paths}
- **Constraints**: {boundaries for this step}
- **Output**: {expected deliverable}

### Step 2: {Step Name}

**Human Gate**: {what needs approval before this step, if any}

**Delegate to**: `<agent-name>` agent

**Mission**:
- **Objective**: ...
- **Input**: ...
- **Context**: ...
- **Constraints**: ...
- **Output**: ...

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| {step} | {gate name} | {what human checks} |

## Output

{What this command produces when complete.}

## Error Handling

{What happens if a step fails.}
```

## Tool boundaries for `allowed-tools`

`allowed-tools` is **pre-approval** for the slash-command session, not restriction (per `claude-platform/reference/skills.md`). Two approaches:

1. **Enumerate** the tracker-specific MCP tools the command needs (current pattern):
   ```yaml
   allowed-tools: Read, Bash, mcp__plugin_linear_linear__get_issue
   ```
   Trade-off: re-edit when swapping trackers.

2. **Drop MCP from `allowed-tools`** and accept the prompts on first use, then run `/fewer-permission-prompts` to baseline.

For SDLC commands, enumeration is acceptable — they're project-specific entry points. The architectural swap point is the **agents** they delegate to, which use `disallowedTools` for tracker-agnostic inheritance (see `templates/agent.md`).

## Mission format guidance

The Mission block is the project's delegation primitive. Each step describes **what the next agent should do**, not **how to do it**. Recipes belong in the agent's `## Instructions`, not in the command body — extracting a step into a fresh agent then becomes mechanical.

## Arguments patterns

```yaml
# Freeform — user describes something
argument-hint: [description...]
# In prompt: $ARGUMENTS

# Structured — user provides specific values
argument-hint: [issue-key] [priority]
# In prompt: $1, $2

# Mixed
argument-hint: [issue-key] [notes...]
# In prompt: $1 for the key, $ARGUMENTS for everything
```

For complex argument shapes, prefer named positional args (frontmatter `arguments: [issue, branch]` → `$issue`, `$branch` in body). See `claude-platform/reference/skills.md § Available string substitutions`.
