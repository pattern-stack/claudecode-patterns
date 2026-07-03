/**
 * SessionIndex — the app's single source of truth for Claude Code sessions.
 *
 * Fetches the recent hook-event history once, then live-tails the SSE stream,
 * and exposes the grouped session/project views that both the sidebar and the
 * pages render. Mounting this once at the app root (rather than per-page) avoids
 * the double-fetch the pages used to do and keeps every surface in sync.
 */

import { createContext, type ReactNode, useContext, useEffect, useMemo, useState } from "react";
import {
  type ProjectBucket,
  type SessionState,
  groupByProject,
  groupClaudeCodeEvents,
} from "../lib/claudeCodeSessions";
import { type StreamEvent, useEventStream } from "./useEventStream";
import { fetchRecentEvents } from "../lib/eventApi";

interface SessionIndex {
  sessions: SessionState[];
  projects: ProjectBucket[];
  /** SSE connection state. */
  connected: boolean;
  /** False until the initial history fetch resolves. */
  ready: boolean;
  error: string | null;
}

const Ctx = createContext<SessionIndex | null>(null);

export function SessionIndexProvider({ children }: { children: ReactNode }) {
  const [initial, setInitial] = useState<StreamEvent[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchRecentEvents({ type: "claude_code.hook", limit: 5000 })
      .then((rows) => {
        if (!cancelled) setInitial(rows);
      })
      .catch(() => {
        if (!cancelled) setInitial([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Keep a large buffer: the reducer needs a session's whole hook trail (incl.
  // older TeammateIdle tags) to classify leads/teammates. Must stay above the
  // 5000-event seed so the first live event doesn't evict the history.
  const { events, connected, error } = useEventStream("/admin/events/stream", {
    initialEvents: initial ?? [],
    maxEvents: 20000,
    // Reduce only hook events. Subscribing to transcript_delta here would flood
    // the 20000-event buffer and re-run groupClaudeCodeEvents on every streamed
    // line — deltas the reducer immediately discards. The chat view has its own
    // dedicated delta stream (useTranscript).
    eventNames: ["claude_code.hook"],
  });

  const sessions = useMemo(() => groupClaudeCodeEvents(events), [events]);
  const projects = useMemo(() => groupByProject(sessions), [sessions]);

  const value = useMemo<SessionIndex>(
    () => ({ sessions, projects, connected, ready: initial !== null, error }),
    [sessions, projects, connected, initial, error],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSessionIndex(): SessionIndex {
  const v = useContext(Ctx);
  if (!v) throw new Error("useSessionIndex must be used within <SessionIndexProvider>");
  return v;
}
