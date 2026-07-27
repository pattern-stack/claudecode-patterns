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
import { readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { type Position, PositionStore, ZERO_POSITION } from "./positions.js";
import { type Forwarder, type TranscriptDelta } from "./forwarder.js";

const POLL_INTERVAL_MS = 1_500;
/** How often a top-level session rescans its `subagents/` dir for new teammates. */
const DISCOVERY_INTERVAL_MS = 3_000;
const AGENT_PREFIX = "agent-";
const JSONL_EXT = ".jsonl";

/**
 * Identity of a teammate ("subagent") transcript, resolved once from its
 * `.meta.json` sidecar at discovery time. Lets the tailer stamp each forwarded
 * line — and the synthetic `SessionStart` — with enough for cc-viewer to nest
 * the teammate under its lead.
 */
export interface TeammateMeta {
  readonly parentSessionId: string;
  /** Distinct id for this teammate session (the filename stem, `agent-` stripped). */
  readonly agentId: string;
  /** Display name, e.g. "implementer-118" (from meta `name`). */
  readonly label: string;
  /** Role / agent type, e.g. "sdlc:implementer" (from meta `agentType`). */
  readonly role: string;
  readonly teamName?: string;
  readonly cwd?: string;
}

interface Session {
  readonly sessionId: string;
  readonly transcriptPath: string;
  position: Position;
  watcher: FSWatcher | null;
  pollTimer: ReturnType<typeof setInterval> | null;
  /** Only set on top-level (lead/standalone) sessions; scans for teammates. */
  discoveryTimer: ReturnType<typeof setInterval> | null;
  flushing: boolean;
  pendingFlush: boolean;
  /** Guards against overlapping subagent scans (a scan slower than the interval). */
  scanning: boolean;
  lastActivity: number;
  /** null for top-level sessions; set for teammate transcripts. */
  meta: TeammateMeta | null;
  /** Lead cwd threaded from `register`, stamped onto discovered teammates. */
  cwd: string | null;
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

  async register(sessionId: string, transcriptPath: string, cwd?: string): Promise<void> {
    await this.startSession(sessionId, transcriptPath, { meta: null, cwd: cwd ?? null });
  }

  /**
   * Shared session bootstrap for both top-level sessions ({@link register}) and
   * teammate transcripts ({@link registerSubagent}). Returns the created session,
   * or null if it was already known (re-register just refreshes activity).
   */
  private async startSession(
    sessionId: string,
    transcriptPath: string,
    opts: { meta: TeammateMeta | null; cwd: string | null },
  ): Promise<Session | null> {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      // Same session re-registered (CC restart, double SessionStart) — refresh
      // activity but don't tear down the running watcher.
      existing.lastActivity = Date.now();
      return null;
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
      discoveryTimer: null,
      flushing: false,
      pendingFlush: false,
      scanning: false,
      lastActivity: Date.now(),
      meta: opts.meta,
      cwd: opts.cwd,
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

    // Only top-level sessions hunt for teammate subagents. Teammates do not
    // recurse (spawnDepth is flat in practice, and this bounds the fan-out).
    if (opts.meta === null) {
      session.discoveryTimer = setInterval(() => {
        void this.scanSubagents(session);
      }, DISCOVERY_INTERVAL_MS);
      session.discoveryTimer.unref?.();
      void this.scanSubagents(session);
    }

    // Best-effort fs.watch for sub-second reaction. Failures are silent —
    // the poll loop is the ground truth.
    this.tryAttachWatcher(session);

    // Initial flush — file may already have content (resume case).
    this.triggerFlush(sessionId);
    return session;
  }

  /**
   * Discover teammate transcripts nested under a lead session and bring each
   * online as its own tailed session. CC 2.1.178+ writes in-process teammates
   * to `<projects>/<slug>/<leadSessionId>/subagents/agent-<id>.jsonl` (with a
   * sibling `.meta.json`), never as a top-level transcript — so nothing
   * registers them with cc-bridge. We find them off the lead and self-register.
   */
  private async scanSubagents(lead: Session): Promise<void> {
    if (lead.scanning) return;
    lead.scanning = true;
    try {
      // Lead transcript: <projects>/<slug>/<leadSessionId>.jsonl
      // Teammates:       <projects>/<slug>/<leadSessionId>/subagents/agent-*.jsonl
      const dir = join(dirname(lead.transcriptPath), lead.sessionId, "subagents");
      let entries: string[];
      try {
        entries = await readdir(dir);
      } catch {
        return; // no subagents dir (standalone session, or none spawned yet)
      }
      for (const name of entries) {
        if (!name.startsWith(AGENT_PREFIX) || !name.endsWith(JSONL_EXT)) continue;
        const agentId = name.slice(AGENT_PREFIX.length, -JSONL_EXT.length);
        if (!agentId || this.sessions.has(agentId)) continue;
        const jsonlPath = join(dir, name);
        const meta = await readTeammateMeta(jsonlPath, agentId, lead);
        await this.registerSubagent(meta, jsonlPath);
      }
    } finally {
      lead.scanning = false;
    }
  }

  private async registerSubagent(meta: TeammateMeta, transcriptPath: string): Promise<void> {
    if (this.sessions.has(meta.agentId)) return;
    // Teammates emit no hooks of their own, so cc-viewer would never mint a
    // session for one. Mint a synthetic SessionStart carrying the parent link +
    // role so it becomes a first-class, nestable session in the viewer.
    await this.forwarder.sendHook("SessionStart", {
      session_id: meta.agentId,
      transcript_path: transcriptPath,
      cwd: meta.cwd,
      source: "teammate",
      parent_session_id: meta.parentSessionId,
      team_name: meta.teamName,
      teammate_role: meta.role,
      teammate_label: meta.label,
      agent_id: meta.agentId,
    });
    await this.startSession(meta.agentId, transcriptPath, { meta, cwd: meta.cwd ?? null });
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
    if (session.discoveryTimer) {
      clearInterval(session.discoveryTimer);
      session.discoveryTimer = null;
    }
    // Final flush — flushes any tail that arrived between the last watch
    // event and the deregister call.
    await this.doFlush(sessionId).catch(() => undefined);
    this.sessions.delete(sessionId);

    // A lead's teammates have no SessionEnd of their own — cascade the teardown
    // so their pollers don't leak past the lead.
    if (session.meta === null) {
      const kids = Array.from(this.sessions.values())
        .filter((s) => s.meta?.parentSessionId === sessionId)
        .map((s) => s.sessionId);
      for (const id of kids) await this.deregister(id);
    }
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
        // Teammate lines carry the parent link so the viewer can attribute them
        // to the nested session even on the transcript (data-plane) path.
        ...(s.meta
          ? { parent_session_id: s.meta.parentSessionId, agent_id: s.meta.agentId }
          : {}),
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

/**
 * Resolve a teammate's identity from its `.meta.json` sidecar (written by the
 * harness next to the subagent transcript). Degrades gracefully: a missing or
 * unreadable sidecar falls back to the id-derived label and a generic role, so
 * a teammate still surfaces (just less prettily named).
 */
async function readTeammateMeta(
  jsonlPath: string,
  agentId: string,
  lead: Session,
): Promise<TeammateMeta> {
  const metaPath = jsonlPath.replace(/\.jsonl$/, ".meta.json");
  let name: string | undefined;
  let role: string | undefined;
  let teamName: string | undefined;
  try {
    const raw = JSON.parse(await Bun.file(metaPath).text()) as Record<string, unknown>;
    if (typeof raw.name === "string" && raw.name) name = raw.name;
    if (typeof raw.agentType === "string" && raw.agentType) role = raw.agentType;
    if (typeof raw.teamName === "string" && raw.teamName) teamName = raw.teamName;
  } catch {
    // sidecar absent/unreadable — fall through to id-derived label below.
  }
  // Best available display name: sidecar `name`, else the role (anonymous
  // Agent-tool subagents carry an agentType but no name), else the raw id.
  const label = name ?? role ?? agentId;
  return {
    parentSessionId: lead.sessionId,
    agentId,
    label,
    role: role ?? "teammate",
    teamName,
    cwd: lead.cwd ?? undefined,
  };
}
