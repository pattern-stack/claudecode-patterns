# Migrating a stack off the retired `st` CLI

The home-grown `st` CLI (`@pattern-stack/stack`) is retired — `gh stack` is the only stacking tool
this skill documents. Use this page only for a stack that `st` still tracks.

**Never let both tools track the same branches.** Each records base tips that the other invalidates
on every rebase.

## Migrate

```bash
st stack status                      # capture branch order (bottom→top) + PR numbers
st submit                            # 🚦 make sure everything is pushed
st delete <name>                     # tracking only — branches and PRs remain
gh stack init <b1> <b2> … <bN>       # adopt, bottom→top
gh stack submit --auto               # 🚦 sign-off — re-bases PRs + creates the stack object
```

- `st`'s PR nav comments stay behind. Delete or ignore them — the GitHub stack UI supersedes them.
- A **dependent** `st` stack (`st create -b <branch>`) has no `gh stack` equivalent; cross-stack
  dependencies are not modeled. Flatten it into one taller stack.
- If you cannot migrate yet, `gh stack link <branches bottom→top>` after each `st submit` gives you
  the stack UI and atomic `gh stack merge` while leaving `st` in charge of local state — `link`
  writes no local tracking, so the two never fight.

## Command mapping

| `st` | `gh stack` |
|---|---|
| `st create <name> -d <desc>` | `gh stack init <branch>` |
| `st create --from b1 b2 b3` | `gh stack init b1 b2 b3` |
| `st branch track` (append at tip) | `gh stack top && gh stack add <name>` |
| `st submit` | `gh stack submit --auto` (drafts) |
| `st submit --ready` | `gh stack submit --auto --open` |
| `st restack` | `gh stack rebase` |
| `st modify -a` (amend + restack) | `git commit --amend` + `gh stack rebase --upstack` |
| `st continue` / `st abort` | `gh stack rebase --continue` / `--abort` |
| `st sync` | `gh stack sync [--prune]` |
| `st merge --all` (daemon cascade) | `gh stack merge --yes` (atomic — nothing to babysit) |
| `st merge --now` | `gh stack merge <bottom-pr#>` |
| `st up`/`down`/`top`/`bottom`, `st <n>` | `up`/`down`/`top`/`bottom`, `checkout <n>` |
| `st nav` | `gh stack switch` (interactive — humans only) |
| `st status` / `st graph` | `gh stack view --json` |
| `st delete [--branches --prs]` | `gh stack unstack` (+ delete branches / close PRs yourself) |
| `st branch fold/pop/move/reorder/rename/insert` | restructure recipes in `troubleshooting.md` |

## Gaps with no direct equivalent

| `st` feature | Replacement |
|---|---|
| `st check <cmd>` | shell loop — see `commands.md` |
| `st absorb` | manual fix routing — see `troubleshooting.md` |
| `st split <specs>` | collapse + re-slice by file manifest, adopt with `init` |
| `st undo` | self-made `backup/*` refs — see `troubleshooting.md` |
| dependent stacks | not modeled — fold into one taller stack |
| `st submit --describe` (AI bodies) | you are the AI: `gh pr edit <n> --body-file` after submit |
| `st comment` (nav comments) | the GitHub stack UI replaces them |
| daemon / auto-merge cascade | unnecessary — `merge` is atomic server-side, queue-aware |

## What `gh stack` adds

- A first-class stack object and stack UI on GitHub — reviewers see the chain natively.
- Atomic all-or-nothing merge, with merge-queue integration.
- `checkout` by stack/PR number or URL from any clone — discovery via API, zero shared state.
- `link` — stack UI + atomic merge for branches managed by any other tool.
- `git rerere` enabled at `init`, so repeated conflict resolutions replay themselves.
