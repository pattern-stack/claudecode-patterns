/**
 * ChatSessionPage — full transcript view for one Claude Code session.
 *
 * Cold-loads via REST + live tails transcript_delta SSE for the path
 * param `:sessionId`. Renders the message thread in a fixed-height
 * ChatPanel so the inner scroll behaves independently of the outer
 * AppShell main column.
 */

import { type ReactNode, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { Badge } from "../components/atoms/Badge";
import { Card } from "../components/atoms/Card";
import { Spinner } from "../components/atoms/Spinner";
import { AlertIcon } from "../components/atoms/icons";
import { Text } from "../components/atoms/Text";
import { ChatPanel } from "../components/organisms/ChatPanel";
import { useRelatedSessions } from "../hooks/useRelatedSessions";
import { useTranscript } from "../hooks/useTranscript";
import { type SessionState, sessionKind, sessionTitle } from "../lib/claudeCodeSessions";
import { fetchSessionCwd } from "../lib/eventApi";

export function ChatSessionPage() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const decoded = sessionId ? decodeURIComponent(sessionId) : undefined;
  const { messages, loading, error, connected } = useTranscript(decoded);
  const { siblings } = useRelatedSessions(decoded);

  // Resolve the session's cwd so the composer can target the live pane.
  const [cwd, setCwd] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (!decoded) return;
    let alive = true;
    fetchSessionCwd(decoded)
      .then((c) => {
        if (alive) setCwd(c ?? undefined);
      })
      .catch(() => {
        /* composer just stays hidden if cwd can't be resolved */
      });
    return () => {
      alive = false;
    };
  }, [decoded]);

  if (!decoded) {
    return <ErrorBanner message="No session id in URL." />;
  }

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 12,
        // Fill main area; ChatPanel owns its inner scroll.
        height: "calc(100vh - 48px)",
        minHeight: 0,
        // Center the thread in a reading-width column so messages don't
        // sprawl across wide screens with a whitespace gulf between
        // user (right-aligned) and assistant (left-aligned) rows.
        width: "100%",
        maxWidth: 880,
        marginInline: "auto",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          flexWrap: "wrap",
        }}
      >
        <Link to="/chat" style={{ color: "var(--fg-muted)", fontSize: 13 }}>
          ← All chats
        </Link>
        <h1 style={{ fontSize: 18, fontWeight: 600 }}>Session</h1>
        <Badge tone="emerald" variant="outline" title={decoded}>
          <span style={{ fontFamily: "var(--font-mono)" }}>{truncateId(decoded)}</span>
        </Badge>
        {loading ? (
          <Badge tone="muted" variant="outline">
            <Spinner size={10} color="var(--fg-muted)" thickness={1.5} />
            loading…
          </Badge>
        ) : connected ? (
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
            live
          </Badge>
        ) : (
          <Badge tone="yellow" variant="outline">
            <Spinner size={10} color="var(--yellow)" thickness={1.5} />
            reconnecting…
          </Badge>
        )}
        <Badge tone="muted">
          {messages.length} message{messages.length === 1 ? "" : "s"}
        </Badge>
      </div>

      {error && <ErrorBanner message={error} />}

      {siblings.length > 0 && <RelatedSessions siblings={siblings} currentId={decoded} />}

      <div style={{ flex: 1, minHeight: 0 }}>
        <ChatPanel
          messages={messages}
          emptyLabel={loading ? "Loading transcript…" : "No transcript entries for this session."}
          expectingReply={connected}
          cwd={cwd}
        />
      </div>
    </div>
  );
}

/**
 * Compact navigator for the sessions related to this one — the swarm lead, its
 * teammates, and other overlapping chats. Grouped by role so a busy run reads as
 * structure. Each chip is titled by role name / first prompt, never a raw id.
 */
const OTHER_CAP = 14;

function RelatedSessions({ siblings }: { siblings: SessionState[]; currentId: string }) {
  const leads: SessionState[] = [];
  const teammates: SessionState[] = [];
  const others: SessionState[] = [];
  for (const s of siblings) {
    const kind = sessionKind(s);
    if (kind === "lead") leads.push(s);
    else if (kind === "teammate") teammates.push(s);
    else others.push(s);
  }

  return (
    <Card padded={false} style={{ padding: "12px 14px" }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 10 }}>
        <Text size="xs" weight="semibold" tone="subtle">RELATED SESSIONS</Text>
        <Text size="xs" tone="subtle" family="mono">{siblings.length}</Text>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <ChipSection label="Lead" sessions={leads} />
        <ChipSection label="Teammates" sessions={teammates} />
        <ChipSection label="Other" sessions={others} cap={OTHER_CAP} muted />
      </div>
    </Card>
  );
}

function ChipSection({
  label,
  sessions,
  muted,
  cap,
}: {
  label: string;
  sessions: SessionState[];
  muted?: boolean;
  cap?: number;
}) {
  if (sessions.length === 0) return null;
  const shown = cap ? sessions.slice(0, cap) : sessions;
  const overflow = sessions.length - shown.length;
  return (
    <ChipRow label={label}>
      {shown.map((s) => (
        <Link
          key={s.sessionId}
          to={`/chat/${encodeURIComponent(s.sessionId)}`}
          style={{ textDecoration: "none", opacity: muted ? 0.8 : 1 }}
          title={`${sessionTitle(s)} · ${s.sessionId}`}
        >
          <Badge tone={muted ? "muted" : undefined} variant="outline">
            {sessionTitle(s)}
          </Badge>
        </Link>
      ))}
      {overflow > 0 && (
        <Text size="xs" tone="subtle" style={{ paddingTop: 4 }}>
          +{overflow} more
        </Text>
      )}
    </ChipRow>
  );
}

function ChipRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
      <Text
        size="xs"
        tone="subtle"
        style={{ minWidth: 74, paddingTop: 3, flexShrink: 0, textAlign: "right" }}
      >
        {label}
      </Text>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>{children}</div>
    </div>
  );
}

function ErrorBanner({ message }: { message: string }) {
  return (
    <Card
      padded={false}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "10px 14px",
        color: "var(--red)",
        borderColor: "var(--red)",
        fontSize: 13,
      }}
    >
      <AlertIcon size={14} />
      <span>{message}</span>
    </Card>
  );
}

function truncateId(id: string, head = 6, tail = 4): string {
  if (id.length <= head + tail + 1) return id;
  return `${id.slice(0, head)}…${id.slice(-tail)}`;
}
