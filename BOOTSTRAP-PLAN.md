# DealBrain Bootstrap Project Plan

**Goal**: Build autonomous development workflow with human-in-the-loop gates, then launch DealBrain using that workflow.

**Philosophy**: 
- Commands stay CLEAN - delegate details to skills
- Conventions abstracted to config (not embedded in commands)
- Human gates at strategy and PR review only
- Everything else automated
- 100% commit consistency via `/commit` across all workflows

---

## Phase 0: Foundation Setup (Manual - 30 minutes)

### Linear Project Setup

**Create Team** (via tp CLI):
```bash
# Option 1: From template
tp team apply-template engineering --key DEAL --name "DealBrain Development"

# Option 2: Custom configuration
tp team create DEAL "DealBrain Development" \
  --description "DealBrain product development" \
  --cycles --cycle-duration 14 --triage

# Get Team ID for .env
tp team show DEAL
```

**Team Configuration**:
- Name: `${PROJECT_NAME}` (e.g., "DealBrain")
- Team Key: `${TEAM_KEY}` (e.g., "DEAL" - short, clean)
- Copy Team ID for `.env` and `.tp/config.json`

**Workflow States** (in order):
1. **Triage** - Raw ideas, no structure required
2. **Ideation** - AI-assisted refinement (optional)
3. **Backlog** - Complete issues ready for development planning
4. **Refinement** - Implementation strategy proposed (HUMAN GATE ⚠️)
5. **Ready** - Detailed spec generated, ready to code
6. **In Progress** - Code being written
7. **In Review** - PR review (HUMAN GATE ⚠️)
8. **Done** - Shipped

**Labels** (bulk create):
```
# Issue Structure
issue        # Regular standalone issue
subissue     # Child of an epic
epic         # Parent container with children

# Issue Type
issue-type:bug
issue-type:chore
issue-type:documentation

# Work
work:architecture
work:infrastructure
work:feature
work:enhancement
work:bugfix

# Stack
stack:backend
stack:frontend
stack:fullstack

# Layer (backend Pattern Stack architecture)
layer:atoms
layer:features
layer:molecules
layer:organisms

# State (workflow metadata)
state:awaiting-strategy-review
state:strategy-approved
state:blocked
state:needs-clarification

# Priority
priority:critical
priority:high
priority:medium
priority:low
```

**GitHub Integration**:
- Settings → Integrations → GitHub
- Connect repository: `${GITHUB_ORG}/${GITHUB_REPO}`
- Enable bi-directional sync
- Issues auto-close on PR merge

---

### GitHub Repository Setup

**Create Repository**:
```bash
cd ~/Projects/${PROJECT_NAME}
gh repo create ${GITHUB_ORG}/${GITHUB_REPO} --private --source=. --remote=origin
git push -u origin main
```

**Branch Protection** (via GitHub UI):
- Settings → Branches → Add rule for `main`
- ✅ Require pull request before merging
- ✅ Require approvals: 1 (or 0 for solo dev)
- ✅ Dismiss stale approvals
- ✅ Require status checks (when CI added later)
- ✅ Do not allow bypassing
- ✅ Restrict pushes (prevents direct commits)

**Result**: No more accidental commits to main ✅

---

### Project Configuration Files

**`.env.example`** (committed, template):
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
PROJECT_TEAM_KEY=YOUR-KEY
PROJECT_STACK=fullstack

# Conventions
COMMIT_FORMAT=conventional
BRANCH_PREFIX_EPIC=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
```

**`.env`** (git-ignored, actual values):
```bash
# Copy .env.example and fill in real values
cp .env.example .env
# Edit with your actual credentials and project info
```

**`.tp/config.json`**:
```json
{
  "defaultTeam": "${TEAM_KEY}",
  "teams": {
    "${TEAM_KEY}": {
      "name": "${PROJECT_NAME}",
      "id": "YOUR-LINEAR-TEAM-ID"
    }
  }
}
```

---

## Phase 1: Command Architecture (Build - 4-6 hours)

### Command Design Principles

**1. Clean Structure** (IndyDevDan pattern):
```markdown
# Command Name

Brief description.

## Purpose
What this command does and when to use it.

## Variables
issue_id: $1
epic_id: $2

## Workflow
1. High-level step 1
2. High-level step 2
3. High-level step 3

## Instructions
- Detailed step 1 with specifics
- Detailed step 2 with specifics
- Delegate to skills: "Use task-patterns skill to create issues"
- Commit changes: "Use git-workflow skill to commit"

## Report
- What to output when done
```

**2. Skill Delegation**:
```markdown
# ❌ BAD (embedded details)
Run: tp add "Issue title" --team DEAL --labels issue,stack:backend,work:feature

# ✅ GOOD (delegate to skill)
Use task-patterns skill to create Linear issue with product requirements
```

**3. Convention Abstraction**:
```markdown
# ❌ BAD (hardcoded conventions)
Commit format: feat(scope): description (DEAL-123)

# ✅ GOOD (reference config)
Use git-workflow skill to commit with project conventions
```

**4. Commit Consistency** (CRITICAL):
```markdown
# EVERY command that modifies files MUST commit via git-workflow skill or /commit
# This includes:
- Creating specs
- Implementing code
- Running formatters
- Updating docs

# Pattern:
Use git-workflow skill: commit_changes(type, scope, message, issue_id)
```

---

### Command Naming Convention

**Format**: `/namespace:command-name` (no numbers)

```
✅ /plan:decompose
✅ /plan:create-issues
✅ /plan:generate-spec
✅ /analyze-implementation
✅ /implement
✅ /implement-epic
✅ /test
✅ /commit
✅ /pr
```

---

### Commands to Build

#### 1. `/refine-idea` (Optional Starting Point)
**Purpose**: Convert raw idea into complete product requirement

**Workflow**:
1. Accept raw idea input
2. Ask clarifying questions (interactive)
3. Draft product requirement document
4. Offer to auto-trigger decomposition

**Output**: Product requirement document

**State Transition**: Triage → Ideation → Backlog

**Size**: ~200-300 lines

---

#### 2. `/plan:decompose` (Existing - Cleanup)
**Purpose**: Break product requirement into epic + sub-issues

**Current**: 407 lines
**Target**: ~200 lines

**Changes**:
- Read from `.env` for project config
- Delegate tp commands to task-patterns skill
- Move YAML format to template file
- Reference conventions from config
- Commit YAML plan via git-workflow skill

**Workflow**:
1. Read product requirements
2. Load project conventions from .env
3. Analyze scope and complexity
4. Generate YAML with epic + children
5. Validate YAML structure
6. Commit YAML: `docs(planning): add issue decomposition plan`

**Output**: `issue-plan-{name}.yaml`

**State**: Ideation → Backlog (after /plan:create-issues)

---

#### 3. `/plan:create-issues` (Existing - Cleanup)
**Purpose**: Create Linear issues from YAML plan

**Current**: 360 lines
**Target**: ~150 lines

**Changes**:
- Read from `.env` for project/team config
- Delegate all tp commands to task-patterns skill
- Extract label validation to skill
- Use conventions from config

**Workflow**:
1. Read YAML file
2. Load project config from .env
3. Validate structure and labels (via skill)
4. Create epic in Linear (via skill)
5. Create child issues with subissue label (via skill)
6. Link children to parent (via skill)

**Output**: Issue IDs (DEAL-1, DEAL-2, etc.)

**State**: Creates issues in Backlog with appropriate labels (epic, subissue)

---

#### 4. `/analyze-implementation` (NEW - Core Innovation)
**Purpose**: Generate high-level implementation strategy

**Workflow**:
1. Fetch issue from Linear (via task-patterns skill)
2. Analyze codebase for similar patterns (via pattern-stack-architect skill)
3. Identify affected files/layers
4. Propose architecture approach
5. Post strategy comment to Linear (via task-patterns skill)
6. Add label: state:awaiting-strategy-review (via task-patterns skill)
7. Commit strategy document (via git-workflow skill)

**Strategy Comment Format**:
```markdown
## 🤖 Implementation Strategy

**Issue**: DEAL-5 - Add user authentication
**Analyzed**: 2025-11-02 14:30 UTC

### Approach
Use Pattern Stack BaseAuth pattern with JWT tokens.

### Architecture Impact
**Layer**: molecules (auth facade) + organisms (API routes)

**New Files**:
- `atoms/security/jwt.py` - JWT utilities
- `molecules/apis/auth.py` - Auth permission facade
- `organisms/api/auth_routes.py` - Login/register endpoints

**Modified Files**:
- `features/users/service.py` - Add login/register methods
- `app/main.py` - Register auth routes

### Dependencies
- Depends on: DEAL-3 (User model)
- Pattern Stack: BaseAuth, BaseSettings

### Testing Strategy
- Unit: JWT generation/validation
- Integration: Full login flow
- Security: Token tampering, expiration

### Implementation Sequence
1. Create JWT utilities (atoms layer)
2. Extend User service with auth methods
3. Create auth permission facade
4. Add API routes
5. Write tests throughout

### Open Questions
- Refresh token strategy? (recommend: yes, 7-day expiry)
- Password reset in scope? (recommend: separate issue)

### Estimated Complexity
Medium (4-5 hours)

---
Add label state:strategy-approved when ready to proceed
```

**Commits**:
- Strategy document: `docs(planning): add implementation strategy for ${ISSUE_ID}`

**Output**: Strategy comment in Linear

**State Transition**: Backlog → Refinement (awaiting review)

**Size**: ~300-400 lines

---

#### 5. `/plan:generate-spec` (Existing - Major Refactor)
**Purpose**: Generate detailed step-by-step implementation spec

**Current**: 1,126 lines 🚨
**Target**: ~400 lines

**Changes**:
- Check for state:strategy-approved label (via task-patterns skill)
- Read approved strategy comment from Linear
- Use strategy to guide spec generation
- Extract bash to libraries
- Move spec templates to separate files
- Delegate file operations to skills
- Commit spec via git-workflow skill

**Workflow**:
1. Fetch issue from Linear (via task-patterns skill)
2. Verify state:strategy-approved label exists
3. Read approved strategy comment
4. Analyze codebase patterns (via pattern-stack-architect skill)
5. Generate detailed spec using strategy as guide
6. Save spec to appropriate location (based on stack label)
7. Commit spec: `docs(specs): add detailed implementation spec for ${ISSUE_ID}`
8. Update Linear with spec location (via task-patterns skill)

**Output**: `specs/issue-{ISSUE_ID}-{name}.md`

**State Transition**: Refinement (approved) → Ready

**Size**: ~400 lines (64% reduction)

---

#### 6. `/implement` (Existing - Enhance)
**Purpose**: Execute detailed spec with quality gates

**Current**: 287 lines (already lean ✅)

**Changes**: 
- Check for state:strategy-approved before proceeding
- Auto-run /plan:generate-spec if spec missing
- Delegate git operations to git-workflow skill
- Use conventions from .env
- Commit at EVERY step (via git-workflow skill)

**Workflow**:
1. Fetch issue from Linear (via task-patterns skill)
2. Verify state:strategy-approved label exists
3. Find or generate spec
4. Detect TDD mode from labels
5. Create feature branch (via git-workflow skill)
6. Implement following spec
   - Commit after each logical change
   - Commit format: determined by file type and layer
7. Run quality gates (via quality-gates skill)
8. Create PR (via git-workflow skill)
9. Update Linear status (via task-patterns skill)

**Commit Pattern During Implementation**:
```bash
# Example commits for DEAL-5:
feat(atoms/security): add JWT utilities (DEAL-5)
test(atoms/security): add JWT utility tests (DEAL-5)
feat(features/users): add login/register methods (DEAL-5)
test(features/users): add user service tests (DEAL-5)
feat(molecules/apis): add auth permission facade (DEAL-5)
feat(organisms/api): add auth endpoints (DEAL-5)
test(organisms/api): add auth endpoint tests (DEAL-5)
```

**Output**: Feature branch + PR

**State Transition**: Ready → In Progress → In Review

**Size**: Keep at ~300 lines

---

#### 7. `/implement-epic` (NEW - Epic Orchestrator)
**Purpose**: Implement entire epic autonomously with human gates

**Workflow**:
1. Fetch epic + all children from Linear (via task-patterns skill)
2. For each child issue:
   a. Run `/analyze-implementation`
   b. Post strategy to Linear
3. PAUSE: Report all strategies posted, wait for approvals
4. Check for state:strategy-approved labels (via task-patterns skill)
5. For each approved child:
   a. Run `/plan:generate-spec`
   b. Run `/implement`
   c. Update Linear status
6. Create single PR for entire epic (via git-workflow skill)
7. Report summary

**Human Gates**:
- After all strategies posted: Batch review in Linear
- Add state:strategy-approved label to each approved issue
- Agent checks for labels before continuing
- Async workflow: Review strategies in morning, implementations run all day

**Output**: PR with all epic changes

**Size**: ~400-500 lines

**Note**: Uses BATCH strategy approval (Option B)

---

#### 8. `/test` (Existing - Cleanup)
**Purpose**: Run all quality gates with auto-fix loop

**Current**: 354 lines
**Target**: ~200 lines

**Changes**:
- Read gate commands from .env/config
- Delegate execution to quality-gates skill
- Simplify retry logic
- Commit fixes via git-workflow skill

**Workflow**:
1. Detect stack (backend/frontend) from current directory or .env
2. Run format (auto-fix)
3. Commit if changes: `style: auto-format code`
4. Run lint (auto-fix if possible)
5. Commit if changes: `style: auto-fix lint issues`
6. Run typecheck (report errors)
7. Run tests (report failures)
8. Loop on failures (max 3 attempts)

**Output**: Pass/fail status

---

#### 9. `/commit` (Existing - Keep as Primitive)
**Purpose**: Create atomic commit with conventional format

**Current**: ~50 lines (in git/ subdirectory)
**Keep as-is**: Used by both humans and git-workflow skill

**Workflow**:
1. Read conventions from .env
2. Format commit message per convention
3. Create commit

**Note**: This is a primitive command. Both humans and the git-workflow skill call it.

---

#### 10. `/pr` (Existing - Enhance)
**Purpose**: Create PR with Linear integration

**Current**: ~326 lines (in git/ subdirectory)

**Changes**: 
- Read strategy comment from Linear
- Read spec file
- Include both in PR description
- Read conventions from .env

**Workflow**:
1. Fetch issue details from Linear (via task-patterns skill)
2. Read strategy comment
3. Read spec file
4. Generate PR description including both
5. Create PR (via gh CLI)
6. Link Linear issue to PR

**Note**: This is a primitive command. Both humans and git-workflow skill call it.

---

### Supporting Files

#### `.claude/config/conventions.md`
```markdown
# Project Conventions

These conventions are referenced by commands and can be overridden in `.env`.

## Commit Format
**Type**: Conventional Commits
**Format**: `{type}({scope}): {description} ({ISSUE-ID})`

**Types**: 
- feat: New feature
- fix: Bug fix
- docs: Documentation changes
- style: Formatting, missing semi colons, etc
- refactor: Code change that neither fixes a bug nor adds a feature
- test: Adding tests
- chore: Maintain

**Override in .env**: `COMMIT_FORMAT=conventional`

## Branch Naming
**Epic**: `feature/{ISSUE-ID}-{epic-name}`
**Feature**: `feature/{ISSUE-ID}-{feature-name}`
**Bug**: `fix/{ISSUE-ID}-{bug-name}`
**Chore**: `chore/{ISSUE-ID}-{chore-name}`

**Override in .env**: 
```bash
BRANCH_PREFIX_EPIC=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
```

## PR Format
**Title**: `{Issue Title} ({ISSUE-ID})`
**Body**: Auto-generated from strategy + spec

## Linear Labels
**Required**: Every issue must have:
- One structural label: `issue`, `subissue`, or `epic`
- One `stack:*` label
- One or more `work:*` labels
- One or more `layer:*` labels (if stack:backend)

## Spec Location
**Backend**: `application/backend/specs/`
**Frontend**: `application/frontend/specs/`
**Fullstack**: `specs/` (project root)

**Override in .env**: `SPEC_DIR=custom/path/`
```

---

## Phase 2: Skill Enhancement (Build - 2-3 hours)

### Skills to Create/Enhance

#### 1. `task-patterns` Skill (Enhance Existing)
**Add to existing skill**:
- `get_issue(issue_id)` - Fetch issue from Linear
- `get_epic_children(epic_id)` - Fetch all children of an epic
- `check_label(issue_id, label)` - Check if issue has specific label
- `add_label(issue_id, label)` - Add label to Linear issue
- `post_comment(issue_id, content)` - Post comment to Linear
- `update_status(issue_id, status)` - Update Linear issue state

**Purpose**: Centralize all Linear API interactions

---

#### 2. `quality-gates` Skill (NEW)
**Purpose**: Centralize quality gate execution

**Functions**:
- `detect_stack()` - Determine backend/frontend/fullstack from .env or directory
- `run_format()` - Auto-format code, return if changes made
- `run_lint()` - Lint with auto-fix, return if changes made
- `run_typecheck()` - Type checking, return errors
- `run_tests()` - Test suite with coverage, return results
- `run_all()` - Run all gates in sequence

**Note**: Does NOT commit - calling command uses git-workflow skill to commit fixes

---

#### 3. `git-workflow` Skill (NEW - CRITICAL)
**Purpose**: Ensure 100% commit consistency

**Functions**:
- `create_feature_branch(issue_id, branch_type)` - Create branch following conventions from .env
- `commit_changes(type, scope, message, issue_id)` - Calls `/commit` with conventions
- `create_pr(issue_id, title, body)` - Calls `/pr` command
- `ensure_clean_state()` - Check for uncommitted changes

**Key Responsibility**: This skill is the ONLY way commands commit changes. It ensures:
- All commits follow project conventions
- All commits are atomic
- All commits reference issue IDs
- Consistency across all workflows

**Usage Pattern**:
```python
# In any command that modifies files:
from skills.git_workflow import commit_changes

# After creating spec:
commit_changes("docs", "specs", f"add implementation spec for {issue_id}", issue_id)

# After implementing feature:
commit_changes("feat", "atoms/security", "add JWT utilities", issue_id)

# After writing tests:
commit_changes("test", "atoms/security", "add JWT utility tests", issue_id)
```

---

#### 4. `pattern-stack-architect` Skill (Enhance Existing)
**Add**:
- `analyze_architecture(issue_id, codebase_path)` - Identify affected layers/files
- `suggest_patterns(issue_description)` - Recommend Pattern Stack patterns
- `validate_dependencies(file_path)` - Check layer dependency rules

---

### Skill → Command Relationship

**Commands are primitives** (user-facing tools):
- `/commit` - Can be called by humans or skills
- `/pr` - Can be called by humans or skills

**Skills are orchestrators** (automation layer):
- `git-workflow` skill calls `/commit` and `/pr`
- `task-patterns` skill calls `tp` CLI
- `quality-gates` skill calls gate commands
- `pattern-stack-architect` skill analyzes code

**Result**: 
- Humans can still use commands directly
- Workflows guarantee consistency via skills
- Separation of concerns maintained

---

## Phase 3: Testing (1-2 hours)

### Test Epic Creation

**Create test epic manually in Linear**:
- Epic (DEAL-1): "Test Epic: User Authentication"
- Add label: `epic`
- Create 3 sub-issues:
  - DEAL-2: "Create JWT utilities" (label: `subissue`)
  - DEAL-3: "Add user login endpoint" (label: `subissue`)
  - DEAL-4: "Add user register endpoint" (label: `subissue`)
- Each with product requirements only (no implementation details)
- Link sub-issues to epic

### Test Workflow End-to-End

```bash
# 1. Test strategy generation
/analyze-implementation DEAL-2

# Verify:
# - Strategy comment posted to Linear ✅
# - Comment has proper format ✅
# - Label state:awaiting-strategy-review added ✅
# - Strategy doc committed to branch ✅

# 2. Approve strategy in Linear
# - Review comment
# - Add label: state:strategy-approved
# - Leave in Refinement state

# 3. Test spec generation
/plan:generate-spec DEAL-2

# Verify:
# - Checks for state:strategy-approved label ✅
# - Spec file created ✅
# - Spec uses strategy as guide ✅
# - Spec committed to branch ✅
# - Linear updated with spec location ✅

# 4. Move to Ready in Linear

# 5. Test implementation
/implement DEAL-2

# Verify:
# - Checks for state:strategy-approved ✅
# - Feature branch created ✅
# - Code follows spec ✅
# - Multiple atomic commits created ✅
# - All commits follow convention ✅
# - Quality gates pass ✅
# - PR created ✅
# - Linear updated to In Review ✅

# 6. Test epic orchestration
/implement-epic DEAL-1

# Verify:
# - All children analyzed ✅
# - All strategies posted to Linear ✅
# - Reports and waits for approvals ✅
# - Implements each after label added ✅
# - Single PR for epic ✅
# - All commits follow convention ✅
```

---

## Phase 4: Bootstrap Documentation (30 min)

### Update CLAUDE.md

Add workflow state machine diagram, command mapping, and commit consistency rules.

### Create WORKFLOW.md

Complete guide to the autonomous development process:
- State transitions
- Human gate points (strategy approval, PR review)
- Command usage examples
- Commit patterns
- Troubleshooting

### Create CONVENTIONS.md

Document all project conventions:
- Commit format and types
- Branch naming patterns
- Label taxonomy
- PR format
- Spec locations

---

## Success Criteria

**After Phase 4, you should be able to**:

1. ✅ Drop raw idea in Linear (Triage)
2. ✅ Run `/refine-idea` to create product requirements
3. ✅ Run `/plan:decompose` + `/plan:create-issues`
4. ✅ Run `/implement-epic DEAL-1`
5. ✅ Agent generates ALL strategies, posts to Linear
6. ✅ You batch-review/approve strategies (add state:strategy-approved labels)
7. ✅ Agent generates specs, implements, creates PRs
8. ✅ ALL changes committed with consistent format
9. ✅ You review PRs, merge
10. ✅ Epic complete, shipped! 🚀

**AFK Time**: ~80% (only review strategies + PRs)

**Human Touchpoints**: 2 only
- Strategy approval (batch review in Linear)
- PR review (code review in GitHub)

**Commit Consistency**: 100% via git-workflow skill

---

## Rollout Plan

### Weekend (This Weekend)
- Phase 0: Manual setup (30 min)
- Phase 1: Build commands (4-6 hours)
- Phase 2: Build/enhance skills (2-3 hours)
- Phase 3: End-to-end testing (1-2 hours)

### Week 1 (Real Usage)
- Create backend foundation epic in Linear
- Use workflow for real implementation
- Document pain points and rough edges
- Refine based on learnings

### Week 2 (Optimize)
- Complete remaining cleanup (TEMPO-33)
- Add webhook automation
- Polish rough edges discovered in Week 1

### Month 2 (Scale)
- Full Linear webhook integration
- True AFK: approve in morning, PRs by afternoon
- Extract as reusable bootstrap for new projects

---

## Decisions Made (Open Questions Resolved)

### Q1: Command Naming Convention
**Decision**: Keep namespaced, remove numbers
- `/plan:decompose` (not `/plan:1-decompose`)
- `/plan:create-issues` (not `/plan:2-create-issues`)
- `/plan:generate-spec` (not `/plan:3-generate-spec`)

### Q2: Epic Orchestration Behavior
**Decision**: Option B - Batch strategy approval
- Generate ALL strategies first
- Post all to Linear at once
- Wait for human to batch-review
- Implement all approved issues
- Better for async review

### Q3: Strategy Approval Mechanism
**Decision**: Option B - Linear label
- Check for label: `state:strategy-approved`
- Human adds label when ready
- Clean, explicit, no ambiguity

### Q4: Convention Configuration Location
**Decision**: Option C - Both
- `.env` for project-specific values
- `.claude/config/conventions.md` for defaults + docs
- .env overrides conventions.md

### Q5: Label Taxonomy
**Decision**: Simplified structure
- `issue` - Regular standalone issue
- `subissue` - Child of an epic
- `epic` - Parent container

### Q6: Commit Commands vs Skills
**Decision**: Keep both
- `/commit` and `/pr` remain as primitive commands
- `git-workflow` skill wraps them for automation
- Humans can still call commands directly
- Skills ensure consistency

---

## Critical Implementation Notes

### Commit Consistency is Non-Negotiable

**Rule**: EVERY file change gets committed via git-workflow skill or `/commit`

**Includes**:
- Creating specs → `docs(specs): add implementation spec`
- Implementing code → `feat(scope): add feature`
- Writing tests → `test(scope): add tests`
- Auto-formatting → `style: auto-format code`
- Refactoring → `refactor(scope): improve structure`

**Enforcement**:
- All commands delegate commits to git-workflow skill
- git-workflow skill is the ONLY commit pathway
- Skill internally calls `/commit` with correct conventions
- Result: 100% consistency guaranteed

### Spec → Implementation Pattern

```bash
# On feature branch feature/DEAL-5-user-auth:

# Commit 1: Create spec FIRST
docs(specs): add implementation spec for user auth (DEAL-5)

# Commit 2-N: Implement following spec
feat(atoms/security): add JWT utilities (DEAL-5)
test(atoms/security): add JWT utility tests (DEAL-5)
feat(features/users): add login/register methods (DEAL-5)
test(features/users): add user service tests (DEAL-5)
...

# Result: Spec commit shows in PR first, then implementation
# Clear traceability: spec → implementation
```

---

## Next Immediate Steps

1. **Save this updated plan** ✅ (already done)
2. **Set up project config** - Create `.env` with your values
3. **Start Phase 1** - Build `/analyze-implementation` first
4. **Test immediately** - Create dummy issue, test strategy generation
5. **Iterate** - Refine based on real usage
6. **Continue** - Build remaining commands
7. **Ship** - Copy to fresh dealbrain repo
8. **Use** - Build real backend foundation with workflow

**Estimated Total Time**: 8-12 hours (over 2-3 days)

**ROI**: Infinite - this workflow builds itself, then builds everything else 🚀

---

## Architecture Diagram

```
┌─────────────┐
│   Triage    │ Raw ideas
└──────┬──────┘
       │ /refine-idea (optional)
       ↓
┌─────────────┐
│  Ideation   │ AI-assisted refinement
└──────┬──────┘
       │ /plan:decompose + /plan:create-issues
       ↓
┌─────────────┐
│   Backlog   │ Complete issues (epic/issue/subissue)
└──────┬──────┘
       │ /analyze-implementation
       ↓
┌─────────────┐
│ Refinement  │ Strategy posted
└──────┬──────┘   HUMAN GATE: Add state:strategy-approved ⚠️
       │
       ↓
┌─────────────┐
│    Ready    │ Spec generated
└──────┬──────┘
       │ /implement (or /implement-epic)
       ↓
┌─────────────┐
│ In Progress │ Code being written (atomic commits)
└──────┬──────┘
       │ Auto: PR created
       ↓
┌─────────────┐
│  In Review  │ HUMAN GATE: Review PR ⚠️
└──────┬──────┘
       │ Merge
       ↓
┌─────────────┐
│    Done     │ Shipped! 🎉
└─────────────┘
```

---

## File Structure After Bootstrap

```
dealbrain/
├── .env                           # Your project config
├── .env.example                   # Template
├── .gitignore
├── BOOTSTRAP-PLAN.md              # This file
├── CLAUDE.md                      # Project guide
├── WORKFLOW.md                    # User guide
├── README.md
├── .tp/
│   └── config.json                # Linear integration
├── .claude/
│   ├── commands/
│   │   ├── refine-idea.md
│   │   ├── plan/
│   │   │   ├── decompose.md       # Cleaned up
│   │   │   ├── create-issues.md   # Cleaned up
│   │   │   └── generate-spec.md   # Major refactor
│   │   ├── analyze-implementation.md  # NEW
│   │   ├── implement.md           # Enhanced
│   │   ├── implement-epic.md      # NEW
│   │   ├── test.md                # Cleaned up
│   │   └── git/
│   │       ├── commit.md          # Keep as primitive
│   │       └── pr.md              # Enhanced
│   ├── config/
│   │   └── conventions.md         # Project conventions
│   └── skills/
│       ├── task-patterns/         # Enhanced
│       ├── quality-gates/         # NEW
│       ├── git-workflow/          # NEW
│       └── pattern-stack-architect/  # Enhanced
├── application/
│   ├── backend/
│   │   └── specs/                 # Implementation specs
│   └── frontend/
│       └── specs/                 # Implementation specs
└── specs/                         # Fullstack specs
```

