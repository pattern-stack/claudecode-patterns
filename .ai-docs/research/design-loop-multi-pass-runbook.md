<!--
RESEARCH ARTIFACT — vendored from pattern-stack/sales-patterns-ts PR #74 (`docs/multi-pass-loop-runbook.md`).

Origin: the runbook that drove issue #47 (vocabulary refactor) and informed the
design-loop port into this plugin. Project-specific (mentions `pts dev`, port 9002,
sales-patterns-ts frontend conventions). Kept here for historical context.

NOT THE CANONICAL REFERENCE. The canonical references for using `/design-loop`
and `/design-audit` inside the SDLC plugin are:

- `plugin/skills/design-loop/SKILL.md`
- `plugin/skills/design-audit/SKILL.md`
- `plugin/canvases/design-spec/README.md`

This runbook is preserved because the design decisions it embeds (per-pass
invariants, the dispatch order, the screenshot-as-evidence requirement) are
what those skills codify. Read it for the "why", read the SKILL.md files for
the "how".
-->

# Multi-Pass Refinement Loop — Runbook

A self-driving review/build/validate/re-audit/design loop coordinated by the main Claude session, executed by sub-agents. Each pass posts a detailed comment on a tracking GitHub issue with embedded screenshots.

## Pass shape

```
Pass N:
  1. browser-pilot   → audit (screenshots + GH comment)
  2. implementer     → fix the clear issues (commit + GH comment)
  3. validator       → typecheck/lint/tests + smoke endpoints (GH comment)
  4. browser-pilot   → re-audit, verify fixes landed (GH comment)
  5. designer        → taste pass — typography, palette, spacing, states (GH comment, may also commit)
→ Pass N+1
```

Pass N+1 starts only when the user signals (or designer's recommendation says PROCEED).

## Per-pass invariants the coordinator must enforce

### Before spawning each sub-agent

- **Confirm branch.** Run `git branch --show-current`. Hard-fail if it changed. (Pass 1 burned cycles when an unrelated `pts dev` flow checked out a sibling branch and screenshots disappeared from the working tree.)
- **Confirm dev env.** `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9002/api/v1/health` should return 200. If pts dev died (worker-events crashes are common), restart bare-bones: `PORT=9002 bun src/main.ts &` and `cd frontend && bun run dev &`.
- **Confirm session for image upload.** `test -f "$HOME/.config/gh-attach/session.json"` — if missing, instruct the user to run `node scripts/gh-attach-image.mjs --auth` themselves (interactive headed browser, can't be automated).

### How sub-agents are spawned

**MANDATORY: spawn every loop sub-agent with `isolation: "worktree"`.**

Reason: this repo is shared with concurrent agents (and with humans running `pts dev`). When two processes both call `git checkout` on the same working tree, branches drift unpredictably — we lost ~30 minutes of audit work on 2026-04-25 to exactly this. Worktrees give each agent its own checkout so concurrent branch ops don't collide.

In the Agent tool call:
```
Agent({
  subagent_type: "implementer",
  isolation: "worktree",   ← REQUIRED
  prompt: "...",
})
```

The agent's worktree path + branch are returned in the result. Coordinator then merges/cherry-picks the agent's commits onto the canonical branch (or — if the agent already pushed to a shared branch — just verifies the remote is updated).

### Inside each sub-agent's prompt

Always include:
1. **Tracking issue number + repo.** Don't ask the agent to guess.
2. **Reading order for prior comments.** `gh issue view <N> --repo <repo> --comments --json comments --jq '.comments[].body'` — explicit, complete.
3. **Image upload contract.** "Use `node scripts/gh-attach-image.mjs --issue <N> --image <path> --body \"...\"` for embedding screenshots. Do NOT use raw blob URLs."
4. **Commit + push contract.** "After committing, push with `git push origin <branch>`. Comments embed `user-attachments/assets/<uuid>` URLs that resolve regardless of push state, but the screenshot tree should still match the comment's claims."
5. **Output contract.** Explicit comment-section list, word budget, and a 3-line summary returned to the coordinator.
6. **User-tagging contract.** Any GH comment that includes "Open questions", "Questions for user", "Needs input", or any text where the agent is awaiting a human decision MUST @-tag the user (currently `@dugshub`) on the FIRST line of that section. Without the tag the user gets no GH notification and the loop stalls silently. This convention makes GH comments serve as a real interaction surface today; when the loop migrates off GH we'll replace the tag with a structured `requestUserInput()` call.

### After each sub-agent completes

- **Read the comment.** `gh issue view <N> --comments --json comments --jq '.comments[-1].body' | head -200`. Don't trust the agent's self-reported summary alone.
- **Verify any commits.** `git log --oneline -3` — confirm the SHA the agent claimed exists.
- **Update the task list.** Mark the previous task completed, mark the next in_progress.

## Ports / processes

`pts dev` aliases (current offset +1000):
- Backend: `:9002` (sometimes drifts to `:9100` if backend port resolution misfires — verify via `/api/v1/health`)
- Frontend: `:4000`

When `pts dev` dies because worker-events crashes (recurring issue), the API and frontend die with it. Bare-bones startup that works in isolation:
```bash
PORT=9002 bun src/main.ts > /tmp/be.log 2>&1 &
cd frontend && bun run dev > /tmp/fe.log 2>&1 &
```

## Image upload — privacy posture

The `user-attachments/assets/<uuid>` URL embedded in a comment is auth-gated; only viewers with repo access resolve it. GitHub then redirects to a 5-minute presigned S3 URL — that S3 URL is publicly fetchable for its 5-minute window (AWS presigned-URL design), but expires automatically. Safe for screenshots without PII/secrets; treat sensitive content with extra caution.

## Failure modes seen (Pass 1)

| Symptom | Root cause | Fix |
|---|---|---|
| Embedded images all 404 in comments | Comments used `github.com/.../blob/...?raw=true` URLs against a PRIVATE repo, plus the branch was never pushed | `gh-attach-image` skill — drives composer upload, produces `user-attachments` URLs that work on private repos |
| Designer agent not selectable as `subagent_type: designer` | Agent file written mid-session; agent registry not reloaded | Restart Claude Code session after adding new agent files, or use `general-purpose` with the agent's brief inlined |
| Re-audit screenshots disappeared from working tree | `pts dev` checked out a different branch | Coordinator pre-flight: assert branch via `git branch --show-current` |
| `/api/v1/health` 404 after builder added the route | Backend process predated the commit; pts dev never restarted | Restart backend; coordinator should verify health endpoint behavior matches what builder claims |
| `pts dev` exits when worker-events crashes | Worker process supervises everything | Run backend + frontend bare-bones for screenshot work; investigate worker-events as a separate task |

## Future improvements

- **Coordinator agent** that owns the full loop end-to-end (currently the main session shepherds prompts manually).
- **Folded validator** — fold typecheck/lint/tests into builder pre-commit, fold endpoint smoke into re-auditor.
- **Auto-push hook** — after any sub-agent commits, automatically push so embedded references stay live.
- **Pre-flight skill** — encode the branch/health/session checks above as a single skill the coordinator invokes before each sub-agent spawn.
