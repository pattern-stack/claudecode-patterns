/**
 * RoleBadge — one pill that says what a session *is*: a swarm lead, a teammate,
 * a subagent, or a plain chat. Shared by the chat list and the related-sessions
 * navigator so the visual language for roles stays identical across surfaces.
 */

import { Badge, type BadgeTone } from "../atoms/Badge";
import {
  type SessionState,
  sessionKind,
  teamLabel,
  teammateName,
  worktreeName,
} from "../../lib/claudeCodeSessions";

interface RoleVisual {
  icon: string;
  text: string;
  tone: BadgeTone;
  filled: boolean;
  title: string;
}

export function roleVisual(session: SessionState): RoleVisual {
  const kind = sessionKind(session);
  if (kind === "lead") {
    const n = session.teammates?.length ?? 0;
    return {
      icon: "👥",
      text: `${teamLabel(session.teamName) ?? "swarm"} · lead`,
      tone: "purple",
      filled: false,
      title: `Swarm lead — ${n} teammate${n === 1 ? "" : "s"}`,
    };
  }
  if (kind === "teammate") {
    return {
      icon: "🤝",
      text: teammateName(session) ?? "teammate",
      tone: "accent",
      filled: true,
      title: session.teamName ? `Teammate in ${teamLabel(session.teamName)}` : "Teammate",
    };
  }
  const wt = worktreeName(session.cwd);
  return {
    icon: "",
    text: "chat",
    tone: "emerald",
    filled: false,
    title: wt ? `Session · worktree ${wt}` : "Top-level session",
  };
}

export function RoleBadge({ session }: { session: SessionState }) {
  const v = roleVisual(session);
  return (
    <Badge tone={v.tone} variant={v.filled ? "filled" : "outline"} title={v.title}>
      {v.icon && <span style={{ marginRight: 4 }}>{v.icon}</span>}
      {v.text}
    </Badge>
  );
}
