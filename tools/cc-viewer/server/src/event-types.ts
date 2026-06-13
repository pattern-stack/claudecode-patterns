/**
 * Event shapes for the Claude Code viewer. Two event classes today:
 *   - `claude_code.hook`             — control-plane lifecycle + tool calls
 *   - `claude_code.transcript_delta` — data-plane assistant text + thinking
 *                                      forwarded by cc-bridge from the
 *                                      session JSONL transcript.
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

/**
 * One JSONL line forwarded by cc-bridge. `entry` is the parsed line, kept
 * unmodified so the viewer-side reducer owns the chat mapping. Dedupe key
 * on the wire and in storage is `(sessionId, lineUuid)`.
 */
export interface TranscriptDeltaEvent extends BaseEvent {
  readonly type: "claude_code.transcript_delta";
  readonly sessionId: string;
  readonly lineUuid: string;
  readonly lineIndex: number;
  readonly transcriptPath?: string;
  readonly entry: Record<string, unknown>;
}

export const TRANSCRIPT_DELTA_TYPE = "claude_code.transcript_delta" as const;

/** Broadcast when the slash-command catalog sources change on disk. */
export const COMMANDS_CHANGED_TYPE = "cc_viewer.commands_changed" as const;
