/**
 * Minimal event shapes for the Claude Code viewer. The viewer only handles
 * one event type — `claude_code.hook` — so no wider union is needed.
 */

export interface BaseEvent {
  readonly type: string;
  readonly traceId: string;
  readonly runId: string;
  readonly spanId: string;
  readonly parentSpanId?: string;
  readonly timestamp: Date;
}

export const CLAUDE_CODE_HOOK_EVENTS = [
  "SessionStart",
  "InstructionsLoaded",
  "UserPromptSubmit",
  "PreToolUse",
  "PermissionRequest",
  "PermissionDenied",
  "PostToolUse",
  "PostToolUseFailure",
  "Notification",
  "SubagentStart",
  "SubagentStop",
  "TaskCreated",
  "TaskCompleted",
  "Stop",
  "StopFailure",
  "TeammateIdle",
  "ConfigChange",
  "CwdChanged",
  "FileChanged",
  "WorktreeCreate",
  "WorktreeRemove",
  "PreCompact",
  "PostCompact",
  "Elicitation",
  "ElicitationResult",
  "SessionEnd",
] as const;

export type ClaudeCodeHookName = (typeof CLAUDE_CODE_HOOK_EVENTS)[number];

export interface ClaudeCodeHookEvent extends BaseEvent {
  readonly type: "claude_code.hook";
  readonly hookName: ClaudeCodeHookName;
  readonly sessionId: string;
  readonly transcriptPath?: string;
  readonly cwd?: string;
  readonly permissionMode?: string;
  readonly toolName?: string;
  readonly toolInput?: unknown;
  readonly toolResponse?: unknown;
  readonly toolUseId?: string;
  readonly payload: Record<string, unknown>;
}

export function isClaudeCodeHookName(s: unknown): s is ClaudeCodeHookName {
  return typeof s === "string" && (CLAUDE_CODE_HOOK_EVENTS as readonly string[]).includes(s);
}
