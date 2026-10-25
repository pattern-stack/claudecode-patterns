import { describe, expect, test } from "bun:test";
import type { InputTarget, SessionInput } from "../../input/index.js";
import { inputRoutes } from "../input.js";

function recorder(result: Awaited<ReturnType<SessionInput["deliver"]>>) {
  const seen: { target: InputTarget; text: string; submit: boolean }[] = [];
  const input: SessionInput = {
    name: "fake",
    async deliver(target, text, submit) {
      seen.push({ target, text, submit });
      return result;
    },
  };
  return { input, seen };
}

const post = (app: ReturnType<typeof inputRoutes>, body: unknown) =>
  app.request("/admin/input/send", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

describe("POST /admin/input/send", () => {
  test("passes the session id through to the port", async () => {
    const { input, seen } = recorder({
      ok: true,
      adapter: "fake",
      terminalId: "w1:p1",
      matched: 1,
    });
    const res = await post(inputRoutes(input), { session_id: "s1", cwd: "/repo", text: "hi" });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      ok: true,
      adapter: "fake",
      terminal_id: "w1:p1",
      matched: 1,
    });
    expect(seen[0]).toEqual({
      target: { sessionId: "s1", cwd: "/repo", tty: undefined },
      text: "hi",
      submit: true,
    });
  });

  test("a session id alone is enough (no cwd)", async () => {
    const { input } = recorder({ ok: true, adapter: "fake", terminalId: null, matched: null });
    expect((await post(inputRoutes(input), { session_id: "s1", text: "hi" })).status).toBe(200);
  });

  test("400 without a session id or a cwd", async () => {
    const { input, seen } = recorder({
      ok: true,
      adapter: "fake",
      terminalId: null,
      matched: null,
    });
    expect((await post(inputRoutes(input), { text: "hi" })).status).toBe(400);
    expect(seen).toHaveLength(0);
  });

  test("an adapter's refusal keeps its status and details", async () => {
    const { input } = recorder({
      ok: false,
      adapter: "fake",
      status: 423,
      error: "draft in the box",
      details: { reason: "draft" },
    });
    const res = await post(inputRoutes(input), { session_id: "s1", text: "hi" });
    expect(res.status).toBe(423);
    expect(await res.json()).toEqual({
      error: "draft in the box",
      adapter: "fake",
      details: { reason: "draft" },
    });
  });
});
