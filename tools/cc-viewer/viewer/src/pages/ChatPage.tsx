/**
 * ChatPage — top-level list of Claude Code sessions, each one a link to
 * its transcript view at /chat/:sessionId.
 *
 * Reuses the LogsPage discovery path (hook history + live SSE grouped by
 * session_id) so the same set of sessions shows up in both places. We
 * render slimmer clickable rows here instead of the LogsPage's
 * SessionCard because the chat view doesn't need the hook-name chips —
 * just enough to pick a session.
 */

import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Badge } from "../components/atoms/Badge";
import { Card } from "../components/atoms/Card";
import { Spinner } from "../components/atoms/Spinner";
import { AlertIcon } from "../components/atoms/icons";
import { type StreamEvent, useEventStream } from "../hooks/useEventStream";
import {
  type SessionState,
  formatDuration,
  groupClaudeCodeEvents,
} from "../lib/claudeCodeSessions";
import { fetchRecentEvents } from "../lib/eventApi";

export function ChatPage() {
  const [initial, setInitial] = useState<StreamEvent[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchRecentEvents({ type: "claude_code.hook" })
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

  if (initial === null) {
    return <HydratingState />;
  }
  return <ChatPageLoaded initialEvents={initial} />;
}

function ChatPageLoaded({ initialEvents }: { initialEvents: StreamEvent[] }) {
  const { events, connected, error } = useEventStream("/admin/events/stream", {
    initialEvents,
  });

  const sessions: SessionState[] = useMemo(() => groupClaudeCodeEvents(events), [events]);

  return (
    <div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 20,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <h1 style={{ fontSize: 20, fontWeight: 600 }}>Chat</h1>
          {connected ? (
            <Badge tone="green" variant="outline">
              <span
                style={{
                  display: "inline-block",
                  width: 6,
                  height: 6,
                  borderRadius: "50%",
                  background: "var(--green)",
                }}
              />
              connected
            </Badge>
          ) : (
            <Badge tone="yellow" variant="outline">
              <Spinner size={10} color="var(--yellow)" thickness={1.5} />
              reconnecting…
            </Badge>
          )}
        </div>
        <Badge tone="muted" variant="outline">
          {sessions.length} session{sessions.length === 1 ? "" : "s"}
        </Badge>
      </div>

      {error && (
        <Card
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            marginBottom: 12,
            padding: "10px 14px",
            color: "var(--red)",
            borderColor: "var(--red)",
            fontSize: 13,
          }}
          padded={false}
        >
          <AlertIcon size={14} />
          <span>{error}</span>
        </Card>
      )}

      {sessions.length === 0 ? (
        <EmptyState />
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {sessions.map((s) => (
            <SessionLinkRow key={s.sessionId} session={s} />
          ))}
        </div>
      )}
    </div>
  );
}

function SessionLinkRow({ session }: { session: SessionState }) {
  const duration = formatDuration(session.firstSeen, session.lastSeen);
  return (
    <Link
      to={`/chat/${encodeURIComponent(session.sessionId)}`}
      style={{ textDecoration: "none", color: "inherit" }}
    >
      <Card
        padded={false}
        style={{
          display: "flex",
          alignItems: "center",
          flexWrap: "wrap",
          gap: 10,
          padding: "12px 16px",
          cursor: "pointer",
        }}
      >
        <Badge tone="emerald" variant="outline" title={session.sessionId}>
          <span style={{ fontFamily: "var(--font-mono)" }}>{truncateId(session.sessionId)}</span>
        </Badge>
        {session.source === "resume" && (
          <Badge tone="purple" variant="outline">
            resumed
          </Badge>
        )}
        {session.cwd && (
          <span
            title={session.cwd}
            style={{
              color: "var(--fg-muted)",
              fontFamily: "var(--font-mono)",
              fontSize: 12,
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
              maxWidth: 480,
            }}
          >
            {session.cwd}
          </span>
        )}
        <Badge tone="muted">{session.events.length} hooks</Badge>
        <div
          style={{
            marginLeft: "auto",
            display: "flex",
            gap: 8,
            alignItems: "center",
            color: "var(--fg-subtle)",
            fontSize: 12,
            fontFamily: "var(--font-mono)",
          }}
        >
          <span>{formatTime(session.lastSeen)}</span>
          <Badge tone="muted" variant="outline">
            {duration}
          </Badge>
        </div>
      </Card>
    </Link>
  );
}

function truncateId(id: string, head = 6, tail = 4): string {
  if (id.length <= head + tail + 1) return id;
  return `${id.slice(0, head)}…${id.slice(-tail)}`;
}

function formatTime(timestamp: string): string {
  try {
    return new Date(timestamp).toLocaleTimeString();
  } catch {
    return timestamp;
  }
}

function EmptyState() {
  return (
    <Card>
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 6,
          padding: "36px 16px",
          color: "var(--fg-muted)",
          fontSize: 13,
          textAlign: "center",
        }}
      >
        <span style={{ fontWeight: 600, color: "var(--fg-default)" }}>
          No Claude Code sessions observed yet
        </span>
        <span style={{ color: "var(--fg-subtle)", maxWidth: 520 }}>
          Open Claude Code in a project running the plugin. Sessions will appear here as their
          transcripts stream in.
        </span>
      </div>
    </Card>
  );
}

function HydratingState() {
  return (
    <Card>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 10,
          padding: "36px 16px",
          color: "var(--fg-muted)",
          fontSize: 13,
        }}
      >
        <Spinner size={12} color="var(--fg-muted)" thickness={1.5} />
        <span>Loading recent sessions…</span>
      </div>
    </Card>
  );
}
