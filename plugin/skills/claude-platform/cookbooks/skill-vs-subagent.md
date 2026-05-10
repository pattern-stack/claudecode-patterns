# Cookbook: skill vs subagent vs hook vs CLAUDE.md

The question that comes up every time. Map your need to the primitive.

## Quick decision

> **Always-on rule** ("never edit `.env`", "use pnpm not npm")
> → CLAUDE.md (or `.claude/rules/<topic>.md` with `paths:` for path-scoped)

> **Reusable workflow** that the user (or Claude) invokes when relevant
> → Skill (`.claude/skills/<name>/SKILL.md`)

> **Side-task that floods context** (test runs, log greps, "read 30 files and summarize")
> → Subagent (`.claude/agents/<name>.md`)

> **Deterministic side-effect on a lifecycle event** (lint after edit, block `rm -rf`)
> → Hook (`.claude/settings.json` → `hooks.<Event>`)

> **Multiple independent sessions communicating** (parallel review hypotheses)
> → Agent teams (`/en/agent-teams`, experimental)

## Skill vs Subagent — the most common confusion

| | Skill | Subagent |
|---|---|---|
| Where it runs | Main conversation | Own isolated context window |
| What loads | Description always; full body when invoked, **stays for rest of session** | Fresh context when spawned; result returns; agent goes away |
| Best for | Reusable knowledge / workflows / reference docs | Tasks producing verbose output, parallel research, specialized workers |
| Token cost | Low until invoked, then recurring | Isolated — main conversation only sees the summary |
| Naming | Verb (`/deploy`) or topic (`/api-conventions`) | Role (`code-reviewer`) |
| Invocation | `/<name>` or auto-match | `Use the <name> agent to ...` or `@<name>` |

### They compose

- A subagent can preload skills (`skills:` field) — full content injected at startup.
- A skill can fork into a subagent (`context: fork` + `agent:`) — the skill body becomes the subagent's task.

## Skill vs Hook

| | Skill | Hook |
|---|---|---|
| Triggers | Claude decides, or user types `/<name>` | Lifecycle event fires deterministically |
| Reasoning | Yes (Claude executes the instructions) | No (it's a script with stdin/stdout/exit code) |
| Context cost | Description + (when invoked) body | Zero unless hook returns text |
| Best for | Multi-step procedures needing judgment | Linting, blocking, logging, notifications |

> **"Enforce" → hook. "Suggest" → skill.**
> A `permissions.deny` rule or a `PreToolUse` hook with `exit 2` is a guarantee. A skill saying "don't do X" is a request.

## CLAUDE.md vs Skill vs Rules

| | CLAUDE.md | `.claude/rules/<topic>.md` | Skill |
|---|---|---|---|
| Loads | Every session | Every session, or when matching `paths:` files entered | On demand (description in context, body on invoke) |
| Scope | Whole project | Path-globbed | Task-specific |
| Cost | Recurring (every request) | Recurring (when active) | Low until invoked |

Rule of thumb: keep CLAUDE.md under ~200 lines. As it grows, split into rules (when content is path-specific) or skills (when content is reference material that's only sometimes needed).

## Subagent vs Agent team

| | Subagent | Agent team |
|---|---|---|
| Architecture | Inside your session, returns result | Separate Claude Code sessions |
| Communication | Reports back to main | Peers message each other directly |
| Coordination | Main agent manages | Shared task list, self-coordination |
| Cost | Lower (summary returns) | Higher (each teammate is a full instance) |

Use a subagent for "do this side task and tell me what you found." Use an agent team for "discuss and challenge each other; build a feature with three people in parallel."

## When `context: fork` (skill that runs in a subagent)

Use it when:
- The skill produces lots of intermediate context (file reads, log analysis) you don't want in main.
- The skill is task content (not reference content) — e.g. `/deep-research` rather than `/api-conventions`.

Don't use it when:
- The skill is reference material like a style guide. The forked subagent gets the guidelines but no task and produces nothing useful.

## Worked examples

**"Run tests and report failures"** → subagent (verbose output stays out of main).
**"Our API conventions"** → skill (reference; auto-load when relevant).
**"Lint after every edit"** → `PostToolUse` hook (deterministic).
**"Deploy to prod"** → skill with `disable-model-invocation: true` (user must trigger).
**"Debug a flaky test"** → subagent (multi-step, verbose, isolated).
**"Always use conventional commits"** → CLAUDE.md (always-on).
**"React component review checklist for `**/*.tsx`"** → skill with `paths:` (path-gated).
**"Block writes to `.env`"** → hook with `exit 2` on `Edit/Write` matching path.
