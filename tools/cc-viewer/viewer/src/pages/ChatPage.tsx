/**
 * ChatPage — top-level list of Claude Code sessions, grouped by project
 * (basename of cwd). Each row is a link to the session's transcript view.
 */

import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Badge } from "../components/atoms/Badge";
import { Card } from "../components/atoms/Card";
import { Spinner } from "../components/atoms/Spinner";
import { StatusDot } from "../components/atoms/StatusDot";
import { Text } from "../components/atoms/Text";
import { Timestamp } from "../components/atoms/Timestamp";
import { TruncateMid } from "../components/atoms/Truncate";
import { AlertIcon } from "../components/atoms/icons";
import { type StreamEvent, useEventStream } from "../hooks/useEventStream";
import {
  type SessionState,
  formatDuration,
  groupClaudeCodeEvents,
} from "../lib/claudeCodeSessions";
import { fetchRecentEvents } from "../lib/eventApi";

const LIVE_THRESHOLD_MS = 30_000;

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
  const projects = useMemo(() => groupByProject(sessions), [sessions]);

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
              <StatusDot tone="live" size={6} />
              connected
            </Badge>
          ) : (
            <Badge tone="yellow" variant="outline">
              <Spinner size={10} color="var(--yellow)" thickness={1.5} />
              reconnecting…
            </Badge>
          )}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <Badge tone="muted" variant="outline">
            {sessions.length} session{sessions.length === 1 ? "" : "s"}
          </Badge>
          <Badge tone="muted" variant="outline">
            {projects.length} project{projects.length === 1 ? "" : "s"}
          </Badge>
        </div>
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
          <Text size="sm" tone="danger">{error}</Text>
        </Card>
      )}

      {sessions.length === 0 ? (
        <EmptyState />
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
          {projects.map((p) => (
            <ProjectGroup key={p.key} project={p} />
          ))}
        </div>
      )}
    </div>
  );
}

interface ProjectBucket {
  key: string;
  label: string;
  cwd?: string;
  sessions: SessionState[];
  latestActivity: string;
}

function groupByProject(sessions: SessionState[]): ProjectBucket[] {
  const byKey = new Map<string, ProjectBucket>();
  for (const s of sessions) {
    const key = s.cwd ?? "__no_cwd__";
    const existing = byKey.get(key);
    if (existing) {
      existing.sessions.push(s);
      if (s.lastSeen > existing.latestActivity) existing.latestActivity = s.lastSeen;
      continue;
    }
    byKey.set(key, {
      key,
      label: projectLabel(s.cwd),
      cwd: s.cwd,
      sessions: [s],
      latestActivity: s.lastSeen,
    });
  }
  return Array.from(byKey.values()).sort((a, b) =>
    a.latestActivity < b.latestActivity ? 1 : -1,
  );
}

function projectLabel(cwd: string | undefined): string {
  if (!cwd) return "Unknown project";
  const trimmed = cwd.replace(/\/+$/, "");
  const last = trimmed.split("/").pop();
  return last || cwd;
}

function ProjectGroup({ project }: { project: ProjectBucket }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          gap: 10,
          padding: "0 4px",
        }}
      >
        <Text size="md" weight="semibold">{project.label}</Text>
        {project.cwd && (
          <Text size="xs" tone="subtle" family="mono" truncate style={{ maxWidth: 520 }}>
            {project.cwd}
          </Text>
        )}
        <span style={{ marginLeft: "auto" }}>
          <Text size="xs" tone="subtle" family="mono">
            {project.sessions.length} session{project.sessions.length === 1 ? "" : "s"}
          </Text>
        </span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        {project.sessions.map((s) => (
          <SessionLinkRow key={s.sessionId} session={s} />
        ))}
      </div>
    </div>
  );
}

function SessionLinkRow({ session }: { session: SessionState }) {
  const duration = formatDuration(session.firstSeen, session.lastSeen);
  const isLive = Date.now() - new Date(session.lastSeen).getTime() < LIVE_THRESHOLD_MS;
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
          padding: "10px 14px",
          cursor: "pointer",
        }}
      >
        <StatusDot
          tone={isLive ? "live" : "idle"}
          pulse={isLive}
          title={isLive ? "Active within the last 30 seconds" : undefined}
        />
        <Badge tone="emerald" variant="outline" title={session.sessionId}>
          <TruncateMid value={session.sessionId} />
        </Badge>
        {session.source === "resume" && (
          <Badge tone="purple" variant="outline">
            resumed
          </Badge>
        )}
        <Badge tone="muted">{session.events.length} hooks</Badge>
        <div
          style={{
            marginLeft: "auto",
            display: "flex",
            gap: 8,
            alignItems: "center",
          }}
        >
          <Timestamp iso={session.lastSeen} size="sm" />
          <Badge tone="muted" variant="outline">
            {duration}
          </Badge>
        </div>
      </Card>
    </Link>
  );
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
          textAlign: "center",
        }}
      >
        <Text weight="semibold">No Claude Code sessions observed yet</Text>
        <Text size="sm" tone="subtle" style={{ maxWidth: 520 }}>
          Open Claude Code in a project running the plugin. Sessions will appear here as their
          transcripts stream in.
        </Text>
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
        }}
      >
        <Spinner size={12} color="var(--fg-muted)" thickness={1.5} />
        <Text size="sm" tone="muted">Loading recent sessions…</Text>
      </div>
    </Card>
  );
}
