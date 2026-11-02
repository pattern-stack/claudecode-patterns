/**
 * SessionInput adapter: ghostty-bridge, a local control plane that types into the matching Ghostty pane, keyed by
 * the session's working directory (or tty). Moved unchanged from routes/input.ts.
 *
 * Bridge base URL: env `GHOSTTY_BRIDGE_URL` (default http://127.0.0.1:4848).
 */

import type { SessionInput } from "./session-input.js";

export function ghosttyBridgeInput(
  baseUrl = "http://127.0.0.1:4848",
  fetchImpl: typeof fetch = fetch,
): SessionInput {
  const url = baseUrl.replace(/\/+$/, "");
  return {
    name: "ghostty",
    async deliver(target, text, submit) {
      if (!target.cwd) {
        return {
          ok: false,
          adapter: "ghostty",
          status: 404,
          error: "ghostty-bridge matches by cwd, and none was given",
        };
      }
      let res: Response;
      try {
        res = await fetchImpl(`${url}/api/v1/send-by-cwd`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ cwd: target.cwd, tty: target.tty, text, submit }),
        });
      } catch (err) {
        return {
          ok: false,
          adapter: "ghostty",
          status: 502,
          unavailable: true,
          error: "ghostty-bridge unreachable",
          details: {
            hint: `is it running at ${url}? (cd ~/ghostty-bridge && node server.js)`,
            detail: String(err instanceof Error ? err.message : err),
          },
        };
      }
      const payload = (await res.json().catch(() => ({}))) as Record<string, unknown>;
      if (!res.ok) {
        const error =
          res.status === 404
            ? "no live terminal found for this session's working directory"
            : typeof payload.error === "string"
              ? payload.error
              : `ghostty-bridge error (HTTP ${res.status})`;
        // 404 = no pane in this cwd, 409 = ambiguous: both carry meaning the UI shows verbatim. The rest is a failure.
        const status = res.status === 404 || res.status === 409 ? res.status : 502;
        // Ambiguous-match candidates ride along in details so the UI can let the user pick.
        return { ok: false, adapter: "ghostty", status, error, details: payload.details ?? null };
      }
      return {
        ok: true,
        adapter: "ghostty",
        terminalId: (payload.terminal_id as string | null | undefined) ?? null,
        matched: (payload.matched as number | null | undefined) ?? null,
      };
    },
  };
}
