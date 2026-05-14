/**
 * Per-session JSONL transcript tailer.
 *
 * Each registered CC session gets:
 *   - a periodic `setInterval` poll-flush (every ~1.5s) — robust, simple,
 *     works whether or not the file exists yet
 *   - an optional `fs.watch` for sub-second reaction when the file is
 *     present. The watch is opportunistic: if `fs.watch` ENOENTs at
 *     register time (the SessionStart hook fires before CC has written
 *     the transcript), we leave it unset and try again on each poll until
 *     it sticks.
 *
 * Concurrency: at most one flush in-flight per session. While flushing,
 * additional change/poll events set a `pending` bit and re-trigger the
 * flush once the current pass finishes — bursts process everything but
 * never overlap.
 *
 * UUIDs: each JSONL entry carries its own `uuid` in normal CC output. For
 * synthetic / metadata lines that lack one we hash the line bytes to get
 * a stable dedupe key — same line ingested twice produces the same hash,
 * which is exactly what cc-viewer's `(session_id, line_uuid)` dedupe wants.
 */

import { type FSWatcher, watch } from "node:fs";
import { type Position, PositionStore, ZERO_POSITION } from "./positions.js";
import { type Forwarder, type TranscriptDelta } from "./forwarder.js";

const POLL_INTERVAL_MS = 1_500;

interface Session {
  readonly sessionId: string;
  readonly transcriptPath: string;
  position: Position;
  watcher: FSWatcher | null;
  pollTimer: ReturnType<typeof setInterval> | null;
  flushing: boolean;
  pendingFlush: boolean;
  lastActivity: number;
}

export interface SessionInfo {
  readonly sessionId: string;
  readonly transcriptPath: string;
  readonly lineIndex: number;
  readonly byteOffset: number;
  readonly lastActivityMs: number;
}

export class Tailer {
  private readonly sessions = new Map<string, Session>();

  constructor(
    private readonly positions: PositionStore,
    private readonly forwarder: Forwarder,
  ) {}

  async register(sessionId: string, transcriptPath: string): Promise<void> {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      // Same session re-registered (CC restart, double SessionStart) — refresh
      // activity but don't tear down the running watcher.
      existing.lastActivity = Date.now();
      return;
    }

    const persisted = await this.positions.read(sessionId);
    // If the transcript has been truncated below our persisted offset, reset.
    const fileSize = await safeFileSize(transcriptPath);
    const position =
      fileSize !== null && fileSize < persisted.byteOffset ? ZERO_POSITION : persisted;

    const session: Session = {
      sessionId,
      transcriptPath,
      position,
      watcher: null,
      pollTimer: null,
      flushing: false,
      pendingFlush: false,
      lastActivity: Date.now(),
    };
    this.sessions.set(sessionId, session);

    // Periodic poll — primary mechanism. Also handles the "transcript
    // file doesn't exist yet at register time" case (SessionStart hook
    // races with CC's first write). Each poll attempts to (re-)attach
    // the fs.watch optimization once the file exists.
    session.pollTimer = setInterval(() => {
      this.triggerFlush(sessionId);
    }, POLL_INTERVAL_MS);
    session.pollTimer.unref?.();

    // Best-effort fs.watch for sub-second reaction. Failures are silent —
    // the poll loop is the ground truth.
    this.tryAttachWatcher(session);

    // Initial flush — file may already have content (resume case).
    this.triggerFlush(sessionId);
  }

  async deregister(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.watcher?.close();
    session.watcher = null;
    if (session.pollTimer) {
      clearInterval(session.pollTimer);
      session.pollTimer = null;
    }
    // Final flush — flushes any tail that arrived between the last watch
    // event and the deregister call.
    await this.doFlush(sessionId).catch(() => undefined);
    this.sessions.delete(sessionId);
  }

  /** Drop sessions inactive for longer than `maxIdleMs`. */
  async reapIdle(maxIdleMs: number): Promise<string[]> {
    const now = Date.now();
    const dropped: string[] = [];
    for (const [id, s] of this.sessions) {
      if (now - s.lastActivity > maxIdleMs) {
        await this.deregister(id);
        dropped.push(id);
      }
    }
    return dropped;
  }

  list(): SessionInfo[] {
    return Array.from(this.sessions.values()).map((s) => ({
      sessionId: s.sessionId,
      transcriptPath: s.transcriptPath,
      lineIndex: s.position.lineIndex,
      byteOffset: s.position.byteOffset,
      lastActivityMs: s.lastActivity,
    }));
  }

  // ---- internals -----------------------------------------------------------

  private triggerFlush(sessionId: string): void {
    const s = this.sessions.get(sessionId);
    if (!s) return;
    if (s.flushing) {
      s.pendingFlush = true;
      return;
    }
    s.flushing = true;
    void (async () => {
      try {
        do {
          s.pendingFlush = false;
          await this.doFlush(sessionId);
        } while (s.pendingFlush && this.sessions.has(sessionId));
      } finally {
        s.flushing = false;
      }
    })();
  }

  private tryAttachWatcher(session: Session): void {
    if (session.watcher !== null) return;
    try {
      const w = watch(session.transcriptPath, { persistent: true }, () => {
        this.triggerFlush(session.sessionId);
      });
      w.on("error", (err) => {
        // Watcher died (file rotated, deleted) — drop reference; poll will
        // pick the new file up on next tick and re-attach.
        const code = (err as NodeJS.ErrnoException).code;
        if (code !== "ENOENT") {
          console.warn(`[cc-bridge] watch ${session.sessionId}: ${(err as Error).message}`);
        }
        session.watcher = null;
      });
      session.watcher = w;
    } catch {
      // ENOENT etc. — silent; next poll will retry.
    }
  }

  private async doFlush(sessionId: string): Promise<void> {
    const s = this.sessions.get(sessionId);
    if (!s) return;
    s.lastActivity = Date.now();

    // If the watcher isn't attached (file didn't exist at register, or
    // dropped after an error), opportunistically try again every flush.
    if (s.watcher === null) {
      this.tryAttachWatcher(s);
    }

    const file = Bun.file(s.transcriptPath);
    const fileSize = file.size;
    if (fileSize <= s.position.byteOffset) return;

    const slice = file.slice(s.position.byteOffset);
    const buf = new Uint8Array(await slice.arrayBuffer());

    const { lines, consumedBytes } = splitCompleteLines(buf);
    if (lines.length === 0) return;

    let lineIndex = s.position.lineIndex;
    const decoder = new TextDecoder();
    for (const lineBytes of lines) {
      if (lineBytes.length === 0) {
        lineIndex += 1;
        continue;
      }
      let parsed: Record<string, unknown> | undefined;
      try {
        parsed = JSON.parse(decoder.decode(lineBytes)) as Record<string, unknown>;
      } catch {
        parsed = undefined; // forward malformed line as opaque
      }
      const lineUuid = await deriveLineUuid(lineBytes, parsed);
      const delta: TranscriptDelta = {
        session_id: s.sessionId,
        line_uuid: lineUuid,
        line_index: lineIndex,
        transcript_path: s.transcriptPath,
        timestamp: new Date().toISOString(),
        entry: parsed ?? { _raw: decoder.decode(lineBytes) },
      };
      await this.forwarder.send(delta);
      lineIndex += 1;
    }

    const newPos: Position = {
      byteOffset: s.position.byteOffset + consumedBytes,
      lineIndex,
    };
    s.position = newPos;
    await this.positions.write(sessionId, newPos).catch((err) =>
      console.warn(`[cc-bridge] persist position ${sessionId}: ${(err as Error).message}`),
    );
  }
}

// ---- helpers --------------------------------------------------------------

interface LineSplit {
  readonly lines: Uint8Array[];
  /** Bytes consumed up to and including the last `\n` we found. */
  readonly consumedBytes: number;
}

/**
 * Split a buffer into complete `\n`-terminated lines. The bytes after the
 * last `\n` are treated as a partial trailing line and left for the next
 * flush (not returned).
 */
function splitCompleteLines(buf: Uint8Array): LineSplit {
  const lines: Uint8Array[] = [];
  let start = 0;
  let consumed = 0;
  for (let i = 0; i < buf.length; i += 1) {
    if (buf[i] === 0x0a) {
      lines.push(buf.subarray(start, i));
      start = i + 1;
      consumed = start;
    }
  }
  return { lines, consumedBytes: consumed };
}

async function deriveLineUuid(
  lineBytes: Uint8Array,
  parsed: Record<string, unknown> | undefined,
): Promise<string> {
  const fromEntry =
    parsed && typeof parsed.uuid === "string" && parsed.uuid.length > 0
      ? parsed.uuid
      : undefined;
  if (fromEntry) return fromEntry;
  // `.slice()` produces a Uint8Array backed by a fresh ArrayBuffer (not a
  // SharedArrayBuffer-typed view from `.subarray()`), which `crypto.subtle.digest`
  // wants under strict lib.dom typings.
  const hash = await crypto.subtle.digest("SHA-256", lineBytes.slice());
  const out: string[] = [];
  const view = new Uint8Array(hash);
  for (let i = 0; i < 16; i += 1) {
    out.push((view[i] ?? 0).toString(16).padStart(2, "0"));
  }
  return out.join("");
}

async function safeFileSize(path: string): Promise<number | null> {
  try {
    return Bun.file(path).size;
  } catch {
    return null;
  }
}
