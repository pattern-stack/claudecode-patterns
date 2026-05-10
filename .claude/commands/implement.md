# Implement - Execute Specification with Strategy-Driven TDD Support

Follow the `Instructions` to implement the `Specs`, then `Report` the completed work.

## Variables

None required - accepts Linear issue IDs as arguments

## Configuration Validation

Before executing, validate .env configuration:

```bash
source .claude/commands/lib/validate-env.sh || exit 1
```

This ensures:
- .env file exists
- Required variables are set (PROJECT_TEAM_KEY, GITHUB_*, etc.)
- Optional Linear keys show warnings if not configured

## Read
.claude/config/project-config.md

## Arguments

- `$1, $2, $3...`: One or more Linear issue IDs (e.g., TEMPO-101 TEMPO-102 TEMPO-103)
- `--tdd`: Force TDD mode (write tests first)
- `--no-tdd`: Force standard mode (implement then test)

## Instructions

**IMPORTANT**: You've just read `project-config.md` which contains all Pattern Stack context.

### Step 1: Verify Prerequisites

For each issue ID provided, verify it's ready for implementation:

**Fetch issue details**:
```markdown
Use task-patterns skill to fetch issue TEMPO-123
```

**Check for strategy approval**:
- Look for label `state:strategy-approved` in the issue
- If not present:
  - ERROR: "Issue TEMPO-123 must have approved strategy before implementation"
  - SUGGEST: "Run /analyze-implementation TEMPO-123 first to generate and approve strategy"
  - EXIT with code 1

**Check status**:
- Issue should be in "Ready" status
- If not in "Ready":
  - Use task-patterns skill to update status to "Ready"

### Step 2: Find or Generate Specifications

For each issue, find the corresponding spec file based on stack label:

**Determine spec location from stack label**:
- `stack:backend` → `application/backend/specs/issue-TEMPO-123-*.md`
- `stack:frontend` → `application/frontend/specs/issue-TEMPO-123-*.md`
- `stack:fullstack` → `specs/issue-TEMPO-123-*.md`

**Check if spec exists**:
```bash
# Example for backend issue
ls application/backend/specs/issue-TEMPO-123-*.md
```

**If spec missing**:
```markdown
WARN: "Spec file not found for TEMPO-123. Auto-generating..."

Use SlashCommand to run: /plan:3-generate-spec TEMPO-123

Wait for spec generation to complete.

Verify spec was created successfully.
```

**Read all spec files** to understand:
- What needs to be implemented
- Architecture layer affected
- Step-by-step tasks
- Validation commands
- Acceptance criteria

### Step 3: Ensure Clean Working State

Before starting implementation:

```markdown
Use git-workflow skill to ensure working directory is clean
```

If working directory has uncommitted changes, the skill will report them. You must:
1. Review changes: What files are modified?
2. Decide action:
   - Commit them (via git-workflow skill)
   - Stash them: `git stash`
   - Discard them: `git restore .`
3. Retry clean state check

### Step 4: Create Feature Branch

For the first issue (or if not on a feature branch):

```markdown
Use git-workflow skill to create feature branch for TEMPO-123
```

The skill will:
- Read branch naming convention from `.env`
- Generate branch name from issue title
- Create and checkout new branch
- Example: `feature/TEMPO-123-add-user-authentication`

### Step 5: Detect TDD Mode

For EACH issue individually, determine if TDD is required:

1. **Check flags first** (highest priority):
   - If `--tdd` flag: TDD mode for ALL issues
   - If `--no-tdd` flag: Standard mode for ALL issues
   - If no flags: continue to step 2

2. **Check Linear labels**:
   - If issue has `tdd:required` label: TDD mode
   - If issue has `type:bug` label: TDD mode (bugs should have regression tests)
   - Otherwise: continue to step 3

3. **Check spec content**:
   - Search spec for keywords: "TDD", "test-first", "red-green-refactor"
   - If found: TDD mode
   - Otherwise: continue to step 4

4. **Ask user**:
   - "Should I use TDD for TEMPO-{number} ({title})?"
   - Explain: TDD = write failing test first, implement, refactor
   - Wait for yes/no

### Step 6: Update Linear Status

Mark issue as in progress:

```markdown
Use task-patterns skill to update status to "In Progress" for TEMPO-123
```

### Step 7: Implement Each Issue

For each issue, follow the mode determined above:

#### TDD Mode (Red-Green-Refactor)

**For each feature/fix in the spec**:

1. **RED - Write Failing Test**:
   - Write a test that validates the desired behavior
   - Run the test: `pytest path/to/test_file.py::test_name -xvs`
   - Verify it FAILS (this proves the test is actually testing something)
   - Commit via git-workflow skill:
     ```markdown
     Use git-workflow skill to commit changes:
     - Type: test
     - Scope: {layer}/{module}
     - Message: add failing test for {feature}
     - Issue: TEMPO-123
     ```

2. **GREEN - Implement Minimum Code**:
   - Write the simplest code that makes the test pass
   - Run the test again: `pytest path/to/test_file.py::test_name -xvs`
   - Verify it PASSES
   - Commit via git-workflow skill:
     ```markdown
     Use git-workflow skill to commit changes:
     - Type: feat
     - Scope: {layer}/{module}
     - Message: implement {feature}
     - Issue: TEMPO-123
     ```

3. **REFACTOR - Improve Quality**:
   - Clean up the code (remove duplication, improve names, etc.)
   - Run test to ensure it still passes
   - If changes made, commit via git-workflow skill:
     ```markdown
     Use git-workflow skill to commit changes:
     - Type: refactor
     - Scope: {layer}/{module}
     - Message: improve {feature} implementation
     - Issue: TEMPO-123
     ```

4. **Repeat** for next feature in spec

#### Standard Mode (Implementation-First)

**For each task in the spec**:

1. **Implement**:
   - Write the implementation following the spec
   - Follow existing patterns in the codebase
   - Use proper type hints
   - Commit via git-workflow skill:
     ```markdown
     Use git-workflow skill to commit changes:
     - Type: feat (or fix, refactor based on work)
     - Scope: {layer}/{module}
     - Message: {description of change}
     - Issue: TEMPO-123
     ```

2. **Test**:
   - Write comprehensive tests for what you just implemented
   - Include edge cases
   - Run: `pytest path/to/test_file.py -xvs`
   - Verify all pass
   - Commit via git-workflow skill:
     ```markdown
     Use git-workflow skill to commit changes:
     - Type: test
     - Scope: {layer}/{module}
     - Message: add tests for {feature}
     - Issue: TEMPO-123
     ```

3. **Repeat** for next task in spec

### Step 8: Run Quality Gates

After ALL issues are implemented, run quality gates via the quality-gates skill:

**Format**:
```markdown
Use quality-gates skill to run format
```

If auto-formatting made changes:
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty)
- Message: auto-format code
- Issue: TEMPO-123
```

**Lint**:
```markdown
Use quality-gates skill to run lint
```

If auto-fixes were applied:
```markdown
Use git-workflow skill to commit changes:
- Type: style
- Scope: (empty)
- Message: auto-fix lint issues
- Issue: TEMPO-123
```

**Type Check**:
```markdown
Use quality-gates skill to run typecheck
```

If errors: Report them and EXIT. User must fix type errors manually.

**Architecture Validation**:
```markdown
Use quality-gates skill to run validate
```

If errors: Report violations and EXIT. User must fix architecture issues.

**Tests**:
```markdown
Use quality-gates skill to run tests
```

If failures: Report them and EXIT. User must fix failing tests.

**If all gates pass**: Proceed to Linear update and PR creation.

### Step 9: Update Linear Progress

After implementing each issue:

```markdown
Use task-patterns skill to post comment to TEMPO-123:

"Implementation complete!

✅ {Summary of what was implemented}
✅ Tests written and passing
✅ Coverage: {percentage}%

Quality gates:
✅ Format
✅ Lint
✅ Type Check
✅ Architecture Validation
✅ Tests

Next: Creating PR"
```

### Step 10: Create Pull Request

Create PR with full traceability:

```markdown
Use git-workflow skill to create PR for TEMPO-123
```

**Note**: The git-workflow skill will delegate to the `/pr` command which:
- Fetches issue details from Linear
- Reads strategy comment if exists
- Reads spec file
- Generates comprehensive PR description
- Creates PR via `gh` CLI
- Links Linear issue to PR

### Step 11: Final Linear Status Update

Mark issue as in review:

```markdown
Use task-patterns skill to update status to "In Review" for TEMPO-123
```

## Implementation Guidelines

### Follow Atomic Architecture

From `project-config.md`, respect layer boundaries:
- **Atoms**: Can only import other atoms
- **Features**: Can only import atoms
- **Molecules**: Can import features + atoms
- **Organisms**: Can import all layers

### Use Existing Patterns

Before implementing, check for similar code:
- Look in the target layer for examples
- Follow established patterns (don't reinvent)
- Use Field abstraction for models
- Use BaseService for services
- Use FastAPI patterns for organisms/api

### Code Quality Standards

- Use type hints everywhere
- Write docstrings for public APIs
- Keep functions small and focused
- Prefer composition over inheritance
- Use async/await for I/O operations

### Commit Standards

ALL commits MUST go through git-workflow skill (never call git directly):

**Scope Examples**:
- Backend: `atoms/cache`, `features/users`, `molecules/apis`, `organisms/api`
- Frontend: `atoms/button`, `organisms/header`, `pages/dashboard`
- Specs: `specs`, `backend/specs`, `frontend/specs`
- Commands: `commands/implement`, `skills/git-workflow`

**Commit Type Guide**:
- `feat`: New feature or functionality
- `fix`: Bug fix or correction
- `test`: Adding or modifying tests
- `docs`: Documentation changes (specs, README, etc.)
- `refactor`: Code restructuring without behavior change
- `style`: Auto-formatting, auto-fixes (no logic change)
- `chore`: Dependencies, build, config

**Examples**:
```
feat(atoms/security): add JWT utilities (TEMPO-123)
test(atoms/security): add JWT utility tests (TEMPO-123)
feat(features/users): add login/register methods (TEMPO-123)
docs(specs): add implementation spec for TEMPO-123 (TEMPO-123)
style: auto-format code (TEMPO-123)
```

## Report

After all issues are implemented and gates pass:

### Summary Format

```
Implementation Complete ✅
=========================

Issues Implemented:
✅ TEMPO-101: Create cache abstraction layer
✅ TEMPO-102: Implement Redis cache adapter
✅ TEMPO-103: Add caching to UserService

Implementation Mode:
- TEMPO-101: TDD (test-first)
- TEMPO-102: TDD (test-first)
- TEMPO-103: Standard (implementation-first)

Strategy Verification:
✅ All issues had approved strategies
✅ Specs generated/validated before implementation

Changes:
- Files created: {number}
- Files modified: {number}
- Total tests: {number} (all passing)
- Coverage: {percentage}%

Git Summary:
{show diff stats via git diff --stat working-files}

Quality Gates:
✅ Format
✅ Lint
✅ Type Check
✅ Architecture Validation
✅ Tests ({percentage}% coverage)

Pull Request:
- PR #{number}: {title}
- URL: {pr_url}
- Linked to: TEMPO-101, TEMPO-102, TEMPO-103

Linear Status:
✅ All issues moved to "In Review"
✅ Implementation comments posted
✅ Ready for code review

Next Steps:
- Review PR: {pr_url}
- Assign reviewers
- Wait for approval
- Merge when ready
```

### Linear Status

All issues should be:
- ✅ Marked as "In Review" via task-patterns skill
- ✅ Commented with implementation summary
- ✅ Linked to PR
- ✅ Ready for review

## Integration

- **Called after**: `/plan:3-generate-spec` creates specs AND `/analyze-implementation` approves strategy
- **Calls**: `quality-gates` skill for validation, `git-workflow` skill for ALL git operations
- **Before**: Human code review, then merge

## Example Usage

```bash
# Implement all sub-issues for an epic
/implement TEMPO-101 TEMPO-102 TEMPO-103

# Implement single issue with forced TDD
/implement TEMPO-104 --tdd

# Implement without TDD
/implement TEMPO-105 --no-tdd
```

## Notes

- **Strategy Required**: Issues MUST have `state:strategy-approved` label
- **Auto-Generate Specs**: Missing specs are auto-generated
- **Atomic Commits**: Via git-workflow skill only - NEVER call git directly
- **Test Coverage**: Aim for 90%+ on new code (80% minimum)
- **TDD Default**: Bugs get TDD by default, features ask user
- **Quality Gates**: Auto-runs via quality-gates skill
- **Linear Integration**: Updates progress throughout
- **100% Commit Consistency**: All commits follow project conventions via git-workflow skill
