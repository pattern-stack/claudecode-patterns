---
description: Generate git commit with proper format
argument-hint: <type> <scope> <description> [issue-id]
allowed-tools:
  - Bash
---

# Generate Git Commit

Atomic command to create a properly formatted commit for staged changes.

**Philosophy**: This command is a simple formatter. The calling agent decides what to commit and when. The agent stages files, this command formats the message.

## Variables

- `$1`: Commit type (feat|fix|test|docs|chore|refactor)
- `$2`: Scope (e.g., atoms/cache, features/users)
- `$3`: Description (e.g., "add Redis adapter")
- `$4`: Issue ID (e.g., TEMPO-101) - optional

## Instructions

### Step 1: Verify Staged Changes

```bash
if [ -z "$(git diff --cached --name-only)" ]; then
  echo "❌ No changes staged for commit"
  echo ""
  echo "The calling agent must stage files first:"
  echo "  git add <file>"
  exit 1
fi
```

### Step 2: Validate Parameters

```bash
TYPE="$1"
SCOPE="$2"
DESCRIPTION="$3"
ISSUE_ID="$4"

if [ -z "$TYPE" ] || [ -z "$SCOPE" ] || [ -z "$DESCRIPTION" ]; then
  echo "❌ Missing required parameters"
  echo ""
  echo "Usage: /commit <type> <scope> <description> [issue-id]"
  echo ""
  echo "Example:"
  echo "  /commit feat \"atoms/cache\" \"add Redis adapter\" TEMPO-101"
  exit 1
fi
```

### Step 3: Generate Commit Message

```bash
if [ -n "$ISSUE_ID" ]; then
  COMMIT_MSG="$TYPE($SCOPE): $DESCRIPTION ($ISSUE_ID)"
else
  COMMIT_MSG="$TYPE($SCOPE): $DESCRIPTION"
fi
```

### Step 4: Create Commit

```bash
git commit -m "$COMMIT_MSG"

if [ $? -eq 0 ]; then
  echo "$COMMIT_MSG"
else
  echo "❌ Commit failed"
  exit 1
fi
```

## Important Notes

**This command does NOT stage files.**

The calling agent/workflow is responsible for:
1. Making specific, atomic changes
2. Staging those changes: `git add <specific-file>`
3. Calling this command with proper context

## Commit Message Format

Follows conventional commit specification:

```
<type>(<scope>): <description> (ISSUE-ID)
```

**Type**: feat|fix|test|docs|chore|refactor
**Scope**: Layer and component (e.g., atoms/cache, features/users, molecules/accounts)
**Description**: Present tense, lowercase, no period (e.g., "add Redis adapter")
**Issue ID**: Optional Linear issue (e.g., TEMPO-101)

## Example Usage (from /implement agent)

```bash
# Agent makes atomic change
# Edit: backend/app/atoms/cache/base.py

# Agent stages ONLY that file
git add backend/app/atoms/cache/base.py

# Agent calls commit with context
/commit feat "atoms/cache" "add CacheInterface" TEMPO-101

# Result: feat(atoms/cache): add CacheInterface (TEMPO-101)

# ───────────────────────────────────────────

# Agent makes next atomic change
# Edit: backend/app/atoms/cache/redis.py

# Agent stages ONLY that file
git add backend/app/atoms/cache/redis.py

# Agent calls commit
/commit feat "atoms/cache" "add RedisAdapter" TEMPO-101

# Result: feat(atoms/cache): add RedisAdapter (TEMPO-101)

# ───────────────────────────────────────────

# Agent adds tests
# Edit: backend/tests/atoms/test_cache.py

# Agent stages test file
git add backend/tests/atoms/test_cache.py

# Agent calls commit with test type
/commit test "atoms/cache" "add cache adapter tests" TEMPO-101

# Result: test(atoms/cache): add cache adapter tests (TEMPO-101)
```

## Agent Workflow Integration

### In /implement or similar workflows:

```markdown
### Making Atomic Commits

After each logical change:

1. Agent analyzes what it changed
2. Agent stages specific files
3. Agent determines type and scope from file paths
4. Agent calls /commit with proper parameters

Example:
```bash
# Just modified backend/app/features/users/service.py
git add backend/app/features/users/service.py
/commit feat "features/users" "add get_user_by_email method" TEMPO-105
```

**Never** use `git add -A` or `git add .` - always stage specific files.
```

## Error Handling

### No Staged Changes
```
❌ No changes staged for commit

The calling agent must stage files first:
  git add <file>
```

### Missing Parameters
```
❌ Missing required parameters

Usage: /commit <type> <scope> <description> [issue-id]

Example:
  /commit feat "atoms/cache" "add Redis adapter" TEMPO-101
```

### Commit Failure
```
❌ Commit failed
```

## Valid Commit Types

- **feat**: New feature or functionality
- **fix**: Bug fix
- **test**: Add or update tests
- **docs**: Documentation changes
- **chore**: Maintenance (dependencies, config)
- **refactor**: Code restructuring without behavior change

## Scope Guidelines

Based on file path:
- `backend/app/atoms/cache/` → `atoms/cache`
- `backend/app/features/users/` → `features/users`
- `backend/app/molecules/accounts/` → `molecules/accounts`
- `backend/app/organisms/api/` → `organisms/api`
- `frontend/src/atoms/Button/` → `atoms/Button`
- `frontend/src/pages/Dashboard/` → `pages/Dashboard`

## Success Criteria

✅ Simple, focused command (does one thing well)
✅ No auto-staging (agent controls what gets committed)
✅ Proper conventional commit format
✅ Clear error messages if misused
✅ Easy to call from agent workflows
✅ Enforces atomic commit discipline
