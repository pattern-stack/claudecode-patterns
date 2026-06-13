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

import { useEffect, useMemo, useRef, useState } from "react";
import { sendAgentInput } from "../../lib/eventApi";
import { type ChatGroup, groupTurns } from "../../lib/turns";
import type { ChatMessage } from "../../lib/transcript";
import { Button } from "../atoms/Button";
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
  /** Working directory of this session. When set, an input composer is
   * rendered that injects text into the live terminal pane in this cwd
   * (via ghostty-bridge). Omit for a purely read-only thread. */
  cwd?: string;
}

export function ChatPanel({
  messages,
  emptyLabel = "No messages yet.",
  expectingReply = false,
  cwd,
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
      {cwd && <Composer cwd={cwd} />}
    </div>
  );
}

/**
 * Input composer — types a message into the live terminal pane for `cwd`.
 *
 * Enter sends (paste + Enter so the agent submits); Shift+Enter inserts a
 * newline for multi-line prompts. Bracketed paste on the bridge keeps the
 * newlines from auto-submitting before the final Enter.
 */
function Composer({ cwd }: { cwd: string }) {
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    const value = text.trim();
    if (value === "" || sending) return;
    setSending(true);
    setError(null);
    try {
      await sendAgentInput({ cwd, text: value, submit: true });
      setText("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSending(false);
    }
  }

  return (
    <div
      style={{
        borderTop: "1px solid var(--border)",
        padding: 10,
        display: "flex",
        flexDirection: "column",
        gap: 6,
        background: "var(--bg-canvas)",
      }}
    >
      <div style={{ display: "flex", gap: 8, alignItems: "flex-end" }}>
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void send();
            }
          }}
          placeholder="Message this agent…  (Enter to send · Shift+Enter for newline)"
          rows={1}
          disabled={sending}
          style={{
            flex: 1,
            resize: "none",
            maxHeight: 140,
            minHeight: 38,
            padding: "9px 11px",
            fontFamily: "inherit",
            fontSize: 13,
            lineHeight: 1.5,
            color: "var(--fg-default)",
            background: "var(--bg-inset, var(--bg-surface))",
            border: "1px solid var(--border)",
            borderRadius: 6,
            outline: "none",
          }}
        />
        <Button variant="primary" size="md" disabled={sending || text.trim() === ""} onClick={() => void send()}>
          {sending ? "Sending…" : "Send"}
        </Button>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 8, minHeight: 14 }}>
        {error ? (
          <span style={{ color: "var(--red)", fontSize: 11 }}>{error}</span>
        ) : (
          <span style={{ color: "var(--fg-muted)", fontSize: 11, fontFamily: "var(--font-mono)" }}>
            → {cwd}
          </span>
        )}
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
