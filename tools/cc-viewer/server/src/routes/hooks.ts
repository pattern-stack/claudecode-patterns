/**
 * Claude Code hook ingestion. Receives one POST per hook callback from the
 * `cc-viewer` plugin's `emit.mjs` shim, normalizes it into a
 * `ClaudeCodeHookEvent`, appends to the durable store, and broadcasts to
 * any connected SSE clients.
 */

import { Hono } from "hono";
import type { EventStore } from "../event-store.js";
import { type ClaudeCodeHookEvent, isClaudeCodeHookName } from "../event-types.js";
import type { SSEBroadcaster } from "../sse-broadcaster.js";

function newSpanId(): string {
  if (typeof globalThis !== "undefined" && "crypto" in globalThis) {
    return (globalThis as unknown as { crypto: { randomUUID(): string } }).crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export function hookRoutes(broadcaster: SSEBroadcaster, store: EventStore | undefined): Hono {
  const app = new Hono();

  app.post("/hooks/:eventType", async (c) => {
    const eventType = c.req.param("eventType");
    if (!isClaudeCodeHookName(eventType)) {
      return c.json({ error: `unknown hook event: ${eventType}` }, 400);
    }

    const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
    const sessionId = typeof body.session_id === "string" ? body.session_id : "unknown";

    const hookEvent: ClaudeCodeHookEvent = {
      type: "claude_code.hook",
      traceId: sessionId,
      runId: sessionId,
      spanId: newSpanId(),
      timestamp: new Date(),
      hookName: eventType,
      sessionId,
      transcriptPath: typeof body.transcript_path === "string" ? body.transcript_path : undefined,
      cwd: typeof body.cwd === "string" ? body.cwd : undefined,
      permissionMode: typeof body.permission_mode === "string" ? body.permission_mode : undefined,
      toolName: typeof body.tool_name === "string" ? body.tool_name : undefined,
      toolInput: body.tool_input,
      toolResponse: body.tool_response,
      toolUseId: typeof body.tool_use_id === "string" ? body.tool_use_id : undefined,
      payload: body,
    };

    store?.append(hookEvent);
    broadcaster.broadcast("claude_code.hook", hookEvent);

    return c.json({ ok: true });
  });

  return app;
}
