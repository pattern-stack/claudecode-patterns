/**
 * Local-only HTTP control surface for cc-bridge.
 *
 * Routes are deliberately tiny — the daemon is a side process, not a UI.
 * Plugin hook scripts hit /sessions/register and /sessions/deregister;
 * everything else is for diagnostics.
 */

import { Hono } from "hono";
import type { Tailer } from "./tailer.js";

interface RegisterBody {
  session_id?: unknown;
  transcript_path?: unknown;
  cwd?: unknown;
}

interface DeregisterBody {
  session_id?: unknown;
}

export function createServer(tailer: Tailer): Hono {
  const app = new Hono();

  app.get("/health", (c) => c.json({ ok: true, sessions: tailer.list().length }));

  app.post("/sessions/register", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as RegisterBody;
    const sessionId = typeof body.session_id === "string" ? body.session_id : undefined;
    const transcriptPath =
      typeof body.transcript_path === "string" ? body.transcript_path : undefined;
    if (!sessionId || !transcriptPath) {
      return c.json({ error: "missing session_id or transcript_path" }, 400);
    }
    await tailer.register(sessionId, transcriptPath);
    return c.json({ ok: true });
  });

  app.post("/sessions/deregister", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as DeregisterBody;
    const sessionId = typeof body.session_id === "string" ? body.session_id : undefined;
    if (!sessionId) return c.json({ error: "missing session_id" }, 400);
    await tailer.deregister(sessionId);
    return c.json({ ok: true });
  });

  app.get("/admin/state", (c) => c.json({ sessions: tailer.list() }));

  return app;
}
