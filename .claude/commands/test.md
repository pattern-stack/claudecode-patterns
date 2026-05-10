# Quality Gate Validation with Auto-Fix

Run comprehensive quality gates with automatic fixes and retry loop.

## Purpose

Execute all quality gates for the current stack (backend/frontend/fullstack) with automatic fixing where possible:
- Auto-format code (format gate)
- Auto-fix safe lint issues (lint gate)
- Report type errors (typecheck gate)
- Run test suite (test gate)
- Retry loop on failures (max 3 attempts)

**Philosophy**: Quality gates prevent bad code from reaching review. This command runs gates, applies auto-fixes, commits them atomically, and loops until all gates pass or manual intervention is required.

## Usage

```bash
/test [ISSUE-ID]
```

**Parameters**:
- `ISSUE-ID` (optional): Linear issue ID for commit messages (e.g., TEMPO-123)

## Variables

- `issue_id`: $1 (optional - used in commit messages)
- `max_attempts`: 3 (maximum retry attempts)
- `current_attempt`: 1 (increments on each loop)

## Read

- `.claude/config/project-config.md` - Quality gate configuration
- `.env` - Project conventions

## Workflow

### Step 1: Detect Stack

Use the quality-gates skill to detect current stack:
```markdown
Use quality-gates skill to detect stack
```

**Expected Response**: `backend`, `frontend`, or `fullstack`

**Validation**:
- If stack detection fails, exit with error
- If fullstack, ask user which stack to run gates for

### Step 2: Run Format Gate (Auto-Fix)

Use the quality-gates skill to run format gate:
```markdown
Use quality-gates skill to run format gate with --fix flag
```

**Expected Behavior**:
- Skill executes `make format` (backend) or `npm run lint:fix` (frontend)
- Returns: `{ "passed": boolean, "auto_fixed": boolean, "files_changed": [] }`

**If Changes Made** (`auto_fixed: true`):
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty string)
- Message: auto-format code
- Issue: {ISSUE_ID} (if provided, otherwise omit)
```

### Step 3: Run Lint Gate (Auto-Fix)

Use the quality-gates skill to run lint gate:
```markdown
Use quality-gates skill to run lint gate with --fix flag
```

**Expected Behavior**:
- Skill executes `make lint` with safe fixes (backend) or `npm run lint` (frontend)
- Returns: `{ "passed": boolean, "auto_fixed": boolean, "error_count": number, "errors": [] }`

**If Changes Made** (`auto_fixed: true`):
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty string)
- Message: auto-fix lint issues
- Issue: {ISSUE_ID} (if provided, otherwise omit)
```

**If Errors Remain** (`passed: false`):
- Display errors with file paths and line numbers
- Continue to next gate (errors will be caught in retry loop)

### Step 4: Run Type Check Gate (Report Only)

Use the quality-gates skill to run typecheck gate:
```markdown
Use quality-gates skill to run typecheck gate
```

**Expected Behavior**:
- Skill executes `make typecheck` (backend) or `npm run type-check` (frontend)
- Returns: `{ "passed": boolean, "error_count": number, "errors": [] }`
- NO auto-fixing available

**If Errors** (`passed: false`):
- Display all type errors with file paths and line numbers
- Ask user: "Type errors found. Continue to tests or exit?"
  - If continue: proceed to Step 5
  - If exit: stop and report status
  - Default: continue

### Step 5: Run Test Gate

Use the quality-gates skill to run test gate:
```markdown
Use quality-gates skill to run test gate
```

**Expected Behavior**:
- Skill executes `make test-ci` (backend) or `npm run test` (frontend)
- Returns: `{ "passed": boolean, "test_count": number, "failures": [], "coverage_percent": number }`
- NO auto-fixing available

**If Tests Pass** (`passed: true`):
- Display coverage percentage
- Validate coverage meets threshold (80% default)
- If coverage too low: FAIL with message

**If Tests Fail** (`passed: false`):
- Display failed test names and error messages
- Mark for retry loop

### Step 6: Evaluate Results and Retry Loop

**Logic**:

```python
if all_gates_passed:
    display_success_report()
    exit(0)
elif current_attempt >= max_attempts:
    display_failure_report()
    exit(1)
elif manual_fixes_required:
    display_current_status()
    ask_user: "Failures detected. Fix and retry (y) or Exit (n)?"
    if yes: increment attempt, return to Step 2
    if no: display report, exit(1)
```

**Retry Behavior**:
- If user chooses retry, wait for them to make changes
- Then restart from Step 2 (format gate)
- Increment `current_attempt`
- Show: "Retry attempt {current_attempt}/{max_attempts}"

### Step 7: Final Report

**Success Report**:
```
Quality Gates Report
====================
Stack: backend
Attempt: 1/3

✅ Format: PASSED (auto-fixed and committed)
✅ Lint: PASSED (auto-fixed and committed)
✅ Type Check: PASSED
✅ Tests: PASSED (142 tests, 89% coverage)

All quality gates passed! ✅
```

**Failure Report**:
```
Quality Gates Report
====================
Stack: backend
Attempt: 3/3 (max attempts reached)

✅ Format: PASSED (auto-fixed and committed)
⚠️  Lint: PARTIAL (2 manual fixes required)
❌ Type Check: FAILED (1 error)
❌ Tests: FAILED (2 of 142 tests)

Summary: 2 gates failed after 3 attempts

Next Steps:
1. Fix lint issues (run: make lint for details)
2. Fix type error in app/features/users/service.py:15
3. Fix failing tests: test_user_login, test_get_account
4. Re-run: /test TEMPO-123
```

## Integration Notes

### Called By
- `/implement` - After each implementation step
- Manual invocation - Developers run anytime

### Depends On
- quality-gates skill (`.claude/skills/quality-gates/SKILL.md`)
- git-workflow skill (`.claude/skills/git-workflow/SKILL.md`)
- Project configuration (`.claude/config/project-config.md`)

### Outputs
- Git commits (via git-workflow skill for auto-fixes)
- Console report (structured text)
- Exit code (0 = success, 1 = failure)

## Examples

### Example 1: All Gates Pass on First Try

```bash
$ /test TEMPO-123

Detecting stack... backend

✅ Format: PASSED (no changes needed)
✅ Lint: PASSED (no issues)
✅ Type Check: PASSED
✅ Tests: PASSED (142 tests, 89% coverage)

All quality gates passed! ✅
```

### Example 2: Auto-Fixes Applied

```bash
$ /test TEMPO-123

Detecting stack... backend

✅ Format: PASSED (auto-fixed and committed)
   Committed: style: auto-format code (TEMPO-123)

✅ Lint: PASSED (auto-fixed and committed)
   Committed: style: auto-fix lint issues (TEMPO-123)

✅ Type Check: PASSED
✅ Tests: PASSED (142 tests, 89% coverage)

All quality gates passed! ✅
```

### Example 3: Failures Require Manual Fix

```bash
$ /test TEMPO-123

Detecting stack... backend

✅ Format: PASSED (auto-fixed and committed)
✅ Lint: PASSED (auto-fixed and committed)
❌ Type Check: FAILED (2 errors)
   - app/features/users/service.py:15: Incompatible types

Type errors found. Continue to tests? (y/n): y

❌ Tests: FAILED (1 of 142 tests)
   - test_user_login: AssertionError: Expected 200, got 401

Failures detected. Fix and retry? (y/n): y

[user fixes code]

Retry attempt 2/3

✅ Format: PASSED
✅ Lint: PASSED
✅ Type Check: PASSED
✅ Tests: PASSED (142 tests, 89% coverage)

All quality gates passed! ✅
```

## Notes

- Reduced from 354 lines to ~200 lines by delegating to quality-gates skill
- All git operations go through git-workflow skill for 100% consistency
- Quality gate commands are defined in quality-gates skill, not hardcoded
- Retry loop allows iterative fixing without restarting from scratch
- Auto-fix commits are atomic and properly attributed to issues
