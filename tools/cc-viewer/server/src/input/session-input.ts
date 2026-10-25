/**
 * Port: send text into the live terminal that hosts a Claude Code session.
 *
 * `POST /admin/input/send` (routes/input.ts) is this port's HTTP projection. The chat composer and the voice page
 * both reach a session through it; adapters decide how the text gets there:
 *   - ghostty-bridge (by cwd, or tty) — input/ghostty-bridge.ts
 *   - herdr (by Claude session id)    — input/herdr.ts
 * input/index.ts binds the configured adapters once, at the composition root.
 */

export interface InputTarget {
  /** Claude Code session id: the identity on every hook and transcript event. Adapters that can match it should. */
  readonly sessionId?: string;
  /** The session's working directory (ghostty-bridge matches on it). */
  readonly cwd?: string;
  /** Terminal device, to tell two panes in one cwd apart (ghostty-bridge). */
  readonly tty?: string;
}

/**
 * 404 no live terminal for this target · 409 more than one matches · 423 found, but not ready for input (a draft in
 * the box, an approval prompt) · 502 the adapter failed.
 */
export type InputStatus = 404 | 409 | 423 | 502;

export type DeliverResult =
  | {
      readonly ok: true;
      readonly adapter: string;
      readonly terminalId: string | null;
      readonly matched: number | null;
    }
  | {
      readonly ok: false;
      readonly adapter: string;
      readonly status: InputStatus;
      readonly error: string;
      readonly details?: unknown;
      /** The adapter's backend isn't running here at all (no ghostty-bridge, no Herdr), so another adapter may try. */
      readonly unavailable?: boolean;
    };

export interface SessionInput {
  readonly name: string;
  deliver(target: InputTarget, text: string, submit: boolean): Promise<DeliverResult>;
}

/**
 * Try adapters in order. The first one that finds the target decides (success, ambiguity, refusal or failure);
 * "not found here" and "not running here" fall through to the next.
 */
export function firstMatch(adapters: readonly SessionInput[]): SessionInput {
  return {
    name: adapters.map((a) => a.name).join("+"),
    async deliver(target, text, submit) {
      const misses: DeliverResult[] = [];
      for (const adapter of adapters) {
        const r = await adapter.deliver(target, text, submit);
        if (r.ok || (r.status !== 404 && !r.unavailable)) return r;
        misses.push(r);
      }
      // Nothing matched: report a plain miss before a "not running" one, since it says more.
      return (
        misses.find((m) => !m.ok && !m.unavailable) ??
        misses[0] ?? {
          ok: false,
          adapter: "none",
          status: 404,
          error: "no input adapter is configured",
        }
      );
    },
  };
}
