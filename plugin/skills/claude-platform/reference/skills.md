# Skills — full reference

Skills live at `.claude/skills/<name>/SKILL.md` (project), `~/.claude/skills/<name>/SKILL.md` (user), or in a plugin's `skills/` directory. The directory name becomes the slash-command (`/<name>`) unless the `name` frontmatter overrides it.

## Frontmatter (every supported field)

| Field | Type | Default | Notes |
|---|---|---|---|
| `name` | string | dirname | Lowercase letters/numbers/hyphens; max 64 chars |
| `description` | string | first paragraph of body | **Recommended.** Drives auto-invocation; combined with `when_to_use` and capped at 1,536 chars in the skill listing |
| `when_to_use` | string | — | Trigger phrases / examples; appended to `description` |
| `argument-hint` | string | — | Autocomplete display, e.g. `<branch>` or `[issue-number]` |
| `arguments` | string \| list | — | Named positional args mapped to `$name` substitutions |
| `disable-model-invocation` | bool | `false` | When `true`, only the user can invoke (`/name`); skill is hidden from Claude's listing |
| `user-invocable` | bool | `true` | When `false`, hides from `/` menu; Claude can still invoke |
| `allowed-tools` | string \| list | — | Pre-approves these tools while skill is active (does not restrict what's available) |
| `model` | string | inherit | `sonnet` / `opus` / `haiku` / full ID / `inherit`. Override applies for the rest of the current turn only |
| `effort` | string | inherit | `low` / `medium` / `high` / `xhigh` / `max` |
| `context` | string | — | Set to `fork` to run in a subagent context |
| `agent` | string | `general-purpose` | Which subagent type to fork into (when `context: fork`) |
| `hooks` | object | — | Lifecycle hooks scoped to this skill |
| `paths` | string \| list | — | Glob patterns; auto-invocation only fires for matching files |
| `shell` | string | `bash` | `bash` or `powershell` (powershell requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`) |

All fields are optional. Only `description` is *recommended* (so Claude knows when to use it).

## String substitutions in body content

| Variable | Expands to |
|---|---|
| `$ARGUMENTS` | Full argument string as typed. If absent from body, args appended as `ARGUMENTS: <value>` |
| `$ARGUMENTS[N]` / `$N` | 0-indexed positional. Shell-style quoted (`"hello world"` → single arg) |
| `$<name>` | Named arg from `arguments:` frontmatter list |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_EFFORT}` | Active effort level |
| `${CLAUDE_SKILL_DIR}` | Absolute path to this skill's directory — use this in `!`...`` so scripts work regardless of cwd |

## Dynamic context injection (the `!` syntax)

Run shell commands and inject output into the prompt before Claude reads the body.

Inline form:
```markdown
## Current diff
!`git diff HEAD`
```

Multi-line fenced form:
````markdown
## Environment
```!
node --version
git status --short
```
````

Each command is preprocessing: Claude sees the rendered output, never executes the command itself. Disable globally with `"disableSkillShellExecution": true` in settings.

## Lifecycle: what loads when

| Phase | What loads |
|---|---|
| Session start | All skill names. Descriptions in context unless `disable-model-invocation: true`. Combined description text capped per skill at 1,536 chars; total listing budget = 1% of context window (fallback 8,000) — override via `SLASH_COMMAND_TOOL_CHAR_BUDGET` |
| Skill invocation | Full rendered `SKILL.md` (with `!`...`` already executed and `$N` already substituted) is injected as one message |
| Rest of session | The rendered content **stays in context** for every subsequent turn. The file is not re-read |
| After auto-compact | Most recent invocation of each skill is re-attached, first 5,000 tokens kept; combined cap 25,000 tokens across all re-attached skills |

Implication: write skill bodies as standing instructions, not one-time steps. Move long reference material to bundled files and link from the body.

## Bundled files

```
my-skill/
├── SKILL.md         # required entrypoint
├── reference.md     # supporting docs (loaded on demand)
├── examples/
│   └── sample.md
└── scripts/
    └── helper.py    # executed via Bash, not loaded
```

Reference bundled files from `SKILL.md` so Claude knows what they contain. Use `${CLAUDE_SKILL_DIR}` in `!`...`` invocations to script paths that survive any cwd.

Keep `SKILL.md` under 500 lines; push detail into separate files.

## Invocation control matrix

| Frontmatter | User can invoke (`/name`) | Claude can invoke | Description in context |
|---|:---:|:---:|:---:|
| (default) | ✓ | ✓ | ✓ |
| `disable-model-invocation: true` | ✓ | ✗ | ✗ |
| `user-invocable: false` | ✗ | ✓ | ✓ |

Use `disable-model-invocation: true` for skills with side effects (`/deploy`, `/commit`). Use `user-invocable: false` for background reference (`legacy-system-context`).

## `skillOverrides` (settings-level visibility control)

For skills you didn't author (shipped by a repo or MCP server), control visibility from `.claude/settings.local.json` without editing the SKILL.md:

```json
{
  "skillOverrides": {
    "legacy-context": "name-only",
    "deploy": "off"
  }
}
```

Values: `on` (default) | `name-only` | `user-invocable-only` | `off`. Plugin skills are *not* affected — manage those via `/plugin`.

## Permissions

`allowed-tools` grants pre-approval — does **not** restrict what can be called. Tools you don't list still work, gated by your normal permission rules.

To restrict what Claude can invoke as a skill, use `permissions.deny` in settings:

```text
Skill                 # deny all skills
Skill(deploy *)       # deny one with arg-prefix match
```

## Examples

### Reference skill (knowledge, not action)
```yaml
---
description: API design conventions for this codebase
---

When writing API endpoints:
- Use RESTful naming
- Return `{data, error}` shape
- Validate with Zod
```

### Action skill with side effects
```yaml
---
description: Deploy the application to production
disable-model-invocation: true
allowed-tools: Bash(git push *) Bash(./scripts/deploy.sh *)
argument-hint: <env>
---
Deploy $ARGUMENTS to production.
```

### Forked-context research skill
```yaml
---
description: Research a topic in an isolated Explore agent
context: fork
agent: Explore
---
Research $ARGUMENTS thoroughly. Find relevant files, summarize with file references.
```

### Path-gated skill
```yaml
---
description: React component review checklist
paths:
  - "**/*.tsx"
  - "src/components/**/*.ts"
---
Check: hooks rules, key props, accessibility...
```
