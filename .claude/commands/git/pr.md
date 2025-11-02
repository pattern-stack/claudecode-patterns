---
description: Create GitHub pull request with proper format
argument-hint: <issue-id> <pr-title> [--base=BRANCH]
allowed-tools:
  - Bash
---

# Create Pull Request

Atomic command to create a properly formatted GitHub pull request for the current branch.

**Philosophy**: This command is a simple PR creator. The calling agent determines PR content and context. The agent analyzes changes, this command creates the PR.

## Variables

- `$1`: Issue identifier (e.g., TEMPO-32, BE-101)
- `$2`: PR title (e.g., "Refactor git commands into dedicated subdirectory")
- `--base=<branch>`: Base branch for PR (default: main)
- `--draft`: Create as draft PR (optional)

## Instructions

### Step 1: Verify We're on a Feature Branch

```bash
# Call ensure-feature-branch to verify we're on a valid feature branch
# This will exit with error if on main/master
/ensure-feature-branch

# If we get here, we're on a valid feature branch
CURRENT_BRANCH=$(git branch --show-current)
```

### Step 2: Validate Parameters

```bash
ISSUE_ID="$1"
PR_TITLE="$2"
BASE_BRANCH="${BASE:-main}"

if [ -z "$ISSUE_ID" ] || [ -z "$PR_TITLE" ]; then
  echo "❌ Missing required parameters"
  echo ""
  echo "Usage: /pr <issue-id> <pr-title> [--base=BRANCH]"
  echo ""
  echo "Example:"
  echo "  /pr TEMPO-32 \"Refactor git commands into dedicated subdirectory\""
  exit 1
fi
```

### Step 3: Verify Branch is Pushed

```bash
# Check if branch exists on remote
if ! git ls-remote --heads origin "$CURRENT_BRANCH" | grep -q "$CURRENT_BRANCH"; then
  echo "❌ Branch not pushed to remote"
  echo ""
  echo "Push first:"
  echo "  git push -u origin $CURRENT_BRANCH"
  exit 1
fi

# Check if local is ahead of remote
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/$CURRENT_BRANCH 2>/dev/null)

if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
  echo "❌ Local branch has unpushed commits"
  echo ""
  echo "Push first:"
  echo "  git push"
  exit 1
fi
```

### Step 4: Fetch Issue Details from Linear

```bash
# Get issue details for PR body
ISSUE_INFO=$(tp show "$ISSUE_ID" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "⚠️  Warning: Could not fetch issue details from Linear"
  ISSUE_TITLE="$PR_TITLE"
  ISSUE_URL=""
else
  # Extract issue title and URL
  ISSUE_TITLE=$(echo "$ISSUE_INFO" | grep "Title:" | sed 's/Title: //' | xargs)
  ISSUE_URL=$(echo "$ISSUE_INFO" | grep "View at:" | awk '{print $NF}')
fi
```

### Step 5: Analyze Changes

```bash
# Get commit summary
COMMITS=$(git log origin/$BASE_BRANCH..HEAD --oneline)
COMMIT_COUNT=$(echo "$COMMITS" | wc -l | xargs)

# Get changed files
CHANGED_FILES=$(git diff origin/$BASE_BRANCH...HEAD --name-only)
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | xargs)

# Get diff stats
DIFF_STATS=$(git diff origin/$BASE_BRANCH...HEAD --stat)
```

### Step 6: Generate PR Body

```bash
# Build PR body with Linear issue integration
PR_BODY=$(cat <<EOF
## Linear Issue

Closes [$ISSUE_ID]($ISSUE_URL)

**Title**: $ISSUE_TITLE

## Summary

$PR_TITLE

## Changes

$FILE_COUNT files changed across $COMMIT_COUNT commits

\`\`\`
$DIFF_STATS
\`\`\`

## Commits

\`\`\`
$COMMITS
\`\`\`

## Checklist

- [ ] All quality gates pass
- [ ] Tests added/updated
- [ ] Documentation updated (if needed)
- [ ] Linear issue reviewed
- [ ] Ready for review

---

**Linear**: $ISSUE_URL
EOF
)
```

### Step 7: Create Pull Request

```bash
# Determine if draft flag is set
DRAFT_FLAG=""
if [ "$DRAFT" = "true" ]; then
  DRAFT_FLAG="--draft"
fi

# Create PR using GitHub CLI
PR_URL=$(gh pr create \
  --base "$BASE_BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  $DRAFT_FLAG 2>&1 | grep -o 'https://.*')

if [ -z "$PR_URL" ]; then
  echo "❌ Failed to create pull request"
  echo ""
  echo "Ensure GitHub CLI is authenticated:"
  echo "  gh auth login"
  exit 1
fi

echo "$PR_URL"
```

## Important Notes

**This command does NOT:**
- Analyze what changed (agent does this)
- Determine PR title (agent provides it)
- Auto-push commits (must be pushed first)
- Make commits (use /commit for that)

**The calling agent/workflow is responsible for:**
1. Making changes and commits
2. Pushing branch to remote
3. Determining appropriate PR title
4. Calling this command with proper context

## Example Usage (from /implement agent)

```bash
# Agent has completed implementation
# Agent has made multiple atomic commits
# Agent is ready to create PR

# 1. Agent pushes branch
git push -u origin feature/TEMPO-32-git-commands

# 2. Agent calls PR command with context
/pr TEMPO-32 "Refactor git commands into dedicated subdirectory"

# Result: PR created with proper formatting and issue linkage
# Returns: https://github.com/org/repo/pull/123
```

## PR Title Format

Keep it simple and descriptive:
- "Refactor git commands into dedicated subdirectory"
- "Add Redis caching to user service"
- "Fix authentication timeout issue"

**Don't include:**
- Issue type prefix (feat:, fix:) - this is for commits, not PRs
- Issue number in title - it's in the body

## PR Body Sections

1. **Issue** - Link to Linear issue
2. **Summary** - What this PR does
3. **Changes** - Diff stats showing file changes
4. **Commits** - List of commits included
5. **Checklist** - Review readiness checklist

## Agent Workflow Integration

### In /implement or similar workflows:

```markdown
### Final Step: Create Pull Request

After all commits are made and pushed:

1. Agent determines PR title from issue
2. Agent ensures branch is pushed
3. Agent calls /pr with issue ID and title

Example:
```bash
# Implementation complete, branch pushed
/pr TEMPO-32 "Refactor git commands into dedicated subdirectory"
```

Agent should verify before calling /pr:
- All commits made
- All quality gates pass
- Branch pushed to remote
- Ready for review
```

## Error Handling

### Not on Feature Branch
```
❌ Cannot create PR from protected branch: main
Switch to a feature branch first
```

### Branch Not Pushed
```
❌ Branch not pushed to remote

Push first:
  git push -u origin feature/TEMPO-32-git-commands
```

### Unpushed Commits
```
❌ Local branch has unpushed commits

Push first:
  git push
```

### Missing Parameters
```
❌ Missing required parameters

Usage: /pr <issue-id> <pr-title> [--base=BRANCH]

Example:
  /pr TEMPO-32 "Refactor git commands into dedicated subdirectory"
```

### GitHub CLI Not Authenticated
```
❌ Failed to create pull request

Ensure GitHub CLI is authenticated:
  gh auth login
```

## Advanced Usage

### Create Draft PR
```bash
/pr TEMPO-32 "Work in progress changes" --draft
```

### Target Different Base Branch
```bash
/pr TEMPO-32 "Hotfix for production issue" --base=production
```

### From Agent with Full Context
```bash
# Agent implementation workflow
# 1. Makes changes
# 2. Commits atomically: /commit feat "atoms/cache" "add interface" TEMPO-32
# 3. Pushes: git push -u origin feature/TEMPO-32-cache-interface
# 4. Creates PR: /pr TEMPO-32 "Add cache interface to atoms layer"
```

## Success Criteria

✅ Simple, focused command (does one thing well)
✅ Agent provides context (issue ID, title)
✅ Proper PR formatting with Linear integration
✅ Clear error messages if preconditions not met
✅ Returns PR URL for agent to use
✅ Easy to call from agent workflows
