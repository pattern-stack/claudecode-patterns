# Linear Team Setup Guide

Complete guide for setting up a new Linear team for autonomous development workflow.

## Overview

This guide walks through creating a new Linear team (e.g., "DEAL" for DealBrain) with the full workflow state machine, labels, and tp CLI integration needed for the autonomous development workflow described in BOOTSTRAP-PLAN.md.

**Time Required**: ~30 minutes
**Prerequisites**: Linear workspace admin access, tp CLI installed and authenticated

---

## Phase 0: Linear Team Setup

### Step 1: Decide Your Configuration

Before starting, decide on these key values:

```bash
# Project Configuration
PROJECT_NAME="DealBrain"           # Full project name
TEAM_KEY="DEAL"                    # Short uppercase identifier (2-5 chars)
TEAM_NAME="DealBrain Development"  # Display name in Linear
```

**Team Key Guidelines:**
- Short and memorable (2-5 characters)
- All uppercase
- Matches your issue IDs (DEAL-1, DEAL-2, etc.)
- Examples: DEAL, TEMPO, BE, FE, CORE

---

### Step 2: Create Team

**Option A: Using tp CLI (Recommended)**

```bash
# Basic team creation
tp team create DEAL "DealBrain Development" \
  --description "DealBrain product development team" \
  --cycles \
  --cycle-duration 14 \
  --triage

# Or use a template
tp team apply-template engineering \
  --key DEAL \
  --name "DealBrain Development"
```

Available templates:
- `engineering` - Standard engineering team with sprints
- `support` - Customer support team with triage

After creation, get the Team ID:
```bash
tp team show DEAL
# Copy the Team ID (UUID) for .env configuration
```

**Option B: Using Linear Web UI**

If you prefer the Web UI:

1. Go to [Linear](https://linear.app) → Settings → Teams → "Create Team"
2. Configure:
   - Name: DealBrain Development
   - Key: DEAL
   - Icon & Color: Choose as desired
3. Copy Team ID from Team Settings

---

### Step 3: Configure Workflow States

In Linear Web UI (Settings → Teams → DEAL → Workflow):

**Option A: Full Workflow (from BOOTSTRAP-PLAN.md)**

Create these states in order:

1. **Triage** - Raw ideas, no structure required
2. **Ideation** - AI-assisted refinement (optional)
3. **Backlog** - Complete issues ready for development planning
4. **Refinement** - Implementation strategy proposed (⚠️ HUMAN GATE)
5. **Ready** - Detailed spec generated, ready to code
6. **In Progress** - Code being written
7. **In Review** - PR review (⚠️ HUMAN GATE)
8. **Done** - Shipped

**Option B: Minimal Workflow (recommended for starting)**

```
1. Backlog         - Issues ready for development
2. Refinement      - Strategy proposed (⚠️ HUMAN GATE)
3. Ready           - Spec generated, ready to implement
4. In Progress     - Code being written
5. In Review       - PR review (⚠️ HUMAN GATE)
6. Done            - Shipped
```

**State Configuration Tips:**
- Set **Backlog** as the default state for new issues
- Mark **Done** as "completed" state
- Mark **Canceled** as "canceled" state (if you add one)

---

### Step 4: Update Project Configuration Files

#### Update `.env`

```bash
# Copy template if you haven't already
cp .env.example .env

# Edit .env with your team details
```

Add/update these values in `.env`:

```bash
# Linear Integration
LINEAR_API_KEY=lin_api_xxxxx          # Get from Linear Settings → API
LINEAR_TEAM_ID=your-team-uuid-here    # From Step 2
LINEAR_ORG_ID=your-org-uuid           # Optional, for multi-workspace

# GitHub
GITHUB_ORG=your-github-org
GITHUB_REPO=dealbrain
GITHUB_BASE_BRANCH=main

# Project
PROJECT_NAME=DealBrain
PROJECT_TEAM_KEY=DEAL
PROJECT_STACK=fullstack

# Conventions
COMMIT_FORMAT=conventional
BRANCH_PREFIX_FEATURE=feature
BRANCH_PREFIX_BUG=fix
BRANCH_PREFIX_CHORE=chore
BRANCH_PREFIX_EPIC=feature
```

#### Update `.tp/config.json`

**Option A: Use tp CLI (Recommended)**

```bash
tp config teams DEAL
tp config set defaultTeam DEAL
```

**Option B: Edit manually**

```json
{
  "defaultTeam": "DEAL",
  "teamFilter": [
    "DEAL"
  ]
}
```

#### Verify Configuration

```bash
# Check tp is using the correct team
tp config show

# Test team access
tp team show DEAL
```

---

### Step 5: Create Labels

Labels are critical for the autonomous workflow. They enable:
- Issue classification (epic, subissue, issue)
- Stack routing (backend, frontend, fullstack)
- Workflow state tracking (awaiting-strategy-review, strategy-approved)
- Architecture layer identification (atoms, features, molecules, organisms)

#### Option A: Use Setup Script (Recommended)

```bash
# From project root
./.claude/scripts/setup-linear-labels.sh DEAL
```

This creates all labels from BOOTSTRAP-PLAN.md:
- Issue structure: `issue`, `subissue`, `epic`
- Issue types: `issue-type:bug`, `issue-type:chore`, `issue-type:documentation`
- Work types: `work:architecture`, `work:infrastructure`, `work:feature`, `work:enhancement`, `work:bugfix`
- Stack: `stack:backend`, `stack:frontend`, `stack:fullstack`
- Layers: `layer:atoms`, `layer:features`, `layer:molecules`, `layer:organisms`
- State: `state:awaiting-strategy-review`, `state:strategy-approved`, `state:blocked`, `state:needs-clarification`
- Priority: `priority:critical`, `priority:high`, `priority:medium`, `priority:low`

#### Option B: Use Label Template

```bash
# Check available templates
tp labels templates

# Apply template (if suitable for your workflow)
tp labels apply-template task-patterns --team DEAL
```

#### Option C: Manual Label Creation

See the script at `.claude/scripts/setup-linear-labels.sh` for individual label creation commands.

#### Verify Labels

```bash
# List all labels for your team
tp labels list --team DEAL

# View hierarchical structure
tp labels list --team DEAL --hierarchy

# Search for specific label
tp labels search "stack" --team DEAL
```

---

### Step 6: Set Up GitHub Integration

In Linear Web UI (Settings → Integrations → GitHub):

1. **Connect GitHub**:
   - Click "Add GitHub integration"
   - Authorize Linear for your GitHub org
   - Select repository: `your-org/dealbrain`

2. **Configure Integration**:
   - ✅ Enable bi-directional sync
   - ✅ Auto-close issues on PR merge
   - ✅ Create Linear issue from GitHub issue
   - ✅ Link GitHub PRs to Linear issues

3. **Branch Configuration** (optional):
   - Auto-create branches from Linear issues
   - Branch naming: `{issueKey}-{issueTitle}`
   - Example: `DEAL-123-add-user-authentication`

---

### Step 7: Configure Branch Protection (GitHub)

Protect your main branch to enforce PR workflow:

1. Go to GitHub repo → Settings → Branches
2. Add branch protection rule for `main`:
   - ✅ Require pull request before merging
   - ✅ Require approvals: 1 (or 0 for solo dev)
   - ✅ Dismiss stale approvals
   - ✅ Require status checks to pass (when CI added)
   - ✅ Restrict who can push to matching branches
   - ✅ Do not allow bypassing the above settings

**Result**: No more accidental commits directly to main ✅

---

### Step 8: Verify Complete Setup

Run these verification checks:

```bash
# 1. Verify tp configuration
tp config show
# Expected: defaultTeam: DEAL, teamFilter: [DEAL]

# 2. Check team access
tp team show DEAL
# Expected: Team details displayed

# 3. List labels
tp labels list --team DEAL
# Expected: All labels from Step 5

# 4. Test issue creation
tp add "Test issue - setup verification" --team DEAL
# Expected: DEAL-1 created

# 5. Verify issue was created
tp show DEAL-1
# Expected: Issue details displayed

# 6. Clean up test issue (optional)
tp update DEAL-1 --status "Canceled"
```

---

## Post-Setup: Initial Project Structure

### Create Seed Issues

Start with a project foundation epic:

```bash
# Create epic
tp add "Epic: Project Foundation and Setup"
# → Creates DEAL-1

# Add labels
tp update DEAL-1 --add-labels "epic,stack:fullstack,work:infrastructure"

# Create initial children
tp add "Set up project structure and configuration"  # → DEAL-2
tp add "Configure development environment"           # → DEAL-3
tp add "Set up CI/CD pipeline"                       # → DEAL-4

# Link children to epic
tp link-parent DEAL-2 DEAL-1
tp link-parent DEAL-3 DEAL-1
tp link-parent DEAL-4 DEAL-1

# Label children
for issue in DEAL-2 DEAL-3 DEAL-4; do
  tp update $issue --add-labels "subissue,stack:fullstack,work:infrastructure"
done
```

---

## Workflow Integration

### State Machine

Your workflow now follows this state machine:

```
┌─────────────┐
│   Backlog   │ Issues ready for development
└──────┬──────┘
       │ /analyze-implementation
       ↓
┌─────────────┐
│ Refinement  │ Strategy posted to Linear
└──────┬──────┘
       │ HUMAN GATE: Add state:strategy-approved ⚠️
       ↓
┌─────────────┐
│    Ready    │ Spec generated
└──────┬──────┘
       │ /implement
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
│    Done     │ Shipped!
└─────────────┘
```

### Command Integration

Your commands now work with the new team:

```bash
# Planning
/plan:decompose "Add user authentication system"
/plan:create-issues issue-plan-user-auth.yaml --team DEAL

# Strategy (NEW!)
/analyze-implementation DEAL-2

# Spec generation
/plan:generate-spec DEAL-2

# Implementation
/implement DEAL-2

# Git operations
/git:commit feat "atoms/security" "add JWT utilities" DEAL-2
/git:pr DEAL-2 "Add user authentication"
```

---

## Troubleshooting

### "Team not found"

```bash
# Check team key is correct
tp team list

# Verify configuration
tp config show
cat .tp/config.json
```

### "Label not found"

```bash
# Re-run label setup script
./.claude/scripts/setup-linear-labels.sh DEAL

# Or check existing labels
tp labels list --team DEAL
```

### "Cannot commit to protected branch"

This is expected! Use feature branches:
```bash
git checkout -b feature/DEAL-1-project-setup
# ... make changes ...
git add .
git commit -m "feat: initialize project structure (DEAL-1)"
git push -u origin feature/DEAL-1-project-setup
```

Then create PR via GitHub or `/git:pr` command.

### Environment Variables Not Loading

```bash
# Verify .env exists and has correct values
cat .env | grep TEAM_KEY

# Check .env is not committed (security)
git status .env
# Should show: nothing to commit (ignored)
```

---

## Next Steps

After completing this setup:

1. **Test the workflow**:
   - Create a test issue: `tp add "Test workflow" --team DEAL`
   - Run through planning → implementation → PR cycle
   - Verify all integrations work

2. **Create initial epic**:
   - Use `/plan:decompose` for your first real feature
   - Create issues with `/plan:create-issues`
   - Generate strategies with `/analyze-implementation`

3. **Start developing**:
   - Follow the workflow state machine
   - Use human gates at Refinement (strategy approval) and In Review (PR review)
   - Enjoy ~80% AFK time! 🚀

---

## Reference

### Required Labels per Issue

Every issue MUST have:
- **One structure label**: `issue`, `subissue`, or `epic`
- **One stack label**: `stack:backend`, `stack:frontend`, or `stack:fullstack`
- **One or more work labels**: `work:architecture`, `work:infrastructure`, `work:feature`, etc.
- **Layer labels** (if backend): `layer:atoms`, `layer:features`, `layer:molecules`, `layer:organisms`

### Label Taxonomy

See `.claude/config/conventions.md` for complete label reference.

### Configuration Files

- `.tp/config.json` - tp CLI team configuration
- `.env` - Project secrets and configuration (git-ignored)
- `.env.example` - Configuration template (committed)
- `.claude/config/conventions.md` - Project conventions

---

## Success Criteria

✅ Team created in Linear with correct workflow states
✅ Labels created and organized
✅ tp CLI configured for new team
✅ GitHub integration enabled
✅ Branch protection enabled
✅ Test issue created successfully
✅ Commands work with new team

**You're ready to build!** 🎉

---

**See Also**:
- `BOOTSTRAP-PLAN.md` - Complete bootstrap strategy
- `.claude/docs/agentic-workflow-architecture.md` - Workflow deep dive
- `.claude/skills/task-patterns/SKILL.md` - tp CLI reference
- `.claude/config/conventions.md` - Project conventions
