/**
 * ChatPage — top-level list of Claude Code sessions, grouped by the project
 * each session was launched from. Worktree, subagent, and subdir sessions
 * collapse onto their parent project (see `sessionProjectKey`) instead of
 * fragmenting into separate rows. Each row links to the session's transcript.
 */

import { Link } from "react-router-dom";
import { Badge } from "../components/atoms/Badge";
import { Card } from "../components/atoms/Card";
import { Spinner } from "../components/atoms/Spinner";
import { StatusDot } from "../components/atoms/StatusDot";
import { Text } from "../components/atoms/Text";
import { Timestamp } from "../components/atoms/Timestamp";
import { AlertIcon } from "../components/atoms/icons";
import { RoleBadge } from "../components/molecules/RoleBadge";
import { useSessionIndex } from "../hooks/useSessionIndex";
import {
  type ProjectBucket,
  type SessionState,
  clusterProjectSessions,
  formatDuration,
  sessionKind,
  sessionTitle,
  teamLabel,
  worktreeName,
} from "../lib/claudeCodeSessions";

const LIVE_THRESHOLD_MS = 30_000;

export function ChatPage() {
  const { sessions, projects, connected, ready, error } = useSessionIndex();

  if (!ready) {
    return <HydratingState />;
  }

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
          <h1 style={{ fontSize: 20, fontWeight: 600 }}>All activity</h1>
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
        {clusterProjectSessions(project.sessions).map((row) =>
          row.kind === "team" ? (
            <TeamCluster key={`team:${row.teamName}`} teamName={row.teamName} sessions={row.sessions} />
          ) : (
            <SessionLinkRow key={row.session.sessionId} session={row.session} />
          ),
        )}
      </div>
    </div>
  );
}

function TeamCluster({ teamName, sessions }: { teamName: string; sessions: SessionState[] }) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 6,
        paddingLeft: 10,
        borderLeft: "2px solid var(--border-muted)",
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, padding: "0 4px" }}>
        <Text size="xs" weight="semibold" tone="subtle">👥 {teamLabel(teamName)}</Text>
        <Text size="xs" tone="subtle" family="mono">
          {sessions.length} member{sessions.length === 1 ? "" : "s"}
        </Text>
      </div>
      {sessions.map((s) => (
        <SessionLinkRow key={s.sessionId} session={s} />
      ))}
    </div>
  );
}

function SessionLinkRow({ session }: { session: SessionState }) {
  const duration = formatDuration(session.firstSeen, session.lastSeen);
  const isLive = Date.now() - new Date(session.lastSeen).getTime() < LIVE_THRESHOLD_MS;
  const worktree = worktreeName(session.cwd);
  const kind = sessionKind(session);
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
        <span
          title={session.sessionId}
          style={{
            fontSize: 14,
            fontWeight: 500,
            color: "var(--fg-default)",
            maxWidth: 360,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
          }}
        >
          {sessionTitle(session)}
        </span>
        {kind !== "session" && <RoleBadge session={session} />}
        {session.source === "resume" && (
          <Badge tone="purple" variant="outline">
            resumed
          </Badge>
        )}
        {worktree && (
          <Badge tone="muted" variant="outline" title={`worktree: ${worktree}`}>
            ⑂ {worktree}
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
