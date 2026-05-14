/**
 * ChatPanel organism — read-only chat thread.
 *
 * We are viewing someone else's Claude Code conversation, not authoring
 * one, so there is intentionally no input area. Auto-scrolls to the
 * bottom when new messages arrive.
 */

import { useEffect, useRef } from "react";
import type { ChatMessage } from "../../lib/transcript";
import { MessageRow } from "./MessageRow";

interface ChatPanelProps {
  messages: ChatMessage[];
  emptyLabel?: string;
}

export function ChatPanel({ messages, emptyLabel = "No messages yet." }: ChatPanelProps) {
  const bottomRef = useRef<HTMLDivElement>(null);

  // Scroll to bottom whenever message list identity changes (new entries
  // arrive via SSE or the snapshot loads). `messages` is re-derived by
  // useMemo, so identity = content has changed.
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

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
          gap: 20,
        }}
      >
        {messages.length === 0 ? (
          <EmptyState label={emptyLabel} />
        ) : (
          messages.map((m) => <MessageRow key={m.id} message={m} />)
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
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
