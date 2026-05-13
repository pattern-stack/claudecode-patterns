/**
 * Historical event REST + live SSE stream.
 */

import { Hono } from "hono";
import type { EventStore } from "../event-store.js";
import type { SSEBroadcaster } from "../sse-broadcaster.js";

export function eventRoutes(
  eventStore: EventStore | undefined,
  broadcaster: SSEBroadcaster,
): Hono {
  const app = new Hono();

  app.get("/admin/events/recent", (c) => {
    if (!eventStore) {
      return c.json(
        {
          error: "persistence not configured",
          hint: "unset CC_VIEWER_PERSISTENCE=0 (bun:sqlite ships with bun)",
        },
        503,
      );
    }
    const since = parseDate(c.req.query("since"));
    const limit = parseInt10(c.req.query("limit"), 1000, 1, 10000);
    const type = c.req.query("type") ?? undefined;
    const rows = eventStore.recent({ since, limit, type });
    return c.json({ events: rows });
  });

  app.get("/admin/claude-code/sessions", (c) => {
    if (!eventStore) {
      return c.json({ error: "persistence not configured" }, 503);
    }
    const limit = parseInt10(c.req.query("limit"), 50, 1, 500);
    return c.json({ sessions: eventStore.sessions(limit) });
  });

  app.get("/admin/claude-code/sessions/:sessionId", (c) => {
    if (!eventStore) {
      return c.json({ error: "persistence not configured" }, 503);
    }
    const sessionId = c.req.param("sessionId");
    return c.json({ sessionId, events: eventStore.sessionEvents(sessionId) });
  });

  app.get("/admin/events/stream", (c) => {
    const stream = broadcaster.connect();
    c.req.raw.signal.addEventListener("abort", () => {
      broadcaster.disconnect(stream);
    });
    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  });

  return app;
}

function parseDate(s: string | undefined): Date | undefined {
  if (!s) return undefined;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? undefined : d;
}

function parseInt10(s: string | undefined, fallback: number, min: number, max: number): number {
  if (!s) return fallback;
  const n = Number.parseInt(s, 10);
  if (Number.isNaN(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}
