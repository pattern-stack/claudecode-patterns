/**
 * ChatSessionPage — full transcript view for one Claude Code session.
 *
 * Cold-loads via REST + live tails transcript_delta SSE for the path
 * param `:sessionId`. Renders the message thread in a fixed-height
 * ChatPanel so the inner scroll behaves independently of the outer
 * AppShell main column.
 */

import { Link, useParams } from "react-router-dom";
import { Badge } from "../components/atoms/Badge";
import { Card } from "../components/atoms/Card";
import { Spinner } from "../components/atoms/Spinner";
import { AlertIcon } from "../components/atoms/icons";
import { ChatPanel } from "../components/organisms/ChatPanel";
import { useTranscript } from "../hooks/useTranscript";

export function ChatSessionPage() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const decoded = sessionId ? decodeURIComponent(sessionId) : undefined;
  const { messages, loading, error, connected } = useTranscript(decoded);

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

      <div style={{ flex: 1, minHeight: 0 }}>
        <ChatPanel
          messages={messages}
          emptyLabel={loading ? "Loading transcript…" : "No transcript entries for this session."}
          expectingReply={connected}
        />
      </div>
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
