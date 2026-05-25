/**
 * Text atom — typography primitive. Replaces the ~dozen inline-styled
 * `<span style={{ fontSize, fontFamily, color }}>` patterns scattered
 * across the chat surface.
 *
 * Tones map onto our semantic foreground tokens; sizes follow a small
 * 4-step scale (xs/sm/md/lg) tuned for dense chat-style UI; family
 * defaults to sans, switch to mono for IDs/code/timestamps.
 */

import type { CSSProperties, HTMLAttributes, ReactNode } from "react";

export type TextTone = "default" | "muted" | "subtle" | "accent" | "danger" | "success";
export type TextSize = "xs" | "sm" | "md" | "lg";
export type TextFamily = "sans" | "mono";
export type TextWeight = "regular" | "medium" | "semibold";

interface TextProps extends Omit<HTMLAttributes<HTMLSpanElement>, "color"> {
  children: ReactNode;
  tone?: TextTone;
  size?: TextSize;
  family?: TextFamily;
  weight?: TextWeight;
  as?: "span" | "div" | "p";
  truncate?: boolean;
}

const TONE_COLOR: Record<TextTone, string> = {
  default: "var(--fg-default)",
  muted: "var(--fg-muted)",
  subtle: "var(--fg-subtle)",
  accent: "var(--accent)",
  danger: "var(--red)",
  success: "var(--green)",
};

const SIZE_PX: Record<TextSize, number> = {
  xs: 11,
  sm: 12,
  md: 13,
  lg: 15,
};

const WEIGHT: Record<TextWeight, number> = {
  regular: 400,
  medium: 500,
  semibold: 600,
};

export function Text({
  children,
  tone = "default",
  size = "md",
  family = "sans",
  weight = "regular",
  as = "span",
  truncate = false,
  style,
  ...rest
}: TextProps) {
  const composed: CSSProperties = {
    color: TONE_COLOR[tone],
    fontSize: SIZE_PX[size],
    fontFamily: family === "mono" ? "var(--font-mono)" : "var(--font-sans)",
    fontWeight: WEIGHT[weight],
    ...(truncate
      ? {
          overflow: "hidden",
          whiteSpace: "nowrap",
          textOverflow: "ellipsis",
          display: "block",
          maxWidth: "100%",
        }
      : null),
    ...style,
  };
  if (as === "div") return <div style={composed} {...rest}>{children}</div>;
  if (as === "p") return <p style={composed} {...rest}>{children}</p>;
  return <span style={composed} {...rest}>{children}</span>;
}
