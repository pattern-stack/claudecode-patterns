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
