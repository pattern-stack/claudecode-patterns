# Cookbook: author once, compile to both `.claude/` and the SDK

You can drive both surfaces from a single markdown definition with a superset frontmatter, by deciding upfront which fields are **portable**, which are **CLI-only**, and which are **SDK-only**. The compiler emits CLI files for one target and an API payload for the other.

This is feasible because the conceptual model (system prompt + tools + MCP + skills + multi-agent) is shared. Only the wire format and a few UX/safety primitives differ.

## The translation matrix (concise)

| Source frontmatter | → CLI (`.claude/agents/`) | → SDK (Agents API) |
|---|---|---|
| `name` | `name:` | `name` |
| `description` | `description:` | `description` |
| `model: sonnet|opus|haiku|<id>|inherit` | `model:` | `model: {id, speed?}` (drop `inherit`; resolve at compile time) |
| `system` (or markdown body) | body of `.md` | `system` |
| `tools: [a, b, ...]` | `tools: a, b, ...` | `[{type: agent_toolset_20260401, default_config: {enabled: false}, configs: [{name: a, enabled: true}, ...]}]` |
| `disallowedTools: [a, b]` | `disallowedTools: a, b` | `[{type: agent_toolset_20260401, configs: [{name: a, enabled: false}, ...]}]` |
| `mcpServers` (inline + refs) | `mcpServers:` list | `mcp_servers` array |
| `customTools: [...]` | implement as MCP server | first-class `[{type: custom, name, description, input_schema}]` |
| `skills: [name, ...]` | `skills:` (preload list) | upload each as a custom skill, then `[{type: custom, skill_id, version: latest}]` |
| `multiagent: {type: coordinator, agents: [...]}` | `tools: Agent(a, b, ...)` plus matching `.md` files | `multiagent.coordinator.agents[]` |
| `metadata: {k: v}` | drop or stash in CLAUDE.md comment | `metadata` |
| `permissionMode` | `permissionMode:` | drop; reify per-tool `permission_policy` instead |
| `disable-model-invocation` (skill) | `disable-model-invocation:` | drop (no slash menu) |
| `user-invocable` (skill) | `user-invocable:` | drop |
| `paths` (skill) | `paths:` | drop |
| `argument-hint`, `arguments` (skill) | as-is | drop (or pre-bake into `system`) |
| `color`, `background`, `isolation`, `initialPrompt` | as-is | drop |
| `hooks` | `hooks:` | drop; equivalent fires on the event stream — your client app handles |
| Output style file | `output-styles/<n>.md` | concat into `system` |
| `CLAUDE.md` | live file | concat into `system` |
| `!`...`` dynamic context | live preprocessing | pre-render at compile time |

## Sketch: a unified definition

```markdown
---
# Portable
name: code-reviewer
description: Reviews code for security, correctness, and maintainability
model: sonnet
tools: [Read, Grep, Glob, Bash]
mcpServers:
  - github
skills: [security-conventions, error-handling-patterns]

# CLI-only (silently dropped by SDK compile)
permissionMode: plan
color: blue
memory: project

# SDK-only (silently dropped by CLI compile)
metadata:
  team: platform
  cost_tier: t2
---

You are a senior reviewer. Run `git diff`, focus on modified files, organize feedback as Critical / Warning / Suggestion.
```

## Compile to CLI: emit `.claude/agents/code-reviewer.md`

Strip SDK-only keys, write the file as-is:

```yaml
---
name: code-reviewer
description: Reviews code for security, correctness, and maintainability
model: sonnet
tools: Read, Grep, Glob, Bash
mcpServers:
  - github
skills:
  - security-conventions
  - error-handling-patterns
permissionMode: plan
color: blue
memory: project
---

You are a senior reviewer. Run `git diff`, focus on modified files, organize feedback as Critical / Warning / Suggestion.
```

## Compile to SDK: emit JSON for `POST /v1/agents`

1. Resolve `model: sonnet` → `claude-sonnet-4-6` (or your pinned ID).
2. Translate `tools` to a single toolset config:
   ```json
   {
     "type": "agent_toolset_20260401",
     "default_config": {"enabled": false},
     "configs": [
       {"name": "read", "enabled": true},
       {"name": "grep", "enabled": true},
       {"name": "glob", "enabled": true},
       {"name": "bash", "enabled": true}
     ]
   }
   ```
3. Resolve `mcpServers: github` against your MCP registry → emit the inline definition.
4. For `skills`: upload `security-conventions/` and `error-handling-patterns/` as custom skills (returns `skill_*` IDs), reference them.
5. Concat any `CLAUDE.md` + selected output style into `system`, prefixed before the body.
6. Drop `permissionMode`, `color`, `memory`.

```json
{
  "name": "code-reviewer",
  "model": "claude-sonnet-4-6",
  "system": "<CLAUDE.md content>\n\n<output style content>\n\nYou are a senior reviewer. ...",
  "tools": [{
    "type": "agent_toolset_20260401",
    "default_config": {"enabled": false},
    "configs": [
      {"name": "read", "enabled": true},
      {"name": "grep", "enabled": true},
      {"name": "glob", "enabled": true},
      {"name": "bash", "enabled": true}
    ]
  }],
  "mcp_servers": [{"name": "github", "type": "stdio", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"]}],
  "skills": [
    {"type": "custom", "skill_id": "skill_<security_conventions_id>", "version": "latest"},
    {"type": "custom", "skill_id": "skill_<error_handling_patterns_id>", "version": "latest"}
  ],
  "metadata": {"team": "platform", "cost_tier": "t2"},
  "description": "Reviews code for security, correctness, and maintainability"
}
```

## Skills: the upload step

CLI skills are filesystem markdown. SDK custom skills are uploaded (one-time) and referenced by `skill_id`. The compiler must:

1. For each skill listed in `skills:`, package the `SKILL.md` + bundled files as the skill upload payload.
2. Call the custom-skill upload endpoint to register it under your org.
3. Cache the returned `skill_*` ID and version. On re-upload, generate a new version.

This is a state-keeping step — the compiler needs a manifest mapping skill name → `skill_id`.

## Hooks: the asymmetry

Hooks have no SDK analog. To get equivalent behavior on the SDK side:
- The hook's logic moves into your **client application** that processes the session event stream.
- For `PreToolUse`-style guardrails, use per-tool `permission_policy: always_ask`. Your client receives `requires_action` events, evaluates, then sends `user.tool_confirmation` (allow/deny).
- For `PostToolUse` side effects (linting, notifications), trigger them from your client when you observe a `tool_result` event.

Compile-time: emit a stub `hooks-on-event-stream.ts` that maps each `hooks.<Event>` definition to an event-stream handler. The cookbook can include a small runtime that reads the same `hooks` config and dispatches.

## CLAUDE.md and rules: pre-bake into `system`

The SDK has no concept of "automatically loaded project context." At compile time:
- Concatenate `CLAUDE.md` + global `~/.claude/CLAUDE.md` + applicable `.claude/rules/*.md` (filtered by `paths:` against expected file scope) into the `system` prompt.
- Optionally append the active output style.
- Done.

Tradeoff: paths-gated rules can no longer activate dynamically. Either bake them all in (token cost), or don't include them and rely on the agent loading them via a tool call.

## What the compiler should refuse

- A skill with `disable-model-invocation: true` and no clear user-trigger affordance on the SDK side. Either drop the skill or surface a comment explaining the user must trigger it via the API.
- A subagent with `Agent(a, b)` referencing names not in the SDK roster. Either upload all referenced agents and emit `multiagent.coordinator.agents`, or fail.
- A skill with live `!`...`` injection where the command depends on session state (`$CLAUDE_SESSION_ID`). Pre-rendering at compile time loses the dynamic value. Refuse or warn.

## Validation strategy

For round-trippability:
1. CLI → SDK → CLI should produce a CLI definition equivalent to the original modulo the lossy fields (which were CLI-only and reapplied from the source).
2. Compiler keeps a `source.yaml` alongside outputs so the original lives next to both compiled targets.

## Bottom line

You can have a single source of truth in markdown if you accept:
- Some frontmatter is portable, some isn't, and that's fine.
- Skills require an upload step for the SDK side (compiler manages a name → ID map).
- Hooks/rules/output-styles need pre-baking or runtime equivalents.
- A handful of UX flags (`color`, `background`, `disable-model-invocation`) are silently dropped by the SDK compile path.

The exercise is mostly mechanical translation — the hard parts are skill uploads (state) and hook semantics (no equivalent, only convention).
