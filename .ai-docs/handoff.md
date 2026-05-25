# Handoff — 2026-05-14

**Branch:** `feat/cc-viewer-chat-surface` (PR #85, awaiting merge)
**Last action:** Resolved CI version-bump failure — bumped plugin 0.1.11 → 0.1.12 (PR #84 grabbed 0.1.11), split CHANGELOG into two version entries, amended + force-pushed. Local `verify-version-bump.sh` clean.
**Next action:** After PR #85 merges → `git fetch origin main && git tag v0.1.12 <merge-sha> && git push origin v0.1.12` to trigger the release workflow. Confirm 8 tarballs attach (cc-viewer + cc-bridge × 4 platforms). Then start **Piece 2** of the chat dashboard work.
**Obstacles:** None. CI checks queued; only the version-bump gate was failing.

## Notes

**Piece 2 — Rich session cards** (next ~1.5 hr of work after release):
- Server: new `EventStore.sessionSummaries(limit)` aggregating `transcript_entries` per session — `firstUserPrompt`, `latestUserPrompt`, `messageCounts {user, assistant, toolUses}`, `tokens {input, output}` (sum), `model` (latest assistant `message.model`), `firstSeen`/`lastSeen`.
- Server REST: `GET /admin/claude-code/sessions?include=summary` returning the array.
- UI: new molecules `PromptPreview`, `SessionMetaStrip`; new organism `ChatSessionCard` replacing `SessionLinkRow`; new hook `useSessionSummaries`.
- `ChatPage` switches from `useEventStream + groupClaudeCodeEvents` to `useSessionSummaries()`.

**Piece 3 — Project grouping via cc-bridge** (~1 hr after Piece 2):
- cc-bridge: in `/sessions/register`, run `git -C <cwd> rev-parse --show-toplevel`, persist `repo_root` per session and forward on each `TranscriptDelta` POST.
- Server: store `repo_root` per session (new column on `transcript_entries` or new `sessions` table); join into summary response.
- UI: group `ChatSessionCard`s by `repo_root`; new molecule `ProjectGroupHeader` (display label = `basename(repo_root)`).

**Reference**: full architectural decision record at `.ai-docs/research/cc-viewer-chat-surface.md` (committed in this PR).

**Local state**: dev cc-viewer + cc-bridge binaries are staged at `~/.local/state/{cc-viewer,cc-bridge}/bin/*-v0.1.10-darwin-arm64`. Once v0.1.12 release publishes, the next SessionStart's `ensure_tool` will pull the official tarballs (path changes to `-v0.1.12-darwin-arm64`).

**Untracked**: `experimental/teammate-fanout/` — explicitly excluded from PR #85; leave as-is.
