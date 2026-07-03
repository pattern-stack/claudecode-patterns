/**
 * SessionSidebar — collapsible project tree (Option A).
 *
 * Projects are collapsible headers with a live-count + status dot; their
 * sessions nest underneath, and a swarm lead expands to reveal its teammates.
 * A global "All activity" entry and a Logs link sit above the tree. One click
 * routes into a session's transcript; the active row stays highlighted.
 */

import { useEffect, useMemo, useState } from "react";
import { NavLink, useLocation } from "react-router-dom";
import { StatusDot } from "../atoms/StatusDot";
import { Text } from "../atoms/Text";
import { ChevronRightIcon } from "../atoms/icons";
import {
  type ProjectBucket,
  type SessionKind,
  type SessionState,
  clusterProjectSessions,
  isSessionLive,
  sessionKind,
  sessionTitle,
  teammateName,
  worktreeName,
} from "../../lib/claudeCodeSessions";
import { useSessionIndex } from "../../hooks/useSessionIndex";

const LS_COLLAPSED = "cc-viewer.sidebar.collapsed";

export function SessionSidebar() {
  const { projects, connected, ready } = useSessionIndex();
  const location = useLocation();
  const activeId = useMemo(() => {
    const m = location.pathname.match(/^\/chat\/([^/]+)/);
    return m?.[1] ? decodeURIComponent(m[1]) : undefined;
  }, [location.pathname]);

  const [query, setQuery] = useState("");
  const [collapsed, setCollapsed] = useState<Set<string>>(() => loadCollapsed());

  // Auto-expand the project that owns the active session.
  useEffect(() => {
    if (!activeId) return;
    const owner = projects.find((p) => p.sessions.some((s) => s.sessionId === activeId));
    if (owner && collapsed.has(owner.key)) {
      setCollapsed((prev) => {
        const next = new Set(prev);
        next.delete(owner.key);
        return next;
      });
    }
  }, [activeId, projects]); // eslint-disable-line react-hooks/exhaustive-deps

  const toggle = (key: string) =>
    setCollapsed((prev) => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      saveCollapsed(next);
      return next;
    });

  const q = query.trim().toLowerCase();
  const filtered = useMemo(() => (q ? projects.map((p) => filterProject(p, q)).filter(Boolean) as ProjectBucket[] : projects), [projects, q]);

  return (
    <nav
      style={{
        width: 280,
        background: "var(--bg-surface)",
        borderRight: "1px solid var(--border)",
        flexShrink: 0,
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        overflow: "hidden",
      }}
    >
      <div style={{ padding: "16px 16px 10px", display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: "-0.01em" }}>cc-viewer</span>
        <StatusDot
          tone={connected ? "live" : "idle"}
          pulse={connected}
          title={connected ? "Live" : "Reconnecting…"}
        />
      </div>

      <div style={{ padding: "0 12px 8px" }}>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search sessions…"
          style={{
            width: "100%",
            boxSizing: "border-box",
            padding: "6px 10px",
            fontSize: 13,
            background: "var(--bg-inset, rgba(0,0,0,0.15))",
            color: "var(--fg-default)",
            border: "1px solid var(--border)",
            borderRadius: 7,
            outline: "none",
          }}
        />
      </div>

      <div style={{ padding: "0 8px 6px" }}>
        <TopLink to="/chat" label="All activity" exact />
        <TopLink to="/logs" label="Logs" />
      </div>

      <div style={{ borderTop: "1px solid var(--border)", margin: "2px 0" }} />

      <div style={{ flex: 1, overflowY: "auto", padding: "6px 8px 16px" }}>
        {!ready ? (
          <Hint text="Loading sessions…" />
        ) : filtered.length === 0 ? (
          <Hint text={q ? "No matches." : "No sessions yet."} />
        ) : (
          filtered.map((p) => (
            <ProjectNode
              key={p.key}
              project={p}
              collapsed={collapsed.has(p.key) && !q}
              onToggle={() => toggle(p.key)}
              activeId={activeId}
            />
          ))
        )}
      </div>
    </nav>
  );
}

function TopLink({ to, label, exact }: { to: string; label: string; exact?: boolean }) {
  return (
    <NavLink
      to={to}
      end={exact}
      style={({ isActive }) => ({
        display: "flex",
        alignItems: "center",
        padding: "6px 10px",
        fontSize: 13,
        borderRadius: 7,
        textDecoration: "none",
        color: isActive ? "var(--fg-default)" : "var(--fg-muted)",
        background: isActive ? "var(--bg-surface-hover)" : "transparent",
      })}
    >
      {label}
    </NavLink>
  );
}

function ProjectNode({
  project,
  collapsed,
  onToggle,
  activeId,
}: {
  project: ProjectBucket;
  collapsed: boolean;
  onToggle: () => void;
  activeId?: string;
}) {
  const rows = useMemo(() => clusterProjectSessions(project.sessions), [project.sessions]);
  const liveCount = project.sessions.filter((s) => isSessionLive(s)).length;

  return (
    <div style={{ marginBottom: 2 }}>
      <button
        type="button"
        onClick={onToggle}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          width: "100%",
          padding: "6px 8px",
          background: "transparent",
          border: "none",
          cursor: "pointer",
          color: "var(--fg-default)",
          textAlign: "left",
        }}
      >
        <ChevronRightIcon
          size={12}
          style={{
            transform: collapsed ? "none" : "rotate(90deg)",
            transition: "transform 120ms",
            opacity: 0.6,
            flexShrink: 0,
          }}
        />
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            flex: 1,
          }}
          title={project.cwd}
        >
          {project.label}
        </span>
        {liveCount > 0 ? (
          <span style={{ display: "flex", alignItems: "center", gap: 4 }}>
            <StatusDot tone="live" pulse size={6} />
            <Text size="xs" tone="subtle" family="mono">{liveCount}</Text>
          </span>
        ) : (
          <Text size="xs" tone="subtle" family="mono">{project.sessions.length}</Text>
        )}
      </button>

      {!collapsed && (
        <div style={{ marginLeft: 6, borderLeft: "1px solid var(--border-muted)", paddingLeft: 6 }}>
          {rows.map((row) =>
            row.kind === "team" ? (
              <SwarmNode key={`team:${row.teamName}`} sessions={row.sessions} activeId={activeId} />
            ) : (
              <SessionRow key={row.session.sessionId} session={row.session} activeId={activeId} />
            ),
          )}
        </div>
      )}
    </div>
  );
}

/** A swarm cluster: the lead row expands to reveal its teammates. */
function SwarmNode({ sessions, activeId }: { sessions: SessionState[]; activeId?: string }) {
  const lead = sessions.find((s) => sessionKind(s) === "lead") ?? sessions[0];
  const activeInside = sessions.some((s) => s.sessionId === activeId);
  const [open, setOpen] = useState(activeInside);
  useEffect(() => {
    if (activeInside) setOpen(true);
  }, [activeInside]);
  if (!lead) return null;
  const members = sessions.filter((s) => s !== lead);

  return (
    <div>
      <SessionRow
        session={lead}
        activeId={activeId}
        expandable={members.length > 0}
        open={open}
        onExpand={() => setOpen((o) => !o)}
      />
      {open &&
        members.map((s) => (
          <SessionRow key={s.sessionId} session={s} activeId={activeId} indent />
        ))}
    </div>
  );
}

function SessionRow({
  session,
  activeId,
  indent,
  expandable,
  open,
  onExpand,
}: {
  session: SessionState;
  activeId?: string;
  indent?: boolean;
  expandable?: boolean;
  open?: boolean;
  onExpand?: () => void;
}) {
  const kind = sessionKind(session);
  const active = session.sessionId === activeId;
  const live = isSessionLive(session);
  const title = sessionTitle(session);
  const dot = ROLE_DOT[kind];

  return (
    <div style={{ display: "flex", alignItems: "center" }}>
      {expandable ? (
        <button
          type="button"
          onClick={onExpand}
          title={open ? "Collapse teammates" : "Show teammates"}
          style={{
            background: "transparent",
            border: "none",
            cursor: "pointer",
            padding: "0 2px",
            display: "flex",
            alignItems: "center",
          }}
        >
          <ChevronRightIcon
            size={11}
            style={{ transform: open ? "rotate(90deg)" : "none", opacity: 0.55 }}
          />
        </button>
      ) : (
        <span style={{ width: indent ? 22 : 15, flexShrink: 0 }} />
      )}
      <NavLink
        to={`/chat/${encodeURIComponent(session.sessionId)}`}
        title={title}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 7,
          flex: 1,
          minWidth: 0,
          padding: "5px 8px",
          borderRadius: 7,
          textDecoration: "none",
          fontSize: 13,
          color: active ? "var(--fg-default)" : "var(--fg-muted)",
          background: active ? "var(--bg-surface-hover)" : "transparent",
        }}
      >
        <span
          title={dot.label}
          style={{
            width: 7,
            height: 7,
            borderRadius: "50%",
            flexShrink: 0,
            background: live ? "var(--green)" : dot.color,
            boxShadow: live ? "0 0 0 2px color-mix(in srgb, var(--green) 30%, transparent)" : "none",
          }}
        />
        <span
          style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1 }}
        >
          {title}
        </span>
      </NavLink>
    </div>
  );
}

const ROLE_DOT: Record<SessionKind, { color: string; label: string }> = {
  lead: { color: "var(--purple)", label: "Swarm lead" },
  teammate: { color: "var(--accent)", label: "Teammate" },
  session: { color: "var(--fg-subtle)", label: "Session" },
};

function filterProject(p: ProjectBucket, q: string): ProjectBucket | null {
  if (p.label.toLowerCase().includes(q)) return p;
  const sessions = p.sessions.filter(
    (s) =>
      s.sessionId.toLowerCase().includes(q) ||
      (teammateName(s)?.toLowerCase().includes(q) ?? false) ||
      (s.firstPrompt?.toLowerCase().includes(q) ?? false) ||
      (worktreeName(s.cwd)?.toLowerCase().includes(q) ?? false),
  );
  return sessions.length ? { ...p, sessions } : null;
}

function Hint({ text }: { text: string }) {
  return (
    <div style={{ padding: "10px 12px" }}>
      <Text size="xs" tone="subtle">{text}</Text>
    </div>
  );
}

function loadCollapsed(): Set<string> {
  try {
    const raw = localStorage.getItem(LS_COLLAPSED);
    return raw ? new Set(JSON.parse(raw) as string[]) : new Set();
  } catch {
    return new Set();
  }
}

function saveCollapsed(set: Set<string>) {
  try {
    localStorage.setItem(LS_COLLAPSED, JSON.stringify([...set]));
  } catch {
    /* ignore quota / private-mode errors */
  }
}
