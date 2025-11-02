---
name: Quality Gates
description: Centralized quality gate execution for backend, frontend, and fullstack projects. Use when running format, lint, typecheck, or tests. Auto-detects stack and runs appropriate commands. Does NOT commit - calling command uses git-workflow skill.
---

# Quality Gates Skill

Centralized quality validation for tempo-demo workflows.

## Purpose

Provide consistent quality gate execution:
- Auto-detect stack (backend/frontend/fullstack)
- Run appropriate commands per stack
- Return status for calling command to handle
- Does NOT commit (calling command uses git-workflow skill)

## Core Responsibility

This skill is the single source of truth for quality gate execution. Commands should use this skill's functions rather than calling quality commands directly. This guarantees:
- ✅ Consistent execution across all workflows
- ✅ Proper stack detection and command routing
- ✅ Standardized return formats
- ✅ Separation of concerns (gates vs commits)

## Functions

### 1. detect_stack()

**Purpose**: Determine if backend, frontend, or fullstack based on context

**Usage**:
```markdown
Use quality-gates skill to detect stack
```

**Implementation**:
```bash
# Priority 1: Check .env PROJECT_STACK variable
if [ -f .env ]; then
  source .env 2>/dev/null
  if [ -n "$PROJECT_STACK" ]; then
    echo "$PROJECT_STACK"
    return
  fi
fi

# Priority 2: Detect from current directory
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" == *"/application/backend"* ]]; then
  echo "backend"
  return
elif [[ "$CURRENT_DIR" == *"/application/frontend"* ]]; then
  echo "frontend"
  return
fi

# Priority 3: Check for both backend and frontend existence
BACKEND_EXISTS=false
FRONTEND_EXISTS=false

if [ -f "application/backend/pyproject.toml" ]; then
  BACKEND_EXISTS=true
fi

if [ -f "application/frontend/package.json" ]; then
  FRONTEND_EXISTS=true
fi

if [ "$BACKEND_EXISTS" = true ] && [ "$FRONTEND_EXISTS" = true ]; then
  echo "fullstack"
elif [ "$BACKEND_EXISTS" = true ]; then
  echo "backend"
elif [ "$FRONTEND_EXISTS" = true ]; then
  echo "frontend"
else
  echo "unknown"
fi
```

**Returns**:
- `backend` - Backend-only work
- `frontend` - Frontend-only work
- `fullstack` - Both stacks present
- `unknown` - Cannot determine

---

### 2. run_format()

**Purpose**: Auto-format code, return whether changes were made

**Usage**:
```markdown
Use quality-gates skill to run format
```

**Implementation**:
```bash
# Detect stack first
STACK=$(detect_stack)

case "$STACK" in
  backend)
    cd application/backend || exit 1

    # Capture files before formatting
    BEFORE=$(git diff --name-only | sort)

    # Run format
    uv run ruff format .

    # Check if changes were made
    AFTER=$(git diff --name-only | sort)

    if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
      echo "CHANGES_MADE"
      return 0
    else
      echo "NO_CHANGES"
      return 0
    fi
    ;;

  frontend)
    cd application/frontend || exit 1

    # Capture files before formatting
    BEFORE=$(git diff --name-only | sort)

    # Run format
    npm run format

    # Check if changes were made
    AFTER=$(git diff --name-only | sort)

    if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
      echo "CHANGES_MADE"
      return 0
    else
      echo "NO_CHANGES"
      return 0
    fi
    ;;

  fullstack)
    # Run both, aggregate results
    BACKEND_RESULT="NO_CHANGES"
    FRONTEND_RESULT="NO_CHANGES"

    # Backend
    if [ -f "application/backend/pyproject.toml" ]; then
      cd application/backend || exit 1
      BEFORE=$(git diff --name-only | sort)
      uv run ruff format .
      AFTER=$(git diff --name-only | sort)
      if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
        BACKEND_RESULT="CHANGES_MADE"
      fi
      cd ../..
    fi

    # Frontend
    if [ -f "application/frontend/package.json" ]; then
      cd application/frontend || exit 1
      BEFORE=$(git diff --name-only | sort)
      npm run format
      AFTER=$(git diff --name-only | sort)
      if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
        FRONTEND_RESULT="CHANGES_MADE"
      fi
      cd ../..
    fi

    # Determine overall result
    if [ "$BACKEND_RESULT" = "CHANGES_MADE" ] || [ "$FRONTEND_RESULT" = "CHANGES_MADE" ]; then
      echo "CHANGES_MADE"
    else
      echo "NO_CHANGES"
    fi
    return 0
    ;;

  *)
    echo "ERROR: Unknown stack"
    return 1
    ;;
esac
```

**Returns**:
- `CHANGES_MADE` - Files were modified by formatting
- `NO_CHANGES` - No formatting changes needed
- `ERROR: {message}` - Execution failed

**Calling Command Responsibility**:
If `CHANGES_MADE`, use git-workflow skill to commit:
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty)
- Message: auto-format code
- Issue: {ISSUE_ID}
```

---

### 3. run_lint()

**Purpose**: Lint code with auto-fix where possible

**Usage**:
```markdown
Use quality-gates skill to run lint
```

**Implementation**:
```bash
# Detect stack first
STACK=$(detect_stack)

case "$STACK" in
  backend)
    cd application/backend || exit 1

    # Capture files before linting
    BEFORE=$(git diff --name-only | sort)

    # Run lint with auto-fix
    if uv run ruff check --fix .; then
      # Check if changes were made
      AFTER=$(git diff --name-only | sort)

      if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
        echo "CHANGES_MADE"
        return 0
      else
        echo "PASSED"
        return 0
      fi
    else
      # Lint failed - capture errors
      echo "FAILED"
      return 1
    fi
    ;;

  frontend)
    cd application/frontend || exit 1

    # Capture files before linting
    BEFORE=$(git diff --name-only | sort)

    # Run lint
    if npm run lint; then
      # Check if changes were made
      AFTER=$(git diff --name-only | sort)

      if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
        echo "CHANGES_MADE"
        return 0
      else
        echo "PASSED"
        return 0
      fi
    else
      echo "FAILED"
      return 1
    fi
    ;;

  fullstack)
    # Run both, aggregate results
    BACKEND_RESULT="PASSED"
    FRONTEND_RESULT="PASSED"
    OVERALL_EXIT=0

    # Backend
    if [ -f "application/backend/pyproject.toml" ]; then
      cd application/backend || exit 1
      BEFORE=$(git diff --name-only | sort)
      if uv run ruff check --fix .; then
        AFTER=$(git diff --name-only | sort)
        if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
          BACKEND_RESULT="CHANGES_MADE"
        fi
      else
        BACKEND_RESULT="FAILED"
        OVERALL_EXIT=1
      fi
      cd ../..
    fi

    # Frontend
    if [ -f "application/frontend/package.json" ]; then
      cd application/frontend || exit 1
      BEFORE=$(git diff --name-only | sort)
      if npm run lint; then
        AFTER=$(git diff --name-only | sort)
        if [ "$BEFORE" != "$AFTER" ] || [ -n "$(git diff)" ]; then
          FRONTEND_RESULT="CHANGES_MADE"
        fi
      else
        FRONTEND_RESULT="FAILED"
        OVERALL_EXIT=1
      fi
      cd ../..
    fi

    # Determine overall result
    if [ "$OVERALL_EXIT" -ne 0 ]; then
      echo "FAILED"
      return 1
    elif [ "$BACKEND_RESULT" = "CHANGES_MADE" ] || [ "$FRONTEND_RESULT" = "CHANGES_MADE" ]; then
      echo "CHANGES_MADE"
      return 0
    else
      echo "PASSED"
      return 0
    fi
    ;;

  *)
    echo "ERROR: Unknown stack"
    return 1
    ;;
esac
```

**Returns**:
- `CHANGES_MADE` - Auto-fixes were applied
- `PASSED` - Lint passed with no changes
- `FAILED` - Lint errors that cannot be auto-fixed
- `ERROR: {message}` - Execution failed

**Calling Command Responsibility**:
If `CHANGES_MADE`, use git-workflow skill to commit:
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty)
- Message: auto-fix lint issues
- Issue: {ISSUE_ID}
```

If `FAILED`, report errors and potentially fix manually.

---

### 4. run_typecheck()

**Purpose**: Type checking (reports errors, no auto-fix)

**Usage**:
```markdown
Use quality-gates skill to run typecheck
```

**Implementation**:
```bash
# Detect stack first
STACK=$(detect_stack)

case "$STACK" in
  backend)
    cd application/backend || exit 1

    # Run type check
    if uv run mypy --strict .; then
      echo "PASSED"
      return 0
    else
      echo "FAILED"
      return 1
    fi
    ;;

  frontend)
    cd application/frontend || exit 1

    # Run type check
    if npm run type-check; then
      echo "PASSED"
      return 0
    else
      echo "FAILED"
      return 1
    fi
    ;;

  fullstack)
    # Run both, aggregate results
    BACKEND_EXIT=0
    FRONTEND_EXIT=0

    # Backend
    if [ -f "application/backend/pyproject.toml" ]; then
      cd application/backend || exit 1
      if ! uv run mypy --strict .; then
        BACKEND_EXIT=1
      fi
      cd ../..
    fi

    # Frontend
    if [ -f "application/frontend/package.json" ]; then
      cd application/frontend || exit 1
      if ! npm run type-check; then
        FRONTEND_EXIT=1
      fi
      cd ../..
    fi

    # Determine overall result
    if [ "$BACKEND_EXIT" -ne 0 ] || [ "$FRONTEND_EXIT" -ne 0 ]; then
      echo "FAILED"
      return 1
    else
      echo "PASSED"
      return 0
    fi
    ;;

  *)
    echo "ERROR: Unknown stack"
    return 1
    ;;
esac
```

**Returns**:
- `PASSED` - Type check passed
- `FAILED` - Type errors found (stderr contains details)
- `ERROR: {message}` - Execution failed

**Note**: Typecheck cannot auto-fix. Calling command should report errors and potentially attempt manual fixes.

---

### 5. run_tests()

**Purpose**: Run test suite

**Usage**:
```markdown
Use quality-gates skill to run tests
```

**Implementation**:
```bash
# Detect stack first
STACK=$(detect_stack)

case "$STACK" in
  backend)
    cd application/backend || exit 1

    # Run tests
    if uv run pytest --cov --cov-report=term-missing; then
      echo "PASSED"
      return 0
    else
      echo "FAILED"
      return 1
    fi
    ;;

  frontend)
    cd application/frontend || exit 1

    # Run tests
    if npm test; then
      echo "PASSED"
      return 0
    else
      echo "FAILED"
      return 1
    fi
    ;;

  fullstack)
    # Run both, aggregate results
    BACKEND_EXIT=0
    FRONTEND_EXIT=0

    # Backend
    if [ -f "application/backend/pyproject.toml" ]; then
      cd application/backend || exit 1
      if ! uv run pytest --cov --cov-report=term-missing; then
        BACKEND_EXIT=1
      fi
      cd ../..
    fi

    # Frontend
    if [ -f "application/frontend/package.json" ]; then
      cd application/frontend || exit 1
      if ! npm test; then
        FRONTEND_EXIT=1
      fi
      cd ../..
    fi

    # Determine overall result
    if [ "$BACKEND_EXIT" -ne 0 ] || [ "$FRONTEND_EXIT" -ne 0 ]; then
      echo "FAILED"
      return 1
    else
      echo "PASSED"
      return 0
    fi
    ;;

  *)
    echo "ERROR: Unknown stack"
    return 1
    ;;
esac
```

**Returns**:
- `PASSED` - All tests passed
- `FAILED` - Test failures (stderr contains details)
- `ERROR: {message}` - Execution failed

**Note**: Tests cannot auto-fix. Calling command should report failures.

---

### 6. run_all()

**Purpose**: Run all gates in sequence

**Usage**:
```markdown
Use quality-gates skill to run all gates
```

**Implementation**:
```markdown
Run in order:
1. Use quality-gates skill to run format
   - If CHANGES_MADE: Calling command should commit via git-workflow
2. Use quality-gates skill to run lint
   - If CHANGES_MADE: Calling command should commit via git-workflow
3. Use quality-gates skill to run typecheck
   - If FAILED: Report errors
4. Use quality-gates skill to run tests
   - If FAILED: Report failures

Return: Overall pass/fail status based on all gates
```

**Returns**:
- `ALL_PASSED` - All gates passed (format and lint may have made changes that were committed)
- `SOME_FAILED` - One or more gates failed
- `ERROR: {message}` - Execution failed

**Note**: This is a meta-function that orchestrates the other functions. The calling command is responsible for:
1. Committing format/lint changes via git-workflow skill
2. Handling typecheck/test failures
3. Potentially re-running after fixes

---

## Usage in Commands

### Pattern: /implement

```markdown
## Quality Gate Execution

1. Use quality-gates skill to run format
   - If CHANGES_MADE:
     Use git-workflow skill to commit changes:
     - Type: style
     - Scope: (empty)
     - Message: auto-format code
     - Issue: {ISSUE_ID}

2. Use quality-gates skill to run lint
   - If CHANGES_MADE:
     Use git-workflow skill to commit changes:
     - Type: style
     - Scope: (empty)
     - Message: auto-fix lint issues
     - Issue: {ISSUE_ID}
   - If FAILED: Report errors, potentially fix

3. Use quality-gates skill to run typecheck
   - If FAILED: Report errors, potentially fix

4. Use quality-gates skill to run tests
   - If FAILED: Report failures
```

### Pattern: /test

```markdown
## Quality Gate Validation

Use quality-gates skill to run all gates

Handle results:
- Format/Lint CHANGES_MADE: Commit via git-workflow
- Typecheck/Test FAILED: Report and loop until fixed
```

---

## Stack Detection Logic

### Priority 1: .env Variable

Check for `PROJECT_STACK` variable in `.env`:
```bash
PROJECT_STACK=backend     # Forces backend
PROJECT_STACK=frontend    # Forces frontend
PROJECT_STACK=fullstack   # Forces fullstack
```

### Priority 2: Current Directory

Detect from current working directory:
- In `application/backend/` → backend
- In `application/frontend/` → frontend

### Priority 3: Project Structure

Check for existence of both stacks:
- Both `application/backend/pyproject.toml` AND `application/frontend/package.json` → fullstack
- Only `application/backend/pyproject.toml` → backend
- Only `application/frontend/package.json` → frontend

---

## Gate Commands by Stack

### Backend Gates

**Working Directory**: `application/backend/`

- **Format**: `uv run ruff format .`
  - Auto-fixes: Yes
  - Can commit: Yes

- **Lint**: `uv run ruff check --fix .`
  - Auto-fixes: Partial (safe fixes only)
  - Can commit: Yes (if changes made)

- **Typecheck**: `uv run mypy --strict .`
  - Auto-fixes: No
  - Can commit: No

- **Tests**: `uv run pytest --cov --cov-report=term-missing`
  - Auto-fixes: No
  - Can commit: No

### Frontend Gates

**Working Directory**: `application/frontend/`

- **Format**: `npm run format`
  - Auto-fixes: Yes
  - Can commit: Yes

- **Lint**: `npm run lint`
  - Auto-fixes: Partial
  - Can commit: Yes (if changes made)

- **Typecheck**: `npm run type-check`
  - Auto-fixes: No
  - Can commit: No

- **Tests**: `npm test`
  - Auto-fixes: No
  - Can commit: No

### Fullstack Gates

Run both backend and frontend gates sequentially:
1. Run backend gate
2. Run frontend gate
3. Aggregate results

**Result Aggregation**:
- `CHANGES_MADE` if either stack has changes
- `FAILED` if either stack fails
- `PASSED` only if both pass with no changes

---

## Error Handling

### Gate Execution Failures

If a gate command fails to execute:
1. Capture stderr
2. Return `ERROR: {message}`
3. Calling command should handle and potentially abort

### Stack Detection Failures

If stack cannot be determined:
1. Return `ERROR: Unknown stack`
2. Suggest:
   - Add `PROJECT_STACK=backend|frontend|fullstack` to `.env`
   - Or run from correct directory
   - Or check project structure

### Missing Dependencies

If required tools are missing:
1. Backend: `uv` not installed
2. Frontend: `npm` not installed
3. Return `ERROR: Missing dependency: {tool}`
4. Suggest installation instructions

---

## Best Practices

1. **Always detect stack first** - Never assume stack type
2. **Run gates in order** - Format → Lint → Typecheck → Test
3. **Commit format/lint changes separately** - Via git-workflow skill
4. **Don't commit typecheck/test fixes** - Let developer fix properly
5. **Handle errors gracefully** - Return clear status codes
6. **Aggregate results for fullstack** - Report both stacks clearly
7. **Use absolute paths** - When changing directories
8. **Capture git state** - Before and after for change detection

---

## Integration with Other Skills

### With git-workflow Skill

Quality-gates skill detects changes, git-workflow skill commits them:

```markdown
# Quality-gates skill
Use quality-gates skill to run format
# Returns: CHANGES_MADE

# Git-workflow skill
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty)
- Message: auto-format code
- Issue: TEMPO-123
```

**Why Separate?**
- Quality-gates focuses on execution and detection
- Git-workflow focuses on commit formatting and conventions
- Single responsibility principle
- Commands can choose when/how to commit

### With task-patterns Skill

Quality-gates can be used before/after Linear operations:

```markdown
# Before implementation
Use task-patterns skill to fetch issue TEMPO-123
Use quality-gates skill to run all gates  # Ensure clean starting state

# After implementation
Use quality-gates skill to run all gates
Use task-patterns skill to comment on TEMPO-123 with gate results
```

---

## Troubleshooting

### Skill not detecting correct stack

**Solution**:
```bash
# Add to .env
PROJECT_STACK=backend  # or frontend or fullstack
```

### Format/lint not finding files

**Solution**:
- Ensure you're in project root
- Check that `application/backend/` or `application/frontend/` exist
- Verify `pyproject.toml` or `package.json` exist

### Commands return "ERROR: Unknown stack"

**Solution**:
1. Check directory structure
2. Add `PROJECT_STACK` to `.env`
3. Ensure at least one stack exists

### Typecheck passes in skill but fails manually

**Solution**:
- Check that same command is being run
- Verify working directory
- Check for environment differences

---

## Examples

### Example 1: Backend Format with Commit

```markdown
## Command: /implement TEMPO-123

1. Use quality-gates skill to detect stack
   # Returns: backend

2. Use quality-gates skill to run format
   # Returns: CHANGES_MADE

3. Use git-workflow skill to commit changes:
   - Type: style
   - Scope: (empty)
   - Message: auto-format code
   - Issue: TEMPO-123
   # Commits format changes
```

### Example 2: Fullstack All Gates

```markdown
## Command: /test

1. Use quality-gates skill to run all gates
   # Runs format, lint, typecheck, test for both backend and frontend
   # Returns: SOME_FAILED (backend typecheck failed)

2. Report: Backend typecheck failed with 3 errors
   - Fix type errors manually
   - Re-run: Use quality-gates skill to run typecheck
   # Returns: PASSED

3. Use quality-gates skill to run all gates
   # Returns: ALL_PASSED
```

### Example 3: Frontend Lint with Auto-Fix

```markdown
## Command: /implement TEMPO-456

1. Use quality-gates skill to detect stack
   # Returns: frontend

2. Use quality-gates skill to run lint
   # Returns: CHANGES_MADE (auto-fixed unused imports)

3. Use git-workflow skill to commit changes:
   - Type: style
   - Scope: (empty)
   - Message: auto-fix lint issues
   - Issue: TEMPO-456
```

---

## Testing the Skill

### Manual Testing

```bash
# Test stack detection
STACK=$(detect_stack)
echo "Detected stack: $STACK"

# Test format (no commit)
RESULT=$(run_format)
echo "Format result: $RESULT"

# Test lint
RESULT=$(run_lint)
echo "Lint result: $RESULT"

# Test typecheck
RESULT=$(run_typecheck)
echo "Typecheck result: $RESULT"

# Test tests
RESULT=$(run_tests)
echo "Tests result: $RESULT"
```

### Integration Testing

From a command:
```markdown
Use quality-gates skill to run all gates
# Verify all gates execute correctly
# Verify correct stack is detected
# Verify results are properly returned
```

---

## Future Enhancements

Potential additions (not required now):

1. **Custom Coverage Thresholds**: Pass coverage minimum to run_tests()
2. **Parallel Execution**: Run backend and frontend gates in parallel for fullstack
3. **Detailed Error Parsing**: Return structured error objects
4. **Gate Timing**: Report execution time per gate
5. **Selective Gate Execution**: Run only specific gates
6. **Watch Mode**: Continuous gate execution on file changes

---

**Ready to use! This skill provides consistent quality validation across all tempo-demo workflows.**
