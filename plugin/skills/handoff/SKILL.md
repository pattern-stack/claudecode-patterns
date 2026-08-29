---
name: handoff
description: End-of-session ceremony — articulate what's next, write `.ai-docs/handoff.md` (or update the destination it points to), update memory, update CLAUDE.md if structural decisions landed, verify clean working tree. Symmetric counterpart to `/prime`. Use when wrapping up a session, before clearing context, or whenever the user signals they want to save state.
when_to_use: User says "let's handoff", "wrap up", "ending session", "save state", "/handoff", "before I clear context", "summarize what we did and prep next session".
allowed-tools: Read, Write, Bash, Glob, Grep
user-invocable: true

# === Project SDLC overlay ===
status: active
topology: none
---

# handoff

End-of-session ceremony. The symmetric counterpart to [`prime`](../prime/SKILL.md), which loads what this skill writes.

The ordering is **load-bearing**: articulating "what's next" first surfaces forgotten todos AND structural conventions that should land in CLAUDE.md before we lose them.

## Pre-rendered context

Branch: !`git branch --show-current`

Status:
!`git status --short`

Recent commits:
!`git log --oneline -5`

Graphite stack:
!`st status 2>/dev/null || echo "(st not available or no stack)"`

## Instructions

Run sequentially — each step's output informs the next.

### 1. Articulate what's next (forces reflection)

Before writing anything, state in chat:
- What was the last meaningful action this session?
- What is the next intended action (specific — not "continue work")?
- What obstacles or open questions are blocking the next action?

Doing this first surfaces things you'd otherwise drop: incomplete todos, missing tracker entries, conventions that should land in CLAUDE.md.

### 2. Write `.ai-docs/handoff.md`

Terse — 5-10 lines. The cold-start `/prime` skill loads this verbatim into the next session.

Format:
```markdown
# Handoff — <YYYY-MM-DD>

**Branch:** `<branch>`
**Last action:** <one-line description of last meaningful change>
**Next action:** <specific next step — file path or command, not "continue X">
**Obstacles:** <bulleted, or "none">

## Notes
<optional: anything the next session needs that doesn't fit above>
```

**Read the existing `handoff.md` before overwriting it.** Two cases where overwriting is wrong:

- **It declares that the handoff lives elsewhere.** A project may keep its running state in a
  published artifact, a tracker epic, or a shared doc, leaving this file as a *pointer* to it. If the
  file says so — a "do not overwrite" marker, or a link presented as the source of truth — update
  that destination instead and leave the pointer alone. Say in chat which destination you updated.
- **`.ai-docs/` is not tracked by git.** It is commonly gitignored, and then there is no previous
  version to recover: the overwrite is permanent. Check with
  `git ls-files --error-unmatch .ai-docs/handoff.md` before replacing a file you did not write, and
  when it is untracked, keep whatever the old file carried that your new one does not.

Otherwise overwrite it — when the file is tracked, the previous version is in git history.

### 3. Update memory

Memory lives at `~/.claude/projects/-Users-USER-Projects-PROJECT/memory/`.

For this session, write any of these that apply (skip what doesn't):
- **feedback** memory: corrections or validated approaches the user expressed (with `**Why:**` and `**How to apply:**` lines per global memory protocol).
- **project** memory: ongoing-work facts not derivable from code or git (deadlines, ownership, motivation).
- **user** memory: stable role/preference facts about the user.
- **reference** memory: pointers to external systems referenced this session.

Don't save: code patterns, fix recipes, ephemeral state, anything in CLAUDE.md, anything in commit messages. Index each new file in `MEMORY.md` with a one-line hook.

### 4. Update tracker (if applicable)

For each completed work item:
- Close the tracker issue or post a closing comment.
- Update `state:*` labels per `.claude/primitives/task-management/<value>.md`.

For each parked / discovered work item:
- File a new tracker issue with enough context to pick up cold.

If no tracker writes are needed (e.g. a meta-session that didn't touch issues), skip explicitly.

### 5. Update CLAUDE.md if structural decisions landed

Edit CLAUDE.md only if the session introduced a convention, layout rule, or tool that future sessions need to know **and that isn't documented elsewhere**. Examples:
- New top-level directory under `.claude/` or `.ai-docs/`.
- New skill that future sessions should auto-trigger.
- New primitive category.
- Convention change (file naming, branch shape, etc.).

Don't duplicate content that lives in skills, primitives, or RFCs — link to them from CLAUDE.md instead.

### 6. Verify clean working tree

Run:
```bash
git status
st status 2>/dev/null || true
```

For each uncommitted file:
- If part of completed work and the user wants to commit → propose a commit message and ask before running.
- If WIP → stash with a descriptive note, OR leave uncommitted if `handoff.md` references it explicitly.
- If accidental → ask the user.

Never auto-commit, auto-stash, or auto-discard. Surface the state and let the user decide.

### 7. Summary + confirmation

Print a single block summarizing:
- What landed (memory entries, handoff.md path, CLAUDE.md edits if any, tracker updates if any).
- What remains uncommitted.
- The line `/prime` will surface next session as the opening move.

Wait for the user to confirm before they clear context.

## Constraints

- Read-only on git history. Never `git reset`, `git rebase`, force-push, or amend during handoff.
- Never auto-commit. The user owns commit decisions.
- Don't write speculative memory entries. If nothing new and durable was learned this session, write none.
- **Never clobber a handoff you did not write.** If the file points at another destination, update that
  destination; if `.ai-docs/` is untracked, an overwrite cannot be undone. See step 2.
- The handoff is for the **next session of this project**, not a generic AI. Reference paths, branch names, and tracker keys directly — assume the reader is starting cold but in this repo.
- Articulate-first ordering is non-negotiable. Skipping straight to file writes loses the reflection that surfaces missing items.
