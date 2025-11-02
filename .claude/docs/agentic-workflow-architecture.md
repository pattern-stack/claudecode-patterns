# Agentic Coding Workflow Architecture

**Version**: 1.0
**Status**: Design
**Purpose**: Production-ready AI coding workflow with quality gates demonstrating that AI can create production-worthy code

## Overview

This document specifies the architecture for an agentic coding workflow system that integrates Claude Code commands with Linear task tracking, Git branching strategy, and comprehensive quality gates.

## Design Philosophy

1. **Quality Gates First**: Prevent bad code through automated checks, not reviews
2. **Human-in-Loop for Oversight**: AI executes, humans guide and approve
3. **Full Traceability**: Every change links back to Linear issue and spec
4. **Incremental Delivery**: Small, testable units of work
5. **Dogfooding**: Build the system using the system itself

## Workflow Phases

```
PLAN → IMPLEMENT → TEST → REVIEW → PR
  ↓         ↓        ↓       ↓      ↓
Linear    TDD/Std  Quality  Multi   GitHub
Epic+Subs  Commits  Gates   Agent   + CI
```

## Linear + Local Specs Integration

### Linear (Source of Truth)
- Task definition & requirements (title, body)
- Status tracking (workflow states - see below)
- Progress comments & discussion
- Labels & metadata (type, layer, domain, etc)
- Parent/child relationships (epics)

### Linear Workflow States
- **Backlog**: Initial state when created (skip "Ideation" - Backlog serves this purpose)
- **Refinement**: Spec being written, details being added to Linear and specs/
- **Ready**: Spec complete, ready for `/implement`
- **In Progress**: `/implement` is actively working on it
- **In Review**: `/review` happening or PR open
- **Done**: Merged to main

### Linear Label Requirements
**Minimum Required Labels** (set during `/plan`):
- **Issue Type**: One of `type:epic`, `type:feature`, `type:bug`, `type:chore`
- **Layer** (for code changes): One of `layer:atoms`, `layer:features`, `layer:molecules`, `layer:organisms`

**Additional Labels** (optional but recommended):
- **Domain**: `domain:tasks`, `domain:teams`, `domain:sync`, `domain:reporting`, etc.
- **Component**: `component:workflow`, `component:entity`, `component:api-facade`, etc.
- **Priority**: `priority:high`, `mvp`, `demo`
- **TDD**: `tdd:required`, `tdd:optional`

**Label Discovery**:
- Agents should run `tp labels list --team BE` during planning to see all available labels
- Agents can propose new labels if existing ones don't fit

**Label Application**:
- Use Linear MCP directly (tp CLI doesn't support labels yet):
  - `mcp__linear__linear_addIssueLabel` with issue ID and label name
- Status updates: `tp update BE-XXX --status "Refinement"`

### Local Specs (Implementation Details)
- Detailed technical plan from `/plan` command
- File-level breakdown & step-by-step tasks
- Validation commands
- Location: `specs/issue-BE-XXX-{short-description}.md`
- Committed to feature branch
- Linked in Linear as first comment

## Git Branching Strategy

### Branch per Epic (Default)
```
/plan "Add user caching feature"
  ↓
Creates:
  - Epic: BE-100 (parent)
  - Sub-issues: BE-101, BE-102, BE-103
  - Branch: feature/BE-100-user-caching
  - Specs on branch:
    * specs/issue-BE-100-user-caching-epic.md
    * specs/issue-BE-101-cache-model.md
    * specs/issue-BE-102-cache-service.md
    * specs/issue-BE-103-cache-api.md
```

### Branch Naming Convention
- Single issue: `feature/BE-XXX-short-desc`
- Epic with subs: `feature/BE-XXX-epic-name`
- Bugfix: `fix/BE-XXX-bug-desc`
- Chore: `chore/BE-XXX-task-desc`

### Commit Convention
```
<type>(<scope>): <description> (BE-XXX)

feat(atoms/cache): add Redis cache adapter (BE-101)
test(atoms/cache): add cache adapter tests (BE-101)
fix(features/users): correct cache key generation (BE-105)
```

### PR Strategy
- 1 PR = 1 branch = 1 epic (or standalone issue)
- PR closes epic + all sub-issues
- PR description includes:
  - Summary of all changes
  - Links to all specs
  - Review summary from `/review`
  - Closes statements for all issues

## Command Catalog

### 1. `/plan` - Task Decomposition & Planning

**Purpose**: Analyze requirements, decompose into manageable Linear issues, create detailed specs

**Usage**:
```bash
/plan "Add user profile caching"
/plan "Fix authentication timeout bug"
/plan BE-50  # Plan from existing Linear issue
```

**Arguments**:
- `$1`: Task description OR Linear issue ID
- `--auto-accept`: Skip approval, create issues immediately
- `--shell`: Create shell issues only (Backlog status), skip spec generation
- `--separate`: Create separate branches per sub-issue (advanced)
- `--tdd`: Force TDD mode for all issues

**Planning Modes**:

1. **Detailed Mode (DEFAULT)** - Recommended for demo:
   - Interactive discussion with `<ultrathink>` for quality reasoning
   - Creates complete Linear issues with full descriptions
   - Generates all spec files
   - Sets appropriate labels (type, layer, etc)
   - Sets status to "Ready" (ready to /implement)
   - Commits specs to feature branch

2. **Shell Mode** (`--shell`):
   - Quick issue creation
   - Basic titles and 1-2 sentence descriptions
   - Minimal labels (just type)
   - Status: "Backlog"
   - No specs created yet
   - Can later run `/plan refine BE-XXX` to add specs

**Workflow (Detailed Mode - Default)**:
1. **Ultrathink Analysis**: Use `<ultrathink>` to deeply analyze requirements
2. **Interactive Requirements Discovery**:
   - Ask clarifying questions about scope, approach, constraints
   - Continue until requirements are crystal clear
3. **Label Discovery**: Run `tp labels list --team BE` to see available labels
4. **Decomposition**: Break into epic + atomic sub-issues
5. **Proposal**: Present structure with:
   - Epic title & description
   - Sub-issue titles & descriptions
   - Proposed labels (type, layer, domain, priority)
   - Branch naming
   - Spec file names
6. **Approval**: Wait for user confirmation (unless `--auto-accept`)
7. **Linear Creation**:
   - Create epic via `tp add` with full description
   - Create sub-issues via `tp add` with full descriptions
   - Add labels via `mcp__linear__linear_addIssueLabel`
   - Set status via `tp update --status "Refinement"`
   - Link children to parent via `tp link-parent`
8. **Branch Creation**: Create/checkout feature branch
9. **Spec Generation**:
   - Generate detailed specs for epic + each sub-issue
   - Follow spec template (see Appendix C)
   - Include: technical approach, acceptance criteria, validation commands
10. **Commit Specs**: `chore: add implementation plans for BE-XXX (BE-XXX)`
11. **Linear Integration**:
    - Comment in each issue with spec path
    - Update status to "Ready"
12. **Summary**: Report Linear URLs and next steps

**Output**:
- Linear epic created
- Linear sub-issues created
- Feature branch created
- Spec files written
- Linear comments with traceability

**Error Handling**:
- If `tp add` fails, rollback and report
- If branch exists, ask to use existing or create new
- If unclear requirements, keep asking until clear

### 2. `/implement` - TDD-Aware Implementation

**Purpose**: Execute implementation plan with optional TDD workflow

**Usage**:
```bash
/implement BE-101              # Single issue
/implement BE-101 BE-102 BE-103  # Multiple issues (one branch)
/implement BE-101 --no-tdd     # Force standard mode
/implement BE-101 --tdd        # Force TDD mode
```

**Arguments**:
- `$1, $2, $3...`: Linear issue IDs
- `--tdd`: Force TDD mode
- `--no-tdd`: Force standard mode
- `--agent=<name>`: Use specific agent (default: pattern-stack-developer)

**TDD Detection Logic**:
1. Check for `--tdd` or `--no-tdd` flags (explicit wins)
2. Check Linear labels for `tdd:required`
3. Check issue type: `type:bug` → TDD by default
4. Search description for keywords: "TDD", "test-first", "red-green-refactor"
5. If still unclear, ask user

**Workflow**:
1. Fetch issue(s) via `tp show BE-XXX`
2. Find associated specs in `specs/issue-BE-XXX-*.md`
3. Detect TDD mode per issue
4. Invoke pattern-stack-developer agent with:
   - Issue metadata from Linear
   - Spec file path
   - TDD flag
   - List of all issues in this batch
5. Agent implements:
   - **TDD Mode**: Write test → Fail → Implement → Pass → Refactor
   - **Standard Mode**: Implement → Test → Refactor
6. Agent makes atomic commits per logical unit
7. Agent updates Linear via `tp comment BE-XXX`
8. Agent marks issues done via `tp done BE-XXX`

**Output**:
- Code changes committed
- Tests written and passing
- Linear issues updated to Done
- Comments in Linear with implementation summary

**Integration**:
- Calls `/test` automatically after all issues complete
- If tests fail, enters fix loop

### 3. `/test` - Quality Gate Enforcement

**Purpose**: Comprehensive pre-PR quality verification with fix loop

**Usage**:
```bash
/test                  # Run all gates on current branch
/test --fix            # Auto-fix what's possible
/test --gate=lint      # Run specific gate only
/test --strict         # Fail fast on first error
```

**Arguments**:
- `--fix`: Attempt auto-fixes (format, imports)
- `--gate=<name>`: Run specific gate (format, lint, typecheck, validate, test)
- `--strict`: Exit on first failure
- `--coverage=<N>`: Override coverage threshold (default: 80)

**Quality Gates (Sequential)**:

#### Phase 1: Code Quality
1. **Format** - `make format` (auto-fixes)
   - Runs `ruff format`
   - Auto-commits if changes made

2. **Lint** - `make lint`
   - Runs `ruff check --select ALL`
   - Reports: unused imports, style violations, complexity

3. **Type Check** - `make typecheck`
   - Runs `mypy --strict`
   - Reports: type errors, missing annotations

4. **Architecture Validation** - `make validate`
   - Runs Pattern Stack architecture validator
   - Reports: layer violations, import direction errors

#### Phase 2: Testing
5. **Test Suite** - `make test-ci`
   - Runs exactly as CI does
   - Parallel tests (excludes benchmarks initially)
   - Sequential pattern integration tests
   - Benchmarks last
   - Enforces 80% coverage minimum
   - Reports: failures, coverage gaps, slow tests

**Output Format** (JSON):
```json
{
  "success": false,
  "gates": [
    {
      "name": "format",
      "passed": true,
      "execution_command": "make format",
      "duration_seconds": 2.3,
      "auto_fixed": true
    },
    {
      "name": "lint",
      "passed": false,
      "execution_command": "make lint",
      "duration_seconds": 1.8,
      "error_count": 3,
      "errors": [
        {
          "file": "pattern_stack/atoms/cache/redis.py",
          "line": 45,
          "code": "F841",
          "message": "Local variable 'key' is assigned but never used"
        }
      ]
    }
  ],
  "total_duration_seconds": 45.2,
  "failures_count": 2
}
```

**Fix Loop**:
```
/test
  ↓
If failures:
  ↓
Parse errors into actionable items
  ↓
For each error:
  - Show error context
  - Attempt fix
  - Re-run specific gate
  ↓
Loop until: success = true
```

**Output**:
- JSON results printed (for machine processing)
- Human-readable summary
- Git commit if auto-fixes applied
- Exit code: 0 = all pass, 1 = failures remain

**Integration**:
- Called automatically by `/implement`
- Blocks `/review` until all gates pass
- Can be called standalone anytime

### 4. `/review` - Multi-Agent Code Review

**Purpose**: Comprehensive code review before PR creation

**Usage**:
```bash
/review                    # Review current branch
/review BE-100             # Review specific epic
/review --agents=security,performance  # Run specific agents only
```

**Arguments**:
- `$1`: Optional epic ID to review
- `--agents=<list>`: Comma-separated list of agents to run
- `--parallel`: Run agents in parallel (default)
- `--sequential`: Run agents sequentially

**Review Agents (7 Specialized)**:

1. **Architecture Compliance**
   - Validates Atomic Architecture boundaries
   - Checks import directions (Atoms ← Features ← Molecules ← Organisms)
   - Verifies layer responsibilities
   - Reports violations with suggested fixes

2. **Security Review**
   - OWASP top 10 checks
   - SQL injection vulnerabilities
   - Secrets in code
   - Authentication/authorization gaps
   - Input validation coverage

3. **Performance Review**
   - N+1 query detection
   - Missing database indexes
   - Inefficient algorithms
   - Caching opportunities
   - Async/await usage

4. **Test Coverage Review**
   - Edge case coverage
   - Integration test completeness
   - Mocking strategy
   - Test quality & maintainability
   - Benchmark coverage for critical paths

5. **Documentation Review**
   - Docstring completeness
   - CLAUDE.md updates needed
   - README updates needed
   - Inline comment quality
   - API documentation

6. **Code Style Review**
   - Pythonic patterns
   - Naming conventions
   - Function/class size
   - Complexity metrics
   - Code duplication

7. **Business Logic Review**
   - Correctness verification
   - Edge case handling
   - Error handling completeness
   - Transaction boundaries
   - Data consistency

**Output Format** (JSON):
```json
{
  "success": true,
  "review_summary": "Implemented user profile caching with Redis backend. All 7 review agents found no blocking issues. Minor suggestions for additional edge case tests and docstring improvements documented as non-blocking tech debt.",
  "review_issues": [
    {
      "agent": "test_coverage",
      "severity": "tech_debt",
      "file": "pattern_stack/atoms/cache/redis.py",
      "line": 45,
      "issue": "Missing edge case test for cache eviction when Redis connection drops",
      "suggestion": "Add test_cache_eviction_on_connection_loss to test suite",
      "blocking": false
    }
  ],
  "agent_reports": {
    "architecture": { "passed": true, "issues": [] },
    "security": { "passed": true, "issues": [] },
    "performance": { "passed": true, "issues": [] },
    "test_coverage": { "passed": true, "issues": [1] },
    "documentation": { "passed": true, "issues": [] },
    "code_style": { "passed": true, "issues": [] },
    "business_logic": { "passed": true, "issues": [] }
  },
  "blocking_issues_count": 0,
  "non_blocking_issues_count": 1
}
```

**Workflow**:
1. Verify all quality gates passed (call `/test` if not)
2. Run 7 agents in parallel
3. Aggregate results
4. Comment comprehensive review in Linear
5. If blocking issues:
   - Present issues with context
   - Offer to fix immediately
   - Re-run review after fixes
6. If non-blocking issues:
   - Ask whether to fix now or create follow-up issues
7. Only proceed to PR when: `blocking_issues_count = 0`

**Integration**:
- Requires `/test` to pass first
- Blocks `/pr` until no blocking issues
- Results posted to Linear epic as comment
- Can be triggered automatically in CI

### 5. `/pr` - Pull Request Creation

**Purpose**: Create GitHub PR with full traceability

**Usage**:
```bash
/pr BE-100                 # Create PR for epic
/pr BE-100 --draft         # Create draft PR
/pr BE-100 --no-review     # Skip local review
```

**Arguments**:
- `$1`: Epic or standalone issue ID
- `--draft`: Create as draft PR
- `--no-review`: Skip `/review` (not recommended)
- `--base=<branch>`: Target branch (default: main)

**Workflow**:
1. Verify on correct feature branch
2. Run `/test` if not already passed
3. Run `/review` if not already passed (unless `--no-review`)
4. Generate PR title: `feat: Add user caching feature (BE-100)`
5. Generate PR body:
   ```markdown
   ## Summary
   [From review_summary]

   ## Issues Closed
   Closes #BE-100
   Closes #BE-101
   Closes #BE-102
   Closes #BE-103

   ## Implementation Specs
   - [Epic Plan](../blob/.../specs/issue-BE-100-user-caching-epic.md)
   - [Cache Model](../blob/.../specs/issue-BE-101-cache-model.md)
   - [Cache Service](../blob/.../specs/issue-BE-102-cache-service.md)
   - [Cache API](../blob/.../specs/issue-BE-103-cache-api.md)

   ## Review Summary
   [Non-blocking issues if any]

   ## Test Results
   - ✅ Format
   - ✅ Lint
   - ✅ Type Check
   - ✅ Architecture Validation
   - ✅ Test Suite (80% coverage)

   ## Changed Files
   [Git diff --stat]
   ```
6. Push branch: `git push -u origin feature/BE-100-user-caching`
7. Create PR: `gh pr create --title "..." --body "..."`
8. Comment PR URL in Linear epic
9. Mark Linear epic as "Ready for Review"

**Output**:
- GitHub PR created
- PR URL returned
- Linear updated with PR link
- Exit code: 0 = success

**CI Integration**:
- CI will re-run `/test` and `/review` on PR
- If CI review finds new issues, agent can fix in PR or create follow-up

## Command Composition Patterns

### Pattern 1: Sequential Pipeline
```bash
/implement BE-101 && /test && /review && /pr BE-100
```

### Pattern 2: Fix Loop
```bash
/test
# If failures, internally loops:
while ! success; do
  fix_errors
  /test
done
```

### Pattern 3: Atomic Workflow
```bash
/plan "Add caching"
# Creates BE-100, BE-101, BE-102, BE-103
/implement BE-101 BE-102 BE-103
# Internally calls /test
# Only exits when tests pass
/review
# Only exits when no blockers
/pr BE-100
```

## TDD Detection & Workflow

### Detection Priority
1. Command flags: `--tdd` or `--no-tdd` (explicit)
2. Linear labels: `tdd:required`
3. Issue type: `type:bug` → TDD default
4. Description keywords: "TDD", "test-first", "red-green-refactor"
5. Ask user if unclear

### TDD Workflow (Red-Green-Refactor)
```
For each feature in spec:
  1. RED: Write failing test
     - Run test, verify it fails
     - Commit: "test: add failing test for X (BE-XXX)"

  2. GREEN: Implement minimum code to pass
     - Run test, verify it passes
     - Commit: "feat: implement X (BE-XXX)"

  3. REFACTOR: Improve code quality
     - Maintain passing tests
     - Commit: "refactor: improve X implementation (BE-XXX)"
```

### Standard Workflow (Implementation-First)
```
For each feature in spec:
  1. Implement feature
  2. Write comprehensive tests
  3. Refactor for quality
  4. Commit: "feat: implement X with tests (BE-XXX)"
```

## Quality Gates Specification

### Gate 1: Format
- **Tool**: `ruff format`
- **Auto-fix**: Yes
- **Fail Fast**: No
- **Commit on Fix**: Yes
- **Message**: "style: auto-format code"

### Gate 2: Lint
- **Tool**: `ruff check --select ALL`
- **Auto-fix**: Partial (safe fixes only)
- **Fail Fast**: No
- **Rules**: All ruff rules enabled
- **Exceptions**: Configured in `pyproject.toml`

### Gate 3: Type Check
- **Tool**: `mypy --strict`
- **Auto-fix**: No
- **Fail Fast**: No
- **Coverage**: 100% (strict mode)

### Gate 4: Architecture Validation
- **Tool**: Pattern Stack validator
- **Auto-fix**: No
- **Fail Fast**: Yes (architecture violations are serious)
- **Rules**: Atomic Architecture v2.1

### Gate 5: Tests
- **Tool**: `pytest` via `make test-ci`
- **Auto-fix**: No
- **Fail Fast**: No (run all tests)
- **Coverage**: 80% minimum
- **Parallel**: Yes (safe tests)
- **Sequential**: Pattern integration, benchmarks

## Error Handling

### Command Failures
- All commands return JSON with success status
- Non-zero exit codes on failure
- Detailed error messages with context
- Suggested fixes when possible

### Linear Integration Failures
- Retry with exponential backoff
- Fallback to manual instructions
- Never leave Linear in inconsistent state

### Git Operation Failures
- Detect conflicts early
- Offer to stash/pop
- Never force push to main
- Always verify branch state

## Traceability

### From User Request to Merged Code
```
User: "Add user caching"
  ↓
/plan creates: Epic BE-100 + subs
  ↓
specs/issue-BE-10X-*.md committed
  ↓
/implement creates atomic commits (BE-101, BE-102, BE-103)
  ↓
/test validates all gates
  ↓
/review provides feedback
  ↓
/pr BE-100 creates GitHub PR
  ↓
PR description links:
  - Linear epic: BE-100
  - Linear subs: BE-101, BE-102, BE-103
  - Specs: All spec files
  - Commits: All atomic commits
  - Review: Agent feedback
  - Tests: Coverage report
```

### Linear ↔ GitHub Sync
- PR comments create Linear comments (via webhook/API)
- Linear updates trigger GitHub labels
- Merge closes all linked Linear issues
- Linear shows PR status inline

## Demo Scenario

### Setup (2 min)
- Show CLAUDE.md, architecture docs
- Quick tour: `make test-ci`, `make validate`

### Planning (3 min)
```bash
/plan "Add user profile caching feature"
# Interactive discussion
# Shows decomposition into BE-100 + subs
# Creates Linear issues and specs
```

### Implementation (5 min)
```bash
/implement BE-101 BE-102 BE-103
# Shows TDD workflow for BE-101 (bug fix included)
# Shows standard workflow for BE-102, BE-103
# Shows atomic commits in real-time
# Shows Linear updates
```

### Quality Gates (7 min) ⭐ FOCUS
```bash
/test
# Intentionally planted bugs to catch:
# - Unused import (lint)
# - Type error (mypy)
# - Layer violation (architecture)
# - Failing test (logic error)
# - Coverage gap (missing test)

# Show each gate catching issues
# Show fix loop in action
# Show final success
```

### Review (5 min)
```bash
/review
# Shows 7 parallel agents
# Architecture: ✅
# Security: ✅
# Performance: ⚠️ (suggestion)
# Test Coverage: ✅
# Documentation: ⚠️ (minor)
# Code Style: ✅
# Business Logic: ✅

# Shows aggregated feedback
# Shows Linear integration
```

### Ship (3 min)
```bash
/pr BE-100
# Shows PR creation
# Shows full traceability
# Discusses: "Now CI runs same gates"
# Discusses: "Agents can handle PR feedback autonomously"
```

## Success Metrics

### For Demo
- ✅ Workflow completes in under 25 minutes
- ✅ Quality gates catch all planted bugs
- ✅ Full traceability visible (Linear → Spec → Code → PR)
- ✅ Clear distinction: human guides, AI executes
- ✅ Demonstrates production-readiness

### For Production Use
- ✅ Zero architecture violations reach main
- ✅ 80%+ test coverage maintained
- ✅ All PRs have linked Linear issues
- ✅ All PRs have specs committed
- ✅ CI review catches issues before merge
- ✅ Issues created from review are actioned

## Future Enhancements

### Phase 2 Features
- `/workflow BE-100` - Full pipeline automation with breakpoints
- `/fix` - Dedicated fix command with context awareness
- Multi-repository support
- Custom quality gate plugins
- Agent specialization framework

### CI/CD Integration
- GitHub Action that runs `/review` on every PR
- Automated issue creation from review findings
- PR auto-merge when all gates pass + approval
- Slack/Discord notifications

### Analytics
- Command usage metrics
- Quality gate effectiveness
- Time savings measurements
- Issue resolution patterns

## Appendix A: Command Templates

### Base Template Structure
```markdown
# Command Name

<Purpose statement>

## Variables
<List of input variables>

## Instructions
<Step-by-step instructions for Claude>

## Workflow
<Detailed workflow steps>

## Report
<Output format specification>
```

### Composition Template
```markdown
# Composed Command

## Instructions
1. Call `/subcommand-1 $ARG1`
2. Parse output as JSON
3. If success, call `/subcommand-2 <result>`
4. Otherwise, loop until success
```

## Appendix B: Linear Label Schema

### Type Labels
- `type:epic` - Parent issue
- `type:feature` - New functionality
- `type:bug` - Bug fix
- `type:chore` - Maintenance task
- `type:refactor` - Code improvement

### TDD Labels
- `tdd:required` - Explicit TDD required
- `tdd:optional` - TDD suggested but not required

### Layer Labels
- `layer:atoms` - Atoms layer
- `layer:features` - Features layer
- `layer:molecules` - Molecules layer
- `layer:organisms` - Organisms layer

### Status Labels
- `status:planning` - In planning phase
- `status:implementing` - In implementation
- `status:testing` - In testing phase
- `status:reviewing` - In review
- `status:blocked` - Blocked on something

## Appendix C: Spec File Template

```markdown
# Issue: <Title>

## Metadata
issue_number: BE-XXX
epic_number: BE-YYY (if applicable)
branch: feature/BE-YYY-name
tdd_required: true/false

## Description
<Detailed description from Linear>

## Problem Statement
<What problem does this solve>

## Solution Statement
<How we'll solve it>

## Technical Approach
<Architecture, patterns, technologies>

## Relevant Files
### Existing Files
- `path/to/file.py` - Why relevant

### New Files
- `path/to/new.py` - What it will contain

## Step by Step Tasks
### Task 1: <Name>
- [ ] Subtask 1
- [ ] Subtask 2

### Task 2: <Name>
- [ ] Subtask 1

## Validation Commands
```bash
make format
make lint
make typecheck
make validate
make test-ci
```

## Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2

## Dependencies
- Depends on: BE-XXX
- Blocks: BE-YYY

## Notes
<Additional context>
```

---

**Document Status**: Design Phase
**Next Steps**: Create Linear epic, dogfood this architecture
**Owner**: Dug + Claude
**Last Updated**: 2025-10-26
