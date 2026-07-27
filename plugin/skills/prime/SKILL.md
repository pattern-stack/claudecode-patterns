---
name: prime
description: Load session context at cold-start — handoff, tracker snapshot (open-issue board + branch-derived active ticket), recent commits, stack position. Trigger when the user opens a fresh session or asks "where were we", "what's the state", "starting session", "/prime", or otherwise signals they want a status snapshot.
allowed-tools: Read, Bash, Glob, mcp__plugin_linear_linear__get_issue
user-invocable: true
---

# Prime

## Purpose

Bootstraps a session by loading the same context the user would otherwise gather by hand: the per-branch handoff note, the tracker state (open-issue board + active ticket), recent git shape, and current stack position. Surfaces a checklist for the user to confirm before any work starts.

This is a working spike for what `DocumentationToolbox` will eventually formalize. Stay lean — only load what evidence shows is needed every session. Speculative loads bloat context.

## Pre-rendered context

Branch: !`git branch --show-current`

Recent commits:
!`git log --oneline -5`

Graphite stack:
!`st status 2>/dev/null || echo "(st not available or no stack)"`

## Instructions

Run these in parallel where independent, then summarize. Do NOT silently skip steps; if something fails or is missing, say so.

1. **Handoff** — `Read .ai-docs/handoff.md` if it exists. If missing, note that and continue.
2. **Branch + stack + log** — already pre-rendered above. Reference those values; do not re-run the commands.
3. **Active tracker ticket** — parse the branch name (above) for `<team-key-lowercase>-<n>` (case-insensitive), where team-key comes from `sdlc.yml.team_key`. If found, call the configured tracker's get-issue MCP (per `task-management/{value}.md`). If the branch doesn't encode a ticket, skip and note it.

   *Known gap:* this step is currently parameterized by sdlc.yml's team_key but the get-issue MCP call form is still tracker-specific (see `task-management/{linear,github}.md` for each adapter's MCP signature). A future refactor will fully abstract this through a tracker primitive method.

4. **Issue board** — read `sdlc.yml.task_management`. If `github`, run `gh issue list --state open --limit 20` and `gh issue list --state closed --limit 5` (recent completions). This is the step that catches drift the branch can't: on `main` no ticket is branch-encoded, but open epics/tasks still say exactly where the stack stands — and a closed issue the handoff doesn't mention means the handoff is stale (flag that explicitly). If `linear`, skip the board (no cheap list-issues MCP wired yet) and rely on step 3; note the skip.
5. **Summarize** — render a single concise block in this order:
   - Active ticket: `<TEAM>-<n> — <title>` and one-line status
   - Board: open epics + the next open task in plan order; recently closed issues; any handoff-vs-board staleness
   - Branch + stack position
   - Last 3-5 commits (oneline)
   - Handoff: last action / next action / obstacles (verbatim from file, not paraphrased)
6. **Confirm opening move** — end with the CLAUDE.md cold-start checklist as a `[ ]` list and ask the user which item to start with (or to redirect).

## Output

A single message with six labeled sections (Ticket, Board, Branch, Recent commits, Handoff, Next), then the checklist + question. No file writes. No tool calls beyond the five steps above.

## Notes

- Read-only. This skill must not modify state.
- If multiple `<team>-<n>` matches appear in the branch, prefer the highest number (newest ticket).
- Don't fetch issue *details* beyond the active ticket — the board step is a titles/labels listing only. Expand into bodies/comments only if the user asks.
