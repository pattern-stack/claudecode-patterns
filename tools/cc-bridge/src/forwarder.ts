/**
 * HTTP client that pushes one transcript delta to cc-viewer.
 *
 * Fire-and-tolerate semantics: a failed POST logs a warning and resolves;
 * never throws back into the tailer loop. Telemetry is not allowed to
 * crash the daemon. cc-viewer's `(session_id, line_uuid)` dedupe means
 * retrying on the next watch event is safe.
 */

export interface TranscriptDelta {
  readonly session_id: string;
  readonly line_uuid: string;
  readonly line_index: number;
  readonly transcript_path: string;
  readonly timestamp: string;
  readonly entry: Record<string, unknown>;
  /** Set on teammate ("subagent") transcripts so the viewer can attribute the
   *  line to a nested session distinct from — but parented by — the lead. */
  readonly parent_session_id?: string;
  readonly agent_id?: string;
}

export class Forwarder {
  constructor(
    private readonly ccViewerUrl: string,
    private readonly timeoutMs: number,
  ) {}

  async send(delta: TranscriptDelta): Promise<boolean> {
    return this.post("TranscriptDelta", delta, `${delta.session_id}/${delta.line_index}`);
  }

  /**
   * POST a synthetic hook frame (e.g. a `SessionStart` we mint for a teammate
   * session that emits no hooks of its own). Same fire-and-tolerate contract as
   * {@link send}. cc-viewer stores it under `body.session_id` and broadcasts it
   * as a `claude_code.hook`, which is how a teammate becomes a first-class
   * session in the viewer's session index.
   */
  async sendHook(eventType: string, body: Record<string, unknown>): Promise<boolean> {
    const label = typeof body.session_id === "string" ? `${eventType}/${body.session_id}` : eventType;
    return this.post(eventType, body, label);
  }

  private async post(eventType: string, body: unknown, label: string): Promise<boolean> {
    const url = `${this.ccViewerUrl}/hooks/${eventType}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      if (!res.ok) {
        console.warn(`[cc-bridge] forward ${label} -> ${res.status} ${res.statusText}`);
        return false;
      }
      return true;
    } catch (err) {
      console.warn(`[cc-bridge] forward ${label} failed: ${(err as Error).message}`);
      return false;
    } finally {
      clearTimeout(timer);
    }
  }
}
