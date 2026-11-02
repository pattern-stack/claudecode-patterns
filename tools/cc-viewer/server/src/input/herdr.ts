/**
 * SessionInput adapter: Herdr, the terminal multiplexer Claude Code runs in.
 *
 * Finds the pane by the Claude session id Herdr records for each agent (`herdr agent list` → `agent_session.value`),
 * so a reply follows its session when the pane moves and never lands on whatever runs in a pane after the session
 * ends. Without a session id it matches on cwd, and more than one agent there is a 409 with the candidates.
 *
 * Before typing it checks the pane is ready: not blocked on an approval or question, and (for Claude Code) an empty
 * input box, so a draft on the host is never merged into the text. The text goes in as one bracketed paste
 * (`herdr agent prompt`): raw keystrokes lost the start of long text (2026-10-25: 1,147 characters sent, ~150
 * arrived). `--wait` confirms Claude started; a prompt left unsubmitted gets one Enter.
 * A long paste reaches Claude intact but framed: Claude Code wraps it as `<pasted_content id=…>…</pasted_content>`
 * (seen 2026-11-01: 2,064 characters sent, the same 2,064 inside the tags). Short replies arrive bare. The
 * model then reads a long reply as pasted material rather than the user's own words; the `[voice] ` prefix sits
 * inside the tags.
 *
 * Moved from the voice relay (~/.claude/skills/final-answer/web/server.ts, `paneInfo` / `inputBox` / `sendReply`).
 */

import type { DeliverResult, SessionInput } from "./session-input.js";

export type HerdrRun = (args: string[]) => Promise<{ ok: boolean; out: string; err: string }>;

interface HerdrAgent {
  pane_id: string;
  agent?: string;
  agent_status?: string;
  cwd?: string;
  name?: string;
  agent_session?: { value?: string };
}

export function spawnHerdr(bin = "herdr"): HerdrRun {
  return async (args) => {
    try {
      const p = Bun.spawn([bin, ...args], { stdout: "pipe", stderr: "pipe" });
      const [out, err] = await Promise.all([
        new Response(p.stdout).text(),
        new Response(p.stderr).text(),
      ]);
      return { ok: (await p.exited) === 0, out, err };
    } catch (e) {
      return { ok: false, out: "", err: `can't run ${bin}: ${(e as Error).message}` };
    }
  };
}

// Claude Code's input box sits between the last two horizontal rules on screen. Its text, "" when empty, or null
// when no box is visible (a menu or dialog is open, or the pane is scrolled up).
const RULE = /^\s*─{20,}\s*$/;
export function inputBox(screen: string): string | null {
  const lines = screen.split("\n");
  const rules = lines.map((l, i) => (RULE.test(l) ? i : -1)).filter((i) => i >= 0);
  if (rules.length < 2) return null;
  const [a, b] = rules.slice(-2) as [number, number];
  return lines
    .slice(a + 1, b)
    .join("\n")
    .replace(/^\s*[❯>]/, "")
    .trim();
}
const PLACEHOLDER = /^Try "/; // Claude Code's dim hint in an empty box on a fresh session

// Control characters could end the bracketed paste early or drive the terminal; newlines and tabs are text.
// biome-ignore lint/suspicious/noControlCharactersInRegex: removing control characters is the point
const CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g;

export function herdrInput(run: HerdrRun = spawnHerdr()): SessionInput {
  const fail = (
    status: 404 | 409 | 423 | 502,
    error: string,
    extra: Partial<DeliverResult> = {},
  ): DeliverResult => ({ ok: false, adapter: "herdr", status, error, ...extra }) as DeliverResult;

  return {
    name: "herdr",
    async deliver(target, rawText, submit) {
      const list = await run(["agent", "list"]);
      if (!list.ok)
        return fail(404, "Herdr isn't running here", {
          unavailable: true,
          details: list.err.trim().slice(0, 200),
        });
      let agents: HerdrAgent[];
      try {
        const parsed = JSON.parse(list.out) as { result?: { agents?: HerdrAgent[] } };
        agents = parsed.result?.agents ?? [];
      } catch {
        return fail(502, "couldn't read `herdr agent list`");
      }

      // The session id is the identity. Only without one does cwd stand in, and then it must be unambiguous.
      const matches = target.sessionId
        ? agents.filter((a) => a.agent_session?.value === target.sessionId)
        : target.cwd
          ? agents.filter((a) => a.cwd === target.cwd)
          : [];
      if (matches.length === 0) {
        return fail(
          404,
          target.sessionId
            ? "no Herdr pane is running this session"
            : "no Herdr agent in this working directory",
        );
      }
      if (matches.length > 1) {
        return fail(409, "more than one Herdr agent matches", {
          details: {
            candidates: matches.map((a) => ({
              pane_id: a.pane_id,
              name: a.name ?? null,
              status: a.agent_status ?? null,
            })),
          },
        });
      }
      const agent = matches[0] as HerdrAgent;
      const pane = agent.pane_id;

      if (agent.agent_status === "blocked") {
        return fail(
          423,
          "Claude is waiting on a question or approval in that pane. Answer it there first.",
          { details: { reason: "blocked", pane } },
        );
      }
      if (agent.agent === "claude") {
        const read = await run(["pane", "read", pane, "--source", "visible"]);
        const box = read.ok ? inputBox(read.out) : null;
        if (box === null) {
          return fail(
            423,
            "Can't see Claude's input box (scrolled up, or a menu is open). Nothing was typed.",
            { details: { reason: "no_input_box", pane } },
          );
        }
        if (box && !PLACEHOLDER.test(box)) {
          return fail(
            423,
            `There's a draft in Claude's input box ("${box.slice(0, 60)}"). Nothing was typed; send or clear it, then retry.`,
            {
              details: { reason: "draft", pane },
            },
          );
        }
      }

      const text = rawText.replace(CONTROL, "");
      if (!submit) {
        const t = await run(["pane", "send-text", pane, text]);
        return t.ok
          ? { ok: true, adapter: "herdr", terminalId: pane, matched: 1 }
          : fail(502, `typing into ${pane} failed: ${t.err.trim().slice(0, 160)}`);
      }

      const waitArgs = ["--wait", "--until", "working", "--until", "blocked", "--timeout", "15000"];
      // Pane and text first, options after: herdr reads the text positionally (a leading "-" stays text) and has no
      // `--` separator (checked 2026-10-25, herdr 0.9.5).
      const p = await run(["agent", "prompt", pane, text, ...waitArgs]);
      if (p.ok) return { ok: true, adapter: "herdr", terminalId: pane, matched: 1 };
      if (/stalled/i.test(p.err + p.out)) {
        // Typed but not submitted: Claude's input loop missed the Enter. Press it once, then confirm it started.
        const enter = await run(["agent", "send-keys", pane, "enter"]);
        const again = enter.ok
          ? await run([
              "agent",
              "wait",
              pane,
              "--until",
              "working",
              "--until",
              "blocked",
              "--timeout",
              "5000",
            ])
          : enter;
        if (again.ok) return { ok: true, adapter: "herdr", terminalId: pane, matched: 1 };
        return fail(
          502,
          "The text is in Claude's box but Claude didn't start. Press Enter there.",
          { details: { reason: "stalled", pane } },
        );
      }
      return fail(502, `sending to ${pane} failed: ${(p.err || p.out).trim().slice(0, 160)}`);
    },
  };
}
