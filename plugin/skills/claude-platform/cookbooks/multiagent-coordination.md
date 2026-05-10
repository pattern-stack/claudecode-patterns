# Cookbook: multi-agent coordination

Two paradigms — **CLI** (`.claude/agents/` + Agent tool spawning) and **SDK** (`multiagent.coordinator` on the agent definition). Same conceptual shape, different mechanism.

## CLI pattern: coordinator subagent

Define a coordinator with explicit `Agent(...)` allowlist:

```yaml
# .claude/agents/coordinator.md
---
name: coordinator
description: Orchestrates implementation work across specialist agents for one issue
tools: Agent(implementer, validator, understander), Read, Bash, mcp__plugin_linear_linear__get_issue
model: sonnet
---

You coordinate one Linear issue. Spawn `understander` first, then gate to `implementer`, then `validator`. Aggregate their results.
```

Run as the main thread:
```bash
claude --agent coordinator
```

Or as a subagent spawned from main: `Use the coordinator agent for ABC-101`.

Constraints:
- **Subagents cannot spawn subagents.** If the coordinator runs as a subagent, `Agent(...)` is ignored. Run it as `--agent` to enable spawning.
- Explicit allowlist (`Agent(a, b)`) blocks anything not listed. Bare `Agent` (no parens) allows any. Omitting `Agent` blocks all.

## SDK pattern: coordinator declared at agent-definition time

```bash
curl -fsSL https://api.anthropic.com/v1/agents \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "name": "Engineering Lead",
    "model": "claude-opus-4-7",
    "system": "You coordinate engineering work...",
    "tools": [{"type": "agent_toolset_20260401"}],
    "multiagent": {
      "type": "coordinator",
      "agents": [
        {"type": "agent", "id": "<reviewer_id>"},
        {"type": "agent", "id": "<test_writer_id>", "version": 3},
        {"type": "self"}
      ]
    }
  }'
```

Roster entry types:
- `{"type": "agent", "id": "<id>"}` — pin to latest version implicitly
- `{"type": "agent", "id": "<id>", "version": N}` — pin to exact version
- `{"type": "self"}` — coordinator can spawn copies of itself

Constraints:
- Depth = 1 (children cannot delegate further; further `multiagent` declarations are ignored)
- Roster max = 20 unique agents
- Concurrent threads max = 25 per session

## Patterns

### Parallelization (fan-out)

```
coordinator → spawn(reviewer) // researches security
            → spawn(reviewer) // researches performance
            → spawn(reviewer) // researches accessibility
            (all in parallel, separate threads)
            → synthesize 3 results
```

CLI: spawn three Agent tool calls in one message.
SDK: same — coordinator emits multiple `agent.thread_message_sent` events; each spawns a thread.

### Specialization (route by skill)

Each agent has its own model/system/tools/MCP/skills. Coordinator routes based on task description.

### Escalation

Cheap model coordinates; only delegates to a more expensive model for hard subtasks.

## Threads (SDK only)

- **Primary thread** = session event stream. Shows condensed activity from all threads.
- **Session threads** = per-agent conversation history. Persistent — coordinator can `SendMessage` follow-ups; child retains state.
- **Archive** an `idle` thread (`POST /v1/sessions/:id/threads/:thread_id/archive`) to free a slot against the 25-cap. Running threads must be interrupted first.

### Cross-thread tool permissions

Non-coordinator agents that hit `always_ask` permission or emit a custom tool call have the event **cross-posted to the primary thread** with `session_thread_id` identifying the originator. Reply via the session events endpoint with `tool_use_id` or `custom_tool_use_id`; the server routes the response to the right thread.

### Interrupt

`user.interrupt` with `session_thread_id` stops one thread; omit to target primary. On `requires_action`: denies pending tool calls, emits `session.thread_status_idle` with `stop_reason: end_turn`. On `idle`: no-op.

## Project-level pattern (this repo)

`/orchestrate` (Topology B in `.claude/sdlc.yml`) follows this CLI pattern:
- One **coordinator** teammate per issue.
- Each coordinator runs **implementer** and **validator** as headless subagents.
- `orchestrate_concurrency: 3` caps how many issues run in parallel.

Compare to `/develop` (Topology A): a single flat team operating on one issue with split-pane teammates rather than nested subagents. Topology A is for active human collaboration; Topology B is for AFK throughput on pre-approved issues.

## Costs and gotchas

- Each child agent's results return to the parent's context — running 10 fan-out children that each summarize 30 files can still blow up the parent's context. Use agent teams instead for sustained parallelism.
- Plugin-shipped agents silently ignore `hooks` / `mcpServers` / `permissionMode`. If your coordinator depends on those for security, copy the file into `.claude/agents/`.
- Forked subagents (`/fork`) inherit the **full main conversation** — different from rosters. Use forks for "try several approaches from here"; use rosters for "specialists with their own context."
