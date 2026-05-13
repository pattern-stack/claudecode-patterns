/**
 * Markdown molecule — react-markdown wrapper with our token-driven
 * styling. Used inside TextPart for assistant/user bubbles. GFM is on
 * (tables, strikethrough, task lists, autolinks).
 */

import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface MarkdownProps {
  children: string;
}

export function Markdown({ children }: MarkdownProps) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          p: ({ children: c }) => <p style={{ margin: 0 }}>{c}</p>,
          a: ({ href, children: c }) => (
            <a href={href} style={{ color: "var(--accent)" }} target="_blank" rel="noreferrer">
              {c}
            </a>
          ),
          code: ({ className, children: c, ...rest }) => {
            const isBlock = (className ?? "").startsWith("language-");
            if (isBlock) return <code className={className}>{c}</code>;
            return (
              <code
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: "0.9em",
                  background: "var(--bg-surface-hover)",
                  border: "1px solid var(--border-muted)",
                  borderRadius: 3,
                  padding: "1px 4px",
                }}
                {...rest}
              >
                {c}
              </code>
            );
          },
          pre: ({ children: c }) => (
            <pre
              style={{
                margin: 0,
                padding: 10,
                background: "var(--bg-inset)",
                border: "1px solid var(--border-muted)",
                borderRadius: 6,
                fontFamily: "var(--font-mono)",
                fontSize: 12,
                overflowX: "auto",
                whiteSpace: "pre",
              }}
            >
              {c}
            </pre>
          ),
          ul: ({ children: c }) => <ul style={{ margin: 0, paddingLeft: 20 }}>{c}</ul>,
          ol: ({ children: c }) => <ol style={{ margin: 0, paddingLeft: 20 }}>{c}</ol>,
          li: ({ children: c }) => <li style={{ margin: "2px 0" }}>{c}</li>,
          blockquote: ({ children: c }) => (
            <blockquote
              style={{
                margin: 0,
                paddingLeft: 10,
                borderLeft: "3px solid var(--border)",
                color: "var(--fg-muted)",
              }}
            >
              {c}
            </blockquote>
          ),
          h1: ({ children: c }) => (
            <h1 style={{ fontSize: 18, fontWeight: 600, margin: 0 }}>{c}</h1>
          ),
          h2: ({ children: c }) => (
            <h2 style={{ fontSize: 16, fontWeight: 600, margin: 0 }}>{c}</h2>
          ),
          h3: ({ children: c }) => (
            <h3 style={{ fontSize: 14, fontWeight: 600, margin: 0 }}>{c}</h3>
          ),
        }}
      >
        {children}
      </ReactMarkdown>
    </div>
  );
}
