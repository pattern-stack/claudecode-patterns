# Dual Worktree Strategy: Claude-Managed & Human-Managed Parallel Development

## Overview

This strategy separates worktrees into two distinct workflows:
1. **Claude-Managed Trees** (`/claude-trees/`): For autonomous agent work and delegation
2. **Human-Managed Trees** (`/dev-trees/`): For your direct development work

## Directory Structure

```
project-root/
├── main/                           # Primary workspace
├── claude-trees/                   # Claude-managed worktrees
│   ├── pts-4-cicd/                # Delegated to cicd-infrastructure-developer
│   ├── pts-8-testing/             # Delegated to test-orchestrator
│   ├── be-13-atoms-data/          # Delegated to pattern-stack-developer
│   └── be-14-atoms-security/      # Delegated to security specialist
├── dev-trees/                      # Human-managed worktrees
│   ├── feature/auth-refactor/     # Your active development
│   ├── hotfix/api-bug/            # Urgent fix you're working on
│   └── experiment/new-pattern/    # Exploratory work
└── .claude/
    ├── trees/                      # Claude's worktree context & state
    │   ├── active.json            # Current active trees & status
    │   ├── pts-4-cicd/            # Per-tree context
    │   │   ├── context.md         # Tree-specific instructions
    │   │   ├── progress.md        # Current progress tracker
    │   │   └── agent.json         # Assigned agent & config
    │   └── coordination.md        # Cross-tree coordination notes
    ├── commands/                   # Custom slash commands
    │   ├── tree-init/             # Initialize worktree patterns
    │   ├── tree-status/           # Check all tree statuses
    │   └── tree-merge/            # Coordinate merging
    └── agents/                     # Agent configurations
```

## Claude-Managed Workflow

### Purpose
- Parallel implementation of related tickets
- Autonomous agent work with minimal supervision
- Bulk progress on well-defined tasks

### Workflow
1. **Initialization Phase**
   ```bash
   # You & Claude identify related tickets
   # Claude creates worktrees for each ticket
   # Claude prepares context in .claude/trees/
   ```

2. **Delegation Phase**
   - Deploy specialized agents to each worktree
   - Provide ticket-specific context
   - Set clear success criteria

3. **Monitoring Phase**
   - Regular status checks across all trees
   - Progress tracking in `.claude/trees/`
   - Linear ticket updates

4. **Integration Phase**
   - You & Claude review completed work
   - Deploy review agents for code quality
   - Coordinate merging strategy
   - Cherry-pick or merge successful implementations

### Claude's Context Management

**`.claude/trees/active.json`**
```json
{
  "claude_managed": [
    {
      "name": "pts-4-cicd",
      "branch": "feature/pts-4-cicd",
      "ticket": "PTS-4",
      "status": "in_progress",
      "agent": "cicd-infrastructure-developer",
      "created": "2025-01-30T10:00:00Z",
      "last_update": "2025-01-30T14:30:00Z"
    }
  ],
  "human_managed": [
    {
      "name": "auth-refactor",
      "branch": "feature/auth-refactor",
      "status": "active",
      "notes": "Human working on auth system redesign"
    }
  ]
}
```

**`.claude/trees/pts-4-cicd/context.md`**
```markdown
# PTS-4 CI/CD Infrastructure Context

## Ticket Summary
Implement GitHub Actions CI/CD pipeline for Pattern Stack

## Current Status
- Created workflow files
- Awaiting review on test configuration
- Blocked on: secrets configuration

## Dependencies
- Requires PTS-8 (testing infrastructure) for full integration
- Coordinating with BE-10 for build process

## Next Steps
1. Complete pytest configuration
2. Add deployment workflow
3. Integrate with Linear for status updates
```

## Human-Managed Workflow

### Purpose
- Complex architectural decisions
- Exploratory development
- Work requiring human judgment

### Integration Points
- Claude monitors your progress
- Can provide assistance when requested
- Tracks dependencies with Claude-managed trees
- Helps coordinate merges

## Coordination Patterns

### Pattern 1: Ticket Bundle Implementation
```
You: "Let's implement PTS-4, PTS-8, and BE-13 through BE-15 in parallel"
Claude:
1. Creates 5 worktrees in /claude-trees/
2. Deploys appropriate agents
3. Tracks progress in .claude/trees/
4. Provides regular status updates
5. Coordinates final integration
```

### Pattern 2: Review & Merge Coordination
```
Claude: "All 5 delegated tasks complete. Ready for review."
You & Claude:
1. Deploy review agents to each tree
2. Address review feedback
3. Coordinate merge order
4. Update Linear tickets
5. Clean up worktrees
```

### Pattern 3: Dependency Management
- Claude tracks cross-tree dependencies
- Alerts when blocking issues arise
- Suggests merge order based on dependencies
- Maintains coordination notes

## Benefits of Dual Approach

1. **Clear Separation of Concerns**
   - Claude's trees: Well-defined, delegatable tasks
   - Your trees: Complex, creative, or exploratory work

2. **Optimized Workflows**
   - Claude can work autonomously on routine tasks
   - You focus on high-value architectural decisions

3. **Better Context Management**
   - Claude maintains detailed context per tree
   - Reduces cognitive load for you

4. **Scalable Collaboration**
   - Can handle 5-10 parallel implementations
   - Clear handoff points for review

## Implementation Commands

### Initialize Claude-Managed Trees
```bash
/claude-tree-init PTS-4 PTS-8 BE-13 BE-14 BE-15
```

### Check All Tree Status
```bash
/tree-status
```

### Coordinate Merge
```bash
/tree-merge --review-first
```

## Success Metrics

- Number of parallel tickets completed
- Time from delegation to merge
- Review cycle efficiency
- Reduced context switching for you
- Cleaner git history through coordinated merges

## Cross-repo isolation

The sections above cover *in-repo* parallelism. The harder failure mode — observed in practice — is **two agents mutating the same working tree across repos** (e.g. an SDLC validator generating into, or validating against, a sibling repo that another agent already owns). Symptoms: stray `worktrees/`, `.claude/worktrees/`, a `.claude copy/`, and named worktrees with duplicate files in the sibling repo — parallel-agent worktree churn that correctness should never have depended on a human remembering to prevent.

Rules (these are guardrails, not suggestions):

1. **In-repo work uses a managed worktree.** When `sdlc.yml.worktree.enabled: true`, `/develop` (and the `/orchestrate` coordinator) spawn the `implementer` with `isolation: "worktree"` — the Agent tool gives it an isolated git worktree, auto-cleaned if unchanged. The lead never hand-manages these paths.

2. **Cross-repo work defaults to a throwaway worktree or clone.** Any step that reads-to-validate or writes-to-generate against a *different* repo must operate on a disposable checkout of that repo — `git worktree add` off the sibling's clone, or a fresh `git clone` into a temp dir — **never** the sibling's primary working tree. Tear it down when the step completes.

3. **Never mutate a tree you don't own.** If another agent (or a human) is active in a repo's working tree, treat it as read-only from the outside. A cross-repo oracle/validation step that needs to *build* must do so in its own isolated checkout, so a concurrent agent's uncommitted state can't corrupt the run (and vice-versa).

4. **Lightweight ownership signal (multi-agent setups).** Before mutating a shared tree, drop/check a `.claude/.session/tree-owner` marker (agent id + ISO timestamp). It's advisory — a cheap "who's holding this tree" lock that lets a second agent back off to its own worktree instead of colliding. Not a substitute for rule 2; a backstop for when isolation was skipped.

**Default:** if you're unsure whether a step touches another repo's tree, isolate. A throwaway worktree is cheap; a corrupted concurrent run is not. See `plugin/commands/develop.md` § "Worktree isolation" (Step 5) for where this is wired into the spawn path.
