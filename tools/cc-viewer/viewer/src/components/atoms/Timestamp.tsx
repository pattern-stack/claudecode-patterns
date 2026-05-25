/**
 * Timestamp atom — renders an ISO datetime as a human-friendly relative
 * string ("now", "3m ago", "2h ago") with the full datetime in the
 * tooltip. Auto-refreshes every 30s so the relative label stays current
 * without the parent having to manage its own tick interval.
 *
 * Uses the semantic <time> element with a `dateTime` attribute so the
 * machine-readable timestamp is preserved alongside the display string.
 */

import { useEffect, useState } from "react";
import type { TextSize, TextTone } from "./Text";
import { Text } from "./Text";

interface TimestampProps {
  iso: string;
  /** Always show the absolute value instead of "now / 3m ago". */
  absolute?: boolean;
  size?: TextSize;
  tone?: TextTone;
  mono?: boolean;
}

export function Timestamp({
  iso,
  absolute = false,
  size = "sm",
  tone = "subtle",
  mono = true,
}: TimestampProps) {
  const [, force] = useState(0);
  useEffect(() => {
    if (absolute) return;
    const id = setInterval(() => force((n) => n + 1), 30_000);
    return () => clearInterval(id);
  }, [absolute]);

  const date = new Date(iso);
  const valid = Number.isFinite(date.getTime());
  if (!valid) {
    return (
      <Text size={size} tone={tone} family={mono ? "mono" : "sans"}>
        {iso}
      </Text>
    );
  }

  const display = absolute ? date.toLocaleString() : relative(date);
  return (
    <time dateTime={date.toISOString()} title={date.toLocaleString()}>
      <Text size={size} tone={tone} family={mono ? "mono" : "sans"}>
        {display}
      </Text>
    </time>
  );
}

function relative(date: Date): string {
  const ago = Date.now() - date.getTime();
  if (ago < 30_000) return "now";
  if (ago < 60_000) return "<1m ago";
  if (ago < 3600_000) return `${Math.round(ago / 60_000)}m ago`;
  if (ago < 86_400_000) return `${Math.round(ago / 3600_000)}h ago`;
  return date.toLocaleString();
}
