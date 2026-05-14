/**
 * useTranscript — owns the entry feed for one Claude Code session.
 *
 * Cold-loads the transcript snapshot via REST, then layers live
 * `claude_code.transcript_delta` SSE on top. Entries are deduped by
 * `line_uuid` and kept sorted by `line_index` so out-of-order delivery
 * is harmless. The derived `messages[]` is memoized off the entry list.
 */

import { useEffect, useMemo, useState } from "react";
import { fetchTranscript, type TranscriptEntry } from "../lib/eventApi";
import { type ChatMessage, entriesToMessages } from "../lib/transcript";

const INITIAL_RETRY_MS = 1000;
const MAX_RETRY_MS = 30_000;

export interface UseTranscriptResult {
  messages: ChatMessage[];
  loading: boolean;
  error: string | null;
  connected: boolean;
}

interface DeltaPayload {
  session_id?: string;
  line_uuid?: string;
  line_index?: number;
  timestamp?: string;
  transcript_path?: string;
  entry?: Record<string, unknown>;
}

export function useTranscript(sessionId: string | undefined): UseTranscriptResult {
  const [entries, setEntries] = useState<TranscriptEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [connected, setConnected] = useState(false);

  // Cold-load snapshot.
  useEffect(() => {
    if (!sessionId) {
      setEntries([]);
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchTranscript(sessionId)
      .then((rows) => {
        if (cancelled) return;
        setEntries(rows);
        setLoading(false);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Failed to load transcript");
        setEntries([]);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [sessionId]);

  // Live tail. Kept separate from useEventStream so we can filter
  // server-side cheaply and dedupe by line_uuid (the global event stream
  // is firehose-ordered, not session-scoped).
  useEffect(() => {
    if (!sessionId) return;

    let cancelled = false;
    let source: EventSource | null = null;
    let retryDelay = INITIAL_RETRY_MS;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;

    const connect = () => {
      if (cancelled) return;
      source = new EventSource("/admin/events/stream");

      source.onopen = () => {
        setConnected(true);
        retryDelay = INITIAL_RETRY_MS;
      };

      source.addEventListener("claude_code.transcript_delta", (e) => {
        try {
          const payload = JSON.parse((e as MessageEvent).data) as DeltaPayload;
          if (payload.session_id !== sessionId) return;
          if (!payload.line_uuid || payload.line_index === undefined || !payload.entry) return;
          const entry: TranscriptEntry = {
            line_uuid: payload.line_uuid,
            line_index: payload.line_index,
            timestamp: payload.timestamp ?? new Date().toISOString(),
            transcript_path: payload.transcript_path,
            entry: payload.entry,
          };
          setEntries((prev) => mergeEntry(prev, entry));
        } catch {
          // malformed — ignore
        }
      });

      source.onerror = () => {
        setConnected(false);
        source?.close();
        source = null;
        if (cancelled) return;
        const delay = retryDelay;
        retryDelay = Math.min(delay * 2, MAX_RETRY_MS);
        retryTimer = setTimeout(connect, delay);
      };
    };

    connect();

    return () => {
      cancelled = true;
      source?.close();
      source = null;
      setConnected(false);
      if (retryTimer) clearTimeout(retryTimer);
    };
  }, [sessionId]);

  const messages = useMemo(() => entriesToMessages(entries), [entries]);

  return { messages, loading, error, connected };
}

/**
 * Insert (or no-op dedupe) one entry into the sorted-by-line_index list.
 * Linear scan — entry counts per session are bounded by what fits in one
 * CC conversation, so this is fine.
 */
function mergeEntry(prev: TranscriptEntry[], next: TranscriptEntry): TranscriptEntry[] {
  if (prev.some((e) => e.line_uuid === next.line_uuid)) return prev;
  const out = prev.slice();
  let i = 0;
  while (i < out.length) {
    const cur = out[i];
    if (cur && cur.line_index > next.line_index) break;
    i++;
  }
  out.splice(i, 0, next);
  return out;
}
