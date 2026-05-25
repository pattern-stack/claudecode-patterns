/**
 * Pure presentational grouper.
 *
 * - Consecutive assistant ChatMessages → one `turn` (rendered as a single
 *   TurnCard with one avatar + one summed token-strip footer).
 * - A single assistant ChatMessage also becomes a `turn` of length 1, so
 *   the visual treatment is consistent.
 * - User ChatMessages stay as `single` (rendered as a bubble via
 *   MessageRow).
 *
 * Why: Claude Code emits one assistant ChatMessage per protocol round-trip
 * (thinking + tool_use → tool_result → next assistant call). To a reader,
 * that whole back-and-forth is one logical turn. Without grouping, the
 * chat surface shows 5–15 floating sub-cards per turn with a duplicated
 * avatar and footer on each — that's what reads as "no chat card, no
 * organization".
 */

import type { ChatMessage } from "./transcript";

export type ChatGroup =
  | { kind: "single"; message: ChatMessage }
  | {
      kind: "turn";
      id: string;
      messages: ChatMessage[];
      model?: string;
      inputTokens?: number;
      outputTokens?: number;
    };

export function groupTurns(messages: ChatMessage[]): ChatGroup[] {
  const out: ChatGroup[] = [];
  let buffer: ChatMessage[] = [];

  const flush = () => {
    if (buffer.length === 0) return;
    const first = buffer[0];
    if (!first) {
      buffer = [];
      return;
    }
    let input: number | undefined;
    let output: number | undefined;
    let model: string | undefined;
    for (const m of buffer) {
      if (m.inputTokens !== undefined) input = (input ?? 0) + m.inputTokens;
      if (m.outputTokens !== undefined) output = (output ?? 0) + m.outputTokens;
      if (m.model && !model) model = m.model;
    }
    out.push({
      kind: "turn",
      id: first.id,
      messages: buffer.slice(),
      model,
      inputTokens: input,
      outputTokens: output,
    });
    buffer = [];
  };

  for (const m of messages) {
    if (m.role === "assistant") {
      buffer.push(m);
      continue;
    }
    flush();
    out.push({ kind: "single", message: m });
  }
  flush();

  return out;
}
