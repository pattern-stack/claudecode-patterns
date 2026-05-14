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
}

export class Forwarder {
  constructor(
    private readonly ccViewerUrl: string,
    private readonly timeoutMs: number,
  ) {}

  async send(delta: TranscriptDelta): Promise<boolean> {
    const url = `${this.ccViewerUrl}/hooks/TranscriptDelta`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(delta),
        signal: controller.signal,
      });
      if (!res.ok) {
        console.warn(
          `[cc-bridge] forward ${delta.session_id}/${delta.line_index} -> ${res.status} ${res.statusText}`,
        );
        return false;
      }
      return true;
    } catch (err) {
      console.warn(
        `[cc-bridge] forward ${delta.session_id}/${delta.line_index} failed: ${(err as Error).message}`,
      );
      return false;
    } finally {
      clearTimeout(timer);
    }
  }
}
