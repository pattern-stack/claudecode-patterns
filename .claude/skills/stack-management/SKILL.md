---
name: stack-management
description: Auto-load PR stack context for current branch. Reads stack state and reports position. Use when working on any branch that is part of a PR stack.
user-invocable: false
allowed-tools: Bash, Read
---

# Stack Context Auto-Loader

Provides stack awareness to Claude and subagents automatically. Read-only — never modifies state.

## Steps

1. Check if `stack` CLI is available:
   ```bash
   which stack 2>/dev/null
   ```

2. If available, get stack context:
   ```bash
   stack status --json 2>/dev/null
   ```

3. If JSON output is returned, report concisely:
   ```
   Stack: <stackName> | Branch <position> of <total> | <branchName>
   PRs: <open>/<total> open | CI: <passing>/<total> passing
   ```

4. If a restack is in progress, warn:
   ```
   ⚠ Restack in progress — resolve conflicts and run `stack continue`
   ```

5. If `stack` is not installed, suggest:
   ```
   Stack CLI not installed. Install with: bun install -g git+ssh://git@github.com/dugshub/stack.git
   Then run: stack init
   ```

6. If not on a stack branch, stay silent.

## JSON output fields

The `stack status --json` output includes:
- `stack` — stack name
- `branches` — array of branch objects with `name`, `pr` (number, url, status, checks), `position`
- `current` — index of the current branch
- `trunk` — base branch name

## Principles

- **Lean**: One command, concise output
- **Read-only**: Never modify state or branches
- **Silent when irrelevant**: No output if not on a stack branch
- **Actionable warnings**: Surface restack-in-progress or merge-in-progress states
