/**
 * The voice page and its API: the HTTP projection of VoiceService (voice/voice-service.ts). Behind the app-wide
 * device check like every other route: this machine, or a paired device.
 *
 *   GET  /voice                     the page
 *   GET  /admin/voice/events        SSE for one page: hello, primary, answer, reply, history, link, status, settings, reload
 *   POST /admin/voice/claim         { client } → this page plays and listens
 *   GET  /admin/voice/audio/:id     an answer's mp3 (made on first request)
 *   GET  /admin/voice/ack           "Got it." in the answer voice
 *   POST /admin/voice/transcribe    audio body → { ok, text, model } | { ok: false, reason }
 *   POST /admin/voice/reply         { text, replyId } → typed into the linked session (SessionInput port)
 *   GET  /admin/voice/sessions      sessions the dashboard knows (the only link targets)
 *   POST /admin/voice/link          { session_id } → link the page to that session
 *   GET|POST /admin/voice/settings  the page's listening settings
 *   GET  /admin/voice/status        { pages, link, status }
 *   POST /admin/voice/reload        reload every open page
 */

import { Hono } from "hono";
import type { VoiceService } from "../voice/index.js";
// With `type: "text"` Bun inlines the file as a string (and embeds it in the compiled binary); Bun's own typings
// describe .html imports as HTML bundles, hence the cast.
import pageFile from "../voice/page.html" with { type: "text" };

const pageHtml = pageFile as unknown as string;

const NO_STORE = { "Cache-Control": "no-store" };

const extFor = (type: string) =>
  type.includes("ogg")
    ? "ogg"
    : type.includes("mp4") || type.includes("m4a")
      ? "mp4"
      : type.includes("wav")
        ? "wav"
        : type.includes("mpeg")
          ? "mp3"
          : "webm";

export function voiceRoutes(voice: VoiceService): Hono {
  const app = new Hono();

  app.get("/voice", (c) => c.html(pageHtml, 200, NO_STORE));

  app.get("/admin/voice/events", (c) => {
    const { stream, close } = voice.connect(c.req.query("client"));
    c.req.raw.signal.addEventListener("abort", close);
    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  });

  app.post("/admin/voice/claim", async (c) => {
    const { client } = (await c.req.json().catch(() => ({}))) as { client?: string };
    return c.json({ primary: voice.claim(String(client ?? "")) });
  });

  app.get("/admin/voice/audio/:id", async (c) => {
    const mp3 = await voice.audio(Number.parseInt(c.req.param("id"), 10));
    return mp3
      ? c.body(new Uint8Array(mp3), 200, { "Content-Type": "audio/mpeg", ...NO_STORE })
      : c.json({ error: "no audio for that answer" }, 404);
  });

  app.get("/admin/voice/ack", async (c) => {
    const mp3 = await voice.ack();
    return mp3
      ? c.body(new Uint8Array(mp3), 200, { "Content-Type": "audio/mpeg" })
      : c.json({ error: "no clip" }, 404);
  });

  app.post("/admin/voice/transcribe", async (c) => {
    const type = c.req.header("content-type") ?? "audio/webm";
    const audio = await c.req.blob();
    if (audio.size > 20_000_000) return c.json({ ok: false, reason: "recording too long" }, 413);
    return c.json(await voice.transcribe(new Blob([audio], { type }), extFor(type)));
  });

  app.post("/admin/voice/reply", async (c) => {
    const { text, replyId } = (await c.req.json().catch(() => ({}))) as {
      text?: unknown;
      replyId?: unknown;
    };
    const id = typeof replyId === "string" && replyId ? replyId : crypto.randomUUID();
    return c.json(await voice.takeReply(String(text ?? ""), id));
  });

  app.get("/admin/voice/sessions", (c) => c.json({ sessions: voice.sessionChoices() }));

  app.post("/admin/voice/link", async (c) => {
    const { session_id } = (await c.req.json().catch(() => ({}))) as { session_id?: unknown };
    const r = voice.setLink(String(session_id ?? ""));
    return r.ok ? c.json(r) : c.json(r, 404);
  });

  app.get("/admin/voice/settings", (c) => c.json(voice.getSettings()));
  app.post("/admin/voice/settings", async (c) => {
    const r = voice.updateSettings(
      (await c.req.json().catch(() => ({}))) as Record<string, unknown>,
    );
    return r.ok ? c.json(r) : c.json(r, 400);
  });

  app.get("/admin/voice/status", (c) => c.json({ pages: voice.pageCount, ...voice.linkView() }));
  app.post("/admin/voice/reload", (c) => c.json({ ok: true, pages: voice.reloadPages() }));

  return app;
}
