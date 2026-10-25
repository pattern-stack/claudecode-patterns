import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { createServer } from "../../app.js";
import type { SessionInput } from "../../input/index.js";
import { Pairing } from "../../pairing.js";
import { SSEBroadcaster } from "../../sse-broadcaster.js";
import { VoiceService } from "../../voice/index.js";

const dir = mkdtempSync(path.join(tmpdir(), "voice-routes-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const input: SessionInput = {
  name: "fake",
  deliver: async () => ({ ok: true, adapter: "fake", terminalId: "w1:p1", matched: 1 }),
};
const pairing = new Pairing(dir);
const voice = new VoiceService({
  stateDir: path.join(dir, "voice"),
  input,
  sessions: {
    sessions: () => [{ sessionId: "sess-1", cwd: "/p", lastSeen: "2026-10-25T23:00:00.000Z" }],
  },
  profile: { model: "m", voice: "v", instructions: "i" },
});
const app = createServer({ broadcaster: new SSEBroadcaster(), pairing, input, voice });

// app.request() has no socket, so these requests are never "this machine": they show the network view.
const reply = (headers: Record<string, string> = {}) =>
  app.request("/admin/voice/reply", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ text: "hi", replyId: crypto.randomUUID() }),
  });

describe("voice routes sit behind the device check", () => {
  test("an unpaired device gets 401 and the page sends it to /pair", async () => {
    expect((await reply()).status).toBe(401);
    const page = await app.request("/voice", { headers: { accept: "text/html" } });
    expect([page.status, page.headers.get("location")]).toEqual([302, "/pair"]);
  });

  test("a paired device gets the page and can reply", async () => {
    const page = await app.request("/voice", { headers: { "x-viewer-key": pairing.key } });
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("/admin/voice/events");
    voice.setLink("sess-1");
    const res = await reply({ "x-viewer-key": pairing.key });
    expect(await res.json()).toMatchObject({ ok: true, adapter: "fake" });
  });

  test("another site can't post a reply even with a paired browser's cookie", async () => {
    const res = await reply({ cookie: `ccv_key=${pairing.key}`, origin: "https://evil.example" });
    expect(res.status).toBe(403);
  });
});
