# Variances: `.claude/` (CLI) vs Agent SDK (Managed Agents API)

The two surfaces share a model — system prompt, tools, MCP, skills, multi-agent — but differ in wire format, lifecycle, and what's first-class.

## Side-by-side mapping

| Concept | `.claude/` (CLI) | SDK (Managed Agents) | Translatable? |
|---|---|---|---|
| Agent definition | `.md` with YAML frontmatter | JSON via `POST /v1/agents` | ✓ direct |
| System prompt | Markdown body | `system` field | ✓ direct |
| Storage | Filesystem (committed git) | Server-side, immutable versions | ✗ not interchangeable |
| Versioning | git commits | API `version` (auto-increments on update) | conceptually equivalent |
| Tool allowlist | `tools: Read, Grep, ...` | `tools: [{type: agent_toolset_20260401, configs: [...]}]` | ✓ via toolset config |
| Tool denylist | `disallowedTools: Write, Edit` | `default_config.enabled: false` + per-tool `enabled: true` | ✓ inverse |
| Custom tools | Provided via MCP server | First-class `{type: custom, input_schema}` | ✓ via MCP, or first-class |
| MCP servers | `.mcp.json`, settings, agent inline | `mcp_servers` field on agent | ✓ direct |
| Skills | Filesystem `SKILL.md` | Org-uploaded skill IDs (`skill_*`) | partial — body must be uploaded as a custom skill |
| Permission control | `permissions.{allow,deny,ask}` patterns + `permissionMode` | Per-tool `permission_policy` (`always_allow` / `always_ask`); client confirms via `user.tool_confirmation` | partial — different model |
| Subagents / multi-agent | Spawn via Agent tool; project file rosters | `multiagent.coordinator.agents[]` roster on agent | ✓ direct (depth=1, max 20) |
| Subagent persistent memory | `memory: project/user/local` → `MEMORY.md` files | Not native — implement via custom tool + your storage | ✗ build-it-yourself |
| Hooks | Lifecycle event scripts in settings | Not present — your client app processes the event stream | ✗ different paradigm |
| CLAUDE.md | Always loaded | Not native — concat into `system` | ✓ at compile time |
| Rules (`paths:` gated) | Auto-load on matching files | Not native | ✗ stays CLI-only |
| Output styles | `output-styles/<name>.md` modifies system prompt | Bake into `system` directly | ✓ at compile time |
| `--agent <name>` (run as main) | Replaces session system prompt | Always the case (sessions reference the agent) | conceptually default |
| Worktree isolation | `--worktree`, `isolation: worktree` | Each session has an `environment_id` (sandbox) | similar concept, different mechanism |
| Forked subagent (full convo inheritance) | `/fork`, `CLAUDE_CODE_FORK_SUBAGENT=1` | Not native — each thread has its own history | ✗ stays CLI-only |
| `disable-model-invocation` | ✓ | N/A (no `/` slash interface) | irrelevant |
| `user-invocable: false` | ✓ | N/A | irrelevant |
| Agent `color`, `background` | UX in CLI | N/A | irrelevant |
| Streaming UI / status line | CLI | Caller's responsibility | UX-only |
| Session resumption | `claude --resume`, transcripts in `~/.claude/projects/` | `session_id` + thread streams | similar |
| Effort level | `effort: low/medium/high/...` | Pass at session/thread creation | ✓ |

## What only exists CLI-side

- **Hooks** — deterministic side effects on lifecycle events. The SDK exposes the same events as a stream you process in your own code; there is no server-side hook execution.
- **CLAUDE.md auto-load** — must be concatenated into `system` for SDK.
- **Rules with `paths:` globs** — file-aware loading is CLI-specific.
- **Output styles** — system-prompt-mutation is CLI's own layer; SDK callers just craft `system` directly.
- **Live reload, `/agents` interface, `/skills` menu** — UI concerns.
- **`disable-model-invocation`, `user-invocable`** — control over the `/` slash menu.
- **`color`, `background`, `initialPrompt`** — UI/UX flags.
- **Forked subagents (`/fork`)** — inherits full conversation history; SDK threads don't share history.
- **`skillOverrides`** — settings-level menu visibility.
- **Worktree** as a CLI concept maps loosely to SDK environments.
- **`--add-dir`** — file access from outside cwd.

## What only exists SDK-side

- **Versioned, archivable agents** with `archived_at` semantics.
- **`agent_toolset_20260401`** as a versioned, dated toolset bundle.
- **Per-tool `permission_policy`** (`always_allow` / `always_ask`) at tool definition level.
- **First-class custom tools** with `input_schema` declared on the agent (rather than via MCP).
- **Anthropic-pre-built skills** (e.g. `xlsx`, `pptx`, `docx`) — not in CLI.
- **Coordinator/roster declared at agent-definition time** (CLI subagent rosters live in `tools: Agent(a, b)` on the spawning agent).
- **Sandboxed environments** (`environment_id`) — formal sandbox primitive.
- **Programmatic thread interrupt** (`user.interrupt` with `session_thread_id`).

## Lifecycle differences

| | CLI | SDK |
|---|---|---|
| Edit definition | git commit | `PATCH /v1/agents/:id` (creates new version) |
| Roll back | `git revert` | New PATCH to previous version's content |
| Multi-tenant | repos / users | API key + agent IDs |
| Observability | hooks → external sinks | event stream → your app |

## Translation: what's safe to compile, what isn't

Safe to compile **CLI → SDK**:
- Subagent body → `system`
- `tools` allowlist → `agent_toolset_20260401` + `configs`
- `mcpServers` → `mcp_servers`
- `model` → `model`
- `description` → `description`
- Multi-agent rosters declared via `Agent(a, b)` in CLI tools field → `multiagent.coordinator.agents`
- Skills referenced by name → must first upload each as a custom skill, then reference by `skill_id`

Lossy (CLI-only) when going to SDK:
- `permissionMode`, `disable-model-invocation`, `user-invocable`, `color`, `background`, `isolation`, `initialPrompt`, `paths`, `argument-hint`, `arguments`, `hooks`, `memory`
- Output styles (must merge into `system` at compile time)
- CLAUDE.md / rules (must concat into `system` at compile time)
- `!`...`` dynamic context (must pre-render at compile time, since SDK has no skill loader)

Lossy (SDK-only) when going to CLI:
- Versioning history (just rely on git)
- Per-tool `permission_policy` (closest CLI equiv: `permissions.ask` / `permissions.allow` patterns)
- Anthropic-prebuilt skills (CLI doesn't have these — would need authoring local equivalents)
- `metadata` (no CLI slot)

See [cookbooks/unified-markdown-to-both.md](../cookbooks/unified-markdown-to-both.md) for a concrete compilation strategy.
