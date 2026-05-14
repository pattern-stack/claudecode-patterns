/**
 * ErrorPart — inline red-tinted alert row for assistant-emitted errors
 * (SDK envelope errors, tool rejections that show as a separate part).
 */

import { AlertIcon } from "../../atoms/icons";

interface ErrorPartProps {
  errorType: string;
  message: string;
}

export function ErrorPart({ errorType, message }: ErrorPartProps) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 8,
        background: "rgba(248, 81, 73, 0.08)",
        border: "1px solid var(--red)",
        borderRadius: 6,
        padding: "8px 12px",
        color: "var(--red)",
        fontSize: 12,
        fontFamily: "var(--font-mono)",
      }}
    >
      <AlertIcon size={14} />
      <span style={{ wordBreak: "break-word" }}>
        <span style={{ fontWeight: 600 }}>{errorType}</span>: {message}
      </span>
    </div>
  );
}
