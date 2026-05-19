/**
 * ChatPanel organism — read-only chat thread.
 *
 * Auto-scrolls to the bottom when new messages arrive. Assistant messages
 * (single or a contiguous run from the same logical turn) render as a
 * TurnCard; user messages render as a single bubble via MessageRow.
 *
 * When `expectingReply` is true, a `WaitingTurn` is rendered at the
 * bottom in two situations:
 *   - last group is a user message → Claude hasn't started replying yet
 *   - last group is an assistant turn whose final message has a tool_call
 *     awaiting its result → Claude is mid-turn, running a tool
 */

import { useEffect, useMemo, useRef } from "react";
import { type ChatGroup, groupTurns } from "../../lib/turns";
import type { ChatMessage } from "../../lib/transcript";
import { Avatar } from "../molecules/Avatar";
import { WaitingIndicator } from "../molecules/WaitingIndicator";
import { MessageRow } from "./MessageRow";
import { TurnCard } from "./TurnCard";

interface ChatPanelProps {
  messages: ChatMessage[];
  emptyLabel?: string;
  /** When true, render a waiting indicator if the thread appears to be
   * waiting on Claude (post-user-message or mid-tool). */
  expectingReply?: boolean;
}

export function ChatPanel({
  messages,
  emptyLabel = "No messages yet.",
  expectingReply = false,
}: ChatPanelProps) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const groups = useMemo(() => groupTurns(messages), [messages]);

  const waitingFor = expectingReply ? deriveWaitingState(groups) : null;

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [groups]);

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        minHeight: 0,
        border: "1px solid var(--border)",
        borderRadius: 8,
        background: "var(--bg-surface)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          flex: 1,
          minHeight: 0,
          overflowY: "auto",
          padding: 20,
          display: "flex",
          flexDirection: "column",
          gap: 16,
        }}
      >
        {groups.length === 0 ? (
          <EmptyState label={emptyLabel} />
        ) : (
          groups.map((g) => <GroupView key={groupKey(g)} group={g} />)
        )}
        {waitingFor && <WaitingTurn label={waitingFor} />}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}

/**
 * Decide whether to surface a "Claude is working" indicator and what to
 * label it with.
 *
 * Returns null if the thread looks settled (last group is an assistant
 * turn that already contains a final text part, or there are no groups
 * at all).
 */
function deriveWaitingState(groups: ChatGroup[]): string | null {
  const last = groups[groups.length - 1];
  if (!last) return null;

  if (last.kind === "single") {
    if (last.message.role === "user") return "thinking…";
    return null;
  }

  // Assistant turn. Inspect the last assistant message in the run.
  const lastMsg = last.messages[last.messages.length - 1];
  if (!lastMsg) return null;
  const parts = lastMsg.parts;
  const lastPart = parts[parts.length - 1];
  if (!lastPart) return null;

  // Tool call that hasn't been resolved yet → Claude is running a tool.
  if (lastPart.kind === "tool_call" && lastPart.result === undefined && !lastPart.error) {
    return `running ${lastPart.name}…`;
  }

  // Thinking still streaming (incomplete) → Claude is thinking.
  if (lastPart.kind === "thinking" && !lastPart.complete) {
    return "thinking…";
  }

  return null;
}

function GroupView({ group }: { group: ChatGroup }) {
  if (group.kind === "single") {
    return <MessageRow message={group.message} />;
  }
  return (
    <TurnCard
      messages={group.messages}
      model={group.model}
      inputTokens={group.inputTokens}
      outputTokens={group.outputTokens}
    />
  );
}

function WaitingTurn({ label }: { label: string }) {
  return (
    <div
      style={{
        display: "flex",
        gap: 10,
        alignItems: "flex-start",
      }}
    >
      <Avatar role="assistant" />
      <div
        style={{
          flex: 1,
          minWidth: 0,
          background: "var(--bg-surface)",
          border: "1px dashed var(--border)",
          borderRadius: 10,
          padding: "12px 14px",
        }}
      >
        <WaitingIndicator label={label} />
      </div>
    </div>
  );
}

function groupKey(g: ChatGroup): string {
  return g.kind === "single" ? g.message.id : g.id;
}

function EmptyState({ label }: { label: string }) {
  return (
    <div
      style={{
        textAlign: "center",
        color: "var(--fg-muted)",
        fontSize: 13,
        padding: "32px 16px",
      }}
    >
      {label}
    </div>
  );
}
