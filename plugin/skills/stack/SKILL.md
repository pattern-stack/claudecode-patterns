---
name: stack
description: Manage PR stacks — create, track, submit, restack, sync, merge, split, navigate, undo, and more. Use when user mentions stacks, stacked PRs, restack, stack submit, merge, split, or branch dependencies.
argument-hint: [create|track|submit|restack|sync|merge|split|nav|status|absorb|undo|delete|remove|check|graph|modify|config|login|pop|fold|continue|abort|daemon|update|init]
allowed-tools: Bash, Read
---

# /stack — PR Stack Management

All operations use the `st` CLI (or `bun run src/cli.ts` in dev). This skill teaches you to use it correctly, recover from problems, and leverage smart features.

## Quick Reference

```
st create <name> -d <desc>     Create stack with first branch
st branch insert --after N -d  Add branch at position
st submit                      Push + create/update all PRs
st submit --ready              Mark drafts as ready for review
st sync                        Clean up after merges on GitHub
st merge --all                 Merge entire stack bottom-up
st restack                     Cascade rebase after mid-stack edit
st modify                      Amend current branch + restack
st check <cmd>                 Run command on every branch
st undo                        Restore previous state
st status                      Show stack + PR status
st graph --all                 Show dependency graph
```

## Command Reference

### Stack Lifecycle
```
st create [name]               Interactive create (prompts for details)
st create <name> -d <desc>     Create with first branch description
st create --from b1 b2 b3      Adopt existing branches into a stack
st create <name> -b <branch>   Create dependent stack (base = another stack's branch)
st create <name> -b .          Create dependent stack from current branch
st delete [name]               Remove stack from tracking
st delete [name] --branches    Also delete local + remote git branches
st delete [name] --prs         Also close open PRs
```

### Branch Operations
```
st branch insert --after N -d <desc>   Insert new branch at position
st branch insert --before N -d <desc>  Insert before position
st branch fold                         Merge current branch into parent
st branch pop [--close]                Remove from stack, keep changes
st branch remove [branch]              Remove branch from tracking
st branch remove --branch --pr         Also delete git branch + close PR
st branch move up|down                 Reorder within stack
st branch reorder 3 1 2 4             Reorder by specifying new positions
st branch rename <new-name>            Rename current branch
st branch track [-s <stack>]           Add current branch to a stack
st branch split <specs...>             Split uncommitted changes into branches
st branch absorb                       Route uncommitted fixes to correct branches
```

### Navigation
```
st up / st down                Move one branch in stack
st top / st bottom             Jump to ends
st <number>                    Jump to branch N (e.g., st 3)
st <stack-name>                Switch to a different stack
st nav                         Interactive branch picker
```

### Submit & Sync
```
st submit                      Push all branches, create/update PRs (drafts by default)
st submit --ready              Mark all PRs as ready for review
st submit --describe           Generate AI PR descriptions
st submit --update             Regenerate descriptions for existing PRs
st submit --dry-run            Preview without pushing
st sync                        Fetch, remove merged branches, rebase remaining
st sync -s <stack>             Sync a specific stack
```

### Merge
```
st merge                       Enable auto-merge on current branch's PR
st merge --all                 Merge entire stack bottom-up (auto-merge cascade)
st merge --now                 Merge current branch immediately (must target trunk)
st merge --dry-run             Preview merge plan
st merge -s <stack>            Target specific stack
```

### Check (Run Command Across Stack)
```
st check <command>             Run command on every branch (bottom to top)
st check --from 3 <command>    Start from branch 3
st check --bail <command>      Stop on first failure
st check --quiet <command>     Suppress command output
st check --json <command>      Machine-readable output
```

**This is incredibly useful.** Use it to:
- Type-check entire stack: `st check bun tsc --noEmit`
- Run tests across branches: `st check --bail bun test`
- Lint check: `st check bunx biome check .`
- Verify builds: `st check bun run build`

Check auto-stashes dirty changes, checks out each branch, runs the command, then restores your branch and stash.

### Recovery
```
st continue                    Resume after resolving rebase conflicts
st abort                       Abort in-progress restack, restore previous state
st undo                        Restore to before last mutating command
st undo --steps 3              Go back 3 operations
st undo --list                 Show available restore points
st undo --dry-run              Preview what would change
```

### Observability
```
st status                      Show stack with PR statuses and checks
st status --json               Machine-readable output
st -i / st --interactive       Interactive graph visualization (TUI)
st graph                       Show current stack as graph
st graph --all                 Show all stacks and dependencies
st graph --expand              Show individual branches in graph
st daemon status               Check daemon health
st daemon attach --stack <n>   Stream daemon logs for a stack
st daemon logs [-f]            View daemon logs (follow with -f)
```

### Daemon Management
```
st daemon start                Start background daemon
st daemon stop                 Stop daemon
st daemon status               Check daemon health
st daemon logs [-f]            View logs (follow with -f)
st daemon attach [-s <stack>]  Stream live log events
st daemon run                  Run daemon in foreground (for debugging)
st daemon setup                Initialize daemon config + secrets
```

### Meta
```
st init                        Install stack skills in project (.claude/skills/)
st update                      Self-update to latest version from GitHub
st completions [shell]         Print shell completion script
st completions --install       Install completions for current shell
```

### Authentication & Configuration
```
st login                       Authenticate with Anthropic OAuth (required for AI features)
st logout                      Clear stored credentials
st config                      Show current config
st config --describe           Enable AI PR descriptions (requires `st login` first)
st config --no-describe        Disable AI PR descriptions
```

## Smart Workflows

### Starting a new feature stack
```bash
st create my-feature -d "add-data-model"
# make changes, commit
st branch insert --after 1 -d "add-api-endpoint"
# make changes, commit
st branch insert --after 2 -d "add-ui-component"
# make changes, commit
st submit                      # creates 3 draft PRs
st submit --ready              # mark ready for review
```

### Mid-stack edits (the power move)
```bash
st 2                           # jump to branch 2
# make edits, stage them
st modify                      # amends + cascades rebase to all downstream
st submit                      # push updated branches + update PRs
```

### Absorb (auto-route fixes to correct branch)
When you have uncommitted changes that fix issues across multiple branches:
```bash
st absorb --dry-run            # preview: shows which files go to which branch
st absorb                      # execute: commits each fix to the right branch
st submit                      # push everything
```

### Split (large changes into a stack)
When you have a big batch of uncommitted changes to organize:
```bash
git diff --stat                # inventory your changes
st split --dry-run --name feature \
  "data-model:src/models/**" \
  "api:src/routes/**:src/middleware/**" \
  "ui:src/components/**:!src/components/legacy/**"
# review the plan, then remove --dry-run to execute
st submit
```
Pattern syntax: `branch-desc:glob[:glob...]` — use `!` prefix for negation.

### Merge entire stack
```bash
st merge --dry-run             # preview the plan
st merge --all                 # enables auto-merge bottom-up
# GitHub merges each PR when CI passes
# Daemon handles cascade: rebase next → retarget → enable auto-merge
```

### After PRs merge on GitHub
```bash
st sync                        # removes merged branches, rebases remaining
# if all merged: stack is cleaned up automatically
```

### Check stack health before submitting
```bash
st check bun tsc --noEmit      # type-check every branch
st check --bail bun test       # test every branch, stop on failure
```

## Recovery Guide

### "Working tree is dirty"
**This shouldn't happen anymore** — most commands auto-stash. If it does:
```bash
git stash                      # stash manually
st <command>                   # run your command
git stash pop                  # restore changes
```

### Rebase conflict during restack/modify
```bash
# Git will pause with conflict markers in files
# 1. Edit the conflicting files to resolve
# 2. Stage resolved files:
git add <resolved-files>
# 3. Continue the restack:
st continue
# OR abort and try a different approach:
st abort
```

### Something went wrong — undo it
```bash
st undo --list                 # see what snapshots exist
st undo                        # go back one operation
st undo --steps 3              # go back 3 operations
```
Snapshots are saved automatically before: sync, restack, modify, absorb, split, fold, insert, move, remove.

### PR in weird state after merge
```bash
st sync                        # let sync clean up merged branches
st submit                      # re-push and update remaining PRs
```

### Branch got out of sync
```bash
st restack                     # cascade rebase from the bottom
st submit                      # push updated branches
```

### Dependent stack's base was merged
```bash
st sync                        # auto-converts to standalone stack
```

### Daemon issues
```bash
st daemon stop                 # stop it
st daemon start                # restart fresh
st daemon status               # check health
st daemon logs -f              # follow log file
st daemon attach               # stream live events
```

## Important Rules

1. **Always `st submit` after mutations** — restack, modify, absorb, and merge-cascade all change branch SHAs. Push them.
2. **Use `st check` before submitting** — catches type errors, test failures, lint issues across the whole stack.
3. **Don't manually `git rebase` stack branches** — use `st restack` or `st modify`. The tool tracks parent tips for smart rebasing.
4. **Don't manually retarget PRs** — `st submit` manages PR base branches. Manual changes will be overwritten.
5. **Use `st sync` after merges** — don't manually delete branches or close PRs. Sync handles cleanup.
6. **`st modify` > manual amend + restack** — `modify` does both in one step and handles edge cases.

## Execution

Run the CLI command directly. Pass through all arguments from `$ARGUMENTS`:

```bash
st $ARGUMENTS
```

If `$ARGUMENTS` is empty, run `st status`.

If `st` is not found, try `bun run src/cli.ts` (dev mode) or tell the user to install:
```bash
bun install -g git+ssh://git@github.com/dugshub/stack.git
```
