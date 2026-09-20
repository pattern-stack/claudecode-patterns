---
name: stack
description: Manage PR stacks with GitHub's official `gh stack` extension — init, add, view, submit, push, sync, rebase, merge, checkout, link, unstack. Use when the user mentions stacks, stacked PRs, restack, stack submit/merge, branch dependencies, the GitHub stack UI, atomic stack merge, or splitting work into reviewable layers.
argument-hint: [init|add|view|checkout|up|down|top|bottom|submit|push|sync|rebase|merge|link|unstack]
allowed-tools: Bash, Read
---

# /stack — PR stack management with `gh stack`

All operations use [`github/gh-stack`](https://github.com/github/gh-stack), GitHub's official CLI
extension (**v0.1.1**, verified 2026-09-20). This replaces the retired home-grown `st` CLI — see
[references/st-migration.md](references/st-migration.md) to move a stack that `st` still tracks.

A stack is an ordered chain of branches rooted on trunk, one PR per branch based on the branch
below, so a reviewer sees only that layer's diff. `gh stack` prints it trunk-first, left to right:

```
(main) <- auth <- api <- frontend
```

Left is the **bottom** (`auth`, merges first); right is the **top**. `up` moves away from trunk,
`down` toward it. Foundational work belongs at the bottom.

Local tracking lives in `.git/gh-stack` (JSON, not committed). The remote representation is a
first-class GitHub **stack object** with a stack number — anyone can `gh stack checkout <pr#>` and
materialize the whole chain, with no shared config.

## Setup (once per machine / repo)

```bash
gh extension install github/gh-stack     # or: gh extension upgrade stack
git config rerere.enabled true           # replay repeated conflict resolutions
git config remote.pushDefault origin     # REQUIRED when the repo has >1 remote
```

`gh stack init` enables `rerere` itself, but under a TTY the first run asks to confirm — setting it
beforehand keeps that prompt out of an agent's way.

## Non-interactive use — read this before running anything

`gh stack` branches on whether stdout is a TTY. Under a PTY the commands below open a prompt or a
full-screen TUI and **block forever**. Agent harnesses vary, so always pass the flags rather than
relying on TTY detection.

| Always run | Never run bare | Why |
|---|---|---|
| `gh stack view --json` | `gh stack view` | TUI under a PTY |
| `gh stack submit --auto` | `gh stack submit` | prompts for a title per new PR |
| `gh stack merge <target> --yes` | `gh pr merge` | `gh pr merge` cannot merge a stack |
| `gh stack init <branch>...` | `gh stack init` | prompts for branch names |
| `gh stack add <branch>` | `gh stack add` | prompts for a name; fails even when piped |
| `gh stack up`/`down`/`top`/`bottom` | `gh stack switch` | `switch` is menu-only |
| — | `gh stack modify` | TUI-only; **no** non-interactive path |

**Multiple remotes:** pass `--remote <name>` to `push`, `submit`, `sync`, `rebase`, and `link`
unless `remote.pushDefault` is set. `checkout` and `trunk` have no `--remote` flag and depend on
that config.

`view --short` never opens the TUI but is formatted for humans — parse `--json`, not `--short`.

## Standing rules

- **Push only on the human's explicit sign-off in the current exchange.** `push`, `submit`, `sync`
  (it pushes) and `merge` are all outward-facing.
- **There is no undo.** No `st undo` equivalent, no snapshots. Before any surgery, make your own
  restore points — see [references/troubleshooting.md](references/troubleshooting.md).
- **Don't retarget PR bases by hand** — `submit` and `sync` own them.
- **Don't raw-`git rebase` stack branches** — use `gh stack rebase`; it cascades and knows the
  recorded bases. (Exception: the deliberate restructure recipes, which re-adopt afterwards.)
- **After any mutation, push** so the PRs match local SHAs.
- **After PRs merge, `gh stack sync --prune`** — never hand-delete branches or close PRs.

## Core loop

```bash
gh stack init billing/schema           # create the stack, check out its branch
git add … && git commit -m "Add billing schema"
gh stack add billing/api               # next layer, branched from the current one
git add … && git commit -m "Add billing routes"
gh stack view --json                   # confirm the chain
gh stack submit --auto                 # 🚦 sign-off — pushes + opens draft PRs
```

- `init` takes the whole chain at once: `gh stack init b1 b2 b3` (bottom→top). Existing branches are
  **adopted**, missing ones created — existence decides, there is no separate adopt mode. This is
  the re-slice entry point. `--base <branch>` selects a non-default trunk.
- `add` **must run from the top branch** (or trunk on an empty stack) — anywhere else it exits `5`.
  Run `gh stack top` first.
- `add` without `-Am` does not touch the working tree: uncommitted changes **carry over** to the new
  branch. Commit or stash first if the new layer should start clean.
- Branch names are used verbatim — `gh stack add refactor/foo` creates `refactor/foo`.
- `submit --auto` creates drafts; add `--open` to mark new **and existing** PRs ready for review.
- PR titles/bodies are auto-generated (single-commit branch → that commit's subject/body; otherwise
  the humanized branch name). There is no title flag — use `gh pr edit <n> --title … --body-file …`
  afterwards, including any repo-required body lines.

For how to choose the layers, read [references/stack-design.md](references/stack-design.md).

## Editing a lower layer

Check out the layer that **owns** the change before editing — never commit a lower layer's concern
on the top branch.

```bash
gh stack down                       # or: gh stack checkout billing/api
git add … && git commit -m "Fix the amount rounding"   # or --amend
gh stack rebase --upstack           # replay every branch ABOVE onto the change
gh stack top                        # back to where you were
gh stack push                       # 🚦 sign-off
```

`--upstack` (current → top) is the right tool after editing a lower layer. `--downstack` does trunk
→ current. `--no-trunk` aligns the whole chain with each other but skips the fetch and trunk rebase.
Bare `gh stack rebase` does everything, including fast-forwarding trunk.

If ownership is unclear, `gh stack view --json` plus `git log --all -- <path>` settles it.

## Staying in sync, and landing

```bash
gh stack sync                 # fetch, reconcile with GitHub, rebase, push atomically, refresh PRs
gh stack sync --prune         # …and delete local branches for merged PRs
gh stack merge 42 --yes --squash   # 🚦 PR #42 + every unmerged PR below it, all-or-nothing
gh stack merge 7 --yes             # every unmerged PR in stack #7
```

- `merge` is **atomic**: if any PR in the set cannot merge, none do. A bare number resolves as a
  stack number first, then a PR number. Without a method flag the last-used method is reused.
- Only basic PR state is pre-checked (open, not a draft). Branch protection is evaluated by GitHub
  at merge time and reported back — never bypassed. Submit with `--open` first if the stack is
  still in draft.
- **A merge queue on the base branch overrides everything**: the stack is enqueued, the queue picks
  the method, and any method flag you passed is ignored with a warning. Queued PRs can land in
  separate groups.
- `sync` **never opens PRs** — that is `submit`. Pruning never happens without `--prune`.
- On local/remote divergence, non-interactive `sync` prints both chains, changes nothing, and exits
  **0** with `Sync aborted`. **Exit 0 does not mean it synced** — check for that message, or
  re-read `gh stack view --json`.

## Reading state

`gh stack view --json` writes JSON to **stdout**; status messages go to **stderr**. Don't parse
stderr — branch on exit codes.

```
trunk           string
currentBranch   string
branches[]      name, head, base, isCurrent, isMerged, isQueued, needsRebase
branches[].pr   number, url, state ("OPEN" | "MERGED" | "QUEUED"); absent when no PR exists
```

`base` is the saved SHA of the parent this branch was last known to contain — it may be older than
the parent's current tip. `needsRebase` is true when the parent's tip is no longer an ancestor.

`view` refreshes PR state from GitHub as a best-effort side effect; it does not fail when the API
is unreachable.

## Exit codes

| Code | Meaning | Recovery |
|---|---|---|
| 0 | Success | — (but see the `Sync aborted` caveat above) |
| 1 | Generic error | Read stderr |
| 2 | Not in a stack / unknown stack number | `gh stack init`, or `gh stack checkout <target>` |
| 3 | Rebase conflict | Resolve, `git add`, `gh stack rebase --continue` |
| 4 | GitHub API failure | Check `gh auth status`, retry |
| 5 | Invalid arguments | Fix the invocation (`<command> --help`); also `add` off the top branch |
| 6 | Disambiguation required | Branch is in several stacks — check out a non-shared branch |
| 7 | Rebase already in progress | `gh stack rebase --continue` or `--abort` |
| 8 | Stack file locked | Another `gh stack` process is writing; retry after ~5s |
| 9 | Stacked PRs unavailable | Not enabled on the repository — tell the user |
| 10 | Modify recovery required | `gh stack modify --abort` |

Check `$?` on the command itself, not through a pipe.

## Constraints

- Stacks are **strictly linear**: one parent, at most one child. Parallel work needs a separate
  stack.
- **No non-interactive reorder, rename, or removal.** Errors may suggest `gh stack modify`, but it
  is TUI-only and must never be invoked by an agent. Restructure with git, then `unstack` + `init`
  — recipes in [references/troubleshooting.md](references/troubleshooting.md).
- **`push` and `submit` are not atomic** (per-branch `--force-with-lease`); a later rejection leaves
  earlier pushes standing. Rerunning is safe. Only `sync` pushes atomically.
- Dependent/cross-stack relationships are not modeled. Fold dependent work into one taller stack.
- `gh stack help <command>` does **not** work — it prints the top-level help. Use
  `gh stack <command> --help`, which is authoritative for flags.

## References

Open the one whose trigger matches the task — no need to preload them.

| Reference | When |
|---|---|
| [references/stack-design.md](references/stack-design.md) | Before `init` — how many layers, what goes in each, when work needs its own stack |
| [references/commands.md](references/commands.md) | A command failed unexpectedly, or you need its preconditions, side effects, atomicity, ordering |
| [references/troubleshooting.md](references/troubleshooting.md) | Rebase conflict, squash-merge, divergence, restructuring, driving stacks from another tool |
| [references/st-migration.md](references/st-migration.md) | A stack the retired `st` CLI still tracks |

Adapted from the MIT-licensed agent skill bundled with `github/gh-stack`, plus this project's
agent-driving rules.
