# Project skill template (overlay on `claude-platform/templates/skill-rich.md`)

**First**, copy the platform-rich template:
```
.claude/skills/claude-platform/templates/skill-rich.md
```

That covers every modern Claude Code skill field (`name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `allowed-tools`, `disable-model-invocation`, `user-invocable`, `model`, `effort`, `context: fork`, `agent`, `paths`, `hooks`, `shell`, plus `!`...`` injection and `${CLAUDE_SKILL_DIR}` substitution).

**Then** layer this project's conventions on top:

```markdown
---
# Platform fields (from claude-platform/templates/skill-rich.md)
name: <kebab-case>
description: <one-sentence what + when, drives auto-invocation>
allowed-tools: Read, Glob, Grep            # add Bash, Write, etc. only if needed
user-invocable: true

# === Project SDLC overlay ===
status: active                              # active | skeleton | deferred
topology: none                              # none | A | B | [A, B]

# Primitives this skill consumes
primitives:
  required:
    - <primitive>     # see .claude/primitives/README.md for taxonomy
  optional:
    - <primitive>
---

# {Skill Title}

## Purpose
{One paragraph. Body lives in context for the rest of the session once invoked.}

## Pre-rendered context (optional)
{Use !`...` for cheap shell context the skill always needs. See claude-platform/reference/skills.md § Dynamic context injection.}

## Configuration
Read project config from @.claude/sdlc.yml. Read paths from `artifact_paths`.

## Primitives

| Primitive | Required | Purpose |
|---|---|---|
| `<name>` | yes/no | <why this skill needs it> |

Based on primitives, read `.claude/primitives/<category>/<value>.md`.

## Instructions
{Standing instructions. The body stays in context — write what should apply throughout the task, not one-time steps.}

## Output
{What the skill produces.}
```

## What changed from the older template

- **Frontmatter is now per `claude-platform/reference/skills.md`** — the older template predated `disable-model-invocation`, `context: fork`, `paths`, `arguments`, `${CLAUDE_SKILL_DIR}`, etc.
- **Project SDLC metadata** (`status`, `topology`, `primitives`) is the layer this template adds on top.
- **Pre-rendering** is encouraged where it pays — see `skill-authoring/SKILL.md § 6`.

## Tool boundary guidance

Per project convention (`skill-authoring/SKILL.md § 3`), prefer `disallowedTools` over enumerating tracker-specific MCP tools in `allowed-tools`. Skills are pre-approval, not restriction — but enumerating Linear-specific MCP names creates the same swap-friction as in agents.
