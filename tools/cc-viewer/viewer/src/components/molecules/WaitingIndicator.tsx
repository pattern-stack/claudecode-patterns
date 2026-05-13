/**
 * WaitingIndicator molecule — small spinner + "thinking…" label shown
 * when an assistant message has no parts yet but is expected to arrive.
 */

import { Spinner } from "../atoms/Spinner";

export function WaitingIndicator() {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        color: "var(--fg-muted)",
        fontSize: 12,
        fontFamily: "var(--font-mono)",
      }}
    >
      <Spinner size={10} />
      thinking…
    </div>
  );
}
