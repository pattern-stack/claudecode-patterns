/**
 * ToolCallPart — collapsible mono-typed card for a single assistant
 * tool_use. Header shows status (pending / ok / error) + tool name +
 * optional duration. Body (when expanded) shows the JSON input, the
 * output (if any), and an error block (if any).
 */

import { type ReactNode, useState } from "react";
import { Badge, type BadgeTone } from "../../atoms/Badge";
import { Spinner } from "../../atoms/Spinner";
import { WrenchIcon } from "../../atoms/icons";
import type { Part } from "../../../lib/transcript";

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
        fontFamily: "var(--font-mono)",
        fontSize: 11,
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
          fontFamily: "inherit",
          fontSize: "inherit",
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
        <span style={{ color: "var(--fg-default)" }}>{part.name}</span>
        {part.durationMs !== undefined && (
          <span style={{ color: "var(--fg-subtle)", marginLeft: "auto" }}>
            {Math.round(part.durationMs)}ms
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
            gap: 6,
            color: "var(--fg-muted)",
          }}
        >
          {hasArguments(part.arguments) && (
            <Section label="input">
              <pre style={sectionPreStyle}>{JSON.stringify(part.arguments, null, 2)}</pre>
            </Section>
          )}
          {part.result !== undefined && (
            <Section label="output">
              <pre style={sectionPreStyle}>{formatResult(part.result)}</pre>
            </Section>
          )}
          {part.error && (
            <Section label="error" tone="red">
              <pre style={{ ...sectionPreStyle, color: "var(--red)" }}>{part.error}</pre>
            </Section>
          )}
        </div>
      )}
    </div>
  );
}

const sectionPreStyle = {
  margin: 0,
  whiteSpace: "pre-wrap",
  wordBreak: "break-word",
  color: "var(--fg-muted)",
} as const;

function Section({
  label,
  tone = "muted",
  children,
}: {
  label: string;
  tone?: "muted" | "red";
  children: ReactNode;
}) {
  return (
    <div>
      <div
        style={{
          fontSize: 10,
          textTransform: "uppercase",
          letterSpacing: 0.5,
          color: tone === "red" ? "var(--red)" : "var(--fg-subtle)",
          marginBottom: 2,
        }}
      >
        {label}
      </div>
      {children}
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
