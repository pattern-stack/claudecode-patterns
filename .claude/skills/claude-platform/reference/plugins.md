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
  "components": {
    "skills": "skills/",
    "agents": "agents/",
    "hooks": "...",
    "mcpServers": [...],
    "outputStyles": "output-styles/"
  }
}
```

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

This project's `claude-platform` skill itself is not packaged as a plugin (yet) because it's specific to the dogfood project. If/when this skill graduates, the natural form is to ship it as part of an `agentic-patterns` plugin alongside the SDLC roster (`planner`, `specifier`, `implementer`, `validator`, `coordinator`, `understander`).
