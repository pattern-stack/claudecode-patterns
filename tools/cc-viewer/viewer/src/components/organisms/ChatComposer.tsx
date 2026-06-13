/**
 * ChatComposer — types a message into the live terminal pane for `cwd`
 * (via ghostty-bridge), with a `/` slash-command palette that mirrors the
 * commands Claude Code reads (enabled-plugin commands + user-invocable
 * skills + project commands; built-ins are not file-backed and not listed).
 *
 * Enter sends (paste + Enter so the agent submits); Shift+Enter inserts a
 * newline. When the palette is open, ↑/↓ move, Enter/Tab accept, Esc closes.
 */

import { type KeyboardEvent, useEffect, useMemo, useRef, useState } from "react";
import { type CommandEntry, fetchCommands, sendAgentInput } from "../../lib/eventApi";
import { Button } from "../atoms/Button";

export function ChatComposer({ cwd }: { cwd: string }) {
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);

  // Slash-command palette.
  const [commands, setCommands] = useState<CommandEntry[] | null>(null);
  const [selected, setSelected] = useState(0);
  const [dismissed, setDismissed] = useState(false);

  // A "command query" is a leading "/" with no whitespace yet (the first token).
  const isQuery = text.startsWith("/") && !/\s/.test(text);
  const query = isQuery ? text.slice(1).toLowerCase() : "";

  // Lazy-load the catalog the first time the user reaches for a command.
  useEffect(() => {
    if (isQuery && commands === null) {
      fetchCommands(cwd)
        .then(setCommands)
        .catch(() => setCommands([]));
    }
  }, [isQuery, commands, cwd]);

  const matches = useMemo(() => {
    if (!isQuery || !commands) return [];
    const q = query;
    const hit = commands.filter(
      (c) => c.name.toLowerCase().includes(q) || c.description.toLowerCase().includes(q),
    );
    hit.sort((a, b) => {
      const ar = a.name.toLowerCase().startsWith(q) ? 0 : 1;
      const br = b.name.toLowerCase().startsWith(q) ? 0 : 1;
      return ar - br || a.name.localeCompare(b.name);
    });
    return hit.slice(0, 8);
  }, [isQuery, commands, query]);

  const open = isQuery && matches.length > 0 && !dismissed;

  // Keep the selection in range as the query narrows.
  useEffect(() => {
    setSelected(0);
  }, [query]);

  function accept(cmd: CommandEntry) {
    const next = `/${cmd.name} `;
    setText(next);
    setDismissed(false);
    requestAnimationFrame(() => {
      const ta = taRef.current;
      if (ta) {
        ta.focus();
        ta.setSelectionRange(next.length, next.length);
      }
    });
  }

  async function send() {
    const value = text.trim();
    if (value === "" || sending) return;
    setSending(true);
    setError(null);
    try {
      await sendAgentInput({ cwd, text: value, submit: true });
      setText("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSending(false);
    }
  }

  function onKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (open) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setSelected((s) => Math.min(s + 1, matches.length - 1));
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setSelected((s) => Math.max(s - 1, 0));
        return;
      }
      if (e.key === "Tab" || (e.key === "Enter" && !e.shiftKey)) {
        e.preventDefault();
        const cmd = matches[selected];
        if (cmd) accept(cmd);
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        setDismissed(true);
        return;
      }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send();
    }
  }

  return (
    <div
      style={{
        borderTop: "1px solid var(--border)",
        padding: 10,
        display: "flex",
        flexDirection: "column",
        gap: 6,
        background: "var(--bg-canvas)",
      }}
    >
      <div style={{ position: "relative", display: "flex", gap: 8, alignItems: "flex-end" }}>
        {open && (
          <CommandPalette
            matches={matches}
            selected={selected}
            onPick={accept}
            onHover={setSelected}
          />
        )}
        <textarea
          ref={taRef}
          value={text}
          onChange={(e) => {
            setText(e.target.value);
            setDismissed(false);
          }}
          onKeyDown={onKeyDown}
          placeholder="Message this agent…  ( / for commands · Enter to send · Shift+Enter for newline )"
          rows={1}
          disabled={sending}
          style={{
            flex: 1,
            resize: "none",
            maxHeight: 140,
            minHeight: 38,
            padding: "9px 11px",
            fontFamily: "inherit",
            fontSize: 13,
            lineHeight: 1.5,
            color: "var(--fg-default)",
            background: "var(--bg-inset, var(--bg-surface))",
            border: "1px solid var(--border)",
            borderRadius: 6,
            outline: "none",
          }}
        />
        <Button
          variant="primary"
          size="md"
          disabled={sending || text.trim() === ""}
          onClick={() => void send()}
        >
          {sending ? "Sending…" : "Send"}
        </Button>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 8, minHeight: 14 }}>
        {error ? (
          <span style={{ color: "var(--red)", fontSize: 11 }}>{error}</span>
        ) : (
          <span style={{ color: "var(--fg-muted)", fontSize: 11, fontFamily: "var(--font-mono)" }}>
            → {cwd}
          </span>
        )}
      </div>
    </div>
  );
}

function CommandPalette({
  matches,
  selected,
  onPick,
  onHover,
}: {
  matches: CommandEntry[];
  selected: number;
  onPick: (c: CommandEntry) => void;
  onHover: (i: number) => void;
}) {
  return (
    <div
      style={{
        position: "absolute",
        bottom: "calc(100% + 6px)",
        left: 0,
        right: 0,
        maxHeight: 280,
        overflowY: "auto",
        background: "var(--bg-surface)",
        border: "1px solid var(--border)",
        borderRadius: 8,
        boxShadow: "0 8px 28px rgba(0,0,0,0.45)",
        zIndex: 20,
        padding: 4,
      }}
    >
      {matches.map((c, i) => (
        <button
          key={c.name}
          type="button"
          // onMouseDown (not onClick) so the textarea doesn't blur first.
          onMouseDown={(e) => {
            e.preventDefault();
            onPick(c);
          }}
          onMouseEnter={() => onHover(i)}
          style={{
            display: "block",
            width: "100%",
            textAlign: "left",
            border: "none",
            borderRadius: 6,
            padding: "7px 9px",
            cursor: "pointer",
            background: i === selected ? "var(--bg-inset, rgba(255,255,255,0.05))" : "transparent",
          }}
        >
          <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 12.5,
                color: "var(--accent)",
                whiteSpace: "nowrap",
              }}
            >
              /{c.name}
            </span>
            {c.argumentHint && (
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-muted)" }}>
                {c.argumentHint}
              </span>
            )}
            <span style={{ marginLeft: "auto", fontSize: 10, color: "var(--fg-muted)" }}>{c.kind}</span>
          </div>
          {c.description && (
            <div
              style={{
                fontSize: 11.5,
                color: "var(--fg-muted)",
                marginTop: 2,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {c.description}
            </div>
          )}
        </button>
      ))}
    </div>
  );
}
