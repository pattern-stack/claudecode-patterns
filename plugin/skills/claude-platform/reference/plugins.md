# Plugins — reference

A plugin is a self-contained directory of components that Claude Code can install. Plugins bundle skills, agents, hooks, MCP servers, output styles, LSP servers, and monitors into a single distributable unit.

## Layout

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json              # manifest
├── skills/
│   └── <name>/SKILL.md          # full skill with optional bundled files
├── commands/
│   └── <name>.md                # legacy single-file form (still supported)
├── agents/
│   └── <name>.md                # subagents
├── hooks/                       # hook scripts referenced by plugin.json
├── output-styles/
│   └── <name>.md
└── mcp/                         # MCP server configs (optional structure)
```

## Manifest (`plugin.json`)

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin does",
  "author": "...",
  "hooks": "./config/hooks.json",
  "mcpServers": { "my-server": { "type": "stdio", "command": "npx", "args": ["-y", "..."] } },
  "skills": "./custom/skills/",
  "agents": ["./custom/agents/reviewer.md"],
  "commands": ["./custom/commands/deploy.md"],
  "outputStyles": "./custom/styles/"
}
```

**Every component field is top-level. There is NO `components` wrapper** — Claude Code silently ignores unrecognized top-level fields, so a `"components": {...}` wrapper makes everything inside it a no-op with no error. (`claude plugin validate` warns: `Unknown field 'components'`.) This is a real trap: `skills/`, `commands/`, `agents/` and `output-styles/` are scanned by **default**, so a wrapped manifest still *looks* like it works — only `mcpServers` and `hooks`, which have no default directory scan, silently vanish. This plugin shipped that bug from its first release until 0.2.23.

Corollary: **omit the path fields entirely unless you point at a non-default path.** Declaring them buys nothing and costs something —

| Field | Type | Default-path behavior |
|---|---|---|
| `skills` | string \| array (dirs) | **Adds to** the default `skills/` scan — redeclaring the default scans it twice |
| `commands` | string \| array (dirs or `.md` files) | **Replaces** the default `commands/` |
| `agents` | string \| array — **individual `.md` files only**, a directory fails validation | **Replaces** the default `agents/` |
| `outputStyles` | string \| array (dirs or files) | **Replaces** the default `output-styles/` |
| `hooks` | string \| array \| object (inline) | Merges; default file is `hooks/hooks.json` |
| `mcpServers` | string \| array \| object (inline) | Merges; **no default location — must be declared** |

All paths are relative to the plugin root and must start with `./` (the `skills` field also accepts `"."`).

Exact manifest schema: see `/en/plugins-reference`.

## Namespacing

Plugin skills are namespaced as `<plugin-name>:<skill-name>` so they cannot collide with project / user / managed skills. Subagents follow the same pattern in the `@`-mention picker: `@<plugin-name>:<agent-name>`.

When invoking a plugin-supplied subagent as the main session:
```
claude --agent <plugin-name>:<agent-name>
```

## Plugin subagent restrictions (security)

Subagents shipped via a plugin **silently ignore**:
- `hooks`
- `mcpServers`
- `permissionMode`

Reason: a plugin author shouldn't be able to grant arbitrary script execution or override your permission settings. If you need any of these, copy the agent file into `.claude/agents/` or `~/.claude/agents/`. Alternatively, add rules to `permissions.allow` in your settings, but those apply session-wide rather than scoped to the plugin's agent.

## Plugin output styles

Plugin-shipped output styles can set `force-for-plugin: true` to apply automatically whenever the plugin is enabled, overriding the user's `outputStyle` setting. If multiple enabled plugins force, the first one loaded wins.

## Distribution

Plugins distribute via **marketplaces**. Users install via `/plugin install` and discover via `/plugin browse`. See `/en/plugin-marketplaces`.

## When to package as a plugin

Build one when the same `.claude/` setup needs to ship to multiple repositories or to other teams. The trigger: "a second repo needs the same skills + hooks." Don't package prematurely — start with project files in `.claude/` and lift them into a plugin once shape is validated.

This skill ships as part of the **`sdlc` plugin** (`/plugin marketplace add pattern-stack/claudecode-patterns` + `/plugin install sdlc`) alongside the full SDLC roster: `planner`, `specifier`, `implementer`, `validator`, `coordinator`, `understander`, `canvas-author`, `claude-platform-drift-check`. Project-level overrides (canvases, primitives) layer on top of the plugin defaults via `.claude/canvases/<name>/` and `.claude/primitives/<cat>/<name>.md` — see [`path-resolution.md`](../../../primitives/path-resolution.md).

After install, run `/sdlc:setup` to scaffold your project's `.claude/sdlc.yml` interactively.
