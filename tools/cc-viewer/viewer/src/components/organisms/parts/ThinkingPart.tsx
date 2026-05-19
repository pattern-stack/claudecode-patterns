/**
 * ThinkingPart — visual marker for an assistant `thinking` block.
 *
 * Three states:
 *   - streaming (not complete): spinner + "thinking…", default-expanded so
 *     incremental tokens are visible as they arrive.
 *   - complete with text: collapsible disclosure with a summary line
 *     in the header and full text in the body.
 *   - complete but empty: Claude's redacted/signature-only thinking. We
 *     can't show the text (the server never sent it), so render a small
 *     non-interactive chip — no caret, no fake "thinking" placeholder.
 */

import { useState } from "react";
import { Spinner } from "../../atoms/Spinner";
import { SparkleIcon } from "../../atoms/icons";

interface ThinkingPartProps {
  content: string;
  complete: boolean;
}

export function ThinkingPart({ content, complete }: ThinkingPartProps) {
  const hasBody = content.length > 0;

  if (complete && !hasBody) {
    return <RedactedThinkingChip />;
  }

  return <DisclosureThinking content={content} complete={complete} hasBody={hasBody} />;
}

function RedactedThinkingChip() {
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        padding: "3px 8px",
        borderRadius: 999,
        border: "1px dashed var(--purple)",
        background: "rgba(188, 140, 255, 0.06)",
        color: "var(--purple)",
        fontFamily: "var(--font-mono)",
        fontSize: 11,
        width: "fit-content",
      }}
      title="Claude generated thinking tokens here; the body is signature-only and not displayable."
    >
      <SparkleIcon size={10} />
      <span>thinking</span>
      <span style={{ color: "var(--fg-subtle)" }}>redacted</span>
    </div>
  );
}

function DisclosureThinking({
  content,
  complete,
  hasBody,
}: {
  content: string;
  complete: boolean;
  hasBody: boolean;
}) {
  // Default-open while streaming so live tokens are visible.
  const [expanded, setExpanded] = useState(!complete);
  const firstLine = content.split(/\r?\n/, 1)[0] ?? "";
  const summary = firstLine.length > 80 ? firstLine.slice(0, 80) + "…" : firstLine;

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
        {!expanded && hasBody && (
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
      {expanded && hasBody && (
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
