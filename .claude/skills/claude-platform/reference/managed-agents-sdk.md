# Anthropic Agent SDK — Managed Agents API reference

The hosted, server-side counterpart to `.claude/`. Define an agent once, version it, then start sessions that reference it. Sessions stream events; multi-agent setups spawn child threads.

All requests require beta header: `anthropic-beta: managed-agents-2026-04-01`. The official SDKs set it automatically.

## Agent

`POST /v1/agents` — create. `PATCH /v1/agents/:id` — new version. `GET /v1/agents/:id/versions` — history. `POST /v1/agents/:id/archive` — read-only.

### Fields

| Field | Required | Notes |
|---|:---:|---|
| `name` | ✓ | Human-readable |
| `model` | ✓ | `claude-opus-4-7` etc. — all 4.5+ supported. For Opus 4.6 fast mode: `{"id": "claude-opus-4-6", "speed": "fast"}` |
| `system` | — | System prompt (the `body` of an `.md` agent file in CLI terms) |
| `tools` | — | Combine: `agent_toolset_20260401` (built-ins), MCP tools, custom tools |
| `mcp_servers` | — | Standardized 3rd-party capabilities |
| `skills` | — | Skills attached to the agent (max 20 per session, across all agents) |
| `multiagent` | — | Coordinator declaration |
| `description` | — | Optional |
| `metadata` | — | Arbitrary `{key: value}` for your own tracking |

### Response

Echoes config plus `id`, `version` (starts at 1, increments on update), `created_at`, `updated_at`, `archived_at`.

### Update semantics

- Omitted fields are preserved.
- Scalar fields replaced; `system`/`description` cleared by passing `null`.
- Array fields (`tools`, `mcp_servers`, `skills`) fully replaced (pass `null` or `[]` to clear).
- `multiagent` replaced as a whole.
- `metadata` merged at key level (empty string clears a key).
- No-op detection: identical update returns existing version, no new version.

### Archive

Read-only freeze. Existing sessions continue; no new sessions can reference. `archived_at` set.

## Tools

Built-in toolset: `agent_toolset_20260401` enables all of:

| Tool | Name |
|---|---|
| Bash | `bash` |
| Read | `read` |
| Write | `write` |
| Edit | `edit` |
| Glob | `glob` |
| Grep | `grep` |
| Web fetch | `web_fetch` |
| Web search | `web_search` |

### Disable specific built-ins
```json
{
  "type": "agent_toolset_20260401",
  "configs": [{"name": "web_fetch", "enabled": false}]
}
```

### Allowlist mode (start with all off)
```json
{
  "type": "agent_toolset_20260401",
  "default_config": {"enabled": false},
  "configs": [
    {"name": "bash", "enabled": true},
    {"name": "read", "enabled": true},
    {"name": "write", "enabled": true}
  ]
}
```

### Custom tools

```json
{
  "type": "custom",
  "name": "get_weather",
  "description": "Get current weather for a location",
  "input_schema": {
    "type": "object",
    "properties": {"location": {"type": "string"}},
    "required": ["location"]
  }
}
```

Your application executes the tool when Claude emits a `requires_action` stop reason and posts back via `user.custom_tool_result` event.

### Tool design best practices

- Detailed descriptions (3-4 sentences min); explain when to use and when not.
- Consolidate related ops into one tool with an `action` parameter rather than many tools.
- Namespace tool names by resource (`db_query`, `storage_read`).
- Return high-signal responses only — semantic IDs, no internal opaque references.

## Permission policies

Each tool has a `default_config.permission_policy`. Built-ins default to `{"type": "always_allow"}`. Other policies (e.g. `always_ask`) trigger `requires_action` events the client must respond to with `user.tool_confirmation`.

## Skills

```json
{
  "skills": [
    {"type": "anthropic", "skill_id": "xlsx"},
    {"type": "custom", "skill_id": "skill_abc123", "version": "latest"}
  ]
}
```

| Field | Notes |
|---|---|
| `type` | `anthropic` (Anthropic-prebuilt) or `custom` (org-uploaded) |
| `skill_id` | Short name (e.g. `xlsx`) or `skill_*` ID for custom |
| `version` | Custom only — pin or `latest` |

Max 20 skills per **session** (counted across all agents in a multi-agent setup).

## Sessions

`POST /v1/sessions` with `{agent: <id>, environment_id: <id>}`.

Each session runs in an environment (sandbox). Session events stream at `/v1/sessions/:id/events/stream` (SSE).

### Posting events to a session

`POST /v1/sessions/:id/events` with `events: [...]`. Common event types you send:
- `user.message` — user turn
- `user.interrupt` — stop a thread (or session if no `session_thread_id`)
- `user.tool_confirmation` — respond to `always_ask` permission requests
- `user.custom_tool_result` — return a custom tool's output

## Multiagent (coordinator pattern)

```json
{
  "multiagent": {
    "type": "coordinator",
    "agents": [
      {"type": "agent", "id": "<reviewer_id>"},
      {"type": "agent", "id": "<test_writer_id>", "version": 3},
      {"type": "self"}
    ]
  }
}
```

Constraints:
- **Depth = 1.** The coordinator can delegate to roster agents; those cannot delegate further.
- **Roster max = 20** unique agents. Coordinator can spawn multiple copies of each.
- **Concurrent threads max = 25** per session.

### How it works

- All agents share the same container + filesystem.
- Each agent runs in its own **session thread** (context-isolated event stream + history).
- Threads are **persistent** — the coordinator can send a follow-up to a child thread it called earlier; the child retains history.
- Each agent uses its own model/system/tools/MCP/skills as defined.

### Threads

- **Primary thread** = session-level event stream. Condensed view of all activity. Always shows: thread created/started/idle/terminated, coordinator↔agent messages, blocking events (tool permission requests).
- **Session threads** = per-agent. Drill in via `/v1/sessions/:id/threads/:thread_id/stream`.
- Session `status` aggregates across threads — `running` if any thread is.
- **Archive** a thread (`POST /v1/sessions/:id/threads/:thread_id/archive`) once it's `idle` to free a slot against the 25-thread cap.

### Primary-thread events for multi-agent

| Type | Notes |
|---|---|
| `session.thread_created` | `session_thread_id`, `agent_name` |
| `session.thread_status_running` | thread became active |
| `session.thread_status_idle` | awaiting input; includes `stop_reason` |
| `session.thread_status_terminated` | archived or terminal error |
| `agent.thread_message_received` | child returned result to coordinator |
| `agent.thread_message_sent` | coordinator sent follow-up to child |

### Cross-posted permission/custom-tool requests

When a non-coordinator child needs `always_ask` permission or returns a custom tool call, the event is **cross-posted to the primary thread** with `session_thread_id` identifying the originator. Reply via the session events endpoint with `tool_use_id` or `custom_tool_use_id`; the server routes to the right thread.

### Interrupt

`user.interrupt` with `session_thread_id` stops a specific thread; omit to target primary. On a `requires_action` thread, interrupt denies pending tool calls and emits `session.thread_status_idle` with `stop_reason: end_turn` (without sampling). On an `idle` thread, interrupt is a no-op.

## Lifecycle summary

| Concept | Purpose |
|---|---|
| **Agent** | Reusable, versioned config. Persona + capabilities |
| **Session** | One run of an agent; references an agent by ID |
| **Thread** | One conversation context within a session (the session itself = primary thread; multi-agent spawns more) |
| **Event** | Streaming primitive for input/output/control |

## Where to read more

- `/docs/en/managed-agents/agent-setup` — Agent fields
- `/docs/en/managed-agents/tools` — Toolset, custom tools, permission policy
- `/docs/en/managed-agents/skills` — Anthropic + custom skills attachment
- `/docs/en/managed-agents/multi-agent` — Coordinator + threads
- `/docs/en/managed-agents/sessions` — Session creation
- `/docs/en/managed-agents/events-and-streaming` — Event stream
- `/docs/en/managed-agents/mcp-connector` — MCP integration
