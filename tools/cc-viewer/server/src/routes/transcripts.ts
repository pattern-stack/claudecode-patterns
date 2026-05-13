/**
 * Transcript ingest + cold-load REST.
 *
 * Receives one POST per JSONL line from cc-bridge, persists with dedupe on
 * (session_id, line_uuid), and broadcasts on the SSE channel.
 *
 * The wire format (see .ai-docs/research/cc-viewer-chat-surface.md) is the
 * durable contract between cc-bridge and cc-viewer. cc-bridge may evolve
 * its implementation; this shape stays.
 */

import { Hono } from "hono";
import type { EventStore } from "../event-store.js";
import { TRANSCRIPT_DELTA_TYPE } from "../event-types.js";
import type { SSEBroadcaster } from "../sse-broadcaster.js";

interface TranscriptDeltaPayload {
  session_id?: unknown;
  line_uuid?: unknown;
  line_index?: unknown;
  transcript_path?: unknown;
  timestamp?: unknown;
  entry?: unknown;
}

export function transcriptRoutes(
  broadcaster: SSEBroadcaster,
  store: EventStore | undefined,
): Hono {
  const app = new Hono();

  app.post("/hooks/TranscriptDelta", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as TranscriptDeltaPayload;

    const sessionId = typeof body.session_id === "string" ? body.session_id : undefined;
    const lineUuid = typeof body.line_uuid === "string" ? body.line_uuid : undefined;
    const lineIndex = typeof body.line_index === "number" ? body.line_index : undefined;

    if (!sessionId || !lineUuid || lineIndex === undefined) {
      return c.json(
        { error: "missing required fields: session_id, line_uuid, line_index" },
        400,
      );
    }
    if (!body.entry || typeof body.entry !== "object") {
      return c.json({ error: "missing required field: entry (object)" }, 400);
    }

    const timestamp =
      typeof body.timestamp === "string" ? new Date(body.timestamp) : new Date();
    const transcriptPath =
      typeof body.transcript_path === "string" ? body.transcript_path : undefined;
    const entry = body.entry as Record<string, unknown>;

    const inserted = store?.appendTranscriptEntry({
      sessionId,
      lineUuid,
      lineIndex,
      timestamp,
      transcriptPath,
      entry,
    });

    // Always broadcast — live viewers should see fresh-on-the-wire entries
    // even if persistence is off or the dedupe check fired. Dedupe on the
    // wire is the client's concern (same line_uuid arriving twice).
    broadcaster.broadcast(TRANSCRIPT_DELTA_TYPE, {
      session_id: sessionId,
      line_uuid: lineUuid,
      line_index: lineIndex,
      transcript_path: transcriptPath,
      timestamp: timestamp.toISOString(),
      entry,
    });

    return c.json({ ok: true, deduped: inserted === false });
  });

  app.get("/admin/claude-code/sessions/:sessionId/transcript", (c) => {
    if (!store) {
      return c.json({ error: "persistence not configured" }, 503);
    }
    const sessionId = c.req.param("sessionId");
    const entries = store.transcriptForSession(sessionId);
    return c.json({
      session_id: sessionId,
      entries: entries.map((e) => ({
        line_uuid: e.lineUuid,
        line_index: e.lineIndex,
        timestamp: e.timestamp,
        transcript_path: e.transcriptPath,
        entry: e.entry,
      })),
    });
  });

  return app;
}
