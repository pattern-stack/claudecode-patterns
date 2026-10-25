import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { InputTarget, SessionInput } from "../../input/index.js";
import { SSEBroadcaster } from "../../sse-broadcaster.js";
import type { SpeechSynthesizer } from "../speech.js";
import { VoiceService } from "../voice-service.js";

const profile = { model: "m", voice: "v", instructions: "i" };
const sessions = {
  sessions: () => [
    { sessionId: "sess-1", cwd: "/Users/x/proj", lastSeen: "2026-10-25T23:00:00.000Z" },
    { sessionId: "sess-2", cwd: "/Users/x/other", lastSeen: "2026-10-25T22:00:00.000Z" },
  ],
};
const stop = (sessionId: string, text: unknown) => ({
  type: "claude_code.hook",
  hookName: "Stop",
  sessionId,
  payload: { session_id: sessionId, last_assistant_message: text },
});

let dir: string;
let sent: { target: InputTarget; text: string }[];
let input: SessionInput;
let synthCalls: string[];
const synth: SpeechSynthesizer = {
  name: "fake",
  async synth(text) {
    synthCalls.push(text);
    return { ok: true, mp3: new Uint8Array([1, 2, 3]) };
  },
};

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "voice-"));
  sent = [];
  synthCalls = [];
  input = {
    name: "fake",
    async deliver(target, text) {
      sent.push({ target, text });
      return { ok: true, adapter: "fake", terminalId: "w1:p1", matched: 1 };
    },
  };
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const make = (over: Partial<ConstructorParameters<typeof VoiceService>[0]> = {}) =>
  new VoiceService({ stateDir: dir, input, sessions, synth, profile, ...over });

describe("the link", () => {
  test("only sessions the dashboard knows can be linked", () => {
    const v = make();
    expect(v.setLink("made-up").ok).toBe(false);
    const r = v.setLink("sess-1");
    expect(r.ok && r.link).toMatchObject({
      sessionId: "sess-1",
      cwd: "/Users/x/proj",
      label: "proj · sess-1",
    });
  });

  test("survives a restart", () => {
    make().setLink("sess-2");
    expect(make().linkView().link?.sessionId).toBe("sess-2");
  });
});

describe("answers, from the viewer's event stream", () => {
  test("a Stop hook of the linked session becomes an answer; other sessions are ignored", () => {
    const bus = new SSEBroadcaster();
    const v = make();
    bus.subscribe(v.onViewerEvent);
    v.setLink("sess-1");
    bus.broadcast("claude_code.hook", stop("sess-2", "not for us"));
    bus.broadcast("claude_code.hook", stop("sess-1", "All **done**. Want me to push it?"));
    const { stream } = v.connect("page");
    return new Response(stream).body
      ?.getReader()
      .read()
      .then(({ value }) => {
        const hello = JSON.parse(new TextDecoder().decode(value).split("data: ")[1] as string);
        expect(hello.history).toHaveLength(1);
        expect(hello.history[0]).toMatchObject({
          kind: "answer",
          text: "All **done**. Want me to push it?",
          speech: "All done. Want me to push it?",
          audio: true,
        });
      });
  });

  test("audio is made on first request, once, and kept", async () => {
    const v = make();
    v.setLink("sess-1");
    const a = v.announce("Hello there.");
    const [x, y] = await Promise.all([v.audio(a?.id ?? 0), v.audio(a?.id ?? 0)]);
    expect(x).toEqual(new Uint8Array([1, 2, 3]));
    expect(y).toEqual(x);
    expect(synthCalls).toEqual(["Hello there."]);
    expect(existsSync(path.join(dir, "audio", `${a?.id}.mp3`))).toBe(true);
  });

  test("without a synthesizer an answer is text only (the page uses the browser voice)", () => {
    const v = make({ synth: undefined });
    v.setLink("sess-1");
    expect(v.announce("Hi")?.audio).toBe(false);
  });
});

describe("replies, through the input port", () => {
  test("go to the linked session by id, with the prefix, on one line", async () => {
    const v = make();
    v.setLink("sess-1");
    const r = await v.takeReply("yes,\n push it", "r1");
    expect(r.ok).toBe(true);
    expect(sent).toEqual([
      { target: { sessionId: "sess-1", cwd: "/Users/x/proj" }, text: "[voice] yes, push it" },
    ]);
  });

  test("a retried replyId is sent once", async () => {
    const v = make();
    v.setLink("sess-1");
    await v.takeReply("hello", "r1");
    expect(await v.takeReply("hello", "r1")).toEqual({ ok: true, duplicate: true });
    expect(sent).toHaveLength(1);
  });

  test("the prefix can't be cleared, so a transcript can't start a shell or slash command", async () => {
    const v = make({ replyPrefix: "   " });
    v.setLink("sess-1");
    await v.takeReply("!rm -rf ~", "r1");
    expect(sent[0]?.text).toBe("[voice] !rm -rf ~");
  });

  test("a long reply arrives whole (up to 4,000 characters)", async () => {
    const v = make();
    v.setLink("sess-1");
    const long = "word ".repeat(260).trim(); // 1,299 characters
    await v.takeReply(long, "r1");
    expect(sent[0]?.text).toBe(`[voice] ${long}`);
  });

  test("no link, no send", async () => {
    const r = await make().takeReply("hello", "r1");
    expect(r).toMatchObject({ ok: false });
    expect(sent).toHaveLength(0);
  });

  test("the port's refusal comes back as the reason", async () => {
    input = {
      name: "fake",
      deliver: async () => ({
        ok: false,
        adapter: "fake",
        status: 423,
        error: "There's a draft in Claude's input box",
      }),
    };
    const v = make();
    v.setLink("sess-1");
    expect(await v.takeReply("hello", "r1")).toEqual({
      ok: false,
      reason: "There's a draft in Claude's input box",
      status: 423,
    });
  });
});

describe("settings", () => {
  test("numbers must be zero or more; booleans are booleans", () => {
    const v = make();
    expect(v.updateSettings({ countdownMs: -1 }).ok).toBe(false);
    expect(v.updateSettings({ countdownMs: 1500, liveCaptions: 0 })).toMatchObject({
      ok: true,
      settings: { countdownMs: 1500, liveCaptions: false },
    });
  });
});
