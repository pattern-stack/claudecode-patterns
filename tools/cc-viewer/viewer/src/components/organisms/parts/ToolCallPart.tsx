/**
 * ToolCallPart — collapsible card for an assistant `tool_use` block.
 *
 * Header: disclosure caret + status badge (pending/ok/error) + wrench
 * icon + tool name + optional duration. Body: INPUT json + OUTPUT
 * (string or json) + ERROR (when present), each in its own CodeBlock.
 */

import { useState } from "react";
import type { Part } from "../../../lib/transcript";
import { Badge, type BadgeTone } from "../../atoms/Badge";
import { CodeBlock } from "../../atoms/CodeBlock";
import { Spinner } from "../../atoms/Spinner";
import { Text } from "../../atoms/Text";
import { WrenchIcon } from "../../atoms/icons";

type ToolCallPart = Extract<Part, { kind: "tool_call" }>;

interface ToolCallPartProps {
  part: ToolCallPart;
}

export function ToolCallPart({ part }: ToolCallPartProps) {
  const [expanded, setExpanded] = useState(false);
  const done = part.result !== undefined || part.error !== undefined;
  const stateTone: BadgeTone = part.error ? "red" : done ? "green" : "yellow";
  const stateIcon = part.error ? "✗" : done ? "✓" : "◯";

  return (
    <div
      style={{
        background: "var(--bg-canvas)",
        border: "1px solid var(--border-muted)",
        borderRadius: 6,
        overflow: "hidden",
      }}
    >
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        style={{
          width: "100%",
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "6px 10px",
          background: "transparent",
          border: "none",
          color: "var(--fg-default)",
          cursor: "pointer",
          fontFamily: "var(--font-mono)",
          fontSize: 11,
          textAlign: "left",
        }}
      >
        <span style={{ width: 12, display: "inline-block", textAlign: "center" }}>
          {expanded ? "▾" : "▸"}
        </span>
        {done ? (
          <Badge tone={stateTone} variant="outline" style={{ padding: "1px 6px" }}>
            {stateIcon}
          </Badge>
        ) : (
          <Spinner size={10} color="var(--yellow)" />
        )}
        <WrenchIcon size={11} />
        <Text size="xs" family="mono">{part.name}</Text>
        {part.durationMs !== undefined && (
          <span style={{ marginLeft: "auto" }}>
            <Text size="xs" tone="subtle" family="mono">
              {Math.round(part.durationMs)}ms
            </Text>
          </span>
        )}
      </button>
      {expanded && (
        <div
          style={{
            borderTop: "1px solid var(--border-muted)",
            padding: "8px 10px",
            display: "flex",
            flexDirection: "column",
            gap: 8,
          }}
        >
          {hasArguments(part.arguments) && (
            <CodeBlock label="input" copyable maxHeight={240}>
              {JSON.stringify(part.arguments, null, 2)}
            </CodeBlock>
          )}
          {part.result !== undefined && (
            <CodeBlock label="output" copyable maxHeight={400}>
              {formatResult(part.result)}
            </CodeBlock>
          )}
          {part.error && (
            <CodeBlock label="error" tone="danger" copyable>
              {part.error}
            </CodeBlock>
          )}
        </div>
      )}
    </div>
  );
}

function hasArguments(args: unknown): boolean {
  if (!args || typeof args !== "object") return false;
  return Object.keys(args as Record<string, unknown>).length > 0;
}

function formatResult(result: unknown): string {
  if (typeof result === "string") return result;
  try {
    return JSON.stringify(result, null, 2);
  } catch {
    return String(result);
  }
}
