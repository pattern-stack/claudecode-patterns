import { describe, expect, test } from "bun:test";
import { sessionInputFromEnv } from "../index.js";
import { type DeliverResult, firstMatch, type SessionInput } from "../session-input.js";

// Omit over each member of the union, not the union as a whole.
type Result = DeliverResult extends infer T
  ? T extends unknown
    ? Omit<T, "adapter">
    : never
  : never;

const fixed = (name: string, r: Result): SessionInput & { calls: number } => {
  const a = {
    name,
    calls: 0,
    async deliver() {
      a.calls++;
      return { adapter: name, ...r } as DeliverResult;
    },
  };
  return a;
};

describe("firstMatch", () => {
  test("a miss or a backend that isn't running falls through to the next adapter", async () => {
    const herdr = fixed("herdr", { ok: false, status: 404, error: "no pane", unavailable: true });
    const ghostty = fixed("ghostty", { ok: true, terminalId: "t1", matched: 1 });
    const r = await firstMatch([herdr, ghostty]).deliver({ cwd: "/x" }, "hi", true);
    expect(r).toMatchObject({ ok: true, adapter: "ghostty" });
  });

  test("the first adapter that finds the session decides, even when it refuses", async () => {
    const herdr = fixed("herdr", { ok: false, status: 423, error: "draft" });
    const ghostty = fixed("ghostty", { ok: true, terminalId: "t1", matched: 1 });
    const r = await firstMatch([herdr, ghostty]).deliver({ sessionId: "s" }, "hi", true);
    expect(r).toMatchObject({ ok: false, status: 423, adapter: "herdr" });
    expect(ghostty.calls).toBe(0);
  });

  test("when nobody matches, a plain miss beats 'not running'", async () => {
    const herdr = fixed("herdr", {
      ok: false,
      status: 404,
      error: "no Herdr pane is running this session",
    });
    const ghostty = fixed("ghostty", {
      ok: false,
      status: 502,
      error: "ghostty-bridge unreachable",
      unavailable: true,
    });
    const r = await firstMatch([herdr, ghostty]).deliver({ sessionId: "s" }, "hi", true);
    expect(r).toMatchObject({ ok: false, adapter: "herdr", status: 404 });
  });
});

describe("sessionInputFromEnv", () => {
  test("defaults to herdr, then ghostty", () => {
    expect(sessionInputFromEnv({}).name).toBe("herdr+ghostty");
  });
  test("one adapter by name", () => {
    expect(sessionInputFromEnv({ CC_VIEWER_INPUT: "ghostty" }).name).toBe("ghostty");
  });
  test("an unknown adapter is a startup error, not a silent default", () => {
    expect(() => sessionInputFromEnv({ CC_VIEWER_INPUT: "herdr,tmux" })).toThrow(
      /unknown adapter "tmux"/,
    );
  });
});
