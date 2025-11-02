# Claude Local Configuration Strategy

## Overview

The Pattern Stack project uses a two-tier Claude configuration system:

1. **Shared Configuration** (`.claude/`) - Committed to git, shared across all developers
2. **Local Configuration** (`.claude/local/`) - Git-ignored, worktree-specific overrides

## Configuration Loading Order

Claude settings are loaded in the following priority (highest to lowest):

1. `.claude/local/settings.json` (if exists)
2. `.claude/settings.json` (repository defaults)
3. Claude system defaults

## Setting Up Local Overrides

### 1. Local Settings File

Create `.claude/local/settings.json` for worktree-specific settings:

```json
{
  "project": {
    "worktree": "feature/pts-4-cicd",
    "currentFocus": "CI/CD Infrastructure"
  },
  "development": {
    "activeTicket": "PTS-5",
    "testMode": true
  }
}
```

### 2. Local Agent Configurations

Store worktree-specific agents in `.claude/local/agents/`:

```markdown
# .claude/local/agents/debug-agent.md
A specialized agent for debugging CI/CD issues in this worktree...
```

### 3. Local Context Files

Keep work-in-progress notes in `.claude/local/context/`:

- `current-work.md` - Active development notes
- `debug-notes.md` - Debugging information
- `local-todos.md` - Worktree-specific tasks

## Dual-Worktree Configuration Example

### Main Worktree
`.claude/local/settings.json`:
```json
{
  "worktree": "main",
  "mode": "hotfix",
  "preferences": {
    "autoTest": true,
    "verbosity": "minimal"
  }
}
```

### Feature Worktree
`.claude/local/settings.json`:
```json
{
  "worktree": "feature/pts-4-cicd",
  "mode": "development",
  "preferences": {
    "autoTest": false,
    "verbosity": "detailed"
  }
}
```

## Implementation Notes

- The local directory structure mirrors the main `.claude/` structure
- Local settings merge with (don't replace) shared settings
- Each worktree maintains its own `.claude/local/` directory
- Local configurations are never committed to git

## Benefits

1. **Isolation**: Each worktree can have different active tasks/contexts
2. **Flexibility**: Override shared settings without affecting others
3. **Security**: Keep sensitive information out of version control
4. **Experimentation**: Test new configurations locally before sharing
