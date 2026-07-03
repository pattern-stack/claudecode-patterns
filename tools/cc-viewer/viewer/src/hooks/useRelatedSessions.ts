/**
 * useRelatedSessions — from one session's vantage point, find the other
 * sessions that belong to the same launch project AND were active during this
 * session's lifetime. That scoping surfaces a run's swarm — teammates, spawned
 * worktrees, sibling leads — without dumping every historical chat in the repo.
 *
 * Grouping mirrors the ChatPage list (`sessionProjectKey`), so navigating from
 * a lead into a teammate (or vice-versa) stays inside the same project bucket.
 */

import { useMemo } from "react";
import { type SessionState, sessionProjectKey } from "../lib/claudeCodeSessions";
import { useSessionIndex } from "./useSessionIndex";

export interface RelatedSessions {
  /** False until the initial fetch resolves. */
  ready: boolean;
  /** This session, if found in the recent window. */
  self?: SessionState;
  /** Sibling sessions in the same project, creation-order (newest first). */
  siblings: SessionState[];
}

/** Two sessions overlap if either was active during the other's lifespan. */
function overlaps(a: SessionState, b: SessionState): boolean {
  return a.firstSeen <= b.lastSeen && a.lastSeen >= b.firstSeen;
}

export function useRelatedSessions(sessionId: string | undefined): RelatedSessions {
  const { sessions, ready } = useSessionIndex();

  return useMemo<RelatedSessions>(() => {
    if (!ready || !sessionId) {
      return { ready, siblings: [] };
    }
    const self = sessions.find((s) => s.sessionId === sessionId);
    if (!self) return { ready: true, siblings: [] };
    const key = sessionProjectKey(self);
    const siblings = sessions.filter(
      (s) =>
        s.sessionId !== sessionId &&
        sessionProjectKey(s) === key &&
        (overlaps(s, self) || (!!self.teamName && s.teamName === self.teamName)),
    );
    // groupClaudeCodeEvents already returns newest-created-first; filter preserves it.
    return { ready: true, self, siblings };
  }, [sessions, sessionId, ready]);
}
