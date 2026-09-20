# Troubleshooting and recovery

## Contents

- [Make your own restore points](#make-your-own-restore-points)
- [Rebase conflicts (exit 3)](#rebase-conflicts-exit-3)
- [Mid-flight state that looks finished](#mid-flight-state-that-looks-finished)
- [After a squash merge](#after-a-squash-merge)
- [Local and remote stacks have diverged](#local-and-remote-stacks-have-diverged)
- [Restructuring a stack](#restructuring-a-stack)
- [Routing fixes to their owning branches](#routing-fixes-to-their-owning-branches)
- [Tracking desync](#tracking-desync)
- [Branch belongs to several stacks (exit 6)](#branch-belongs-to-several-stacks-exit-6)
- [Driving stacks from another tool or worktree](#driving-stacks-from-another-tool-or-worktree)
- [Stack file is locked (exit 8)](#stack-file-is-locked-exit-8)
- [An interrupted modify session (exit 10)](#an-interrupted-modify-session-exit-10)

## Make your own restore points

There is no `gh stack undo` and no snapshots. `rebase --abort` restores branches **only while a
rebase is in flight**. Before any surgery, sync, or fix-routing:

```bash
for b in $(gh stack view --json | jq -r '.branches[].name'); do
  git branch -f "backup/$b" "$b"
done
```

Restore with `git branch -f <b> backup/<b>` per branch, then re-adopt (`unstack --local` + `init`).
For anything the backups missed, `git reflog` per branch. Delete the backups once verified.

## Rebase conflicts (exit 3)

`rebase` and `sync` both exit 3 on conflict. `sync` restores every branch to its pre-rebase state
first, so a failed `sync` leaves nothing half-applied; a failed `rebase` stops mid-flight and waits.

```bash
gh stack rebase
# exit 3 — conflicted paths listed on stderr
git add <resolved paths>
gh stack rebase --continue     # repeat if the next branch also conflicts
```

`gh stack rebase --abort` restores **every** branch in the stack, not just the current one.

Because `init` enables `git rerere`, a conflict resolved once replays automatically the next time it
appears — common, since a low change is rebased through every branch above it.

**"All conflicts fixed" but `--continue` refuses.** Git's error often names the wrong cause: the
real gate is usually *unstaged* files elsewhere in the tree (scratch docs, local-only config). Prove
the index is clean (`git ls-files -u` is empty), set the strays aside by **copy** (not stash),
`git restore` them, continue, then copy back.

**A conflict on a commit that is already upstream.** Prove it, then skip:

```bash
git merge-base --is-ancestor <sha> HEAD && git rebase --skip
```

**Stale rerere state** (`.git/MERGE_RR` holding an empty-delta entry): run `git rerere` to clear.

## Mid-flight state that looks finished

Before trusting any cascade, check both:

```bash
ls .git/rebase-merge 2>/dev/null && echo "STILL REBASING"
for pair in "b1 b2" "b2 b3"; do set -- $pair; git merge-base --is-ancestor "$1" "$2" \
  && echo "ok $1 -> $2" || echo "BROKEN $1 -> $2"; done
```

Branch refs still showing the previous cascade's SHAs read as "done" if you skip the ancestry check.
Print SHAs when you compare — an empty-vs-empty diff reads as "SAME".

## After a squash merge

A squash merge replaces the branch's commits with one new commit, so the originals no longer exist
in trunk's history and an ordinary rebase would replay them again.

`gh stack sync` detects this and rebases with `--onto` against the correct target, skipping the
merged branch:

```bash
gh stack sync
gh stack view --json      # merged branch reports "isMerged": true, "state": "MERGED"
```

No manual action needed. If the replay conflicts, `sync` restores all branches and exits 3 — run
`gh stack rebase` to rerun it, resolve, and `--continue`. Add `--prune` to delete local branches for
merged PRs.

## Local and remote stacks have diverged

Divergence means local and the GitHub stack changed in different ways — e.g. branches added locally
while a PR was added to the stack on github.com.

Non-interactive `sync` prints both chains, changes nothing, and exits **0** with `Sync aborted`.
**Success here does not mean the sync happened** — check for that message, or re-run
`gh stack view --json` and compare. Don't force anything; surface both chains to the human.

Two resolution paths, neither of which deletes PRs or branches:

```bash
# Keep the remote version
gh stack unstack --local            # keeps the stack on GitHub
gh stack checkout <stack-number>    # or a PR number

# Keep the local version
gh stack unstack                    # removes the grouping; PRs and branches survive
gh stack submit --auto              # 🚦 sign-off
```

Remote unstacking leaves PRs that are queued or have auto-merge enabled stacked — clear that state
before retrying.

## Restructuring a stack

There is no non-interactive reorder, rename, or removal. `add` from the wrong branch suggests
`gh stack modify`, but that is TUI-only and must never be invoked by an agent. Tear down and rebuild:

```bash
# 0. SNAPSHOT first (see above)
gh stack unstack                       # removes local tracking and the GitHub grouping
# 1. Rewrite ancestry with git (recipes below)
gh stack init --base main b1 b2 b3     # bottom→top, the NEW order; adopts existing branches
gh stack submit --auto                 # 🚦 sign-off — updates PR bases and re-links the stack
```

Changing metadata does **not** change git ancestry. Reorder commits first, then rebuild.

**Insert a layer between `b2` and `b3`:**

```bash
git checkout -b b2.5 b2                       # ...commit the new layer...
git rebase --onto b2.5 b2 b3 --update-refs    # moves b3..top in one shot
```

`--update-refs` is load-bearing — it moves every intermediate branch ref with one rebase instead of
N cascades.

**Fold `b2` into `b1`:**

```bash
git checkout b1 && git merge --ff-only b2     # or cherry-pick if not fast-forwardable
git rebase --onto b1 b2 b3 --update-refs      # reparent the rest
git branch -D b2                              # close its PR yourself: gh pr close <n>
```

**Pop `b2` out, keeping the work elsewhere:**

```bash
git rebase --onto b1 b2 b3 --update-refs      # bridge over b2
gh stack unstack --local && gh stack init b1 b3 …
```

**Reorder** `main <- models <- migration <- ui` into `main <- migration <- models <- ui`:

```bash
old_models=$(git rev-parse models)
old_migration=$(git rev-parse migration)
git rebase --onto main "$old_models" migration
git rebase --onto migration main models
git rebase --onto models "$old_migration" ui
gh stack unstack
gh stack init --base main migration models ui
```

Preserve the old boundary SHAs before moving any branch. For a different reorder, identify each
layer's range with `git log <old-parent>..<branch>` and replay bottom to top.

**Hazards.** Every recipe rewrites SHAs above the surgery point, so the next `submit`/`push`
force-pushes (with lease) the whole chain — don't run while another session holds those branches.
Verify after: ancestry per adjacent pair, and `git diff backup/<top> <top>` is empty unless the
restructure intended a content change.

## Routing fixes to their owning branches

No `st absorb` equivalent. Route by hand — the owning branch is the one whose diff already touches
the file:

```bash
# 1. Find the owner of each file
for b in $(gh stack view --json | jq -r '.branches[].name'); do
  echo "== $b"; git diff --name-only "$b^" "$b"
done

# 2. For each owning branch, BOTTOM-UP:
git stash push -- <files-for-this-branch>     # only that branch's files
gh stack checkout <owning-branch>
git stash pop && git add -A && git commit --amend --no-edit
gh stack rebase --upstack                     # cascade before routing the next batch
```

- **`git add` untracked files for real** before any stash routing — intent-to-add (`git add -N`)
  breaks stash machinery.
- **Route bottom-up and cascade between batches**, or upper branches replay stale tips.

## Tracking desync

Cause: manual `git branch -f`, raw rebases, or ref surgery outside `gh stack`. The base SHAs
recorded in `.git/gh-stack` are stale, so `needsRebase` and the ⚠ markers lie. Fix is always
re-adoption:

```bash
gh stack unstack --local
gh stack init <b1> <b2> … <bN>      # bottom→top, the current true order
```

## Branch belongs to several stacks (exit 6)

Commands exit 6 when the current branch cannot identify a single stack — typically because it is the
trunk of more than one. There is no disambiguation flag.

```bash
gh stack checkout <a-branch-unique-to-the-intended-stack>
```

Commands that take an explicit stack number (`merge 7`, `unstack 7`) sidestep it entirely.

## Driving stacks from another tool or worktree

`gh stack link` creates and updates stacks purely through the API, with no local tracking state. Use
it when branches are managed by jj, Sapling, git-town, a separate worktree, or any workflow where
`.git/gh-stack` would be wrong or absent.

```bash
gh stack link branch-a branch-b branch-c     # bottom to top
gh stack link --base develop --open a b c    # non-default trunk, ready for review
gh stack link 10 20 30                       # by PR number
gh stack link 7 feature-d                    # append to existing stack #7
```

Local navigation will not work on the result. `gh stack checkout <stack-number>` adds tracking later.

## Stack file is locked (exit 8)

Another `gh stack` process holds the exclusive lock on `.git/gh-stack.lock`. It times out after
about five seconds — wait and retry. A persistent exit 8 means another process still holds it;
identify and stop that process first.

## An interrupted modify session (exit 10)

`gh stack modify` is TUI-only and should never be invoked by an agent. If someone leaves a
repository in this state:

```bash
gh stack modify --abort
```

`submit` also detects a pending modify state, and under a TTY asks before overwriting the GitHub
stack with local state.
