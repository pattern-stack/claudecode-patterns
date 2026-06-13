/**
 * MessageRow organism — one chat-thread row.
 *
 * Layout: avatar on the leading edge (right for user, left for assistant)
 * + a column of ordered Parts. Assistant rows get a model/token footer
 * when usage is known.
 */

import type { ChatMessage, Part } from "../../lib/transcript";
import { Avatar } from "../molecules/Avatar";
import { MessageFooter } from "../molecules/MessageFooter";
import { ErrorPart } from "./parts/ErrorPart";
import { ImagePart } from "./parts/ImagePart";
import { TextPart } from "./parts/TextPart";
import { ThinkingPart } from "./parts/ThinkingPart";
import { ToolCallPart } from "./parts/ToolCallPart";

interface MessageRowProps {
  message: ChatMessage;
}

export function MessageRow({ message }: MessageRowProps) {
  const isUser = message.role === "user";
  return (
    <div
      style={{
        display: "flex",
        gap: 10,
        flexDirection: isUser ? "row-reverse" : "row",
        alignItems: "flex-start",
      }}
    >
      <Avatar role={message.role} />
      <div
        style={{
          maxWidth: "min(720px, 82%)",
          display: "flex",
          flexDirection: "column",
          gap: 8,
        }}
      >
        {message.parts.map((part, i) => (
          // biome-ignore lint/suspicious/noArrayIndexKey: parts are append-only and stable by position
          <PartView key={i} part={part} role={message.role} />
        ))}
        {!isUser && (message.inputTokens !== undefined || message.model) && (
          <MessageFooter message={message} />
        )}
      </div>
    </div>
  );
}

function PartView({ part, role }: { part: Part; role: ChatMessage["role"] }) {
  switch (part.kind) {
    case "text":
      return <TextPart content={part.content} role={role} />;
    case "thinking":
      return <ThinkingPart content={part.content} complete={part.complete} />;
    case "tool_call":
      return <ToolCallPart part={part} />;
    case "error":
      return <ErrorPart message={part.message} errorType={part.errorType} />;
    case "image":
      return <ImagePart src={part.src} alt={part.alt} caption={part.caption} />;
    default: {
      const _: never = part;
      void _;
      return null;
    }
  }
}
