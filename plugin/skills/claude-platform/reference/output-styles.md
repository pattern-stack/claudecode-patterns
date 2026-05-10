# Output Styles — reference

Output styles modify Claude Code's **system prompt**. They change how Claude responds (role, tone, output format), not what Claude knows. Use one when you want Claude to act as something other than a software engineer, or when you keep re-prompting for the same voice.

## Locations

| Scope | Path |
|---|---|
| User | `~/.claude/output-styles/<name>.md` |
| Project | `.claude/output-styles/<name>.md` |
| Managed | `<managed-settings-dir>/output-styles/<name>.md` |
| Plugin | `<plugin>/output-styles/<name>.md` |

Built-ins: **Default** (the standard system prompt), **Explanatory** (adds Insights), **Learning** (asks user to write small pieces, leaves `TODO(human)` markers).

## Frontmatter

| Field | Default | Notes |
|---|---|---|
| `name` | filename | Display name |
| `description` | — | Shown in `/config` picker |
| `keep-coding-instructions` | `false` | When false, Claude Code's coding-specific system instructions are **dropped** (the whole point of output styles). When true, they're kept and your style appends |
| `force-for-plugin` | `false` | Plugin only: applies automatically when plugin is enabled. Overrides user `outputStyle` setting. First plugin loaded wins if multiple force |

## How they layer

- Custom output styles **replace** the coding-specific portion of the system prompt unless `keep-coding-instructions: true`.
- All output styles append the file body to the end of the system prompt.
- All output styles add periodic reminders for Claude to adhere.

## Selecting a style

`/config` → Output style picker writes `outputStyle` to `.claude/settings.local.json`. Or set directly:

```json
{ "outputStyle": "Explanatory" }
```

System prompt is fixed at session start (for prompt caching). Changes apply on next session.

## How they differ from related features

| | Output style | CLAUDE.md | `--append-system-prompt` |
|---|---|---|---|
| Edits Claude Code's default system prompt | ✓ (drops coding instructions) | ✗ | ✗ |
| Where content lands | end of system prompt | user message after system prompt | end of system prompt |
| Loads | session start | session start | session start |

| | Output style | Skill |
|---|---|---|
| Always active once selected | ✓ | only when invoked |
| Modifies system prompt | ✓ | ✗ (loads as a message) |
| Best for | tone / format preferences | reusable workflows |

| | Output style | Subagent |
|---|---|---|
| Affects main loop | ✓ | spawned for one task |
| Has its own model / tools | ✗ | ✓ |

## Example

```markdown
---
name: Teaching
description: Explains reasoning and asks the user to implement small pieces
keep-coding-instructions: true
---

After completing each task, add a brief "Why this approach" note explaining the key design decision.

When a change is under 10 lines, ask the user to implement it themselves by leaving a `TODO(human)` marker instead of writing it.
```
