/**
 * Pairing routes (see pairing.ts and middleware/device-auth.ts).
 *
 *   GET  /pair        a small page: enter a code (unpaired), or show one for another device (host / paired)
 *   POST /pair/new    host or paired device only → { code, minutes }
 *   POST /pair/claim  { code } → sets the key cookie and returns { key } once (for scripts and other machines)
 *
 * Both POSTs require a JSON body, so a cross-site form can't send them without a CORS preflight.
 */

import { Hono } from "hono";
import { setCookie } from "hono/cookie";
import { isLocal, isPaired, KEY_COOKIE } from "../middleware/device-auth.js";
import type { Pairing } from "../pairing.js";

const COOKIE_MAX_AGE = 400 * 24 * 60 * 60; // browsers cap cookie lifetime at 400 days

const page = (trusted: boolean) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pair device · cc-viewer</title>
<style>
  :root { color-scheme: light dark; --bg: #f6f7f9; --card: #fff; --ink: #17202a; --muted: #5b6672; --line: #d9dee4; --accent: #0b6a82; --bad: #b3261e; }
  @media (prefers-color-scheme: dark) { :root { --bg: #0f1418; --card: #171e24; --ink: #e6ebef; --muted: #9aa6b1; --line: #2a343d; --accent: #4fb3cc; --bad: #f2867f; } }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 system-ui, sans-serif; }
  main { max-width: 420px; margin: 12vh auto; padding: 24px 16px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 22px; }
  h1 { font-size: 20px; margin: 0 0 6px; } p { color: var(--muted); margin: 0 0 16px; }
  input { font: 600 22px ui-monospace, monospace; letter-spacing: .2em; width: 8.5em; padding: 8px 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--ink); }
  button { font: inherit; font-weight: 600; padding: 9px 16px; border-radius: 8px; border: 1px solid var(--accent); background: var(--accent); color: #fff; cursor: pointer; }
  .code { font: 700 32px ui-monospace, monospace; letter-spacing: .2em; color: var(--accent); }
  #msg { display: block; margin-top: 12px; min-height: 1.5em; } .bad { color: var(--bad); }
</style></head><body><main><div class="card">
${
  trusted
    ? `<h1>Pair another device</h1>
<p>Get a one-time code here, then type it on the new device at <b>/pair</b>. It works once, for 10 minutes.</p>
<button id="new">Get a code</button><span id="msg"></span>
<script>
document.getElementById("new").onclick = async () => {
  const msg = document.getElementById("msg");
  const r = await fetch("/pair/new", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
  const j = await r.json().catch(() => ({}));
  if (r.ok) { msg.className = ""; msg.innerHTML = 'Code <span class="code"></span> for ' + j.minutes + " min, one use"; msg.querySelector(".code").textContent = j.code; }
  else { msg.className = "bad"; msg.textContent = j.error || "Couldn't get a code (" + r.status + ")."; }
};
</script>`
    : `<h1>Pair this device</h1>
<p>On a device that already has the dashboard (or on the host), open <b>/pair</b> and get a code, then type it here.</p>
<form id="f"><input id="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000" aria-label="Pairing code"> <button>Pair</button></form>
<span id="msg"></span>
<script>
document.getElementById("f").onsubmit = async (e) => {
  e.preventDefault();
  const msg = document.getElementById("msg");
  const r = await fetch("/pair/claim", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code: document.getElementById("code").value }) });
  const j = await r.json().catch(() => ({}));
  if (r.ok) { msg.className = ""; msg.textContent = "Paired. Opening the dashboard…"; location.href = "/"; }
  else { msg.className = "bad"; msg.textContent = j.error || "That didn't work (" + r.status + ")."; }
};
</script>`
}
</div></main></body></html>`;

export function pairRoutes(pairing: Pairing): Hono {
  const app = new Hono();
  const jsonOnly = (type: string | undefined) => (type ?? "").toLowerCase().startsWith("application/json");

  app.get("/pair", (c) => c.html(page(isLocal(c) || isPaired(c, pairing))));

  app.post("/pair/new", (c) => {
    if (!jsonOnly(c.req.header("content-type"))) return c.json({ error: "send JSON" }, 415);
    if (!isLocal(c) && !isPaired(c, pairing)) return c.json({ error: "only the host or a paired device can make a code" }, 403);
    return c.json({ ok: true, ...pairing.newCode() });
  });

  app.post("/pair/claim", async (c) => {
    if (!jsonOnly(c.req.header("content-type"))) return c.json({ error: "send JSON" }, 415);
    const body = (await c.req.json().catch(() => ({}))) as { code?: unknown };
    const code = typeof body.code === "string" ? body.code : "";
    if (!pairing.claim(code)) {
      return c.json({ ok: false, error: "That code is wrong or has expired. Get a new one on a paired device." }, 403);
    }
    setCookie(c, KEY_COOKIE, pairing.key, { httpOnly: true, sameSite: "Strict", path: "/", maxAge: COOKIE_MAX_AGE });
    return c.json({ ok: true, key: pairing.key });
  });

  return app;
}
