/**
 * Terminal input: the HTTP projection of the SessionInput port (input/session-input.ts).
 *
 * The viewer is read-only over Claude Code transcripts; this route lets a surface (the chat composer, the voice
 * page) send a message *back into* the live terminal session it is watching. Which terminal, and how, is the
 * adapters' business (input/index.ts): Herdr by Claude session id, ghostty-bridge by working directory.
 *
 *   POST /admin/input/send  { session_id?, cwd?, tty?, text, submit? }
 *     200 { ok, adapter, terminal_id, matched }
 *     400 bad body · 404 no live terminal · 409 ambiguous (details.candidates) · 423 not ready (details.reason)
 *     502 adapter failed
 */

import { Hono } from "hono";
import type { SessionInput } from "../input/index.js";

interface SendInputPayload {
  session_id?: unknown;
  cwd?: unknown;
  tty?: unknown;
  text?: unknown;
  submit?: unknown;
}

const str = (v: unknown): string | undefined => (typeof v === "string" && v !== "" ? v : undefined);

export function inputRoutes(input: SessionInput): Hono {
  const app = new Hono();

  app.post("/admin/input/send", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as SendInputPayload;

    const sessionId = str(body.session_id);
    const cwd = str(body.cwd);
    const tty = str(body.tty);
    const text = typeof body.text === "string" ? body.text : "";
    const submit = body.submit === undefined ? true : Boolean(body.submit);

    if (!cwd && !sessionId) {
      return c.json({ error: "missing required field: session_id or cwd" }, 400);
    }
    if (text === "" && !submit) {
      return c.json({ error: "nothing to send: empty text and submit=false" }, 400);
    }

    const r = await input.deliver({ sessionId, cwd, tty }, text, submit);
    if (!r.ok) {
      return c.json({ error: r.error, adapter: r.adapter, details: r.details ?? null }, r.status);
    }
    return c.json({ ok: true, adapter: r.adapter, terminal_id: r.terminalId, matched: r.matched });
  });

  return app;
}
