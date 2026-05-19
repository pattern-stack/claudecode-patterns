/**
 * TurnCard organism — one chat card for a contiguous run of assistant
 * messages. Avatar + parts + summed token strip.
 */

import type { ChatMessage, Part } from "../../lib/transcript";
import { Text } from "../atoms/Text";
import { Avatar } from "../molecules/Avatar";
import { ErrorPart } from "./parts/ErrorPart";
import { TextPart } from "./parts/TextPart";
import { ThinkingPart } from "./parts/ThinkingPart";
import { ToolCallPart } from "./parts/ToolCallPart";

interface TurnCardProps {
  messages: ChatMessage[];
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
}

export function TurnCard({ messages, model, inputTokens, outputTokens }: TurnCardProps) {
  const partCount = messages.reduce((n, m) => n + m.parts.length, 0);
  if (partCount === 0) return null;

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
          border: "1px solid var(--border-muted)",
          borderRadius: 10,
          padding: "12px 14px",
          display: "flex",
          flexDirection: "column",
          gap: 10,
        }}
      >
        {messages.flatMap((m, mi) =>
          m.parts.map((part, pi) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: parts are append-only and stable by position
            <PartView key={`${mi}:${pi}`} part={part} />
          )),
        )}
        <TokenStrip model={model} inputTokens={inputTokens} outputTokens={outputTokens} />
      </div>
    </div>
  );
}

function PartView({ part }: { part: Part }) {
  switch (part.kind) {
    case "text":
      return <TextPart content={part.content} role="assistant" />;
    case "thinking":
      return <ThinkingPart content={part.content} complete={part.complete} />;
    case "tool_call":
      return <ToolCallPart part={part} />;
    case "error":
      return <ErrorPart message={part.message} errorType={part.errorType} />;
    default: {
      const _: never = part;
      void _;
      return null;
    }
  }
}

function TokenStrip({
  model,
  inputTokens,
  outputTokens,
}: {
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
}) {
  const segments: string[] = [];
  if (model) segments.push(model);
  if (inputTokens !== undefined) segments.push(`${inputTokens.toLocaleString()} in`);
  if (outputTokens !== undefined) segments.push(`${outputTokens.toLocaleString()} out`);
  if (segments.length === 0) return null;
  return (
    <div
      style={{
        marginTop: 2,
        borderTop: "1px dashed var(--border-muted)",
        paddingTop: 6,
      }}
    >
      <Text size="xs" tone="subtle" family="mono">
        {segments.join(" · ")}
      </Text>
    </div>
  );
}
