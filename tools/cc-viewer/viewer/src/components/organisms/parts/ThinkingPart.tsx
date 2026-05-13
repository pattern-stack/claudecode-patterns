/**
 * ThinkingPart — collapsible purple-accented panel for assistant
 * `thinking` blocks. Collapsed by default once complete (shows the first
 * line as a summary); click the header to expand.
 */

import { useState } from "react";
import { Spinner } from "../../atoms/Spinner";
import { SparkleIcon } from "../../atoms/icons";

interface ThinkingPartProps {
  content: string;
  complete: boolean;
}

export function ThinkingPart({ content, complete }: ThinkingPartProps) {
  // Default-open while incomplete (mirrors the chat-patterns TUI default).
  const [expanded, setExpanded] = useState(!complete);
  const firstLine = content.split(/\r?\n/, 1)[0] ?? "";
  const summary = firstLine.length > 80 ? `${firstLine.slice(0, 80)}…` : firstLine || "thinking";

  return (
    <div
      style={{
        background: "rgba(188, 140, 255, 0.06)",
        border: "1px solid var(--purple)",
        borderRadius: 6,
        padding: "6px 10px",
        fontSize: 12,
        color: "var(--purple)",
        fontFamily: "var(--font-mono)",
      }}
    >
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        style={{
          background: "transparent",
          border: "none",
          color: "inherit",
          cursor: "pointer",
          fontFamily: "inherit",
          fontSize: "inherit",
          padding: 0,
          display: "flex",
          alignItems: "center",
          gap: 6,
          width: "100%",
          textAlign: "left",
        }}
      >
        {complete ? (
          <span style={{ width: 12, display: "inline-block", textAlign: "center" }}>
            {expanded ? "▾" : "▸"}
          </span>
        ) : (
          <Spinner size={10} color="var(--purple)" />
        )}
        <SparkleIcon size={11} />
        <span style={{ color: "var(--fg-default)", fontWeight: 500 }}>thinking</span>
        {!expanded && (
          <span
            style={{
              color: "var(--fg-muted)",
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
              flex: 1,
            }}
          >
            {summary}
          </span>
        )}
      </button>
      {expanded && (
        <div
          style={{
            marginTop: 6,
            paddingLeft: 10,
            borderLeft: "2px solid var(--purple)",
            whiteSpace: "pre-wrap",
            color: "var(--fg-muted)",
            fontStyle: "italic",
            lineHeight: 1.55,
          }}
        >
          {content}
        </div>
      )}
    </div>
  );
}
