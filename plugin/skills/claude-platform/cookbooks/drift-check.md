# Cookbook: keep this skill aligned with upstream docs

The Claude Code feature surface evolves. Frontmatter fields land, get renamed, get deprecated. This skill captures the surface as of its last revision — and **needs to be re-checked periodically** against canonical docs.

## When to drift-check

- Before authoring a non-trivial new skill / subagent / output style / plugin.
- When something in this skill conflicts with what you observe in actual Claude Code behavior.
- On a recurring cadence — every couple of weeks, or after a Claude Code release.
- When the user explicitly asks ("is this still right?").

## How to check (delegate to the companion subagent)

Spawn the `claude-platform-drift-check` subagent. It does a focused diff between this skill and live docs, returns a punch list, and **does not edit files** (read-only by design — you decide what to update).

```
Use the claude-platform-drift-check agent to verify this skill against current docs.
```

Or @-mention it directly:
```
@"claude-platform-drift-check (agent)" run a drift check against /en/skills, /en/sub-agents, /en/managed-agents/*.
```

The subagent ships at `.claude/agents/claude-platform-drift-check.md`.

## What it checks

The subagent fetches and diffs against:
- `https://code.claude.com/docs/en/skills`
- `https://code.claude.com/docs/en/sub-agents`
- `https://code.claude.com/docs/en/output-styles`
- `https://code.claude.com/docs/en/plugins-reference`
- `https://code.claude.com/docs/en/claude-directory`
- `https://platform.claude.com/docs/en/managed-agents/agent-setup`
- `https://platform.claude.com/docs/en/managed-agents/tools`
- `https://platform.claude.com/docs/en/managed-agents/multi-agent`
- `https://platform.claude.com/docs/en/managed-agents/skills`

For each, it checks:
1. New frontmatter fields not documented in `reference/*.md`.
2. Renamed or removed fields.
3. New lifecycle events / hook events.
4. Changed precedence rules or scope.
5. New SDK fields or tool types (e.g. a new `agent_toolset_<date>`).
6. New beta-header values.

## Output

A markdown report with:
- ✅ what's still accurate
- 🔄 what changed (field name, scope, semantics) — quote the new doc text and link
- ❓ what's ambiguous and needs human eyeballs
- 🆕 net-new features the skill doesn't cover yet

The report does not modify the skill. You apply changes after review.

## Scheduling the check

Two options, both project-local:

### Option 1: ad-hoc (recommended initial cadence)

Just delegate when it feels stale, or after seeing release notes.

### Option 2: scheduled — `/loop` or `/schedule`

For a cadence, use the bundled `loop` or `schedule` skills:

```
/loop 1w Use the claude-platform-drift-check agent to verify this skill.
```

Or via `schedule` (cron-style remote agent runs):
```
/schedule weekly "claude-platform-drift-check verifies the claude-platform skill"
```

Both bundled skills are in your tool listing — invoke when you're ready to commit to a cadence. Don't schedule until you've run it manually at least once and confirmed the output is useful.

## Anti-patterns

- ❌ Don't have the drift-check subagent **edit** the skill. Always read-only — the human (or a follow-up turn) applies changes deliberately.
- ❌ Don't drift-check on every session start. Cache the report; check when stale.
- ❌ Don't blindly accept the diff — Claude doc pages occasionally update with editorial-only changes that don't change semantics. Read for substance.
