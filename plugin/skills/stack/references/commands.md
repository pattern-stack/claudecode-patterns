# Command behavior

`gh stack <command> --help` is authoritative for flags and arguments. (`gh stack help <command>`
only prints the top-level help.) This file covers what `--help` does not: preconditions, side
effects, atomicity, and failure modes. Verified against **v0.1.1**.

## Contents

- [init](#init) · [add](#add) · [push](#push) · [submit](#submit) · [link](#link)
- [sync](#sync) · [rebase](#rebase) · [view](#view) · [checkout](#checkout)
- [unstack](#unstack) · [merge](#merge) · [Navigation](#navigation)
- [Running a command across the whole stack](#running-a-command-across-the-whole-stack)

## init

Creates the stack and checks out the **last** branch in the list, so one `init` can lay down the
whole chain: `gh stack init auth api frontend`.

Arguments are processed bottom to top. Existing branches are adopted; if the first does not exist it
is created from trunk, and each later new branch from the one before it. **Existence decides —
there is no separate adopt mode.** `--base` selects a non-default trunk.

`init` also enables `git rerere`. Under a TTY the first run in a repo asks for confirmation; set
`git config rerere.enabled true` beforehand to skip it.

## add

- **Must run from the top branch** of the stack (or the trunk when the stack is still empty).
  Anywhere else it exits **5** with `can only add branches on top of the stack`. Run
  `gh stack top` first.
- **Uncommitted changes carry over.** Without `-Am`, `add` does not touch the working tree, so
  staged and unstaged changes follow you onto the new branch. Commit or stash first for a clean
  start.
- **`add -Am` commits in place when the current branch has no commits yet** — for example right
  after `init` — instead of creating a branch. Deliberate: the first layer usually needs content
  before a second layer exists.
- `-A` and `-u` are mutually exclusive, and both require `-m`.
- With `-m` and no branch name, the name is generated from the commit message in date-and-slug form
  (`03-24-add_api_routes`). Prefer naming the branch yourself.
- Since v0.1.1, running `add` from a branch that is not in a stack **offers to initialize one**
  (interactive). As an agent, use `init` explicitly instead.

## push

Pushes every active (non-merged, non-queued) branch in one multi-ref push with per-branch
`--force-with-lease`.

**Not atomic.** Some branches may update while another is rejected. A rejection means that branch
moved on the remote — fix that branch and rerun; rerunning is safe and skips what already landed.
Never escalate to a bare `--force`.

`push` never creates or updates pull requests. Use `submit` for that.

## submit

Pushes each active branch, creates a PR for every branch that lacks one (based on the first
non-merged ancestor), updates existing PRs' bases, then links them into a stack on GitHub.

- **Not atomic.** Branches are pushed sequentially with per-branch `--force-with-lease`. A later
  rejection leaves earlier pushes and PR updates standing. Fix and rerun the same command.
- **A fully merged stack cannot be extended.** When every PR in the current stack is already merged,
  `submit` forks the remaining unmerged branches into a **new** stack rooted at trunk, leaving the
  merged stack untouched.
- **Titles with `--auto`:** a single-commit branch uses that commit's subject as the title and its
  body as the PR body; a multi-commit branch humanizes the branch name. No flag sets a custom title
  or body — use `gh pr edit` afterwards.
- `--open` marks new *and existing* PRs ready for review; without it, new PRs are drafts.
- Requires stacked PRs to be enabled on the repository. If not, `submit` exits **9** when
  non-interactive (under a TTY it offers to create ordinary unstacked PRs instead).

## link

Creates or updates a stack on GitHub **with no local tracking state**. This is the path for branches
managed by another tool, or living in another worktree.

- Arguments are bottom to top. Each is a branch name or a PR number; a numeric argument is tried as
  a PR number first, then as a branch name.
- **A numeric first argument is a stack number only when a stack with that number exists.** Then the
  remaining arguments are appended to the top of that stack and you do not re-list its current PRs:
  `gh stack link 7 feature-c`. Arguments already in the stack are skipped; arguments belonging to a
  different stack are rejected.
- Branch arguments are pushed automatically (non-force, atomic). Missing PRs are created with
  auto-generated titles and correctly chained bases; existing PRs with a wrong base are corrected.
- Membership is **additive only** — `link` never removes a PR from a stack.
- Because `link` writes no local state, `up`/`down`/`top`/`bottom` will not work on the result. Use
  `gh stack checkout <stack-number>` if you later want local tracking.

## sync

The routine command. Steps, in order:

1. **Fetch** from the remote.
2. **Reconcile with the GitHub stack.** PRs added on github.com are pulled down and appended
   locally. On divergence, aborts when non-interactive — **exit 0**, see `troubleshooting.md`.
3. **Fast-forward the trunk.** Skipped when current; warns when diverged.
4. **Cascade rebase when needed** — if trunk moved, a branch was fast-forwarded from its remote, or
   a branch no longer contains its expected parent. Merged PRs are handled automatically. On
   conflict **all branches are restored** to their pre-rebase state and it exits **3**.
5. **Push** all active branches, **atomically** (`--force-with-lease --atomic`).
6. **Refresh PR state** from GitHub.
7. **Sync the stack object** — link open PRs additively, only when two or more PRs exist. `sync`
   never opens PRs; that is `submit`.
8. **Prune** local branches for merged PRs — only with `--prune` when non-interactive.

The final message distinguishes outcomes: `Stack synced` means the GitHub stack object now matches
local; `Branches synced` means branches were rebased and pushed but no stack object was created or
updated (e.g. fewer than two PRs exist).

## rebase

Pulls from the remote and cascade-rebases. Use it when `sync` reported a conflict, or to rebase only
part of the stack.

- `--upstack` — current branch to the top. **This is what you run after editing a lower layer.**
- `--downstack` — trunk to the current branch.
- `--no-trunk` — skip the fetch and trunk rebase entirely; align stack branches with each other only.
- `--continue` after staging resolutions; `--abort` restores **every** branch, not just the current.
- `--preserve-dates` / `--committer-date-is-author-date` keep committer dates stable.
- A merged PR is detected automatically and replayed with `--onto` against the correct target, so a
  squash-merged parent does not produce spurious conflicts.
- Starting a rebase while one is in progress exits **7**.

## view

- `--json` writes the machine-readable payload to **stdout** (schema in `SKILL.md`); status goes to
  stderr.
- Bare `view` opens a full-screen TUI when stdout is a TTY, and prints static text when piped.
- `--short` prints a compact one-line-per-branch summary and never opens the TUI, but it is for
  humans — parse `--json`. Since v0.1.1, on terminals without OSC 8 hyperlink support it prints
  `#N (URL)`; `GH_STACK_HYPERLINKS=1`/`0` forces either form.
- `view` refreshes PR state from GitHub as a best-effort side effect — it does not fail when the API
  is unreachable.

## checkout

Accepts a stack number, PR number, PR URL, or branch name.

- A bare number resolves as a **stack number first**, then a PR number, then a branch name.
- Stack numbers, PR numbers and PR URLs fetch from GitHub, pull the branches down, and set up local
  tracking — the whole chain from any clone.
- Since v0.1.1, a **branch name** not tracked locally is also resolved against active remote stacks,
  and bare `checkout` detects when the current branch belongs to an untracked remote stack and
  offers it. Both are best-effort and interactive — as an agent, name the target explicitly.
- If a local stack already covers those branches with a different composition, `checkout` **cannot
  be forced past it**. Run `gh stack unstack --local` first, then retry.
- `checkout` has no flags. With several remotes it relies on `remote.pushDefault`.

## unstack

Removes the stack **grouping** only. It never deletes pull requests or branches.

- No argument targets the active stack — the one containing the current branch — removing it on
  GitHub and locally.
- A stack number works from anywhere in the repository, tracked locally or not, via the API.
- `--local` removes local tracking only and never contacts GitHub. This is the **re-adopt
  primitive**. Combining `--local` with a stack number that is not tracked locally is an error.
- An unknown stack number exits **2**.
- GitHub refuses to unstack PRs that are queued or have auto-merge enabled — if some remain, the
  stack object survives. Clear that state and retry.

## merge

- Scope with an argument: a **PR number** merges that PR and every unmerged PR below it; a **stack
  number** merges every unmerged PR in that stack. No argument uses the current branch's stack.
- **All-or-nothing.** If any PR in that exact set cannot merge, none are, and the reason is
  reported.
- Method comes from `--squash`, `--rebase`, `--merge`, or `--merge-method <method>`. Without one,
  the last-used method is reused.
- Only basic PR state is checked before merging (open, not a draft). Bypassing merge requirements
  is not supported for stacks.
- **A merge queue on the base branch overrides everything.** The stack is enqueued rather than
  merged; the queue chooses the method and any method flag is ignored with a warning. Queued PRs
  are submitted together but land as the queue processes them, possibly in separate groups.
- `gh pr merge` cannot merge a stack. Always use `gh stack merge`.

Pre-check before a big land: `gh pr checks <n>` per PR. A member missing a required context blocks
the whole atomic merge — fail-safe, never a silent land. Fix a check-less member by pushing a new
head SHA (amend tip → `rebase --upstack` → `push`).

## Navigation

`up`, `down`, `top`, `bottom` and `trunk` are always non-interactive. `up` and `down` accept a count
(`gh stack up 3`). Movement clamps at the stack bounds, and merged branches are skipped when
navigating from an active branch — so `bottom` lands on the lowest *unmerged* branch.

`gh stack switch` is a selection menu with no non-interactive path. Use the commands above.

## Running a command across the whole stack

There is no built-in equivalent of `st check`. Loop it, with a clean tree (`gh stack` does not
auto-stash for you):

```bash
cur=$(git branch --show-current); fail=0
for b in $(gh stack view --json | jq -r '.branches[].name'); do
  git checkout -q "$b"
  echo "== $b"
  <command> || { fail=1; break; }      # drop the break to keep going
done
git checkout -q "$cur"; exit $fail
```

Run this before submitting — typecheck, tests, lint — so a broken middle layer is caught before
reviewers see it.
