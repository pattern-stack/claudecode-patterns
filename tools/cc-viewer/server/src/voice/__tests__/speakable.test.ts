import { describe, expect, test } from "bun:test";
import { speakable } from "../speakable.js";

describe("speakable", () => {
  test("drops markup, code and link targets", () => {
    const md =
      "## Done\n\n- **Fixed** the `parser`\n- See [the PR](https://github.com/x/y/pull/1)\n\n```ts\nconst a = 1;\n```\nMore at https://example.com.";
    expect(speakable(md)).toBe(
      "Done\nFixed the parser\nSee the PR\n(code on screen)\nMore at a link",
    );
  });

  test("tables are left for the screen", () => {
    expect(speakable("Results:\n| a | b |\n|---|---|\n| 1 | 2 |\nThat's it.")).toBe(
      "Results:\nThat's it.",
    );
  });

  test("long answers stop at a sentence end and say the rest is on screen", () => {
    const s = speakable("One sentence here. ".repeat(100), 200);
    expect(s.length).toBeLessThan(240);
    expect(s.endsWith("here. The rest is on screen.")).toBe(true);
  });
});
