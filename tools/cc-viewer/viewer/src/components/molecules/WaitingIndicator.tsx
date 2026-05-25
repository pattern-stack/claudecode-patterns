/**
 * WaitingIndicator molecule — spinner + label shown when Claude is
 * working on something (post-user-message, mid-tool, mid-thinking).
 */

import { Spinner } from "../atoms/Spinner";
import { Text } from "../atoms/Text";

interface WaitingIndicatorProps {
  label?: string;
}

export function WaitingIndicator({ label = "thinking…" }: WaitingIndicatorProps) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
      }}
    >
      <Spinner size={10} />
      <Text size="sm" tone="muted" family="mono">
        {label}
      </Text>
    </div>
  );
}
