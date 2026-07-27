/**
 * Grouping/nesting contract for teammate ("subagent") sessions.
 *
 * Teammates are minted by cc-bridge as a synthetic `SessionStart` carrying the
 * new fields (`parent_session_id`, `teammate_role`, `teammate_label`) in the
 * hook payload — mirroring how the server broadcasts a hook (top-level camel
 * fields + a snake-cased `payload` echo of the raw body). These tests assert the
 * reducer builds a nestable session from that, and that clustering nests by the
 * explicit parent link (with the deprecated `team_name` path kept as fallback).
 */

import { describe, expect, test } from "bun:test";
import type { StreamEvent } from "../hooks/useEventStream";
import {
  clusterProjectSessions,
  groupClaudeCodeEvents,
  sessionKind,
  sessionTitle,
} from "./claudeCodeSessions";

const T0 = Date.parse("2026-07-03T10:00:00.000Z");
const at = (sec: number): string => new Date(T0 + sec * 1000).toISOString();

const LEAD = "9844376c-lead";

/** Shape an event the way the server broadcasts one: camel top-level + snake payload. */
function hook(
  id: string,
  sessionId: string,
  hookName: string,
  extra: Record<string, unknown> = {},
  when = at(0),
): StreamEvent {
  return {
    id,
    type: "claude_code.hook",
    timestamp: when,
    data: {
      sessionId,
      hookName,
      transcriptPath: extra.transcript_path,
      cwd: extra.cwd,
      payload: { session_id: sessionId, ...extra },
    },
  };
}

const leadStart = hook(
  "e1",
  LEAD,
  "SessionStart",
  { transcript_path: "/u/.claude/projects/proj/9844376c-lead.jsonl", cwd: "/u/proj", source: "startup" },
  at(0),
);

function teammateStart(id: string, agentId: string, label: string, role: string, when: string): StreamEvent {
  return hook(
    id,
    agentId,
    "SessionStart",
    {
      transcript_path: `/u/.claude/projects/proj/9844376c-lead/subagents/agent-${agentId}.jsonl`,
      cwd: "/u/proj",
      source: "teammate",
      parent_session_id: LEAD,
      team_name: "session-9844376c",
      teammate_role: role,
      teammate_label: label,
      agent_id: agentId,
    },
    when,
  );
}

describe("teammate nesting", () => {
  test("reducer mints a teammate session with parent link, role, and label", () => {
    const sessions = groupClaudeCodeEvents([
      leadStart,
      teammateStart("e2", "aimpl-118", "implementer-118", "sdlc:implementer", at(1)),
    ]);
    const mate = sessions.find((s) => s.sessionId === "aimpl-118");
    expect(mate).toBeDefined();
    expect(mate?.parentSessionId).toBe(LEAD);
    expect(mate?.role).toBe("sdlc:implementer");
    expect(mate?.label).toBe("implementer-118");
    expect(sessionKind(mate!)).toBe("teammate");
    expect(sessionTitle(mate!)).toBe("implementer-118");
  });

  test("clusters teammates under their lead, lead first", () => {
    const sessions = groupClaudeCodeEvents([
      leadStart,
      teammateStart("e2", "aimpl-118", "implementer-118", "sdlc:implementer", at(1)),
      teammateStart("e3", "aval-118", "validator-118", "sdlc:validator", at(2)),
    ]);
    const rows = clusterProjectSessions(sessions);
    expect(rows).toHaveLength(1);
    const team = rows[0];
    if (!team || team.kind !== "team") throw new Error("expected a team row");
    expect(team.leadId).toBe(LEAD);
    expect(team.sessions[0]?.sessionId).toBe(LEAD); // lead renders first
    expect(team.sessions.map((s) => s.sessionId).sort()).toEqual(
      ["9844376c-lead", "aimpl-118", "aval-118"].sort(),
    );
  });

  test("orphaned teammates (lead not present) still cluster, with no leadId", () => {
    const sessions = groupClaudeCodeEvents([
      teammateStart("e2", "aimpl-118", "implementer-118", "sdlc:implementer", at(1)),
      teammateStart("e3", "aval-118", "validator-118", "sdlc:validator", at(2)),
    ]);
    const rows = clusterProjectSessions(sessions);
    expect(rows).toHaveLength(1);
    const team = rows[0];
    if (!team || team.kind !== "team") throw new Error("expected a team row");
    expect(team.leadId).toBeUndefined();
    expect(team.sessions).toHaveLength(2);
  });

  test("legacy team_name grouping still works when there is no parent link", () => {
    const sessions = groupClaudeCodeEvents([
      hook("e1", "s-a", "TeammateIdle", { team_name: "session-legacy" }, at(0)),
      hook("e2", "s-b", "TeammateIdle", { team_name: "session-legacy" }, at(1)),
    ]);
    const rows = clusterProjectSessions(sessions);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.kind).toBe("team");
  });

  test("standalone sessions stay flat", () => {
    const rows = clusterProjectSessions(
      groupClaudeCodeEvents([
        hook("e1", "solo", "SessionStart", { transcript_path: "/u/.claude/projects/proj/solo.jsonl", cwd: "/u/proj" }, at(0)),
      ]),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.kind).toBe("session");
  });
});
