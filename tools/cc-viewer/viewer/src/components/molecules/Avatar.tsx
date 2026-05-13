/**
 * Avatar molecule — circular badge with a bot/user glyph. Used by
 * MessageRow to anchor each row visually.
 */

import { BotIcon, UserIcon } from "../atoms/icons";

interface AvatarProps {
  role: "user" | "assistant";
}

export function Avatar({ role }: AvatarProps) {
  const isUser = role === "user";
  return (
    <div
      style={{
        width: 28,
        height: 28,
        flexShrink: 0,
        borderRadius: "50%",
        background: isUser ? "var(--bg-surface-hover)" : "var(--accent-emerald-dim)",
        color: isUser ? "var(--fg-muted)" : "var(--accent-emerald)",
        border: "1px solid var(--border-muted)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {isUser ? <UserIcon size={14} /> : <BotIcon size={14} />}
    </div>
  );
}
