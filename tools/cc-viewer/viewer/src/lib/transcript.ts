/**
 * Pure reducer: turns a list of Claude Code JSONL transcript entries into
 * a list of ChatMessages with ordered `parts[]` (text / thinking /
 * tool_call / error), mirroring the chat-patterns Part union.
 *
 * Kept framework-free so the hook (`useTranscript`) can memoize over the
 * entry feed without re-running React effects.
 *
 * Mapping rules (verified against real CC JSONL):
 *   - user/string                     -> user message with text part
 *   - user/[{type:"text"}]            -> user message with text parts
 *   - user/[{type:"tool_result"}]     -> MERGED into matching tool_call on
 *                                        the most recent assistant message
 *   - assistant/[blocks]              -> assistant message; per-block:
 *       text     -> text part
 *       thinking -> thinking part (complete=true; replay, not live)
 *       tool_use -> tool_call part {id, name, arguments: input}
 *   - any other outer type            -> skipped (system, permission-mode,
 *                                        file-history-snapshot, attachment,
 *                                        or entries missing `message`)
 */

import type { TranscriptEntry } from "./eventApi";

export type Part =
  | { kind: "text"; content: string }
  | { kind: "thinking"; content: string; complete: boolean }
  | {
      kind: "tool_call";
      id: string;
      name: string;
      arguments: unknown;
      result?: unknown;
      error?: string;
      durationMs?: number;
      /** Images attached to the tool result (e.g. Read of a PNG). */
      images?: string[];
    }
  | { kind: "error"; errorType: string; message: string }
  | { kind: "image"; src: string; alt?: string; caption?: string };

const IMAGE_EXT = /\.(png|jpe?g|gif|webp|svg|bmp|avif)$/i;

/** Anthropic image block `source` -> a renderable src (data URL or http url). */
function imageSrcFromSource(source: unknown): string | null {
  if (!source || typeof source !== "object") return null;
  const s = source as Record<string, unknown>;
  if (s.type === "base64" && typeof s.media_type === "string" && typeof s.data === "string") {
    return `data:${s.media_type};base64,${s.data}`;
  }
  if (s.type === "url" && typeof s.url === "string") return s.url;
  return null;
}

/** A local image file path -> a URL the backend can stream. Null if not an image. */
function fileImageSrc(p: string): string | null {
  if (!IMAGE_EXT.test(p)) return null;
  return `/admin/file?path=${encodeURIComponent(p)}`;
}

/** Pull base64/url image srcs out of a tool_result content array. */
function extractResultImages(content: unknown): string[] {
  if (!Array.isArray(content)) return [];
  const out: string[] = [];
  for (const b of content) {
    if (b && typeof b === "object" && (b as Record<string, unknown>).type === "image") {
      const src = imageSrcFromSource((b as Record<string, unknown>).source);
      if (src) out.push(src);
    }
  }
  return out;
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  parts: Part[];
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
}

interface AnthropicMessage {
  role?: string;
  model?: string;
  content?: unknown;
  usage?: { input_tokens?: number; output_tokens?: number };
}

interface OuterEntry {
  uuid?: string;
  type?: string;
  message?: AnthropicMessage;
}

interface ToolResultBlock {
  type: "tool_result";
  tool_use_id?: string;
  content?: unknown;
  is_error?: boolean;
}

/**
 * Reduce CC JSONL entries (in `line_index` order) into ChatMessages.
 *
 * The merge-tool-result rule is the load-bearing complexity: a `user` entry
 * carrying tool_result blocks is not a new message, it's the resolution of
 * a tool_call previously emitted by the assistant. We find the matching
 * tool_call by `tool_use_id` -> `part.id` and patch it in place.
 */
export function entriesToMessages(entries: TranscriptEntry[]): ChatMessage[] {
  const messages: ChatMessage[] = [];

  for (const wrapper of entries) {
    const raw = wrapper.entry as OuterEntry | undefined;
    if (!raw || typeof raw !== "object") continue;
    const outerType = raw.type;
    const msg = raw.message;
    if (!msg || (outerType !== "user" && outerType !== "assistant")) continue;

    const role = msg.role;
    if (role !== "user" && role !== "assistant") continue;

    const content = msg.content;

    // Case A: user/string -> single text part on a new user message.
    if (outerType === "user" && typeof content === "string") {
      messages.push({
        id: wrapper.entry.uuid as string ?? wrapper.line_uuid,
        role: "user",
        parts: [{ kind: "text", content }],
      });
      continue;
    }

    // Case B: array content -> walk blocks.
    if (!Array.isArray(content)) continue;
    const blocks = content as Array<Record<string, unknown>>;

    if (outerType === "user") {
      // Detect tool_result(s); merge into the most recent matching tool_call.
      const toolResults = blocks.filter(
        (b): b is ToolResultBlock & Record<string, unknown> => b.type === "tool_result",
      );
      if (toolResults.length > 0) {
        for (const tr of toolResults) {
          mergeToolResult(messages, tr);
        }
        // Real-world CC: user/tool_result entries don't carry user-authored
        // text in the same line. If they did, we'd also want to emit a
        // user message — but we haven't seen that shape in practice.
        continue;
      }

      // Plain user text + pasted images.
      const parts: Part[] = [];
      for (const block of blocks) {
        if (block.type === "text" && typeof block.text === "string") {
          parts.push({ kind: "text", content: block.text });
        } else if (block.type === "image") {
          const src = imageSrcFromSource(block.source);
          if (src) parts.push({ kind: "image", src });
        }
      }
      if (parts.length === 0) continue;
      messages.push({
        id: (raw.uuid as string) ?? wrapper.line_uuid,
        role: "user",
        parts,
      });
      continue;
    }

    // outerType === "assistant"
    const parts: Part[] = [];
    for (const block of blocks) {
      const bType = block.type;
      if (bType === "text" && typeof block.text === "string") {
        parts.push({ kind: "text", content: block.text });
      } else if (bType === "thinking" && typeof block.thinking === "string") {
        // Replay always sees complete thinking blocks (whole-line writes).
        parts.push({ kind: "thinking", content: block.thinking, complete: true });
      } else if (bType === "tool_use") {
        const id = typeof block.id === "string" ? block.id : "";
        const name = typeof block.name === "string" ? block.name : "(tool)";
        parts.push({
          kind: "tool_call",
          id,
          name,
          arguments: block.input ?? {},
        });
        // File-delivery tools carry image paths, not bytes — render them inline.
        if (name === "SendUserFile" || name === "SendUserFiles") {
          const input = (block.input ?? {}) as Record<string, unknown>;
          const files = Array.isArray(input.files) ? input.files : [];
          const caption = typeof input.caption === "string" ? input.caption : undefined;
          let first = true;
          for (const f of files) {
            if (typeof f !== "string") continue;
            const src = fileImageSrc(f);
            if (!src) continue;
            parts.push({ kind: "image", src, alt: f, caption: first ? caption : undefined });
            first = false;
          }
        }
      } else if (bType === "image") {
        const src = imageSrcFromSource(block.source);
        if (src) parts.push({ kind: "image", src });
      }
    }
    if (parts.length === 0) continue;

    const message: ChatMessage = {
      id: (raw.uuid as string) ?? wrapper.line_uuid,
      role: "assistant",
      parts,
    };
    if (typeof msg.model === "string") message.model = msg.model;
    if (msg.usage?.input_tokens !== undefined) message.inputTokens = msg.usage.input_tokens;
    if (msg.usage?.output_tokens !== undefined) message.outputTokens = msg.usage.output_tokens;
    messages.push(message);
  }

  return messages;
}

/**
 * Walk messages newest-to-oldest, find the tool_call with the matching id,
 * and patch in the result / error. Mutates `messages` in place (caller
 * owns the array; we're inside a single reducer pass).
 */
function mergeToolResult(messages: ChatMessage[], tr: ToolResultBlock): void {
  const targetId = tr.tool_use_id;
  if (!targetId) return;
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (!m || m.role !== "assistant") continue;
    const idx = m.parts.findIndex((p) => p.kind === "tool_call" && p.id === targetId);
    if (idx === -1) continue;
    const part = m.parts[idx];
    if (!part || part.kind !== "tool_call") continue;
    const formatted = formatToolResult(tr.content);
    const images = extractResultImages(tr.content);
    const patched: Part = {
      ...part,
      result: formatted,
      error: tr.is_error ? formatted : undefined,
      images: images.length > 0 ? images : part.images,
    };
    const nextParts = m.parts.slice();
    nextParts[idx] = patched;
    messages[i] = { ...m, parts: nextParts };
    return;
  }
}

/**
 * tool_result.content can be:
 *   - a plain string (most CLI tools)
 *   - an array of {type:"text", text} blocks (Anthropic standard)
 *   - something else entirely (fall back to JSON)
 */
function formatToolResult(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((b) => {
        if (b && typeof b === "object" && (b as Record<string, unknown>).type === "text") {
          const text = (b as Record<string, unknown>).text;
          return typeof text === "string" ? text : "";
        }
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }
  try {
    return JSON.stringify(content, null, 2);
  } catch {
    return String(content);
  }
}
