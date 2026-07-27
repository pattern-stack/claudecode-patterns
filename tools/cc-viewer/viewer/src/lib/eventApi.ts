/**
 * REST client for the historical event endpoints.
 *
 * These are used by pages that want to hydrate from the durable event log
 * before layering live SSE on top — so a fresh page load shows yesterday's
 * sessions instead of starting empty.
 */

import type { StreamEvent } from "../hooks/useEventStream";

/** Shape returned by GET /admin/events/recent. */
interface RecentEventsResponse {
  events: PersistedEventRow[];
}

interface PersistedEventRow {
  id: number;
  type: string;
  timestamp: string;
  data: Record<string, unknown>;
}

export interface FetchRecentOptions {
  /** Filter to a single event type (e.g. `"claude_code.hook"`). */
  type?: string;
  /** Lower bound on `timestamp` (ISO). Defaults to 7 days ago. */
  since?: Date;
  /** Max rows returned. Server clamps to [1, 10000]. Default 1000. */
  limit?: number;
  /** Override default base URL (mostly for tests). */
  baseUrl?: string;
}

/**
 * Fetch recent persisted events and translate them into the same `StreamEvent`
 * shape `useEventStream` produces. Returns `[]` when the server reports the
 * store is not configured (503) so consumers can degrade gracefully.
 */
export async function fetchRecentEvents(opts: FetchRecentOptions = {}): Promise<StreamEvent[]> {
  const params = new URLSearchParams();
  if (opts.type) params.set("type", opts.type);
  if (opts.since) params.set("since", opts.since.toISOString());
  if (opts.limit) params.set("limit", String(opts.limit));

  const base = opts.baseUrl ?? "";
  const url = `${base}/admin/events/recent${params.size ? `?${params}` : ""}`;

  const res = await fetch(url);
  if (res.status === 503) return [];
  if (!res.ok) throw new Error(`fetchRecentEvents: HTTP ${res.status}`);

  const body = (await res.json()) as RecentEventsResponse;
  // Server returns DESC; the page assumes ASC arrival order, so reverse.
  const rows = [...body.events].reverse();
  return rows.map((row) => ({
    id: `hist-${row.id}`,
    type: row.type,
    data: row.data,
    timestamp: row.timestamp,
  }));
}

/** One row from GET /admin/claude-code/sessions/:id/transcript. */
export interface TranscriptEntry {
  line_uuid: string;
  line_index: number;
  timestamp: string;
  transcript_path?: string;
  entry: Record<string, unknown>;
}

interface TranscriptResponse {
  session_id: string;
  /** True when a bounded tail filled `limit` — older lines exist server-side
   *  that weren't sent. Declared so the wire contract matches the route; no UI
   *  surfaces it yet ("showing last N" is a follow-up). */
  truncated?: boolean;
  entries: TranscriptEntry[];
}

/**
 * Fetch the cold-loaded transcript snapshot for a single Claude Code
 * session. Entries are returned pre-ordered by `line_index`. When `limit` is
 * given the server returns only the newest N lines (bounded cold-load payload);
 * omit it to fetch the full transcript.
 */
export async function fetchTranscript(
  sessionId: string,
  opts: { baseUrl?: string; limit?: number } = {},
): Promise<TranscriptEntry[]> {
  const base = opts.baseUrl ?? "";
  const query = opts.limit ? `?limit=${opts.limit}` : "";
  const url = `${base}/admin/claude-code/sessions/${encodeURIComponent(sessionId)}/transcript${query}`;
  const res = await fetch(url);
  if (res.status === 404) return [];
  if (!res.ok) throw new Error(`fetchTranscript: HTTP ${res.status}`);
  const body = (await res.json()) as TranscriptResponse;
  return body.entries ?? [];
}

/** One row from GET /admin/claude-code/sessions. */
interface SessionSummary {
  sessionId: string;
  cwd: string | null;
  firstSeen: string;
  lastSeen: string;
}

/**
 * Resolve a session's working directory — the key used to match the live
 * Ghostty terminal pane when sending input. Returns null if unknown.
 */
export async function fetchSessionCwd(
  sessionId: string,
  opts: { baseUrl?: string } = {},
): Promise<string | null> {
  const base = opts.baseUrl ?? "";
  const res = await fetch(`${base}/admin/claude-code/sessions?limit=500`);
  if (!res.ok) return null;
  const body = (await res.json()) as { sessions?: SessionSummary[] };
  const match = (body.sessions ?? []).find((s) => s.sessionId === sessionId);
  return match?.cwd ?? null;
}

/** One slash command from GET /admin/commands. */
export interface CommandEntry {
  /** Invocation token without the leading slash, e.g. "sdlc:design". */
  name: string;
  description: string;
  argumentHint?: string;
  /** Owning plugin key, or null for project-local / built-in commands. */
  plugin: string | null;
  kind: "command" | "skill" | "project" | "builtin";
}

/**
 * Fetch the slash-command catalog Claude Code reads (enabled-plugin commands +
 * user-invocable skills, plus the project's own commands when `cwd` is given).
 * Built-in commands are not file-backed and are not included. Returns [] on
 * error so the composer degrades to a plain input.
 */
export async function fetchCommands(
  cwd?: string,
  opts: { baseUrl?: string } = {},
): Promise<CommandEntry[]> {
  const base = opts.baseUrl ?? "";
  const url = `${base}/admin/commands${cwd ? `?cwd=${encodeURIComponent(cwd)}` : ""}`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const body = (await res.json()) as { commands?: CommandEntry[] };
  return body.commands ?? [];
}

/** Result of POST /admin/input/send. */
export interface SendInputResult {
  ok: boolean;
  terminal_id: string | null;
  matched: number | null;
}

/**
 * Send text into the live terminal session identified by `cwd` (proxied to
 * ghostty-bridge). `submit` presses Enter after the paste (default true).
 * Throws Error with the server's message on failure (e.g. no live pane).
 */
export async function sendAgentInput(
  args: { cwd: string; text: string; submit?: boolean },
  opts: { baseUrl?: string } = {},
): Promise<SendInputResult> {
  const base = opts.baseUrl ?? "";
  const res = await fetch(`${base}/admin/input/send`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ cwd: args.cwd, text: args.text, submit: args.submit ?? true }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(typeof body.error === "string" ? body.error : `send failed (HTTP ${res.status})`);
  }
  return {
    ok: Boolean(body.ok),
    terminal_id: (body.terminal_id as string | null) ?? null,
    matched: (body.matched as number | null) ?? null,
  };
}
