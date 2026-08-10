---
name: claude-platform
description: "Authoritative reference and authoring guide for the Claude platform — both the Claude Code `.claude/` config layer (skills, subagents, output styles, hooks, plugins, settings) and the Anthropic Agent SDK (Managed Agents API: agents, sessions, threads, multiagent, skills). Use when authoring a skill / subagent / output style / hook / plugin manifest, when designing a multi-agent system, or when comparing CLI vs SDK and translating between them."
when_to_use: User asks about `.claude/` structure, "how do I write a skill", "how do hooks work", "should this be a skill or subagent", "how do I ship a plugin", "what's the SDK equivalent", "translate this agent definition to the API", or otherwise wants canonical authoring guidance.
allowed-tools: Read, Glob, Grep
user-invocable: true
---

# claude-platform

Authoring reference for both Claude surfaces: the `.claude/` filesystem layer (Claude Code CLI) and the Anthropic Agent SDK (Managed Agents API).

This skill is reference material. Read the relevant section, then follow the linked detail file. Do not read everything at once — branch by what you're authoring.

## The two surfaces

| Surface | Definition format | Storage | Versioning |
|---|---|---|---|
| **Claude Code CLI** (`.claude/`) | Markdown + YAML frontmatter | Filesystem (project / user / managed / plugin) | git |
| **Anthropic Agent SDK** (Managed Agents) | JSON via `/v1/agents` REST API | Server-side, immutable versions | API-managed (`version` increments) |

Both surfaces share concepts (system prompt, tools, MCP, skills, multi-agent), but the wire format and lifecycle differ. See [reference/variances.md](reference/variances.md) for the full mapping and [cookbooks/unified-markdown-to-both.md](cookbooks/unified-markdown-to-both.md) for translating between them.

## What lives in `.claude/` (the full taxonomy)

```
your-project/
├── CLAUDE.md                     # Always-on project instructions (loads every session)
├── .mcp.json                     # Project-scoped MCP servers (committed)
├── .worktreeinclude              # Gitignored files to copy into worktrees
└── .claude/
    ├── settings.json             # Permissions, hooks, statusLine, model, env, outputStyle, agent, skillOverrides
    ├── settings.local.json       # Personal overrides (gitignored)
    ├── CLAUDE.md                 # Alt location for project CLAUDE.md
    ├── rules/<topic>.md          # Topic-scoped instructions; optional `paths:` glob gating
    ├── skills/<name>/SKILL.md    # Invocable skills (with optional bundled files)
    ├── commands/<name>.md        # Legacy single-file form of skill (still works)
    ├── output-styles/<name>.md   # System-prompt overrides
    ├── agents/<name>.md          # Subagents
    ├── agent-memory/<agent>/     # Subagent persistent memory (committed)
    └── agent-memory-local/       # Subagent memory, gitignored
```

Plus:
- **User scope:** `~/.claude/` mirrors the same layout for personal config across all projects.
- **Plugin scope:** `<plugin>/.claude-plugin/plugin.json` + components in `<plugin>/{skills,agents,hooks,commands,output-styles}/`.
- **Managed scope:** organization-wide deployment via managed settings directory.

Precedence (when same-named definitions exist at multiple scopes):
- **Skills:** managed > user > project (plugin skills are namespaced `<plugin>:<skill>` so don't collide).
- **Subagents:** managed > `--agents` CLI flag > project > user > plugin.
- **MCP servers:** local > project > user.
- **CLAUDE.md / rules:** additive (all levels concatenated).
- **Hooks:** all sources merge (every registered hook fires).
- **Settings (scalar keys):** more specific wins; **settings (array keys):** combine across scopes.

## Decision tree: what to build

```
Need always-on context?              → CLAUDE.md (or .claude/rules/ with paths: globs)
Need on-demand workflow / reference? → skill (.claude/skills/<name>/SKILL.md)
Need isolated context, returns summary?→ subagent (.claude/agents/<name>.md)
Need parallel independent sessions?  → agent teams (experimental) — see /en/agent-teams
Need deterministic side effect on event?→ hook (settings.json.hooks)
Need to bundle and ship the above?   → plugin (.claude-plugin/plugin.json)
Need different system prompt persona? → output-style (.claude/output-styles/<name>.md)
Need to call from a hosted service?  → SDK Agent (POST /v1/agents)
```

A skill can fork into a subagent (`context: fork`); a subagent can preload skills (`skills:` field). The two are intertwined — see [cookbooks/skill-vs-subagent.md](cookbooks/skill-vs-subagent.md).

## Frontmatter quick-reference

| Field | Skill | Subagent | Output style |
|---|:---:|:---:|:---:|
| `name` | optional (defaults to dirname) | **required** | optional |
| `description` | recommended | **required** | optional |
| `when_to_use` | optional | — | — |
| `argument-hint` | ✓ | — | — |
| `arguments` | ✓ (named positional) | — | — |
| `allowed-tools` | ✓ | — | — |
| `tools` | — | ✓ allowlist | — |
| `disallowedTools` | — | ✓ denylist | — |
| `disable-model-invocation` | ✓ | — | — |
| `user-invocable` | ✓ | — | — |
| `model` | ✓ | ✓ | — |
| `effort` | ✓ | ✓ | — |
| `context: fork` | ✓ | — | — |
| `agent` | ✓ (which subagent) | — | — |
| `permissionMode` | — | ✓ | — |
| `maxTurns` | — | ✓ | — |
| `skills` | — | ✓ (preload list) | — |
| `mcpServers` | — | ✓ | — |
| `hooks` | ✓ | ✓ | — |
| `memory` | — | ✓ (user/project/local) | — |
| `background` | — | ✓ | — |
| `isolation: worktree` | — | ✓ | — |
| `color` | — | ✓ | — |
| `initialPrompt` | — | ✓ (when run as `--agent`) | — |
| `paths` | ✓ | — | — |
| `shell` | ✓ (bash/powershell) | — | — |
| `keep-coding-instructions` | — | — | ✓ |
| `force-for-plugin` | — | — | ✓ (plugin only) |

Full per-field semantics live in:
- [reference/skills.md](reference/skills.md)
- [reference/subagents.md](reference/subagents.md)
- [reference/output-styles.md](reference/output-styles.md)
- [reference/settings.md](reference/settings.md)
- [reference/plugins.md](reference/plugins.md)
- [reference/managed-agents-sdk.md](reference/managed-agents-sdk.md)
- [reference/variances.md](reference/variances.md) — the CLI↔SDK translation matrix

## Cookbooks (variances broken apart)

- [skill-vs-subagent](cookbooks/skill-vs-subagent.md) — picking the right primitive
- [workflow-with-fork](cookbooks/workflow-with-fork.md) — skills running in subagent context
- [multiagent-coordination](cookbooks/multiagent-coordination.md) — coordinator + roster (SDK-side patterns)
- [unified-markdown-to-both](cookbooks/unified-markdown-to-both.md) — author once, compile to both `.claude/` and SDK
- [drift-check](cookbooks/drift-check.md) — keep this skill aligned with upstream docs

## Staying current — drift check

Claude Code's surface evolves; this skill captures it as of its last revision. Before authoring anything non-trivial, or on a recurring cadence, **delegate to the `claude-platform-drift-check` subagent** (`.claude/agents/claude-platform-drift-check.md`). It diffs each `reference/*.md` against canonical docs and returns a punch list. It is read-only — you apply changes deliberately.

```
Use the claude-platform-drift-check agent to verify this skill against current docs.
```

Recurring cadence options (start ad-hoc; only schedule once you've seen the report be useful):
- `/loop 1w Use the claude-platform-drift-check agent to verify this skill.`
- `/schedule weekly "claude-platform-drift-check verifies the claude-platform skill"`

See [cookbooks/drift-check.md](cookbooks/drift-check.md) for the full protocol.

## Templates

- [skill-rich.md](templates/skill-rich.md) — every modern skill field
- [subagent-rich.md](templates/subagent-rich.md) — full subagent surface
- [output-style.md](templates/output-style.md)
- [plugin-manifest.json](templates/plugin-manifest.json)

## Project context

This project's `.claude/sdlc.yml` defines `artifact_paths` and primitives (`language`, `quality_profile`, `commit_style`, `task_management`). New skills/agents/commands authored here should declare which primitives they consume and read paths from `sdlc.yml` rather than hardcoding. See `.claude/skills/skill-authoring/SKILL.md` for the project's specific SDLC component-creation conventions; this skill (`claude-platform`) is the broader platform reference that backs it.

## Authoring discipline

1. **Description is the trigger.** It's how Claude (and humans browsing `/`) decide whether to invoke. Put the key use case first; the combined `description` + `when_to_use` is truncated at 1,536 chars in the listing.
2. **Skill body lives in context for the rest of the session** once invoked — every line is recurring tokens. Move long reference into bundled files and link from `SKILL.md`.
3. **Restrict tools deliberately.** `allowed-tools` (skill) grants pre-approval; `tools` (subagent) is an allowlist; `disallowedTools` is a denylist. Plugin subagents cannot use `hooks` / `mcpServers` / `permissionMode` — copy the file into `.claude/agents/` if you need them.
4. **Enforce with hooks, suggest with prompts.** "Never edit `.env`" in a system prompt is a request, not a guarantee. A `PreToolUse` hook with `exit 2` is enforcement.
5. **Live reload:** skills hot-reload mid-session; subagents and `settings.json` require a session restart.
