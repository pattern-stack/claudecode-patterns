/**
 * Per-session position cursor persistence.
 *
 * Stored as one tiny JSON file per session at
 * `<stateDir>/positions/<sessionId>.pos`. Holds the byte offset we've
 * forwarded up to and the corresponding line index, so a restart of
 * cc-bridge resumes from where it left off without re-emitting old lines.
 *
 * If the transcript file is found to be SHORTER than `byteOffset` at
 * registration time (rotated / truncated) we treat the file as fresh and
 * start from zero — better to risk a few duplicate emits than miss data;
 * the cc-viewer side dedupes on (session_id, line_uuid) anyway.
 */

import { mkdirSync } from "node:fs";
import path from "node:path";

export interface Position {
  readonly byteOffset: number;
  readonly lineIndex: number;
}

export const ZERO_POSITION: Position = { byteOffset: 0, lineIndex: 0 };

export class PositionStore {
  constructor(private readonly stateDir: string) {
    mkdirSync(path.join(stateDir, "positions"), { recursive: true });
  }

  private pathFor(sessionId: string): string {
    // Defensive: sessionIds come from the wire. Strip anything that could
    // escape the positions dir; the CC session_id format is a UUID so this
    // is normally a no-op.
    const safe = sessionId.replace(/[^a-zA-Z0-9_-]/g, "_");
    return path.join(this.stateDir, "positions", `${safe}.pos`);
  }

  async read(sessionId: string): Promise<Position> {
    try {
      const text = await Bun.file(this.pathFor(sessionId)).text();
      const parsed = JSON.parse(text) as Partial<Position>;
      const byteOffset = typeof parsed.byteOffset === "number" ? parsed.byteOffset : 0;
      const lineIndex = typeof parsed.lineIndex === "number" ? parsed.lineIndex : 0;
      return { byteOffset, lineIndex };
    } catch {
      return ZERO_POSITION;
    }
  }

  async write(sessionId: string, pos: Position): Promise<void> {
    // Atomic rename — never leave a half-written .pos behind.
    const target = this.pathFor(sessionId);
    const tmp = `${target}.tmp`;
    await Bun.write(tmp, JSON.stringify(pos));
    await Bun.$`mv ${tmp} ${target}`.quiet();
  }
}
