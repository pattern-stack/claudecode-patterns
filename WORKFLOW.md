# Autonomous Development Workflow

**Complete guide to the AI-assisted development workflow with strategy approval and PR review gates.**

---

## Quick Start (5 Lines)

```bash
/plan:decompose "Add user caching"           # 1. Generate YAML plan
/plan:create-issues issue-plan-*.yaml        # 2. Create Linear issues
/analyze-implementation TEMPO-123            # 3. AI generates strategy → posts to Linear
# Review strategy in Linear, add state:strategy-approved label
/implement TEMPO-123                         # 4. AI implements → creates PR
# Review PR in GitHub, approve, merge
```

**Result**: Feature shipped with full traceability and only 2 human touchpoints (strategy + PR review).

---

## Table of Contents

1. [Overview](#overview)
2. [Detailed Workflow (Step-by-Step)](#detailed-workflow-step-by-step)
3. [Human Gates Explained](#human-gates-explained)
4. [Configuration](#configuration)
5. [Troubleshooting](#troubleshooting)
6. [Tips & Best Practices](#tips--best-practices)
7. [Command Reference](#command-reference)

---

## Overview

This workflow enables **~80% AFK development** with only two human approval gates:

1. **Strategy Approval** - Review high-level approach before implementation
2. **PR Review** - Review actual code before merge

Everything else (planning, spec generation, coding, testing, quality gates) is automated.

### Workflow States

```
Triage → Backlog → Refinement → Ready → In Progress → In Review → Done
           ↑           ↑ GATE 1     ↑                    ↑ GATE 2
         /plan      Strategy      Spec              PR Review
                   Approval     Generated           (GitHub)
                   (Linear)
```

### Time Investment

- **Morning (15-30 min)**: Batch review strategies in Linear
- **Afternoon (~5 min)**: PRs ready for review
- **Evening**: Merge approved PRs

---

## Detailed Workflow (Step-by-Step)

### Phase 1: Planning

**Goal**: Break requirements into structured issues in Linear.

#### Step 1.1: Decompose Requirements

```bash
/plan:decompose "Add Redis caching to user service"
```

**What happens**:
- AI asks clarifying questions (interactive)
- Analyzes scope and complexity
- Generates structured YAML plan
- Commits YAML to project root

**Output**: `issue-plan-redis-caching.yaml`

**Review the YAML**:
```bash
cat issue-plan-redis-caching.yaml
```

**YAML Structure**:
```yaml
epic:
  title: "Epic: Add Redis Caching to User Service"
  description: |
    Problem: User service queries are slow...
    Approach: Implement Redis cache layer...
    Success: 90% cache hit rate, <10ms response times
  labels: [type:epic, stack:backend, work:infrastructure, layer:atoms, layer:features]
  status: Refinement

  children:
    - title: "Create Redis cache adapter"
      description: "Implement adapter in atoms layer..."
      labels: [type:feature, stack:backend, work:infrastructure, layer:atoms]
      status: Refinement

    - title: "Add caching to UserService"
      description: "Integrate cache in features layer..."
      labels: [type:feature, stack:backend, work:feature, layer:features]
      status: Refinement
```

**Why it stops here**: Allows you to review and edit the plan before creating issues.

---

#### Step 1.2: Create Linear Issues

```bash
/plan:create-issues issue-plan-redis-caching.yaml
```

**What happens**:
- Creates epic in Linear (TEMPO-100)
- Creates all child issues (TEMPO-101, TEMPO-102)
- Links children to parent epic
- Applies labels from YAML
- Sets all to "Refinement" status

**Output**:
```
✅ Created Epic: TEMPO-100 - "Epic: Add Redis Caching to User Service"
✅ Created Children:
   - TEMPO-101 - "Create Redis cache adapter"
   - TEMPO-102 - "Add caching to UserService"

Next: /analyze-implementation TEMPO-101
```

**Result**: Issues exist in Linear in Refinement status, ready for strategy generation.

---

### Phase 2: Strategy Generation (AI)

**Goal**: AI generates high-level implementation strategies for batch human review.

#### Step 2.1: Generate Strategy

```bash
/analyze-implementation TEMPO-101
```

**What the AI analyzes**:
- Issue description and requirements
- Codebase patterns (similar implementations)
- Affected layers (atoms/features/molecules/organisms)
- Architecture approach
- Dependencies (other issues, Pattern Stack patterns)
- Testing strategy
- Estimated complexity

**What gets generated**:
1. **Strategy document** (committed to branch):
   - Location: `application/backend/specs/strategy-TEMPO-101.md`
   - Contents: High-level approach, architecture impact, dependencies

2. **Linear comment** posted to issue:

```markdown
## 🤖 Implementation Strategy

**Issue**: TEMPO-101 - Create Redis cache adapter
**Analyzed**: 2025-11-02 14:30 UTC

### Approach
Create Redis cache adapter in atoms layer following Pattern Stack patterns.
Use Field() for configuration, implement async operations, follow existing
cache patterns from codebase.

### Architecture Impact
**Layer**: atoms (infrastructure)

**New Files**:
- `atoms/cache/redis.py` - Redis adapter implementation
- `atoms/cache/__init__.py` - Export cache utilities

**Modified Files**:
- `atoms/cache/base.py` - Add base cache interface if missing

### Dependencies
- Depends on: None (foundation layer)
- Pattern Stack: Field(), async patterns
- External: redis-py, aioredis

### Testing Strategy
- Unit: Redis operations (set, get, delete, ttl)
- Integration: Real Redis connection tests
- Coverage: 90%+ (critical infrastructure)

### Implementation Sequence
1. Create base cache interface (atoms layer)
2. Implement Redis adapter with async operations
3. Add configuration via Field()
4. Write comprehensive tests
5. Add usage documentation

### Open Questions
- Should we support Redis Cluster? (recommend: not in MVP)
- Connection pooling strategy? (recommend: use aioredis defaults)

### Estimated Complexity
Medium (4-5 hours)

---
Add label state:strategy-approved when ready to proceed
```

**What gets updated in Linear**:
- Status: Backlog → **Refinement**
- Label added: `state:awaiting-strategy-review`
- Strategy comment posted

**AI output**:
```
✅ Implementation Strategy Generated

Issue: TEMPO-101 - Create Redis cache adapter
Strategy Location: application/backend/specs/strategy-TEMPO-101.md
Linear Comment: https://linear.app/tempo/issue/TEMPO-101

Status: Awaiting strategy review
Label Added: state:awaiting-strategy-review

Next Steps:
1. Review the strategy in Linear
2. Address open questions in comments
3. Add label state:strategy-approved when ready
4. Run /implement TEMPO-101

Complexity: Medium (4-5 hours)
Layer: atoms
```

---

### Phase 3: Human Gate 1 - Strategy Approval

**This is your first human touchpoint.**

#### What to Review

Open Linear, filter by `state:awaiting-strategy-review`:

**For each strategy comment, check**:

1. **Approach** - Does the technical approach make sense?
   - ✅ Good: Uses existing patterns, aligns with architecture
   - ❌ Concern: Introduces new dependencies, breaks layer boundaries

2. **Architecture Impact** - Are the right layers affected?
   - ✅ Good: Respects atomic architecture (no backward imports)
   - ❌ Concern: Violates layer rules, too many files changed

3. **Dependencies** - Are dependencies reasonable?
   - ✅ Good: Builds on existing code, minimal external deps
   - ❌ Concern: Requires refactoring other issues first

4. **Open Questions** - Need clarification on anything?
   - Add comments to the Linear issue
   - AI will read your comments and adjust

5. **Complexity Estimate** - Does it seem right?
   - Trust but verify: "4-5 hours" for cache adapter seems reasonable

#### How to Approve

**If strategy looks good**:
```bash
# Option 1: Via tp CLI
tp update TEMPO-101 --add-labels "state:strategy-approved"

# Option 2: Via Linear UI
# Click issue → Labels → Add "state:strategy-approved"
```

**If you need changes**:
```bash
# Add comment with questions/concerns
tp comment TEMPO-101 "Can we use redis-py instead of aioredis? More mature library."

# AI will read comment and regenerate strategy
/analyze-implementation TEMPO-101
```

#### Batch Workflow (Recommended)

**Morning routine (15-30 minutes)**:
```bash
# View all issues awaiting strategy review
tp context --filter "state:awaiting-strategy-review"

# Review each in Linear UI or terminal
tp show TEMPO-101
tp show TEMPO-102
tp show TEMPO-103

# Approve the good ones
tp update TEMPO-101 --add-labels "state:strategy-approved"
tp update TEMPO-102 --add-labels "state:strategy-approved"

# Request changes on others
tp comment TEMPO-103 "Please use existing logging pattern instead of new library"
```

**Result**: By 10am, AI knows what to implement today.

---

### Phase 4: Spec Generation (AI)

**Goal**: AI generates detailed, step-by-step implementation specs from approved strategies.

#### Step 4.1: Generate Spec

Once strategy is approved:

```bash
/plan:generate-spec TEMPO-101
```

**Prerequisites checked**:
- ✅ Issue has `state:strategy-approved` label
- ✅ Issue is in Refinement status
- ✅ Strategy comment exists

**If prerequisites fail**:
```
❌ ERROR: Issue must have approved strategy

Issue TEMPO-101 does not have label 'state:strategy-approved'

Required workflow:
1. Run: /analyze-implementation TEMPO-101
2. Review and approve strategy
3. Then: /plan:generate-spec TEMPO-101
```

**What the AI does**:
1. Fetches approved strategy from Linear
2. Analyzes codebase for patterns and similar implementations
3. Generates detailed spec with:
   - File-level implementation guidance
   - Code patterns to follow
   - Testing strategy with specific test cases
   - Validation commands

**Spec location** (based on stack label):
- `stack:backend` → `application/backend/specs/issue-TEMPO-101-*.md`
- `stack:frontend` → `application/frontend/specs/issue-TEMPO-101-*.md`
- `stack:fullstack` → `specs/issue-TEMPO-101-*.md`

**Example spec structure**:
```markdown
# Feature: Create Redis cache adapter

## Metadata
- **Issue**: TEMPO-101
- **Stack**: backend
- **Generated**: 2025-11-02T15:00:00Z
- **Strategy**: Approved 2025-11-02T14:30:00Z

## Approved Strategy Summary
[Strategy from /analyze-implementation is included here]

## Implementation Plan

### Phase 1: Base Cache Interface
1. **Create base interface**
   - File: `atoms/cache/base.py`
   - Action: Define abstract CacheAdapter class
   - Pattern: Similar to `atoms/storage/base.py`
   - Reference: `atoms/storage/base.py:15-45`

### Phase 2: Redis Implementation
...

## Detailed Task Breakdown

### Task 1: Create Base Cache Interface

**File**: `atoms/cache/base.py`

**Action**: Define abstract cache adapter

**Implementation Guidance**:
```python
from abc import ABC, abstractmethod
from typing import Any, Optional

class CacheAdapter(ABC):
    @abstractmethod
    async def get(self, key: str) -> Optional[Any]:
        """Get value from cache."""
        pass
```

**Reference**: Similar pattern at `atoms/storage/base.py:15-45`

**Tests**: Test abstract interface can be subclassed

...

## Testing Strategy

### Unit Tests

**File**: `tests/atoms/cache/test_redis.py`

**Test Cases**:
1. **test_redis_set_and_get**
   - Setup: Redis connection, test key/value
   - Action: Set value, then get it
   - Assert: Retrieved value matches original

...

## Validation Commands

```bash
cd application/backend
uv run format      # Auto-fix formatting
uv run lint        # Check code quality
uv run typecheck   # Type checking
uv run test        # Run tests with coverage
uv run ci          # All gates
```
```

**What gets updated in Linear**:
- Status: Refinement → **Ready**
- Label removed: `state:strategy-approved`
- Label added: `state:spec-ready`
- Comment posted with spec location

**AI output**:
```
✅ Spec Generated Successfully!

Spec: application/backend/specs/issue-TEMPO-101-create-redis-cache-adapter.md
Issue: https://linear.app/tempo/issue/TEMPO-101

Summary:
- ✅ Strategy verified and used as foundation
- ✅ Researched 12 files
- ✅ Generated 8 implementation tasks
- ✅ Defined 15 test cases
- ✅ Updated issue status: Refinement → Ready

Issue TEMPO-101 is Ready for Implementation

Next step:
/implement TEMPO-101
```

---

### Phase 5: Implementation (AI)

**Goal**: AI implements the spec with TDD, atomic commits, and quality gates.

#### Step 5.1: Run Implementation

```bash
/implement TEMPO-101
```

**What the AI does**:

1. **Verify Prerequisites**:
   - Checks for `state:strategy-approved` label
   - Finds spec file (or auto-generates if missing)
   - Validates issue is in Ready status

2. **Ensure Clean State**:
   - Checks for uncommitted changes
   - Ensures working directory is clean

3. **Create Feature Branch**:
   - Reads branch naming from `.env`
   - Creates: `feature/TEMPO-101-create-redis-cache-adapter`
   - Checks out branch

4. **Detect TDD Mode**:
   - Checks for `--tdd` flag
   - Checks for `tdd:required` or `type:bug` labels
   - Asks user if unclear

5. **Implement Following Spec**:

   **TDD Mode** (test-first):
   ```
   For each feature:
   1. Write failing test
   2. Commit: test(atoms/cache): add failing test for redis adapter
   3. Implement minimum code to pass
   4. Commit: feat(atoms/cache): implement redis adapter
   5. Refactor if needed
   6. Commit: refactor(atoms/cache): improve redis adapter structure
   ```

   **Standard Mode** (implement-first):
   ```
   For each task:
   1. Implement the feature
   2. Commit: feat(atoms/cache): implement redis adapter
   3. Write comprehensive tests
   4. Commit: test(atoms/cache): add redis adapter tests
   ```

6. **Run Quality Gates**:
   ```bash
   # Format (auto-fix)
   cd application/backend && uv run format
   # Commit if changes: style: auto-format code

   # Lint (check)
   uv run lint
   # Commit if auto-fixes: style: auto-fix lint issues

   # Type check (must pass)
   uv run typecheck
   # Exit if errors

   # Tests (must pass)
   uv run test
   # Exit if failures
   ```

7. **Update Linear**:
   - Posts implementation summary comment
   - Status: Ready → **In Progress** → **In Review**

8. **Create PR**:
   - Fetches strategy from Linear
   - Reads spec file
   - Generates comprehensive PR description
   - Creates PR via `gh` CLI
   - Links Linear issue to PR

**Atomic Commits Pattern**:

The AI makes many small, focused commits:

```
feat(atoms/cache): create base cache interface (TEMPO-101)
test(atoms/cache): add base cache interface tests (TEMPO-101)
feat(atoms/cache): implement redis adapter (TEMPO-101)
test(atoms/cache): add redis adapter tests (TEMPO-101)
feat(atoms/cache): add connection pooling (TEMPO-101)
test(atoms/cache): add connection pooling tests (TEMPO-101)
docs(atoms/cache): add usage documentation (TEMPO-101)
style: auto-format code (TEMPO-101)
```

**AI output**:
```
Implementation Complete ✅

Issue: TEMPO-101 - Create Redis cache adapter

Implementation Mode: TDD (test-first)

Changes:
- Files created: 3
- Files modified: 1
- Total tests: 15 (all passing)
- Coverage: 92%

Git Summary:
 atoms/cache/base.py          | 45 ++++++++++++++
 atoms/cache/redis.py         | 120 ++++++++++++++++++++++++++++++++
 atoms/cache/__init__.py      | 3 +
 tests/atoms/cache/test_redis.py | 180 +++++++++++++++++++++++++++++++++++++++++++++
 4 files changed, 348 insertions(+)

Quality Gates:
✅ Format
✅ Lint
✅ Type Check
✅ Architecture Validation
✅ Tests (92% coverage)

Pull Request:
- PR #45: Create Redis cache adapter (TEMPO-101)
- URL: https://github.com/org/repo/pull/45
- Linked to: TEMPO-101

Linear Status:
✅ Issue moved to "In Review"
✅ Implementation comment posted
✅ Ready for code review

Next Steps:
- Review PR: https://github.com/org/repo/pull/45
- Assign reviewers
- Wait for approval
- Merge when ready
```

---

### Phase 6: Human Gate 2 - PR Review

**This is your second (and final) human touchpoint.**

#### What to Review in PR

The PR includes full traceability:

**PR Structure**:
```markdown
# Create Redis cache adapter (TEMPO-101)

## Linear Issue
https://linear.app/tempo/issue/TEMPO-101

## Strategy Summary
[Approved strategy from Phase 3 is included]

## Implementation Spec
[Link to spec file in repo]

## Changes
- Created Redis cache adapter in atoms layer
- Implemented async operations with connection pooling
- Added comprehensive tests (92% coverage)
- Updated documentation

## Test Plan
- ✅ Unit tests: 15 passing
- ✅ Integration tests: Redis connection tested
- ✅ Coverage: 92% (target: 80%)

## Quality Gates
✅ Format (ruff)
✅ Lint (ruff --select ALL)
✅ Type Check (mypy --strict)
✅ Architecture Validation (layer boundaries)
✅ Tests (pytest with coverage)

## Commits
- feat(atoms/cache): create base cache interface (TEMPO-101)
- test(atoms/cache): add base cache interface tests (TEMPO-101)
- feat(atoms/cache): implement redis adapter (TEMPO-101)
- ... [all atomic commits listed]

## Session Logs
Full implementation trace: agent-logs/2025-11-02_implement_tempo-101_xyz123/
```

**What to check**:

1. **Code Quality**
   - ✅ Follows existing patterns
   - ✅ Type hints present
   - ✅ Tests are comprehensive
   - ✅ No obvious bugs

2. **Architecture**
   - ✅ Respects layer boundaries
   - ✅ Matches approved strategy
   - ✅ Doesn't introduce technical debt

3. **Tests**
   - ✅ Coverage meets target (80%+)
   - ✅ Tests are meaningful (not just coverage)
   - ✅ Edge cases handled

4. **Commits**
   - ✅ Atomic and well-scoped
   - ✅ Follow project conventions
   - ✅ Reference issue ID

**Typical review time**: 5-10 minutes (already saw strategy, spec follows it)

#### Approve and Merge

**If PR looks good**:
```bash
# Option 1: Via gh CLI
gh pr review 45 --approve
gh pr merge 45 --squash  # or --merge, --rebase

# Option 2: Via GitHub UI
# Click "Approve" → "Merge pull request"
```

**If you need changes**:
```bash
# Request changes via GitHub
gh pr review 45 --request-changes --body "Please add error handling for connection failures"

# Or add review comments in GitHub UI
```

**After merge**:
- Linear issue automatically moves to **Done** (via GitHub integration)
- Epic automatically updates if all children are done
- Celebration time! 🎉

---

### Phase 7: Done

**Feature is shipped!**

**What happened automatically**:
- ✅ Strategy reviewed and approved (you)
- ✅ Detailed spec generated (AI)
- ✅ Code implemented with TDD (AI)
- ✅ Tests written and passing (AI)
- ✅ Quality gates passed (AI)
- ✅ PR created with full traceability (AI)
- ✅ PR reviewed and approved (you)
- ✅ Merged to main (you)
- ✅ Linear issue closed (automatic)

**Total human time**: ~20-25 minutes
- Strategy review: 15 minutes
- PR review: 5-10 minutes

**Total AI time**: ~30-60 minutes (depending on complexity)

---

## Human Gates Explained

### Why Two Gates?

1. **Strategy Approval (Gate 1)** - Catch architectural mistakes early
   - **Cost of mistake**: High (wrong approach = wasted implementation time)
   - **Time to review**: 5-15 minutes per issue
   - **When**: Before any code is written
   - **What you're approving**: High-level approach, architecture, dependencies

2. **PR Review (Gate 2)** - Catch implementation mistakes before merge
   - **Cost of mistake**: Medium (bugs in production)
   - **Time to review**: 5-10 minutes per PR
   - **When**: After code is written and tested
   - **What you're approving**: Actual code, tests, quality

**Why not more gates?**
- Spec generation is deterministic from strategy (low risk)
- Quality gates are automated (format, lint, typecheck, tests)
- Atomic commits allow easy rollback if needed

**Why not fewer gates?**
- Strategy approval prevents wasted effort on wrong approach
- PR review ensures code quality and catches edge cases

### Batch Workflow (Optimal)

**Morning (Strategy Approval)**:
```bash
# Generate strategies for all ready issues
/analyze-implementation TEMPO-101
/analyze-implementation TEMPO-102
/analyze-implementation TEMPO-103

# 30 minutes later, batch review in Linear
tp context --filter "state:awaiting-strategy-review"

# Approve good strategies
tp update TEMPO-101 TEMPO-102 TEMPO-103 --add-labels "state:strategy-approved"
```

**Lunchtime (AI Implements)**:
```bash
# AI implements all approved issues
/implement TEMPO-101
/implement TEMPO-102
/implement TEMPO-103

# Takes 2-3 hours for AI to implement all
```

**Afternoon (PR Review)**:
```bash
# 3 PRs waiting for review
gh pr list

# Review each (5-10 min each)
gh pr view 45
gh pr view 46
gh pr view 47

# Approve all
gh pr review 45 46 47 --approve

# Merge all
gh pr merge 45 46 47 --squash
```

**Result**: 3 features shipped with 30-45 minutes of human time.

---

## Configuration

### Initial Setup

#### 1. Linear Project Setup

**Create Project in Linear**:
- Project name: "Your Project Name"
- Team key: "PROJ" (short, uppercase)
- Copy Team ID for configuration

**Create Workflow States** (in order):
1. **Triage** - Raw ideas
2. **Backlog** - Complete issues
3. **Refinement** - Strategy being reviewed (HUMAN GATE)
4. **Ready** - Spec generated, ready to code
5. **In Progress** - Code being written
6. **In Review** - PR review (HUMAN GATE)
7. **Done** - Shipped

**Create Labels** (bulk create in Linear settings):
```
# State labels (workflow metadata)
state:awaiting-strategy-review
state:strategy-approved
state:spec-ready
state:blocked
state:needs-clarification

# Stack labels (REQUIRED)
stack:backend
stack:frontend
stack:fullstack

# Type labels
type:epic
type:feature
type:bug
type:chore

# Work labels
work:architecture
work:infrastructure
work:feature
work:enhancement
work:bugfix

# Layer labels (backend)
layer:atoms
layer:features
layer:molecules
layer:organisms

# Priority
priority:critical
priority:high
priority:medium
priority:low
```

**Enable GitHub Integration**:
- Settings → Integrations → GitHub
- Connect repository
- Enable bi-directional sync
- Issues auto-close on PR merge ✅

---

#### 2. GitHub Repository Setup

**Branch Protection** (Settings → Branches → Add rule for `main`):
- ✅ Require pull request before merging
- ✅ Require approvals: 1 (or 0 for solo dev)
- ✅ Dismiss stale approvals
- ✅ Require status checks (if CI configured)
- ✅ Restrict pushes (prevents direct commits to main)

**Result**: No more accidental commits to main ✅

---

#### 3. Project Configuration Files

**`.env`** (create at project root, git-ignored):
```bash
# Linear Integration
LINEAR_API_KEY=lin_api_xxxxx
LINEAR_TEAM_ID=your-team-uuid
LINEAR_ORG_ID=your-org-uuid

# GitHub
GITHUB_ORG=your-org
GITHUB_REPO=your-repo

# Project
PROJECT_NAME=your-project
PROJECT_TEAM_KEY=PROJ
PROJECT_STACK=fullstack

# Conventions
COMMIT_FORMAT=conventional
BRANCH_PREFIX_EPIC=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
```

**`.env.example`** (create at project root, committed):
```bash
# Copy this to .env and fill in real values

# Linear Integration
LINEAR_API_KEY=lin_api_xxxxx
LINEAR_TEAM_ID=your-team-uuid
LINEAR_ORG_ID=your-org-uuid

# GitHub
GITHUB_ORG=your-org
GITHUB_REPO=your-repo

# Project
PROJECT_NAME=your-project
PROJECT_TEAM_KEY=PROJ
PROJECT_STACK=fullstack
```

**`.tp/config.json`** (create at project root):
```json
{
  "defaultTeam": "PROJ",
  "teams": {
    "PROJ": {
      "name": "Your Project Name",
      "id": "your-linear-team-id-here"
    }
  }
}
```

**`.gitignore`** (ensure these are ignored):
```
.env
agent-logs/
*.tmp
```

---

#### 4. Verify Setup

```bash
# Test tp CLI
tp context

# Test git-workflow
git status

# Test Linear API
tp add "Test issue" && tp done $(tp context | head -1 | awk '{print $1}')
```

---

## Troubleshooting

### Common Errors and Solutions

#### "Issue must have state:strategy-approved"

**Error**:
```
❌ ERROR: Issue must have approved strategy before implementation

Issue TEMPO-123 does not have label 'state:strategy-approved'
```

**Cause**: You tried to run `/implement` before approving the strategy.

**Solution**:
```bash
# Option 1: Approve existing strategy
tp update TEMPO-123 --add-labels "state:strategy-approved"
/implement TEMPO-123

# Option 2: Generate new strategy first
/analyze-implementation TEMPO-123
# Review in Linear, then approve
tp update TEMPO-123 --add-labels "state:strategy-approved"
/implement TEMPO-123
```

---

#### ".env file not found"

**Error**:
```
❌ ERROR: .env file not found at project root
```

**Cause**: Missing or incorrectly located `.env` file.

**Solution**:
```bash
# Copy example and fill in values
cp .env.example .env

# Edit with real values
# nano .env  # or your preferred editor

# Required values:
LINEAR_API_KEY=lin_api_xxxxx      # From Linear settings
LINEAR_TEAM_ID=your-team-uuid      # From Linear team page
LINEAR_ORG_ID=your-org-uuid        # From Linear organization settings
GITHUB_ORG=your-org                # Your GitHub org
GITHUB_REPO=your-repo              # Your repo name
PROJECT_TEAM_KEY=PROJ              # Your team key (matches .tp/config.json)
```

---

#### "No approved strategy found"

**Error**:
```
❌ ERROR: No approved strategy comment found

Issue TEMPO-123 does not have strategy comment with header '🤖 Implementation Strategy'
```

**Cause**: Strategy comment was never posted or deleted.

**Solution**:
```bash
# Regenerate strategy
/analyze-implementation TEMPO-123

# Approve it
tp update TEMPO-123 --add-labels "state:strategy-approved"

# Try implementation again
/implement TEMPO-123
```

---

#### "Issue must be in Refinement status"

**Error**:
```
❌ ERROR: Issue must be in Refinement status

Current status: Backlog
```

**Cause**: Issue hasn't been moved to Refinement state yet.

**Solution**:
```bash
# Update status in Linear
tp update TEMPO-123 --status "Refinement"

# Or via Linear UI
# Click issue → Status → Refinement

# Then retry command
/plan:generate-spec TEMPO-123
```

---

#### "Label not found: state:awaiting-strategy-review"

**Error**:
```
⚠️  Warning: Label 'state:awaiting-strategy-review' not found in Linear team
```

**Cause**: Label doesn't exist in Linear yet.

**Solution**:
```bash
# Create missing label
tp labels create "state:awaiting-strategy-review" \
  --description "Strategy posted, awaiting human review" \
  --team PROJ

# Verify it was created
tp labels list --team PROJ | grep awaiting
```

---

#### "Cannot commit on protected branch: main"

**Error**:
```
❌ ERROR: Cannot commit directly to protected branch 'main'
```

**Cause**: You're on main branch and trying to make changes.

**Solution**:
```bash
# Let git-workflow skill handle it
/implement TEMPO-123
# Automatically creates feature branch

# Or manually create branch first
git checkout -b feature/TEMPO-123-your-feature
/implement TEMPO-123
```

---

#### "Quality gate failed: typecheck"

**Error**:
```
❌ Type check failed
atoms/cache/redis.py:45: error: Function is missing a return type annotation
```

**Cause**: Code doesn't pass type checking.

**Solution**:
```bash
# Read the error message carefully
cd application/backend
uv run typecheck

# Fix the type errors
# Example: Add return type annotation
# def get(key: str):  # ❌ Missing return type
# def get(key: str) -> Optional[str]:  # ✅ Correct

# Run typecheck again
uv run typecheck

# If AI is implementing, it will fix automatically
# If you're implementing manually, fix and commit
```

---

#### "No stack: label on issue"

**Error**:
```
❌ ERROR: No valid stack label found

Issue must have one of: stack:backend, stack:frontend, stack:fullstack
```

**Cause**: Issue missing required stack label.

**Solution**:
```bash
# Add stack label
tp update TEMPO-123 --add-labels "stack:backend"

# Or via Linear UI
# Click issue → Labels → Add "stack:backend"

# Then retry command
/analyze-implementation TEMPO-123
```

---

## Tips & Best Practices

### Batch Operations

**Generate multiple strategies at once**:
```bash
for issue in TEMPO-101 TEMPO-102 TEMPO-103 TEMPO-104 TEMPO-105; do
  /analyze-implementation $issue
done

# Review all in Linear
# Approve all
tp update TEMPO-101 TEMPO-102 TEMPO-103 TEMPO-104 TEMPO-105 --add-labels "state:strategy-approved"

# Implement all
for issue in TEMPO-101 TEMPO-102 TEMPO-103 TEMPO-104 TEMPO-105; do
  /implement $issue
done
```

---

### Test Locally Before Pushing

**Run quality gates locally**:
```bash
cd application/backend
uv run ci              # All backend gates

cd ../frontend
npm run ci             # All frontend gates
```

**Run specific tests**:
```bash
# Backend
cd application/backend
uv run pytest tests/atoms/cache/test_redis.py -xvs

# Frontend
cd application/frontend
npm test -- atoms/Button.test.tsx
```

---

### Atomic Commits

**Good commit examples**:
```
feat(atoms/cache): implement redis adapter (TEMPO-101)
test(atoms/cache): add redis adapter tests (TEMPO-101)
fix(features/users): correct cache key generation (TEMPO-105)
docs(specs): add implementation spec for TEMPO-101 (TEMPO-101)
style: auto-format code (TEMPO-101)
```

**Bad commit examples**:
```
❌ "working on stuff"                    # No type, scope, or issue
❌ "feat: add everything"                # Too broad
❌ "Update redis.py"                     # No context
❌ "WIP"                                 # Work in progress shouldn't be committed
```

---

### Label Immediately

**Always add required labels when creating issues**:
```bash
# ✅ Good: Labels from the start
tp add "Create cache adapter" \
  --labels "type:feature,stack:backend,layer:atoms,work:infrastructure"

# ❌ Bad: No labels
tp add "Create cache adapter"
# Now you have to go back and add them
```

**Required labels checklist**:
- [ ] One `stack:*` label (backend/frontend/fullstack)
- [ ] One `type:*` label (epic/feature/bug/chore)
- [ ] One or more `work:*` labels (architecture/infrastructure/feature/enhancement/bugfix)
- [ ] One or more `layer:*` labels (atoms/features/molecules/organisms) - backend only

---

### Review Strategy Comments Carefully

**Good strategy approval workflow**:
```bash
# 1. Read the entire strategy
tp show TEMPO-101

# 2. Check for red flags
# - Too many files changed?
# - External dependencies?
# - Complexity seems off?

# 3. Ask questions if needed
tp comment TEMPO-101 "Why aioredis instead of redis-py?"

# 4. Approve when satisfied
tp update TEMPO-101 --add-labels "state:strategy-approved"
```

---

### Session Logs Are Your Friend

**Check session logs when things go wrong**:
```bash
# Find recent sessions
ls -lt agent-logs/ | head

# View session summary
cat agent-logs/2025-11-02_implement_tempo-101_xyz123/summary.md

# Check session metadata
cat agent-logs/2025-11-02_implement_tempo-101_xyz123/session.json | jq
```

---

### Use TDD for Bugs

**Bugs should always use TDD**:
```bash
# Bug reports automatically trigger TDD mode
tp add "Cache returns stale data" --labels "type:bug,stack:backend"

# Implementation will be test-first:
# 1. Write failing test that reproduces bug
# 2. Fix bug (test now passes)
# 3. Refactor if needed
```

---

## Command Reference

### Planning Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `/plan:decompose` | Decompose requirements into YAML | Task description | `issue-plan-*.yaml` |
| `/plan:create-issues` | Create Linear issues from YAML | YAML file | Issue IDs |

**Example**:
```bash
/plan:decompose "Add Redis caching to user service"
# → issue-plan-redis-caching.yaml

/plan:create-issues issue-plan-redis-caching.yaml
# → Epic: TEMPO-100, Children: TEMPO-101, TEMPO-102
```

---

### Strategy Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `/analyze-implementation` | Generate implementation strategy | Issue ID | Strategy document + Linear comment |

**Example**:
```bash
/analyze-implementation TEMPO-101
# → application/backend/specs/strategy-TEMPO-101.md
# → Linear comment with strategy
# → Label: state:awaiting-strategy-review
```

---

### Spec Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `/plan:generate-spec` | Generate detailed implementation spec | Issue ID (with approved strategy) | Spec file |

**Example**:
```bash
/plan:generate-spec TEMPO-101
# → application/backend/specs/issue-TEMPO-101-create-redis-cache-adapter.md
```

---

### Implementation Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `/implement` | Implement issue with TDD and quality gates | Issue ID(s) | Commits + PR |
| `/test` | Run all quality gates | None | Pass/fail status |

**Example**:
```bash
/implement TEMPO-101
# → Feature branch created
# → Code implemented with atomic commits
# → Quality gates passed
# → PR created

/test
# → Format, lint, typecheck, tests all run
```

---

### Git Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `/git:commit` | Create atomic commit | Type, scope, message, issue | Commit |
| `/git:pr` | Create pull request | Issue ID | PR URL |

**Example**:
```bash
/git:commit feat atoms/cache "implement redis adapter" TEMPO-101
# → Commit: feat(atoms/cache): implement redis adapter (TEMPO-101)

/git:pr TEMPO-101
# → PR created with full traceability
```

---

### Linear (tp) Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `tp add` | Create issue | `tp add "New feature"` |
| `tp show` | View issue | `tp show TEMPO-123` |
| `tp update` | Update issue | `tp update TEMPO-123 --status "In Progress"` |
| `tp comment` | Add comment | `tp comment TEMPO-123 "Ready for review"` |
| `tp context` | View your work | `tp context` |
| `tp labels list` | List available labels | `tp labels list --team PROJ` |
| `tp link-parent` | Link child to epic | `tp link-parent TEMPO-124 TEMPO-123` |

---

## Summary

**Two human gates, infinite leverage:**

1. **Morning**: Review strategies (15-30 min)
   - AI generates strategies overnight or in batch
   - You review architectural approaches
   - Approve good ones, reject or request changes on others

2. **Afternoon**: Review PRs (5-10 min each)
   - AI implements approved strategies
   - You review actual code
   - Approve and merge

**Result**: Ship features with ~80% AFK time and full traceability from idea to production.

**Key Files**:
- `.env` - Project configuration (you fill this in)
- `CLAUDE.md` - Full project guide (reference)
- `BOOTSTRAP-PLAN.md` - Workflow architecture (deep dive)

**Need Help?**
- Check troubleshooting section above
- Review session logs in `agent-logs/`
- Read command documentation in `.claude/commands/README.md`

Happy shipping! 🚀
