/**
 * CodeBlock atom — multi-line code surface. Replaces the various
 * hand-rolled `<pre>` and flat-`<code>` patterns scattered across the
 * tool-call body, JSON viewer, and markdown renderer.
 *
 * Wraps content in a real `<pre><code>` pair (semantic + accessible),
 * preserves whitespace, breaks long lines, and shows a tiny copy button
 * in the top-right when `copyable` is on. An optional `label` prop
 * renders a small badge in the header (e.g. "input", "output", "json").
 */

import { type CSSProperties, type ReactNode, useState } from "react";

interface CodeBlockProps {
  children: ReactNode;
  /** A label shown in the small header row (e.g. "input", "output"). */
  label?: string;
  /** Render a copy-to-clipboard button. Only works for string `children`. */
  copyable?: boolean;
  /** Constrain height; overflow scrolls. */
  maxHeight?: number;
  tone?: "default" | "danger";
  style?: CSSProperties;
}

export function CodeBlock({
  children,
  label,
  copyable = false,
  maxHeight,
  tone = "default",
  style,
}: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const borderColor = tone === "danger" ? "var(--red)" : "var(--border-muted)";
  const textColor = tone === "danger" ? "var(--red)" : "var(--fg-muted)";

  const text = typeof children === "string" ? children : null;

  const handleCopy = () => {
    if (!text) return;
    navigator.clipboard?.writeText(text).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1200);
      },
      () => {},
    );
  };

  return (
    <div
      style={{
        border: `1px solid ${borderColor}`,
        borderRadius: 6,
        background: "var(--bg-inset)",
        overflow: "hidden",
        ...style,
      }}
    >
      {(label || (copyable && text)) && (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "4px 8px",
            borderBottom: `1px solid ${borderColor}`,
            fontFamily: "var(--font-mono)",
            fontSize: 10,
            textTransform: "uppercase",
            letterSpacing: 0.5,
            color: tone === "danger" ? "var(--red)" : "var(--fg-subtle)",
          }}
        >
          {label && <span>{label}</span>}
          {copyable && text && (
            <button
              type="button"
              onClick={handleCopy}
              style={{
                marginLeft: "auto",
                background: "transparent",
                border: "1px solid var(--border-muted)",
                borderRadius: 4,
                color: "inherit",
                fontFamily: "inherit",
                fontSize: 10,
                padding: "1px 6px",
                cursor: "pointer",
              }}
            >
              {copied ? "copied" : "copy"}
            </button>
          )}
        </div>
      )}
      <pre
        style={{
          margin: 0,
          padding: "8px 10px",
          maxHeight,
          overflow: maxHeight ? "auto" : "visible",
          fontFamily: "var(--font-mono)",
          fontSize: 11,
          lineHeight: 1.5,
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          color: textColor,
        }}
      >
        <code>{children}</code>
      </pre>
    </div>
  );
}
