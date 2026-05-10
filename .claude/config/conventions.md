# Project Conventions

**Version**: 1.0
**Status**: Active
**Purpose**: Single source of truth for tempo-demo project conventions

This document defines all conventions for commit messages, branch naming, Linear labels, workflow states, spec locations, and PR formatting. Commands reference these conventions, and they can be overridden via `.env` configuration.

---

## Commit Format

### Standard: Conventional Commits

All commits follow the Conventional Commits specification with Linear issue tracking integration.

**Format**:
```
<type>(<scope>): <description> (ISSUE-ID)
```

**Examples**:
```
feat(atoms/cache): add Redis cache adapter (TEMPO-101)
test(atoms/cache): add cache adapter tests (TEMPO-101)
fix(features/users): correct cache key generation (TEMPO-105)
docs(commands): update README to reflect git/ subdirectory structure (TEMPO-32)
refactor(commands): remove embedded bash from /plan:generate-spec (TEMPO-33)
chore(deps): update pattern-stack to v2.5.1 (TEMPO-120)
```

### Commit Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| `feat` | New feature or functionality | Adding new capabilities, components, or APIs |
| `fix` | Bug fix | Correcting errors, resolving issues, fixing broken behavior |
| `test` | Adding or updating tests | Test files, test utilities, test fixtures |
| `docs` | Documentation changes | README, guides, comments, inline documentation |
| `refactor` | Code restructuring | No behavior change, improving structure/readability |
| `style` | Formatting changes | Code style, whitespace, formatting (no logic changes) |
| `chore` | Maintenance tasks | Dependencies, config files, build scripts, tooling |

### Scope Guidelines

The scope indicates **what part of the codebase** was modified. Use the layer/component path structure.

**Backend (Pattern Stack layers)**:
- `atoms/cache` - Atoms layer, cache component
- `atoms/security` - Atoms layer, security component
- `features/users` - Features layer, users service
- `features/accounts` - Features layer, accounts service
- `molecules/accounts` - Molecules layer, accounts entity/facade
- `molecules/brain-dump` - Molecules layer, brain dump workflow
- `organisms/api` - Organisms layer, API endpoints
- `organisms/cli` - Organisms layer, CLI commands

**Frontend (component layers)**:
- `atoms/Button` - Atoms layer, Button component
- `molecules/SearchBar` - Molecules layer, SearchBar component
- `organisms/Header` - Organisms layer, Header module
- `pages/Dashboard` - Pages layer, Dashboard page

**Infrastructure/Tooling**:
- `commands` - Claude Code commands
- `skills` - Claude Code skills
- `config` - Configuration files
- `deps` - Dependencies
- `infra` - Infrastructure setup

**Cross-cutting**:
- `backend` - Backend-wide changes
- `frontend` - Frontend-wide changes
- `repo` - Repository-wide changes

### Description Guidelines

- Use **present tense, imperative mood**: "add feature" not "added feature" or "adds feature"
- Use **lowercase**: "add Redis adapter" not "Add Redis adapter"
- Be **specific and concise**: "add cache adapter" not "add stuff"
- No **period at end**: "add feature" not "add feature."
- Focus on **what and why**, not how

**Good**:
- "add Redis cache adapter"
- "fix null pointer in user lookup"
- "update README with setup instructions"

**Bad**:
- "Added some caching stuff" (past tense, vague)
- "Fix bug." (too vague)
- "This adds a Redis cache adapter that uses redis-py" (too verbose)

### Issue ID Format

- Required: `(TEMPO-XXX)` at end of commit message
- Use the Linear issue ID you're working on
- If no issue exists, create one first (exception: emergency hotfixes can omit)

### Override Configuration

```bash
# In .env
COMMIT_FORMAT=conventional  # or "simple", "detailed"
```

---

## Branch Naming

### Convention

Branches follow a consistent prefix/ID/description pattern that makes the branch purpose and scope immediately clear.

**Format**:
```
{prefix}/{ISSUE-ID}-{short-description}
```

**Examples**:
```
feature/TEMPO-32-git-commands
feature/TEMPO-46-account-model
fix/TEMPO-105-auth-timeout
chore/TEMPO-120-update-dependencies
```

### Branch Prefixes

| Prefix | Issue Type | Purpose | Example |
|--------|-----------|---------|---------|
| `feature/` | Feature, Epic | New features, enhancements | `feature/TEMPO-46-account-model` |
| `fix/` | Bug | Bug fixes | `fix/TEMPO-105-auth-timeout` |
| `chore/` | Chore | Maintenance, tooling, dependencies | `chore/TEMPO-120-deps-update` |

### Branch Types

**Epic Branch** (contains multiple sub-issues):
```
feature/TEMPO-100-user-caching
  ↓
Contains commits for:
  - TEMPO-101 (cache interface)
  - TEMPO-102 (Redis adapter)
  - TEMPO-103 (API integration)
```

**Single Issue Branch**:
```
feature/TEMPO-105-add-user-search
  ↓
Contains commits for only TEMPO-105
```

**Bug Fix Branch**:
```
fix/TEMPO-110-null-pointer-in-auth
  ↓
TDD workflow: test first, then fix
```

### Description Guidelines

- Use **kebab-case**: `account-model` not `account_model` or `AccountModel`
- Keep it **short**: 2-4 words maximum
- Be **descriptive**: what is being built/fixed
- Use the **epic/issue summary** as inspiration

**Good**:
- `feature/TEMPO-46-account-model`
- `fix/TEMPO-105-auth-timeout`
- `feature/TEMPO-100-user-caching`

**Bad**:
- `feature/TEMPO-46` (no description)
- `feature/tempo-46-add-account-model-with-all-fields` (too long, wrong case)
- `my-branch` (no issue ID)
- `TEMPO-46` (no prefix)

### Base Branch

All feature branches are created from and merged back to:
```
working-files
```

**NOT** `main` (main is reserved for stable releases).

### Override Configuration

```bash
# In .env
BRANCH_PREFIX_FEATURE=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
BRANCH_PREFIX_EPIC=feature
GITHUB_BASE_BRANCH=working-files
```

---

## Linear Labels

### Label Philosophy

Labels provide **structured metadata** that enables:
- Automated routing and filtering
- Architecture layer enforcement
- Stack-specific workflows
- Priority and status tracking

### Required Labels

Every issue **MUST** have these labels before moving to "Ready" status:

| Category | Required | Options | Description |
|----------|----------|---------|-------------|
| **Stack** | ✅ One required | `stack:backend`<br>`stack:frontend`<br>`stack:fullstack` | Which part of the codebase |
| **Type** | ✅ One required | `type:epic`<br>`type:feature`<br>`type:bug`<br>`type:chore` | What kind of work |
| **Work** | ✅ One required | `work:architecture`<br>`work:infrastructure`<br>`work:feature`<br>`work:enhancement`<br>`work:bugfix` | Nature of the work |
| **Layer** | ✅ If backend | `layer:atoms`<br>`layer:features`<br>`layer:molecules`<br>`layer:organisms` | Which architectural layer |

### Complete Label Taxonomy

#### Issue Structure

Used to indicate parent/child relationships:

- `issue` - Regular standalone issue
- `subissue` - Child of an epic (has a parent)
- `epic` - Parent container with sub-issues

#### Issue Type

Primary classification of work:

- `type:epic` - Large multi-step body of work with sub-issues
- `type:feature` - Complete user-facing feature or capability
- `type:bug` - Bug fix or correction
- `type:chore` - Maintenance, tooling, dependencies, config

#### Work Type

Nature of the implementation work:

- `work:architecture` - Design, planning, architecture decisions, ADRs
- `work:infrastructure` - Setup, Docker, CI/CD, database config, tooling
- `work:feature` - New feature implementation
- `work:enhancement` - Improvement to existing feature
- `work:bugfix` - Bug fixes and corrections

#### Stack

Which part of the codebase is affected:

- `stack:backend` - Python backend work (FastAPI, SQLAlchemy, services)
- `stack:frontend` - React frontend work (TypeScript, components, UI)
- `stack:fullstack` - Work spanning both backend and frontend

**Important**: Fullstack issues should typically be broken into separate backend and frontend sub-issues.

#### Layer (Backend Only)

Pattern Stack architectural layer (only applicable for `stack:backend`):

- `layer:atoms` - Domain-agnostic utilities, infrastructure (database, cache, security)
- `layer:features` - Data services, CRUD operations (one per entity)
- `layer:molecules` - Business logic, orchestration (entities, facades, workflows)
- `layer:organisms` - User interfaces (HTTP API, CLI, MCP servers)

**Layer Import Rules**:
- ✅ Higher layers CAN import lower layers
- ❌ NEVER import backwards (atoms can't import features)
- ❌ NEVER cross-import within same layer

#### Component (Backend Only)

Specific component type within molecules layer:

- `component:entity` - Entity components in molecules layer
- `component:api-facade` - API facade components in molecules layer
- `component:workflow` - Workflow components in molecules layer
- `component:middleware` - Middleware components

#### Domain

Business domain area:

- `domain:users` - User management and authentication
- `domain:accounts` - Account/company management features
- `domain:activities` - Activity feed and event tracking
- `domain:deals` - Deal pipeline and stage management
- `domain:ai` - AI features and LLM integration
- `domain:search` - Search functionality (semantic, full-text)

#### State (Workflow Metadata)

Supplementary state information beyond Linear workflow states:

- `state:awaiting-strategy-review` - Strategy generated, waiting for human review
- `state:strategy-approved` - Strategy reviewed and approved by human
- `state:blocked` - Cannot proceed, waiting on external dependency
- `state:needs-clarification` - Requires more information or discussion

#### Priority

Urgency and importance:

- `priority:critical` - System down, blocking all work
- `priority:high` - Important, should be done soon
- `priority:medium` - Normal priority
- `priority:low` - Nice to have, can wait

### Label Examples

**Backend Feature (Epic with subs)**:
```
Epic: TEMPO-100 - "Add user caching"
  Labels: epic, stack:backend, work:feature, layer:atoms

Sub: TEMPO-101 - "Implement cache interface"
  Labels: subissue, stack:backend, work:feature, layer:atoms

Sub: TEMPO-102 - "Add Redis adapter"
  Labels: subissue, stack:backend, work:feature, layer:atoms

Sub: TEMPO-103 - "Integrate cache in user service"
  Labels: subissue, stack:backend, work:feature, layer:features
```

**Frontend Feature**:
```
Issue: TEMPO-150 - "Add account timeline component"
  Labels: issue, stack:frontend, work:feature
```

**Fullstack Feature (broken into sub-issues)**:
```
Epic: TEMPO-200 - "Add user authentication"
  Labels: epic, stack:fullstack, work:feature

Sub: TEMPO-201 - "Backend: JWT token service"
  Labels: subissue, stack:backend, work:feature, layer:features

Sub: TEMPO-202 - "Frontend: Login form component"
  Labels: subissue, stack:frontend, work:feature
```

**Bug Fix**:
```
Issue: TEMPO-110 - "Fix null pointer in user lookup"
  Labels: issue, type:bug, stack:backend, work:bugfix, layer:features
```

**Infrastructure Chore**:
```
Issue: TEMPO-120 - "Update Pattern Stack dependency"
  Labels: issue, type:chore, stack:backend, work:infrastructure
```

### Label Discovery

**List all available labels**:
```bash
tp labels list --team TEMPO

# Verbose output with IDs:
LOG_LEVEL=info tp labels list --team TEMPO
```

**Apply labels**:
```bash
# Via tp CLI (when supported):
tp update TEMPO-123 --labels "stack:backend,type:feature,work:feature,layer:atoms"

# Via Linear MCP (current method):
mcp__linear__linear_addIssueLabel --issueId "TEMPO-123" --labelName "stack:backend"
```

### Override Configuration

Labels are managed in Linear UI, not via `.env`.

---

## Workflow States

### Linear Workflow State Machine

The project uses a structured workflow with clear gates and transitions:

```
Triage → Ideation → Backlog → Refinement → Ready → In Progress → In Review → Done
  ↓          ↓         ↓           ↓          ↓          ↓            ↓        ↓
 Raw      Discuss   Complete   Strategy    Spec     Coding      PR Open   Merged
 Idea                Issue     (HUMAN)   Generated  Active      (HUMAN)
```

### State Definitions

| State | Description | Entry Criteria | Exit Criteria | Who Moves It |
|-------|-------------|----------------|---------------|--------------|
| **Triage** | Raw idea, minimal structure | Created manually | Basic info added | Human |
| **Ideation** | Discussion and refinement | From Triage | Decision made | Human or Agent |
| **Backlog** | Ready for planning | Complete issue description | Selected for work | Human |
| **Refinement** | Strategy being generated | `/plan:1-decompose` or `/plan:3-generate-spec` | Strategy approved (HUMAN GATE) | Agent + Human |
| **Ready** | Detailed spec complete, ready to code | Spec approved, all labels set | `/implement` starts | Agent |
| **In Progress** | Code being written | `/implement` active | Code complete, ready for PR | Agent |
| **In Review** | PR open, under review | PR created, tests pass | PR approved, merged (HUMAN GATE) | Human |
| **Done** | Merged to main | PR merged | N/A | Automatic |

### Human Gates

There are **TWO** human review points:

1. **Strategy Review** (Refinement → Ready):
   - Agent generates implementation strategy
   - Issue moves to "Refinement" with `state:awaiting-strategy-review` label
   - Human reviews strategy in Linear
   - If approved: Human adds `state:strategy-approved` label and moves to "Ready"
   - If not approved: Human comments, agent refines

2. **PR Review** (In Review → Done):
   - Agent creates PR, moves issue to "In Review"
   - Human reviews code in GitHub PR
   - If approved: Human merges PR (issue auto-moves to Done via GitHub integration)
   - If not approved: Human requests changes

### State Transition Commands

**Planning**:
```bash
# Create issues (they start in Backlog)
/plan:2-create-issues issue-plan-*.yaml

# Generate strategy (moves to Refinement with awaiting-strategy-review)
/plan:3-generate-spec TEMPO-123
```

**After Human Approval**:
```bash
# Human adds state:strategy-approved label and moves to Ready via Linear UI

# Agent implements (moves to In Progress automatically)
/implement TEMPO-123
```

**Completion**:
```bash
# Create PR (moves to In Review)
/git:pr TEMPO-123 "Add account model"

# Human reviews and merges PR → Done (automatic)
```

### State Label Integration

Workflow state labels complement Linear workflow states:

- `state:awaiting-strategy-review` - In Refinement, waiting for human review
- `state:strategy-approved` - Human approved, ready to move to Ready
- `state:blocked` - Cannot proceed (any state)
- `state:needs-clarification` - Needs more info (any state)

### Override Configuration

Workflow states are configured in Linear UI, not via `.env`.

---

## Spec Locations

### Location Rules

Spec file location is determined by the **stack label** on the Linear issue:

| Stack Label | Spec Location | Reason |
|-------------|---------------|--------|
| `stack:backend` | `application/backend/specs/` | Keep backend specs with backend code |
| `stack:frontend` | `application/frontend/specs/` | Keep frontend specs with frontend code |
| `stack:fullstack` | `specs/` (project root) | Shared visibility for both stacks |

### Spec Naming Convention

```
issue-{ISSUE-ID}-{short-description}.md
```

**Examples**:
```
application/backend/specs/issue-TEMPO-46-account-model.md
application/frontend/specs/issue-TEMPO-150-timeline-component.md
specs/issue-TEMPO-200-user-authentication-epic.md
```

### Spec Structure

Every spec should contain:

1. **Header** - Issue ID, title, Linear link
2. **Overview** - What is being built and why
3. **Requirements** - Functional and technical requirements
4. **Architecture** - Design decisions, layer placement
5. **Implementation Plan** - Step-by-step tasks
6. **Validation** - How to test and verify
7. **Files Changed** - List of files that will be created/modified

### Spec Lifecycle

1. **Generated** by `/plan:3-generate-spec TEMPO-123`
2. **Committed** to feature branch
3. **Linked** in Linear issue as first comment
4. **Updated** during implementation if design changes
5. **Referenced** in PR description

### Override Configuration

```bash
# In .env
SPEC_DIR_BACKEND=application/backend/specs
SPEC_DIR_FRONTEND=application/frontend/specs
SPEC_DIR_FULLSTACK=specs
```

---

## PR Format

### Title Format

PR titles should be clear and descriptive, matching the Linear issue or epic summary:

**Format**:
```
{Issue Title} ({ISSUE-ID})
```

**Examples**:
```
Refactor git commands into dedicated subdirectory (TEMPO-32)
Add account model to backend (TEMPO-46)
Fix authentication timeout issue (TEMPO-105)
```

**Guidelines**:
- Use the **issue title** as-is (don't add type prefixes like "feat:" or "fix:")
- Include the **issue ID** in parentheses at the end
- Use **sentence case**: "Add feature" not "add feature" or "ADD FEATURE"
- Be **descriptive**: what was done, not how

### Body Format

PR body is **auto-generated** by the `/git:pr` command and includes:

1. **Linear Issue** - Link to issue(s) with "Closes" statements
2. **Summary** - What this PR does
3. **Changes** - File count and diff stats
4. **Commits** - List of all commits included
5. **Checklist** - Review readiness checklist

**Example PR Body**:
```markdown
## Linear Issue

Closes [TEMPO-32](https://linear.app/...)

**Title**: Refactor git commands into dedicated subdirectory

## Summary

Refactor git commands into dedicated subdirectory

## Changes

5 files changed across 3 commits

```
 .claude/commands/{ => git}/commit.md         | 0
 .claude/commands/{ => git}/pr.md             | 0
 .claude/commands/{ => git}/ensure-feature-branch.md | 0
 .claude/commands/README.md                   | 12 ++++++------
 4 files changed, 6 insertions(+), 6 deletions(-)
```

## Commits

```
108e3fc docs(commands): update README to reflect git/ subdirectory structure (TEMPO-32)
2c33d50 refactor(commands): move ensure-feature-branch to git/ subdirectory (TEMPO-32)
89c39a7 feat(commands/git): add PR creation command with Linear integration (TEMPO-32)
```

## Checklist

- [ ] All quality gates pass
- [ ] Tests added/updated
- [ ] Documentation updated (if needed)
- [ ] Linear issue reviewed
- [ ] Ready for review

---

**Linear**: https://linear.app/...
```

### Creating PRs

**Command**:
```bash
/git:pr TEMPO-123 "Add account model to backend"
```

**Preconditions**:
1. Feature branch exists
2. All commits pushed to origin
3. All quality gates pass
4. Issue in Linear exists

### PR Merging

**After merge**:
1. PR closes automatically
2. Linear issue moves to "Done" (via GitHub integration)
3. Feature branch can be deleted
4. Commits are in `working-files` branch

### Override Configuration

```bash
# In .env
GITHUB_ORG=your-org
GITHUB_REPO=your-repo
GITHUB_BASE_BRANCH=working-files
```

---

## Configuration Override Reference

All conventions can be customized via `.env` file in project root.

### Available Override Variables

```bash
# ===== Project Configuration =====
PROJECT_NAME=tempo-demo
PROJECT_TEAM_KEY=TEMPO
PROJECT_STACK=fullstack

# ===== Linear Integration =====
LINEAR_API_KEY=lin_api_xxxxx
LINEAR_TEAM_ID=your-team-uuid
LINEAR_ORG_ID=your-org-uuid

# ===== GitHub Configuration =====
GITHUB_ORG=your-org
GITHUB_REPO=your-repo
GITHUB_BASE_BRANCH=working-files

# ===== Commit Conventions =====
COMMIT_FORMAT=conventional

# ===== Branch Conventions =====
BRANCH_PREFIX_FEATURE=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
BRANCH_PREFIX_EPIC=feature

# ===== Spec Locations =====
SPEC_DIR_BACKEND=application/backend/specs
SPEC_DIR_FRONTEND=application/frontend/specs
SPEC_DIR_FULLSTACK=specs
```

### Using Override Variables

**In commands**:
```bash
# Source .env
[ -f .env ] && source .env

# Use variables
BRANCH_NAME="${BRANCH_PREFIX_FEATURE}/${ISSUE_ID}-${DESCRIPTION}"
```

**In skills**:
```markdown
## Step 1: Read Configuration

```bash
# Read from .env or use defaults
BRANCH_PREFIX=${BRANCH_PREFIX_FEATURE:-feature}
BASE_BRANCH=${GITHUB_BASE_BRANCH:-working-files}
```
```

---

## Quick Reference

### Commit Examples by Layer

**Backend - Atoms**:
```
feat(atoms/cache): add Redis cache adapter (TEMPO-101)
test(atoms/cache): add cache adapter tests (TEMPO-101)
fix(atoms/security): correct JWT validation logic (TEMPO-108)
```

**Backend - Features**:
```
feat(features/users): add get_user_by_email method (TEMPO-105)
test(features/users): add user lookup tests (TEMPO-105)
fix(features/accounts): correct null handling in account query (TEMPO-110)
```

**Backend - Molecules**:
```
feat(molecules/accounts): add account entity with caching (TEMPO-115)
feat(molecules/brain-dump): implement processing workflow (TEMPO-118)
```

**Backend - Organisms**:
```
feat(organisms/api): add account endpoints (TEMPO-120)
feat(organisms/cli): add brain dump CLI command (TEMPO-122)
```

**Frontend**:
```
feat(atoms/Button): add loading state prop (TEMPO-150)
feat(organisms/Header): add user menu dropdown (TEMPO-155)
fix(pages/Dashboard): correct timeline rendering (TEMPO-160)
```

**Infrastructure**:
```
chore(deps): update pattern-stack to v2.5.1 (TEMPO-180)
feat(commands): add /analyze-implementation command (TEMPO-182)
docs(README): add setup instructions (TEMPO-185)
```

### Branch Examples

```
feature/TEMPO-46-account-model
feature/TEMPO-100-user-caching
fix/TEMPO-105-auth-timeout
fix/TEMPO-110-null-pointer
chore/TEMPO-120-deps-update
feature/TEMPO-200-authentication-epic
```

### Label Combinations

**Backend feature in atoms layer**:
```
stack:backend + type:feature + work:feature + layer:atoms
```

**Frontend bug fix**:
```
stack:frontend + type:bug + work:bugfix
```

**Backend infrastructure chore**:
```
stack:backend + type:chore + work:infrastructure
```

**Epic with fullstack work**:
```
epic + stack:fullstack + work:feature
(then sub-issues split into stack:backend and stack:frontend)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-02 | Initial comprehensive conventions document |

---

**References**:
- Conventional Commits: https://www.conventionalcommits.org/
- Pattern Stack Architecture: `.claude/docs/patterns/pattern-stack-framework-architecture-v2.md`
- Workflow Architecture: `.claude/docs/agentic-workflow-architecture.md`
- Command Catalog: `.claude/commands/README.md`
