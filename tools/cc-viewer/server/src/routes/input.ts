/**
 * Terminal input proxy.
 *
 * The viewer is read-only over Claude Code transcripts; this route lets the
 * chat surface send a message *back into* the live terminal session it is
 * watching. It forwards to ghostty-bridge (a local control-plane that types
 * into the matching Ghostty pane), keyed by the session's working directory.
 *
 * Server-to-server (no browser CORS): the SPA calls same-origin
 * `POST /admin/input/send`, we call the bridge's `/api/v1/send-by-cwd`.
 *
 * Bridge base URL: env `GHOSTTY_BRIDGE_URL` (default http://127.0.0.1:4848).
 */

import { Hono } from "hono";

const BRIDGE_URL = (process.env.GHOSTTY_BRIDGE_URL ?? "http://127.0.0.1:4848").replace(/\/+$/, "");

interface SendInputPayload {
  cwd?: unknown;
  tty?: unknown;
  text?: unknown;
  submit?: unknown;
}

// HTTP statuses we pass straight through from the bridge (they carry meaning
// the UI should show verbatim): 404 = no pane in this cwd, 409 = ambiguous.
const PASSTHROUGH = new Set([404, 409]);

export function inputRoutes(): Hono {
  const app = new Hono();

  app.post("/admin/input/send", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as SendInputPayload;

    const cwd = typeof body.cwd === "string" ? body.cwd : undefined;
    const tty = typeof body.tty === "string" ? body.tty : undefined;
    const text = typeof body.text === "string" ? body.text : "";
    const submit = body.submit === undefined ? true : Boolean(body.submit);

    if (!cwd) {
      return c.json({ error: "missing required field: cwd" }, 400);
    }
    if (text === "" && !submit) {
      return c.json({ error: "nothing to send: empty text and submit=false" }, 400);
    }

    let res: Response;
    try {
      res = await fetch(`${BRIDGE_URL}/api/v1/send-by-cwd`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ cwd, tty, text, submit }),
      });
    } catch (err) {
      // Bridge down / unreachable.
      return c.json(
        {
          error: "ghostty-bridge unreachable",
          hint: `is it running at ${BRIDGE_URL}? (cd ~/ghostty-bridge && node server.js)`,
          detail: String(err instanceof Error ? err.message : err),
        },
        502,
      );
    }

    const payload = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok) {
      const message =
        res.status === 404
          ? "no live terminal found for this session's working directory"
          : typeof payload.error === "string"
            ? payload.error
            : `ghostty-bridge error (HTTP ${res.status})`;
      const status = (PASSTHROUGH.has(res.status) ? res.status : 502) as 404 | 409 | 502;
      // Forward structured details (e.g. ambiguous-match candidates) so the
      // UI can let the user pick.
      return c.json({ error: message, bridge_status: res.status, details: payload.details ?? null }, status);
    }

    return c.json({
      ok: true,
      terminal_id: payload.terminal_id ?? null,
      matched: payload.matched ?? null,
    });
  });

  return app;
}
