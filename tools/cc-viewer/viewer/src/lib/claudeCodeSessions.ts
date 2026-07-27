/**
 * Pure grouping helper: turns a flat feed of SSE stream events into a list
 * of Claude Code sessions keyed by `session_id`. Kept framework-free so it
 * can be unit-tested and memoized from the page.
 */

import type { StreamEvent } from "../hooks/useEventStream";

export interface SessionEvent {
  id: string;
  hookName: string;
  timestamp: string;
  toolName?: string;
  toolUseId?: string;
  runnerCorrelationId?: string;
  raw: Record<string, unknown>;
}

export interface SessionState {
  sessionId: string;
  firstSeen: string;
  lastSeen: string;
  cwd?: string;
  transcriptPath?: string;
  source?: string;
  /** When this session orchestrates a teammate swarm, the team it leads and the
   *  distinct teammate names it manages. Derived from `TeammateIdle` hooks,
   *  which fire in the *lead's* session (the `teammate_name` names a child, so
   *  this marks the session as a LEAD, never as a teammate itself).
   *  LEGACY: `team_name` is deprecated upstream (CC 2.1.178+); prefer
   *  `parentSessionId` for nesting and keep these only as a fallback. */
  teamName?: string;
  teammates?: string[];
  /** Set on a TEAMMATE session: the lead (parent) session it was spawned under.
   *  The authoritative nesting signal — minted by cc-bridge from the on-disk
   *  `<lead>/subagents/` layout, so it survives the `team_name` deprecation. */
  parentSessionId?: string;
  /** A teammate's agent type / role, e.g. "sdlc:implementer" (from its sidecar). */
  role?: string;
  /** A teammate's display name, e.g. "implementer-118" (from its sidecar). */
  label?: string;
  /** The session's first user prompt — used as a human-readable title, the way
   *  chat tools name a conversation by its opening message. */
  firstPrompt?: string;
  events: SessionEvent[];
  counts: Record<string, number>;
}

export const CLAUDE_CODE_EVENT_TYPE = "claude_code.hook";

function str(v: unknown): string | undefined {
  return typeof v === "string" && v.length > 0 ? v : undefined;
}

/**
 * Groups stream events into per-session buckets. Filters out anything that
 * isn't a `claude_code.hook` frame. Sorts sessions by most-recently-active
 * first (lastSeen desc). Within a session, events are kept in arrival order
 * (which matches timestamp order for a well-behaved stream).
 */
export function groupClaudeCodeEvents(events: StreamEvent[]): SessionState[] {
  const byId = new Map<string, SessionState>();

  for (const event of events) {
    if (event.type !== CLAUDE_CODE_EVENT_TYPE) continue;

    const data = event.data;
    const sessionId = str(data.session_id) ?? str(data.sessionId);
    if (!sessionId) continue;

    const hookName = str(data.hook_name) ?? str(data.hookName) ?? "unknown";
    const toolName = str(data.tool_name) ?? str(data.toolName);
    const toolUseId = str(data.tool_use_id) ?? str(data.toolUseId);
    const cwd = str(data.cwd);
    const transcriptPath = str(data.transcript_path) ?? str(data.transcriptPath);
    const timestamp = event.timestamp;
    const runnerCorrelationId = str(data.runner_correlation_id) ?? str(data.runnerCorrelationId);
    // Teammate identity lives in the nested hook payload, not the envelope top level.
    const payload = (data.payload ?? {}) as Record<string, unknown>;
    const teammateName = str(data.teammate_name) ?? str(payload.teammate_name);
    const teamName = str(data.team_name) ?? str(payload.team_name);
    // Teammate nesting fields, minted by cc-bridge on a synthetic SessionStart.
    const parentSessionId = str(data.parent_session_id) ?? str(payload.parent_session_id);
    const teammateRole = str(data.teammate_role) ?? str(payload.teammate_role);
    const teammateLabel = str(data.teammate_label) ?? str(payload.teammate_label);
    const prompt = hookName === "UserPromptSubmit" ? str(payload.prompt) ?? str(data.prompt) : undefined;

    let session = byId.get(sessionId);
    if (!session) {
      session = {
        sessionId,
        firstSeen: timestamp,
        lastSeen: timestamp,
        events: [],
        counts: {},
      };
      if (cwd) session.cwd = cwd;
      if (transcriptPath) session.transcriptPath = transcriptPath;
      byId.set(sessionId, session);
    }

    if (!session.cwd && cwd) session.cwd = cwd;
    if (!session.transcriptPath && transcriptPath) session.transcriptPath = transcriptPath;
    if (teamName) session.teamName = teamName;
    if (parentSessionId) session.parentSessionId = parentSessionId;
    if (teammateRole) session.role = teammateRole;
    if (teammateLabel) session.label = teammateLabel;
    if (teammateName) {
      (session.teammates ??= []).includes(teammateName) ||
        session.teammates.push(teammateName);
    }
    // Keep the earliest prompt as the session's title. Events arrive ascending,
    // so the first one we see wins.
    if (prompt && !session.firstPrompt) session.firstPrompt = prompt;
    if (hookName === "SessionStart") {
      const source = str(data.source);
      if (source) session.source = source;
    }
    if (timestamp < session.firstSeen) session.firstSeen = timestamp;
    if (timestamp > session.lastSeen) session.lastSeen = timestamp;

    const sessionEvent: SessionEvent = {
      id: event.id,
      hookName,
      timestamp,
      raw: data,
    };
    if (toolName) sessionEvent.toolName = toolName;
    if (toolUseId) sessionEvent.toolUseId = toolUseId;
    if (runnerCorrelationId) sessionEvent.runnerCorrelationId = runnerCorrelationId;

    session.events.push(sessionEvent);
    session.counts[hookName] = (session.counts[hookName] ?? 0) + 1;
  }

  // Order by creation time (firstSeen), NOT lastSeen: a session's position must
  // stay put as live events stream in, otherwise the list reshuffles constantly.
  // Newest-created first; sessionId as a stable tie-break.
  return Array.from(byId.values()).sort((a, b) => {
    if (a.firstSeen !== b.firstSeen) return a.firstSeen < b.firstSeen ? 1 : -1;
    return a.sessionId < b.sessionId ? -1 : a.sessionId > b.sessionId ? 1 : 0;
  });
}

/**
 * A Claude Code session's cwd drifts over its lifetime: subagents report their
 * own cwd, `isolation: "worktree"` spawns run under `.claude/worktrees/<name>`,
 * and the user may `cd` into subdirs. Grouping on the raw cwd therefore scatters
 * one logical project across many rows. These helpers collapse a session back to
 * the project it was *launched* from.
 *
 * The authoritative signal is `transcriptPath`: Claude Code keys each session's
 * transcript directory to its launch cwd and never moves it, so every session
 * launched from a repo shares one transcript project dir — even the ones whose
 * live cwd is a worktree or subdir. cwd is the display-friendly fallback.
 */

const WORKTREE_SEG = /\/\.claude\/worktrees\/[^/]+(?:\/.*)?$/;

/**
 * Collapse a `.../.claude/worktrees/<name>/...` path back to its repo root.
 * Leaves non-worktree paths untouched.
 */
export function stripWorktree(path: string): string {
  return path.replace(WORKTREE_SEG, "");
}

/** The worktree name if `cwd` lives inside one, else undefined. */
export function worktreeName(cwd: string | undefined): string | undefined {
  if (!cwd) return undefined;
  const m = cwd.match(/\/\.claude\/worktrees\/([^/]+)/);
  return m ? m[1] : undefined;
}

/**
 * What role a session played, inferred from its hook trail:
 *  - `lead`     — orchestrates a teammate swarm (emits ≥2 distinct teammate names)
 *  - `teammate` — a single swarm member (self-reports one teammate name)
 *  - `session`  — an ordinary top-level chat
 *
 * Note: there is deliberately no `subagent` kind. A `.claude/worktrees/agent-*`
 * cwd is just Claude Code's default worktree naming (regular chats, teammates,
 * and Agent spawns all land there), so it can't classify a session — and true
 * Agent-tool subagents share their parent's `session_id` and never appear as a
 * separate session anyway.
 */
export type SessionKind = "lead" | "teammate" | "session";

export function sessionKind(session: SessionState): SessionKind {
  // Explicit parent link is authoritative (survives the team_name deprecation).
  if (session.parentSessionId) return "teammate";
  // Legacy: infer from self-reported teammate names on TeammateIdle hooks.
  const n = session.teammates?.length ?? 0;
  if (n >= 2) return "lead";
  if (n === 1) return "teammate";
  return "session";
}

/** The teammate role name when this session is a single swarm member. */
export function teammateName(session: SessionState): string | undefined {
  return session.teammates?.length === 1 ? session.teammates[0] : undefined;
}

/**
 * Human title for a session, best-available first:
 *   teammate role name → swarm summary → first user prompt → worktree → short id.
 * This is what shows in the sidebar and lists instead of a raw session id.
 */
export function sessionTitle(session: SessionState): string {
  // A teammate's own sidecar label is the best name we have for it.
  if (session.label) return session.label;
  const mate = teammateName(session);
  if (mate) return mate;
  const n = session.teammates?.length ?? 0;
  if (n >= 2) return `swarm · ${n} agents`;
  if (session.firstPrompt) return truncate(session.firstPrompt, 52);
  const wt = worktreeName(session.cwd);
  if (wt) return wt.replace(/^agent-/, "");
  return session.sessionId.slice(0, 8);
}

function truncate(s: string, max: number): string {
  const clean = s.replace(/\s+/g, " ").trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

/** A human team label — swarms keyed as `session-<id>` read as "swarm". */
export function teamLabel(teamName: string | undefined): string | undefined {
  if (!teamName) return undefined;
  return teamName.startsWith("session-") ? "swarm" : teamName;
}

/** Basename of a project path, for display. */
export function projectLabel(cwd: string | undefined): string {
  if (!cwd) return "Unknown project";
  const trimmed = cwd.replace(/\/+$/, "");
  return trimmed.split("/").pop() || cwd;
}

export interface ProjectBucket {
  key: string;
  label: string;
  cwd?: string;
  sessions: SessionState[];
  /** Newest session-creation time in the bucket. Immutable per session, so a
   *  project's list position doesn't churn as live events arrive. */
  newestCreated: string;
}

/**
 * Group sessions by their launch project (`sessionProjectKey`). Worktree/subdir
 * sessions collapse onto the repo root. Ordered by newest-created session,
 * which is stable under live activity (firstSeen never changes).
 */
export function groupByProject(sessions: SessionState[]): ProjectBucket[] {
  const byKey = new Map<string, ProjectBucket>();
  for (const s of sessions) {
    const key = sessionProjectKey(s);
    const root = s.cwd ? stripWorktree(s.cwd) : undefined;
    const existing = byKey.get(key);
    if (existing) {
      existing.sessions.push(s);
      if (s.firstSeen > existing.newestCreated) existing.newestCreated = s.firstSeen;
      // Prefer the shortest root seen — closest to the true repo root.
      if (root && (!existing.cwd || root.length < existing.cwd.length)) {
        existing.cwd = root;
        existing.label = projectLabel(root);
      }
      continue;
    }
    byKey.set(key, {
      key,
      label: projectLabel(root),
      cwd: root,
      sessions: [s],
      newestCreated: s.firstSeen,
    });
  }
  return Array.from(byKey.values()).sort((a, b) =>
    a.newestCreated < b.newestCreated ? 1 : a.newestCreated > b.newestCreated ? -1 : 0,
  );
}

export type ProjectRow =
  | { kind: "session"; session: SessionState; activity: string }
  | { kind: "team"; teamName: string; leadId?: string; sessions: SessionState[]; activity: string };

/**
 * Within a project, fold a swarm — a lead plus its teammates — into one cluster;
 * standalone sessions stay flat. Nesting is by the explicit `parentSessionId`
 * link (a teammate points at its lead), which replaces the deprecated
 * `team_name` heuristic; `team_name` grouping is kept only as a fallback for
 * pre-fix sessions that predate the parent link. Stable creation-time order
 * (newest first), never reshuffling on live activity.
 */
export function clusterProjectSessions(sessions: SessionState[]): ProjectRow[] {
  const byId = new Map(sessions.map((s) => [s.sessionId, s] as const));
  const claimed = new Set<string>();

  // Primary: group teammates under the lead they name via parentSessionId.
  const groups = new Map<string, { lead?: SessionState; members: SessionState[] }>();
  for (const s of sessions) {
    if (!s.parentSessionId) continue;
    const g = groups.get(s.parentSessionId) ?? { members: [] };
    g.members.push(s);
    groups.set(s.parentSessionId, g);
    claimed.add(s.sessionId);
  }
  for (const [leadId, g] of groups) {
    const lead = byId.get(leadId);
    if (lead) {
      g.lead = lead;
      claimed.add(lead.sessionId);
    }
  }

  const rows: ProjectRow[] = [];
  for (const [leadId, g] of groups) {
    const members = g.members.slice().sort((a, b) => (a.firstSeen < b.firstSeen ? 1 : -1));
    const ordered = g.lead ? [g.lead, ...members] : members;
    const teamName = g.lead?.teamName ?? members.find((m) => m.teamName)?.teamName ?? leadId;
    const activity = ordered.reduce((a, s) => (s.firstSeen > a ? s.firstSeen : a), ordered[0]?.firstSeen ?? "");
    rows.push({ kind: "team", teamName, leadId: g.lead ? leadId : undefined, sessions: ordered, activity });
  }

  // Legacy fallback: sessions with a team_name but no parent link (pre-fix
  // swarms) still fold by team_name.
  const legacy = new Map<string, SessionState[]>();
  for (const s of sessions) {
    if (claimed.has(s.sessionId) || !s.teamName) continue;
    (legacy.get(s.teamName) ?? legacy.set(s.teamName, []).get(s.teamName)!).push(s);
    claimed.add(s.sessionId);
  }
  for (const [teamName, members] of legacy) {
    members.sort((a, b) => (a.firstSeen < b.firstSeen ? 1 : -1));
    rows.push({ kind: "team", teamName, sessions: members, activity: members[0]?.firstSeen ?? "" });
  }

  // Standalone sessions.
  for (const s of sessions) {
    if (claimed.has(s.sessionId)) continue;
    rows.push({ kind: "session", session: s, activity: s.firstSeen });
  }

  return rows.sort((a, b) => (a.activity < b.activity ? 1 : a.activity > b.activity ? -1 : 0));
}

/** True if the session emitted activity within `ms` of now. */
export function isSessionLive(session: SessionState, ms = 30_000): boolean {
  return Date.now() - new Date(session.lastSeen).getTime() < ms;
}

/**
 * The flattened project directory Claude Code stores a session's transcript
 * under (the segment beneath `.claude/projects/`), normalized so a session
 * launched *inside* a worktree (`<proj>--claude-worktrees-<name>`) folds back
 * onto its parent project. Returns undefined if the path isn't recognizable.
 */
export function projectKeyFromTranscript(transcriptPath: string | undefined): string | undefined {
  if (!transcriptPath) return undefined;
  const m = transcriptPath.match(/\/\.claude\/projects\/([^/]+)\//);
  const dir = m?.[1];
  if (!dir) return undefined;
  const w = dir.indexOf("--claude-worktrees-");
  return w >= 0 ? dir.slice(0, w) : dir;
}

/**
 * Stable grouping key for the project a session belongs to. Prefers the
 * transcript-derived key (survives cwd drift into worktrees/subdirs); falls
 * back to the worktree-stripped cwd when no transcript path is known.
 */
export function sessionProjectKey(session: SessionState): string {
  return (
    projectKeyFromTranscript(session.transcriptPath) ??
    (session.cwd ? stripWorktree(session.cwd) : "__no_cwd__")
  );
}

/**
 * Coarse category for hook names so the UI can colorize consistently.
 */
export type HookCategory =
  | "tool"
  | "permission"
  | "compact"
  | "session"
  | "stop"
  | "notification"
  | "other";

export function hookCategory(hookName: string): HookCategory {
  const n = hookName.toLowerCase();
  if (n === "stop" || n === "stopfailure" || n === "posttoolusefailure") {
    return "stop";
  }
  if (n.includes("tool")) return "tool";
  if (n.includes("permission")) return "permission";
  if (n.includes("compact")) return "compact";
  if (n === "sessionstart" || n === "sessionend" || n === "subagentstop") {
    return "session";
  }
  if (n.includes("notification") || n.includes("userpromptsubmit")) return "notification";
  return "other";
}

/**
 * Human-readable duration string for firstSeen→lastSeen.
 */
export function formatDuration(firstSeen: string, lastSeen: string): string {
  const ms = Math.max(0, new Date(lastSeen).getTime() - new Date(firstSeen).getTime());
  if (ms < 1000) return `${ms}ms`;
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  const rs = s % 60;
  if (m < 60) return `${m}m ${rs}s`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}h ${rm}m`;
}

/**
 * One-line summary derived from a hook event's raw payload.
 */
export function summarizeHook(event: SessionEvent): string {
  const d = event.raw;
  if (event.toolName) {
    const input = (d.tool_input ?? (d as Record<string, unknown>).toolInput) as
      | Record<string, unknown>
      | undefined;
    if (input) {
      const filePath = str(input.file_path) ?? str((input as Record<string, unknown>).filePath);
      if (filePath) return filePath;
      const command = str(input.command);
      if (command) return command.slice(0, 120);
      const pattern = str(input.pattern);
      if (pattern) return pattern;
      const url = str(input.url);
      if (url) return url;
    }
    return event.toolName;
  }
  const message = str(d.message);
  if (message) return message.slice(0, 120);
  const prompt = str(d.prompt) ?? str((d as Record<string, unknown>).user_prompt);
  if (prompt) return prompt.slice(0, 120);
  return "";
}
