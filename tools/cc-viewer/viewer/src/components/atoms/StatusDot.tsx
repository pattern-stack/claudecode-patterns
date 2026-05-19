/**
 * StatusDot atom — small colored circle for connection / liveness /
 * recording-style indicators. Mirrors the inline `<span>` pattern that
 * was hand-rolled at four call sites (the page header "connected" badge,
 * the per-row live indicator on the chat list, etc.).
 *
 * Pass `pulse` to get the apdash-live-pulse ring animation defined in
 * globals.css.
 */

import type { CSSProperties } from "react";

export type DotTone = "live" | "idle" | "warning" | "danger" | "neutral";

const TONE_COLOR: Record<DotTone, string> = {
  live: "var(--green)",
  idle: "var(--border)",
  warning: "var(--yellow)",
  danger: "var(--red)",
  neutral: "var(--fg-subtle)",
};

interface StatusDotProps {
  tone?: DotTone;
  size?: number;
  pulse?: boolean;
  title?: string;
  style?: CSSProperties;
}

export function StatusDot({
  tone = "neutral",
  size = 8,
  pulse = false,
  title,
  style,
}: StatusDotProps) {
  return (
    <span
      title={title}
      aria-hidden={title ? undefined : "true"}
      style={{
        display: "inline-block",
        width: size,
        height: size,
        borderRadius: "50%",
        background: TONE_COLOR[tone],
        flexShrink: 0,
        ...(pulse && tone === "live"
          ? { animation: "apdash-live-pulse 1.8s ease-out infinite" }
          : null),
        ...style,
      }}
    />
  );
}
