/**
 * TextPart — markdown-rendered text bubble. User vs assistant differ by
 * background (hover vs canvas). Optional trailing blinking cursor is
 * displayed when this is the last part of a still-streaming message.
 */

import { Cursor } from "../../atoms/Cursor";
import { Markdown } from "../../molecules/Markdown";

interface TextPartProps {
  content: string;
  role: "user" | "assistant";
  showCursor?: boolean;
}

export function TextPart({ content, role, showCursor = false }: TextPartProps) {
  const isUser = role === "user";
  return (
    <div
      style={{
        background: isUser ? "var(--bg-surface-hover)" : "var(--bg-canvas)",
        border: `1px solid ${isUser ? "var(--border-muted)" : "var(--border)"}`,
        borderRadius: 8,
        padding: "10px 14px",
        fontSize: 13,
        lineHeight: 1.55,
        color: "var(--fg-default)",
        wordBreak: "break-word",
      }}
    >
      <Markdown>{content}</Markdown>
      {showCursor && <Cursor />}
    </div>
  );
}
