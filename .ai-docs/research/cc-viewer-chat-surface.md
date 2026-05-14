# cc-viewer chat surface + cc-bridge daemon

Architectural decisions for adding a real-time chat view to cc-viewer, alongside
the existing trace/logs viewer. Captured here so downstream implementation work
shares one source of truth.

## Goal

`/chat` page in cc-viewer that mirrors the trace viewer's top-level
(session-cards) but renders the **actual conversation** from Claude Code —
user prompts, assistant text, thinking blocks, tool calls/results — in real
time, per CC session.

## Why hook events are not enough

Hook events (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, etc.)
are lifecycle/control-plane notifications. They carry tool intents and
session metadata but **never** carry assistant text or thinking blocks —
those flow directly from the Anthropic API into the local transcript JSONL
that CC maintains at `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`.
The hook payload's `transcript_path` field is the pointer to that file,
not the file's contents.

So a real chat view needs the JSONL as a source. Hooks remain the source
for tool calls and session lifecycle.

## Architecture — three local concerns, three artifacts

```
plugin/hooks/                    (event-driven, fork-exec per CC hook)
  emit.sh                        POST hook events → cc-viewer
  ensure-cc-viewer.sh            SessionStart: ensure cc-viewer running
  ensure-cc-bridge.sh    NEW     SessionStart: ensure cc-bridge running
                                  + POST register {session, transcript_path}
  deregister-cc-bridge-session.sh   NEW
                                 SessionEnd: POST deregister {session}

tools/cc-viewer/                 (long-running, location-flexible)
  HTTP receiver, SQLite storage, SSE broadcast, SPA host.
  + NEW: TranscriptDelta ingest endpoint + transcript_entries table
  + NEW: GET /admin/claude-code/sessions/:id/transcript (cold-load REST)
  + NEW: SSE event class `claude_code.transcript_delta`

tools/cc-bridge/         NEW     (long-running, always-local)
  HTTP server on localhost:3994; fs.watch per registered session;
  batched line forwarder to $CC_VIEWER_URL/hooks/TranscriptDelta.
```

The split:
- **cc-bridge** = local mediator; owns FS access (transcripts, eventually
  history scan, eventually `~/.claude/projects/*` walking).
- **cc-viewer** = pure HTTP receiver + UI; location-flexible. Could be on
  the same machine, on a homelab box, on a team-shared host.

This split is what unlocks: remote/team cc-viewer, offline buffering,
redaction, multi-sink forwarding, eventual bidirectional control. We don't
build any of that now — we just don't paint ourselves into a corner.

## Wire format — the contract that has to last

### `POST /hooks/TranscriptDelta`

cc-bridge → cc-viewer. One POST per transcript JSONL line (no batching on
the wire; batching is a cc-bridge-side concern across the watch loop).

```json
{
  "session_id": "9c5ad33e-3f12-4a6e-a21a-69b9ade5d27b",
  "line_uuid": "18cb4a12-f3eb-4d82-8199-b6d600a67b85",
  "line_index": 142,
  "transcript_path": "/Users/dug/.claude/projects/-Users-...-/9c5ad33e-....jsonl",
  "timestamp": "2026-05-13T12:39:00.000Z",
  "entry": { /* parsed JSONL line, untouched */ }
}
```

**Field decisions:**
- `session_id` — matches `cc_session_id` already used by `claude_code.hook` rows.
- `line_uuid` — comes from the JSONL line itself (most CC JSONL entries carry
  a `uuid` field). If the line has no uuid (rare metadata entries like
  `permission-mode`), bridge synthesizes a stable hash of the line contents
  so dedupe still works.
- `line_index` — monotonic-per-session position. Used for stable ordering on
  the viewer side. Survives out-of-order delivery.
- `transcript_path` — traceability only; the viewer never reads from it.
- `entry` — the parsed JSONL line as-is. We deliberately do NOT normalize
  here. The viewer-side reducer owns the mapping into `ChatMessage.parts[]`.
  Rationale: JSONL is CC's contract and it evolves. We want the bridge to be
  a transparent forwarder, not a translation layer.

**Idempotency:** server dedupes on `(session_id, line_uuid)` via UNIQUE
constraint. Same line POSTed twice (retry, end-of-turn flush overlapping
with future live tailer, etc.) is a no-op.

### `POST localhost:3994/sessions/register`

Plugin hook → cc-bridge.

```json
{
  "session_id": "...",
  "transcript_path": "/Users/...",
  "cwd": "/Users/..."
}
```

### `POST localhost:3994/sessions/deregister`

```json
{ "session_id": "..." }
```

### `GET /admin/claude-code/sessions/:id/transcript` (cc-viewer)

Cold-load REST. Returns the full ordered transcript for a session:

```json
{
  "session_id": "...",
  "entries": [
    { "line_uuid": "...", "line_index": 0, "timestamp": "...", "entry": {...} },
    ...
  ]
}
```

## Storage

New SQLite table in cc-viewer's existing event-store database:

```sql
CREATE TABLE transcript_entries (
  session_id TEXT NOT NULL,
  line_uuid TEXT NOT NULL,
  line_index INTEGER NOT NULL,
  timestamp TEXT NOT NULL,
  transcript_path TEXT,
  entry TEXT NOT NULL,        -- JSON
  PRIMARY KEY (session_id, line_uuid)
);
CREATE INDEX idx_transcript_session_index
  ON transcript_entries(session_id, line_index);
```

INSERT is `OR IGNORE` so dedupe is automatic.

## Viewer reducer (parsed entry → ChatMessage.parts[])

Mapping rules from CC JSONL entries to the chat-patterns `Part` union we
already inherit from agent-dashboard:

| JSONL entry shape | → `Part` |
|---|---|
| `{ type: "user", message: { content: [...] } }` | message with `text` part(s) |
| `{ type: "assistant", message: { content: [...] } }` where content block is `text` | `text` part |
| ...content block is `thinking` | `thinking` part (with `complete: true`) |
| ...content block is `tool_use` | `tool_call` part (id, name, arguments) |
| `{ type: "user", message: { content: [{type: "tool_result", ...}] } }` | merges into matching `tool_call` part (result/error) |
| `{ type: "system" }` / `permission-mode` / `file-history-snapshot` / sidechain | skipped (not chat-relevant) |
| Anthropic SDK error envelope | `error` part |

Token usage and model: from `message.usage` / `message.model` on the last
assistant entry of a turn — flows to `ChatMessage.{model, inputTokens, outputTokens}`.

## Routing + atomic structure

```
viewer/src/
  App.tsx                            BrowserRouter + routes
  components/
    atoms/    Badge Button Card Spinner icons Cursor   (Cursor NEW)
    molecules/  Avatar Markdown MessageFooter WaitingIndicator   (ALL NEW)
    organisms/
      SessionCard.tsx                (existing — logs page)
      ChatInput.tsx                  (NEW — extracted)
      MessageRow.tsx                 (NEW — extracted)
      ChatPanel.tsx                  (NEW — slim composition)
      parts/
        TextPart.tsx                 (NEW)
        ThinkingPart.tsx             (NEW)
        ToolCallPart.tsx             (NEW)
        ErrorPart.tsx                (NEW)
    templates/
      AppShell.tsx                   (NEW — sidebar nav)
  pages/
    LogsPage.tsx                     (renamed from ClaudeCodePage)
    ChatPage.tsx                     (NEW — session list)
    ChatSessionPage.tsx              (NEW — chat for one session)
  hooks/
    useEventStream.ts                (existing)
    useTranscript.ts                 (NEW — snapshot + SSE tail)
  lib/
    claudeCodeSessions.ts            (existing)
    eventApi.ts                      (existing)
    transcript.ts                    (NEW — JSONL entry → ChatMessage[])
```

Routes:
- `/` → redirect to `/logs`
- `/logs` → LogsPage (existing trace viewer)
- `/chat` → ChatPage (session list, same SessionCard styling)
- `/chat/:sessionId` → ChatSessionPage (full chat thread)

## Non-goals for this pass

Explicitly out of scope, to keep this shipping:
- No buffering / retry in cc-bridge if cc-viewer is down (single-line POST,
  silent failure — same fail-silent contract as `emit.sh`).
- No multi-sink forwarding.
- No redaction.
- No enrichment (git context, repo metadata).
- No bidirectional control (viewer → bridge → CC).
- No startup backfill of past `~/.claude/projects/*` sessions.
- No token-level streaming below the JSONL-line granularity.

Each of these has a clear future home (cc-bridge). They're deferred, not
forgotten.

## Risk register

- **`fs.watch` cross-platform quirks.** macOS FSEvents has rename-coalescing
  weirdness; some watchers don't reliably fire on append-only writes. Bun's
  wrapper papers over most of it; JSONL append-mode is the easy case. If we
  see misses, the fallback is `setInterval` + `fstat` polling.
- **Race: SessionStart hook fires register before cc-bridge is healthy.**
  Mitigation: ensure-cc-bridge.sh retries register with backoff for ~6s
  after spawn (same pattern as ensure-cc-viewer.sh does for the SessionStart
  replay POST).
- **Race: SessionEnd hook missed (CC crash).** Mitigation: idle-timeout
  reaper in cc-bridge — registration whose watched file has had no events
  for 10 min is dropped.
- **CC JSONL format change.** Mitigation: bridge forwards `entry` unmodified.
  Format change is a reducer-side update only; storage and bridge unchanged.

## Naming

`cc-bridge` chosen over `cc-tailer` / `cc-relay` / `cc-sidecar` / `ccd`.
Pairs naturally with cc-viewer in conversation ("cc-bridge feeds
cc-viewer"), neutral on direction (survives the bidirectional future), and
reads cleanly in logs.
