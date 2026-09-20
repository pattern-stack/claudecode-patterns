---
name: stack-management
description: Auto-load PR stack context for current branch. Reads stack state and reports position. Use when working on any branch that is part of a PR stack.
user-invocable: false
allowed-tools: Bash, Read
---

# Stack Context Auto-Loader

Provides stack awareness to Claude and subagents automatically. Read-only — never modifies state.
Backed by `gh stack` (GitHub's official extension); `/sdlc:stack` is the full skill.

## Steps

1. Check the extension is installed:
   ```bash
   gh extension list 2>/dev/null | grep -q 'github/gh-stack'
   ```

2. If installed, read stack state. **Always `--json`** — bare `view` opens a TUI under a PTY and
   blocks forever:
   ```bash
   gh stack view --json 2>/dev/null
   ```

3. Exit code **2** means the current branch is not in a stack — **stay silent**, this is the
   common case. Exit **6** means the branch belongs to several stacks; report that and stop.

4. On success, report concisely — `branches[]` is ordered bottom (trunk-side) to top:
   ```
   Stack: <n of total> | <currentBranch> | trunk: <trunk>
   PRs: <open>/<total> open
   ```
   Derive the position from the index of the entry whose `isCurrent` is true. PR state per branch
   is `branches[].pr.state` (`OPEN` | `MERGED` | `QUEUED`); `pr` is absent when no PR exists.

5. If any branch has `needsRebase: true`, warn:
   ```
   ⚠ Stack needs a rebase — run `gh stack rebase` (or `--upstack` after editing a lower layer)
   ```

6. If a rebase is already in flight (`gh stack rebase` would exit **7**), warn:
   ```
   ⚠ Rebase in progress — resolve conflicts, `git add`, then `gh stack rebase --continue`
   ```

7. If the extension is not installed, suggest:
   ```
   gh stack not installed. Install with: gh extension install github/gh-stack
   ```

## `view --json` schema

JSON goes to **stdout**; status messages go to **stderr** — never parse stderr.

```
trunk           string
currentBranch   string
branches[]      name, head, base, isCurrent, isMerged, isQueued, needsRebase
branches[].pr   number, url, state ("OPEN" | "MERGED" | "QUEUED"); absent when no PR exists
```

`base` is the saved SHA of the parent this branch was last known to contain — it can be older than
the parent's current tip, which is what `needsRebase` reflects.

## Principles

- **Lean**: one command, concise output
- **Read-only**: never modify state or branches (note `view` does refresh PR state from GitHub as a
  best-effort side effect, and does not fail when the API is unreachable)
- **Silent when irrelevant**: no output when not on a stack branch (exit 2)
- **Actionable warnings**: surface needs-rebase and rebase-in-progress states
