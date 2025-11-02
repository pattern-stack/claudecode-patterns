# Ensure Feature Branch

Atomic command to ensure the workflow is running on a feature branch, not main/master. Called by any workflow that makes git commits.

## Purpose

Prevents accidental commits to protected branches by enforcing feature branch usage before any commit-making operations.

**Philosophy**: Branch protection is the ultimate safety net, but workflows should be defensive and guide users toward correct branching practices.

## Variables

- `$1`: Issue identifier (e.g., BE-101, TASK-24) - optional but recommended
- `--auto-create`: Automatically create feature branch if on main (optional)
- `--branch-name=<name>`: Specific branch name to use (optional)

## When to Use

Call this atomic command at the start of any workflow that will make git commits:
- `/implement` - before writing code
- `/fix` - before fixing issues
- Any custom workflow that commits

**DO NOT** call for read-only workflows:
- `/plan` - only creates Linear issues
- `/generate-spec` - only writes spec files (not committed)
- `/test` - only runs tests

## Instructions

### Step 1: Check Current Branch

```bash
CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
  echo "❌ Error: Not in a git repository or detached HEAD state"
  exit 1
fi
```

### Step 2: Check if on Protected Branch

```bash
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  PROTECTED_BRANCH=true
else
  PROTECTED_BRANCH=false
fi
```

### Step 3: If on Feature Branch, Continue

```bash
if [ "$PROTECTED_BRANCH" = "false" ]; then
  echo "✓ On feature branch: $CURRENT_BRANCH"
  echo "✓ Safe to proceed with commits"
  exit 0
fi
```

### Step 4: On Protected Branch - Look for Existing Feature Branch

```bash
# If on main/master, look for existing feature branch
ISSUE_ID="$1"

if [ -n "$ISSUE_ID" ]; then
  # Check if issue has parent epic
  PARENT_EPIC=$(tp show $ISSUE_ID 2>/dev/null | grep "Parent:" | awk '{print $2}' | tr -d '[:space:]')

  if [ -n "$PARENT_EPIC" ]; then
    # Look for epic's feature branch
    BRANCH_PATTERN="feature/${PARENT_EPIC}-*"
  else
    # Look for issue's feature branch
    BRANCH_PATTERN="feature/${ISSUE_ID}-*"
  fi

  EXISTING_BRANCH=$(git branch --list "$BRANCH_PATTERN" | head -1 | tr -d ' *')
fi
```

### Step 5: Handle Auto-Create Mode

```bash
if [ "$AUTO_CREATE" = "true" ]; then
  # Auto-create branch

  if [ -n "$EXISTING_BRANCH" ]; then
    # Checkout existing branch
    echo "✓ Found existing branch: $EXISTING_BRANCH"
    git checkout "$EXISTING_BRANCH"
    echo "✓ Switched to $EXISTING_BRANCH"
    exit 0
  fi

  if [ -n "$BRANCH_NAME" ]; then
    # Use provided branch name
    NEW_BRANCH="$BRANCH_NAME"
  elif [ -n "$ISSUE_ID" ]; then
    # Generate branch name from issue
    ISSUE_TITLE=$(tp show $ISSUE_ID 2>/dev/null | grep "Title:" | sed 's/Title: //')
    SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | cut -c1-40)
    NEW_BRANCH="feature/${ISSUE_ID}-${SLUG}"
  else
    # Generic feature branch
    NEW_BRANCH="feature/$(date +%Y%m%d)-work"
  fi

  echo "✓ Creating new branch: $NEW_BRANCH"
  git checkout -b "$NEW_BRANCH"
  echo "✓ Switched to $NEW_BRANCH"
  exit 0
fi
```

### Step 6: Error with Helpful Guidance

```bash
# Not auto-creating, provide helpful error
echo "❌ Cannot commit on protected branch: $CURRENT_BRANCH"
echo ""

if [ -n "$EXISTING_BRANCH" ]; then
  echo "Found existing feature branch for this issue:"
  echo ""
  echo "  git checkout $EXISTING_BRANCH"
  echo ""
else
  echo "No existing feature branch found."
  echo ""

  if [ -n "$ISSUE_ID" ]; then
    # Suggest branch name based on issue
    ISSUE_TITLE=$(tp show $ISSUE_ID 2>/dev/null | grep -A 1 "==> $ISSUE_ID:" | tail -1 | sed 's/^[[:space:]]*//')
    if [ -n "$ISSUE_TITLE" ]; then
      SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | cut -c1-40)
      SUGGESTED_BRANCH="feature/${ISSUE_ID}-${SLUG}"
    else
      SUGGESTED_BRANCH="feature/${ISSUE_ID}-work"
    fi
  else
    SUGGESTED_BRANCH="feature/$(date +%Y%m%d)-work"
  fi

  echo "Create a feature branch:"
  echo ""
  echo "  git checkout -b $SUGGESTED_BRANCH"
  echo ""
fi

echo "Then run your workflow command again."
echo ""
echo "Tip: Use --auto-create flag to automatically create/checkout branch:"
echo "  /implement $ISSUE_ID --auto-create"

exit 1
```

## Return Values

- **Exit 0**: On feature branch, safe to proceed
- **Exit 1**: On protected branch, provided helpful error message

## Usage Examples

### Called by /implement

```bash
# At start of /implement workflow
ISSUE_ID="$1"

# Ensure on feature branch before implementing
/ensure-feature-branch $ISSUE_ID

# If exits 0, continue with implementation
# If exits 1, user sees error and guidance
```

### With Auto-Create

```bash
# User invokes with auto-create
/implement BE-101 --auto-create

# Internally calls:
/ensure-feature-branch BE-101 --auto-create

# If on main, automatically:
# 1. Looks for existing feature/BE-97-* (parent epic branch)
# 2. If found, checkouts existing
# 3. If not found, creates feature/BE-101-{slug}
```

### Manual Invocation

```bash
# User can call directly to check
/ensure-feature-branch BE-101

# Output:
# ✓ On feature branch: feature/BE-97-redis-caching
# ✓ Safe to proceed with commits
```

## Integration with Workflows

### /implement

```markdown
### Phase 0: Pre-flight Checks

**Step 1: Ensure Feature Branch**

```bash
ISSUE_ID="$1"

# Check branch safety
if [ "$AUTO_CREATE" = "true" ]; then
  /ensure-feature-branch $ISSUE_ID --auto-create
else
  /ensure-feature-branch $ISSUE_ID
fi

# If command exits with error (exit 1), workflow stops here
# User sees helpful guidance on how to fix
```
```

### /fix

```markdown
### Phase 0: Pre-flight Checks

**Step 1: Ensure Feature Branch**

```bash
# Always auto-create for fixes (convenience)
/ensure-feature-branch $ISSUE_ID --auto-create
```
```

## Branch Naming Convention

**Format**: `feature/{issue-id}-{slug}`

**Examples**:
- `feature/BE-101-cache-abstraction`
- `feature/TASK-24-batch-update-operations`
- `feature/BE-97-redis-user-caching` (epic branch)

**Slug Generation**:
- Extracted from issue title
- Lowercased
- Alphanumeric and hyphens only
- Max 40 characters
- Consecutive hyphens collapsed

**Epic Branch Usage**:
- When implementing child issue (e.g., BE-101)
- Checks for parent epic branch (e.g., feature/BE-97-*)
- Uses epic branch if exists (all children share epic branch)
- Creates issue-specific branch if no epic

## Error Messages

### On Main Branch (no auto-create)

```
❌ Cannot commit on protected branch: main

Found existing feature branch for this issue:

  git checkout feature/BE-97-redis-caching

Then run your workflow command again.

Tip: Use --auto-create flag to automatically create/checkout branch:
  /implement BE-101 --auto-create
```

### On Main Branch (no existing branch)

```
❌ Cannot commit on protected branch: main

No existing feature branch found.

Create a feature branch:

  git checkout -b feature/BE-101-cache-abstraction

Then run your workflow command again.

Tip: Use --auto-create flag to automatically create/checkout branch:
  /implement BE-101 --auto-create
```

### Not a Git Repo

```
❌ Error: Not in a git repository or detached HEAD state
```

## Notes

- **Lightweight**: Simple bash, no heavy dependencies
- **Defensive**: Prevents accidents, guides users
- **Flexible**: Works with or without issue IDs
- **Epic-Aware**: Understands parent-child relationships
- **Convention-Based**: Follows feature/ naming pattern
- **User-Friendly**: Clear error messages with actionable guidance

## Implementation Checklist

To add branch safety to a workflow:

- [ ] Add `--auto-create` parameter to workflow Variables
- [ ] Call `/ensure-feature-branch` in Phase 0 (Pre-flight Checks)
- [ ] Pass `--auto-create` flag if workflow parameter set
- [ ] Workflow automatically stops if on protected branch
- [ ] User sees helpful guidance on how to proceed

## Success Criteria

✅ Detects protected branches (main, master)
✅ Allows feature branches to proceed
✅ Discovers existing feature branches
✅ Understands epic parent-child relationships
✅ Provides clear, actionable error messages
✅ Supports auto-create mode for convenience
✅ Generates sensible branch names from issue titles
✅ Never accidentally commits to main
