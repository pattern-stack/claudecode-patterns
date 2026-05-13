/**
 * EventStore — bun:sqlite-backed durable log of bus events.
 *
 * Append-only event log with hot-path denormalization for Claude Code hook
 * grouping (cc_session_id / cc_hook_name / cc_cwd). Everything else lives in
 * the JSON `data` column.
 *
 * Single-table v1. Schema versioning via `PRAGMA user_version` so future
 * migrations have a place to land without surprising rewrites.
 */

import { Database, type Statement } from "bun:sqlite";
import type { BaseEvent } from "./event-types.js";

export interface PersistedEvent {
  readonly id: number;
  readonly type: string;
  readonly timestamp: string;
  readonly traceId: string | null;
  readonly runId: string | null;
  readonly spanId: string | null;
  readonly ccSessionId: string | null;
  readonly ccHookName: string | null;
  readonly ccCwd: string | null;
  readonly data: Record<string, unknown>;
}

export interface SessionSummary {
  readonly sessionId: string;
  readonly cwd: string | null;
  readonly firstSeen: string;
  readonly lastSeen: string;
  readonly eventCount: number;
}

export interface PersistedTranscriptEntry {
  readonly sessionId: string;
  readonly lineUuid: string;
  readonly lineIndex: number;
  readonly timestamp: string;
  readonly transcriptPath: string | null;
  readonly entry: Record<string, unknown>;
}

export interface TranscriptEntryInput {
  readonly sessionId: string;
  readonly lineUuid: string;
  readonly lineIndex: number;
  readonly timestamp: Date | string;
  readonly transcriptPath?: string;
  readonly entry: Record<string, unknown>;
}

export interface EventStoreOptions {
  /** Path to the SQLite file. `:memory:` is supported for tests. */
  readonly path: string;
  /** Retention in days. Events older than this are removed at construction. */
  readonly retentionDays?: number;
  /** Row cap. The N most recent rows are kept; older ones are deleted. */
  readonly maxRows?: number;
}

const SCHEMA_V1 = `
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  trace_id TEXT,
  run_id TEXT,
  span_id TEXT,
  cc_session_id TEXT,
  cc_hook_name TEXT,
  cc_cwd TEXT,
  data TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);
CREATE INDEX IF NOT EXISTS idx_events_cc_session ON events(cc_session_id, timestamp) WHERE cc_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_trace ON events(trace_id, timestamp) WHERE trace_id IS NOT NULL;
`;

const SCHEMA_V2 = `
CREATE TABLE IF NOT EXISTS transcript_entries (
  session_id      TEXT    NOT NULL,
  line_uuid       TEXT    NOT NULL,
  line_index      INTEGER NOT NULL,
  timestamp       TEXT    NOT NULL,
  transcript_path TEXT,
  entry           TEXT    NOT NULL,
  PRIMARY KEY (session_id, line_uuid)
);

CREATE INDEX IF NOT EXISTS idx_transcript_session_index
  ON transcript_entries(session_id, line_index);
`;

const TARGET_SCHEMA_VERSION = 2;

export class EventStore {
  private readonly _db: Database;
  private readonly _appendStmt: Statement;
  private readonly _recentStmt: Statement;
  private readonly _sessionEventsStmt: Statement;
  private readonly _sessionListStmt: Statement;
  private readonly _deleteByDateStmt: Statement;
  private readonly _deleteByCapStmt: Statement;
  private readonly _appendTranscriptStmt: Statement;
  private readonly _transcriptForSessionStmt: Statement;

  constructor(opts: EventStoreOptions) {
    this._db = new Database(opts.path);
    this._db.exec("PRAGMA journal_mode = WAL");
    this._db.exec("PRAGMA synchronous = NORMAL");
    this._db.exec("PRAGMA foreign_keys = ON");

    this._migrate();

    this._appendStmt = this._db.prepare(`
      INSERT INTO events (
        type, timestamp, trace_id, run_id, span_id,
        cc_session_id, cc_hook_name, cc_cwd, data
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    this._recentStmt = this._db.prepare(`
      SELECT * FROM events
      WHERE ($since IS NULL OR timestamp >= $since)
        AND ($type  IS NULL OR type = $type)
      ORDER BY timestamp DESC
      LIMIT $limit
    `);

    this._sessionEventsStmt = this._db.prepare(`
      SELECT * FROM events
      WHERE cc_session_id = ?
      ORDER BY timestamp ASC, id ASC
    `);

    this._sessionListStmt = this._db.prepare(`
      SELECT
        cc_session_id    AS sessionId,
        MAX(cc_cwd)      AS cwd,
        MIN(timestamp)   AS firstSeen,
        MAX(timestamp)   AS lastSeen,
        COUNT(*)         AS eventCount
      FROM events
      WHERE type = 'claude_code.hook' AND cc_session_id IS NOT NULL
      GROUP BY cc_session_id
      ORDER BY lastSeen DESC
      LIMIT ?
    `);

    this._deleteByDateStmt = this._db.prepare(`DELETE FROM events WHERE timestamp < ?`);
    this._deleteByCapStmt = this._db.prepare(`
      DELETE FROM events
      WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT ?)
    `);

    // INSERT OR IGNORE makes re-POST of the same line a no-op — the
    // primary key (session_id, line_uuid) is the dedupe key.
    this._appendTranscriptStmt = this._db.prepare(`
      INSERT OR IGNORE INTO transcript_entries (
        session_id, line_uuid, line_index, timestamp, transcript_path, entry
      ) VALUES (?, ?, ?, ?, ?, ?)
    `);
    this._transcriptForSessionStmt = this._db.prepare(`
      SELECT * FROM transcript_entries
      WHERE session_id = ?
      ORDER BY line_index ASC
    `);

    if (opts.retentionDays !== undefined) this.purgeOlderThanDays(opts.retentionDays);
    if (opts.maxRows !== undefined) this.purgeBeyondCap(opts.maxRows);
  }

  append(event: BaseEvent): void {
    const data = event as unknown as Record<string, unknown>;
    const cc = extractClaudeCodeFields(event.type, data);

    this._appendStmt.run(
      event.type,
      timestampToIso(event.timestamp),
      event.traceId ?? null,
      event.runId ?? null,
      event.spanId ?? null,
      cc.sessionId,
      cc.hookName,
      cc.cwd,
      JSON.stringify(event, jsonReplacer),
    );
  }

  recent(opts: { since?: Date; type?: string; limit?: number } = {}): PersistedEvent[] {
    const rows = this._recentStmt.all({
      $since: opts.since ? opts.since.toISOString() : null,
      $type: opts.type ?? null,
      $limit: opts.limit ?? 1000,
    }) as RawRow[];
    return rows.map(rowToPersisted);
  }

  sessionEvents(sessionId: string): PersistedEvent[] {
    const rows = this._sessionEventsStmt.all(sessionId) as RawRow[];
    return rows.map(rowToPersisted);
  }

  sessions(limit = 50): SessionSummary[] {
    const rows = this._sessionListStmt.all(limit) as {
      sessionId: string;
      cwd: string | null;
      firstSeen: string;
      lastSeen: string;
      eventCount: number;
    }[];
    return rows.map((r) => ({
      sessionId: r.sessionId,
      cwd: r.cwd,
      firstSeen: r.firstSeen,
      lastSeen: r.lastSeen,
      eventCount: r.eventCount,
    }));
  }

  purgeOlderThanDays(days: number): number {
    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
    const info = this._deleteByDateStmt.run(cutoff);
    return Number(info.changes);
  }

  purgeBeyondCap(cap: number): number {
    const info = this._deleteByCapStmt.run(cap);
    return Number(info.changes);
  }

  count(): number {
    const row = this._db.prepare("SELECT COUNT(*) AS n FROM events").get() as { n: number };
    return row.n;
  }

  /**
   * Append one transcript entry. Returns true if a new row was inserted,
   * false if it was a duplicate (same session_id + line_uuid).
   */
  appendTranscriptEntry(input: TranscriptEntryInput): boolean {
    const info = this._appendTranscriptStmt.run(
      input.sessionId,
      input.lineUuid,
      input.lineIndex,
      timestampToIso(input.timestamp),
      input.transcriptPath ?? null,
      JSON.stringify(input.entry, jsonReplacer),
    );
    return Number(info.changes) > 0;
  }

  transcriptForSession(sessionId: string): PersistedTranscriptEntry[] {
    const rows = this._transcriptForSessionStmt.all(sessionId) as RawTranscriptRow[];
    return rows.map(rowToTranscriptEntry);
  }

  close(): void {
    this._db.close();
  }

  private _migrate(): void {
    const row = this._db.prepare("PRAGMA user_version").get() as
      | { user_version?: number }
      | undefined;
    let version = row?.user_version ?? 0;

    if (version < 1) {
      this._db.exec(SCHEMA_V1);
      version = 1;
    }
    if (version < 2) {
      this._db.exec(SCHEMA_V2);
      version = 2;
    }

    if (version !== TARGET_SCHEMA_VERSION) {
      throw new Error(
        `event-store schema version mismatch: db is ${version}, expected ${TARGET_SCHEMA_VERSION}`,
      );
    }
    this._db.exec(`PRAGMA user_version = ${TARGET_SCHEMA_VERSION}`);
  }
}

interface RawRow {
  id: number;
  type: string;
  timestamp: string;
  trace_id: string | null;
  run_id: string | null;
  span_id: string | null;
  cc_session_id: string | null;
  cc_hook_name: string | null;
  cc_cwd: string | null;
  data: string;
}

interface RawTranscriptRow {
  session_id: string;
  line_uuid: string;
  line_index: number;
  timestamp: string;
  transcript_path: string | null;
  entry: string;
}

function rowToTranscriptEntry(r: RawTranscriptRow): PersistedTranscriptEntry {
  let entry: Record<string, unknown>;
  try {
    entry = JSON.parse(r.entry) as Record<string, unknown>;
  } catch {
    entry = { _parseError: true, _raw: r.entry };
  }
  return {
    sessionId: r.session_id,
    lineUuid: r.line_uuid,
    lineIndex: r.line_index,
    timestamp: r.timestamp,
    transcriptPath: r.transcript_path,
    entry,
  };
}

function rowToPersisted(r: RawRow): PersistedEvent {
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(r.data) as Record<string, unknown>;
  } catch {
    data = { _parseError: true, _raw: r.data };
  }
  return {
    id: r.id,
    type: r.type,
    timestamp: r.timestamp,
    traceId: r.trace_id,
    runId: r.run_id,
    spanId: r.span_id,
    ccSessionId: r.cc_session_id,
    ccHookName: r.cc_hook_name,
    ccCwd: r.cc_cwd,
    data,
  };
}

function extractClaudeCodeFields(
  eventType: string,
  data: Record<string, unknown>,
): { sessionId: string | null; hookName: string | null; cwd: string | null } {
  if (eventType !== "claude_code.hook") {
    return { sessionId: null, hookName: null, cwd: null };
  }
  return {
    sessionId: str(data.sessionId) ?? str(readPayload(data)?.session_id) ?? null,
    hookName: str(data.hookName) ?? str(readPayload(data)?.hook_event_name) ?? null,
    cwd: str(data.cwd) ?? str(readPayload(data)?.cwd) ?? null,
  };
}

function readPayload(data: Record<string, unknown>): Record<string, unknown> | undefined {
  const p = data.payload;
  return typeof p === "object" && p !== null ? (p as Record<string, unknown>) : undefined;
}

function str(v: unknown): string | undefined {
  return typeof v === "string" && v.length > 0 ? v : undefined;
}

function timestampToIso(t: Date | string | undefined | null): string {
  if (t instanceof Date) return t.toISOString();
  if (typeof t === "string") return t;
  return new Date().toISOString();
}

function jsonReplacer(_key: string, value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  return value;
}
