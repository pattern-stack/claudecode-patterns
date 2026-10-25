import { describe, expect, test } from "bun:test";
import { type HerdrRun, herdrInput, inputBox } from "../herdr.js";

const RULE = "─".repeat(60);
const screen = (box: string) =>
  ["● Done.", "", RULE, `❯ ${box}`, RULE, "  ? for shortcuts"].join("\n");

const agents = [
  {
    pane_id: "w1:p1",
    agent: "claude",
    agent_status: "idle",
    cwd: "/repo",
    name: "lead",
    agent_session: { value: "sess-lead" },
  },
  {
    pane_id: "w1:p2",
    agent: "claude",
    agent_status: "idle",
    cwd: "/repo",
    agent_session: { value: "sess-lane" },
  },
  {
    pane_id: "w2:p1",
    agent: "claude",
    agent_status: "blocked",
    cwd: "/other",
    agent_session: { value: "sess-blocked" },
  },
];

/** A fake herdr: canned answers per subcommand, and a log of every call. */
function fakeHerdr(
  over: {
    screen?: string;
    prompt?: { ok: boolean; err?: string };
    list?: { ok: boolean; out?: string };
  } = {},
) {
  const calls: string[][] = [];
  const run: HerdrRun = async (args) => {
    calls.push(args);
    const [a, b] = args;
    if (a === "agent" && b === "list")
      return {
        ok: over.list?.ok ?? true,
        out: over.list?.out ?? JSON.stringify({ result: { agents } }),
        err: "no server",
      };
    if (a === "pane" && b === "read") return { ok: true, out: over.screen ?? screen(""), err: "" };
    if (a === "agent" && b === "prompt")
      return { ok: over.prompt?.ok ?? true, out: "", err: over.prompt?.err ?? "" };
    return { ok: true, out: "", err: "" };
  };
  return { run, calls };
}

describe("inputBox", () => {
  test("reads the text between the last two rules", () => {
    expect(inputBox(screen(""))).toBe("");
    expect(inputBox(screen("half a thought"))).toBe("half a thought");
  });
  test("null when no box is on screen", () => {
    expect(inputBox("just some output\nno rules here")).toBeNull();
  });
});

describe("herdrInput", () => {
  test("finds the pane by Claude session id and submits one bracketed paste, waiting for Claude to start", async () => {
    const { run, calls } = fakeHerdr();
    const r = await herdrInput(run).deliver(
      { sessionId: "sess-lane", cwd: "/repo" },
      "[voice] hello",
      true,
    );
    expect(r).toEqual({ ok: true, adapter: "herdr", terminalId: "w1:p2", matched: 1 });
    const prompt = calls.find((c) => c[1] === "prompt");
    expect(prompt).toEqual([
      "agent",
      "prompt",
      "w1:p2",
      "[voice] hello",
      "--wait",
      "--until",
      "working",
      "--until",
      "blocked",
      "--timeout",
      "15000",
    ]);
  });

  test("a session Herdr doesn't run is a 404, never a guess by cwd", async () => {
    const { run } = fakeHerdr();
    const r = await herdrInput(run).deliver({ sessionId: "sess-gone", cwd: "/repo" }, "hi", true);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.status).toBe(404);
  });

  test("by cwd alone, two agents in one folder are ambiguous (409 with candidates)", async () => {
    const { run } = fakeHerdr();
    const r = await herdrInput(run).deliver({ cwd: "/repo" }, "hi", true);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.status).toBe(409);
      expect((r.details as { candidates: unknown[] }).candidates).toHaveLength(2);
    }
  });

  test("refuses (423) while Claude waits on an approval, and types nothing", async () => {
    const { run, calls } = fakeHerdr();
    const r = await herdrInput(run).deliver({ sessionId: "sess-blocked" }, "yes", true);
    expect(r.ok).toBe(false);
    if (!r.ok)
      expect([r.status, (r.details as { reason: string }).reason]).toEqual([423, "blocked"]);
    expect(calls.some((c) => c[1] === "prompt")).toBe(false);
  });

  test("refuses (423) when the host has a draft in Claude's box", async () => {
    const { run, calls } = fakeHerdr({ screen: screen("my own half-typed message") });
    const r = await herdrInput(run).deliver({ sessionId: "sess-lead" }, "hi", true);
    expect(r.ok).toBe(false);
    if (!r.ok) expect((r.details as { reason: string }).reason).toBe("draft");
    expect(calls.some((c) => c[1] === "prompt")).toBe(false);
  });

  test("Claude's dim 'Try …' hint is not a draft", async () => {
    const { run } = fakeHerdr({ screen: screen('Try "refactor this file"') });
    const r = await herdrInput(run).deliver({ sessionId: "sess-lead" }, "hi", true);
    expect(r.ok).toBe(true);
  });

  test("strips control characters that could end the paste early; keeps newlines", async () => {
    const { run, calls } = fakeHerdr();
    await herdrInput(run).deliver({ sessionId: "sess-lead" }, "a\u001b[201~b\nc\u0007", true);
    expect(calls.find((c) => c[1] === "prompt")?.[3]).toBe("a[201~b\nc");
  });

  test("a stalled submit gets one Enter, then counts once Claude starts", async () => {
    const { run, calls } = fakeHerdr({ prompt: { ok: false, err: "agent_prompt_stalled" } });
    const r = await herdrInput(run).deliver({ sessionId: "sess-lead" }, "hi", true);
    expect(r.ok).toBe(true);
    expect(calls.map((c) => c.slice(0, 2).join(" "))).toContain("agent send-keys");
  });

  test("no Herdr here is a miss another adapter may take", async () => {
    const { run } = fakeHerdr({ list: { ok: false } });
    const r = await herdrInput(run).deliver({ sessionId: "sess-lead" }, "hi", true);
    expect(r.ok).toBe(false);
    if (!r.ok) expect([r.status, r.unavailable]).toEqual([404, true]);
  });
});
