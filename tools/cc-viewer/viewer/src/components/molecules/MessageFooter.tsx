/**
 * MessageFooter molecule — mono-typed pill under an assistant message
 * showing model + token usage. Hidden when nothing is known.
 */

import type { ChatMessage } from "../../lib/transcript";

interface MessageFooterProps {
  message: ChatMessage;
}

export function MessageFooter({ message }: MessageFooterProps) {
  const parts: string[] = [];
  if (message.model) parts.push(message.model);
  if (message.inputTokens !== undefined) parts.push(`${message.inputTokens} in`);
  if (message.outputTokens !== undefined) parts.push(`${message.outputTokens} out`);
  if (!parts.length) return null;
  return (
    <div
      style={{
        fontSize: 11,
        color: "var(--fg-subtle)",
        fontFamily: "var(--font-mono)",
      }}
    >
      {parts.join(" · ")}
    </div>
  );
}
