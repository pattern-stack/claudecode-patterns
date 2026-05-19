/**
 * Truncate atom — two shapes:
 *
 *   - mid-string ellipsis ("19c6d1…98cf"), useful for UUIDs where the
 *     head + tail are both identifying. The truncation logic runs in JS
 *     so the tooltip can show the full value via the `<span title>`.
 *
 *   - css line-clamp, for variable-length prose like prompt previews.
 *     Uses the `-webkit-line-clamp` route (still the most widely-
 *     supported clamp); on legacy fallback the text simply wraps.
 *
 * Either shape forwards `title` so screen-readers and tooltips still see
 * the full string.
 */

import type { CSSProperties, ReactNode } from "react";

interface MidProps {
  value: string;
  head?: number;
  tail?: number;
  mono?: boolean;
  size?: number;
  style?: CSSProperties;
}

export function TruncateMid({ value, head = 6, tail = 4, mono = true, size, style }: MidProps) {
  const display =
    value.length <= head + tail + 1 ? value : `${value.slice(0, head)}…${value.slice(-tail)}`;
  return (
    <span
      title={value}
      style={{
        fontFamily: mono ? "var(--font-mono)" : "inherit",
        fontSize: size,
        ...style,
      }}
    >
      {display}
    </span>
  );
}

interface ClampProps {
  children: ReactNode;
  lines?: number;
  title?: string;
  style?: CSSProperties;
}

export function TruncateClamp({ children, lines = 2, title, style }: ClampProps) {
  return (
    <span
      title={title}
      style={{
        display: "-webkit-box",
        WebkitLineClamp: lines,
        WebkitBoxOrient: "vertical",
        overflow: "hidden",
        wordBreak: "break-word",
        ...style,
      }}
    >
      {children}
    </span>
  );
}
