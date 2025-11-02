# Claude Code Commands

**Complete workflow system for AI-assisted development with Linear integration, session logging, and quality gates.**

---

## 🚀 Quick Start (Most Common Workflows)

### 1. Plan & Decompose
```bash
/plan "Add Redis caching to user service"
```
**What it does:**
- Analyzes requirements with interactive Q&A
- Decomposes into atomic issues with labels
- Generates structured YAML definition
- **Stops here** - doesn't create issues yet

**Output**: `issue-plan-redis-caching.yaml` (review before creating issues!)

**Why it stops**: Each phase runs in NEW context window for full session logging

---

### 2. Create Linear Issues
```bash
/create-issues issue-plan-redis-caching.yaml
```
**What it does:**
- Creates epic + all sub-issues in Linear
- Links children to epic
- Applies labels from YAML
- Sets status to Refinement
- Returns: `{epic: "BE-100", children: ["BE-101", ...]}`

**Output**: Linear issues in Refinement status (ready for spec generation)

---

### 3. Generate Detailed Spec
```bash
/feature BE-101
```
**What it does:**
- Deep codebase research (10-15 minutes)
- Identifies patterns and similar implementations
- Generates comprehensive implementation plan
- Updates Linear issue to Ready status
- Creates `specs/issue-BE-101-{description}.md`

**When to use**: After `/create-issues` creates issues in Linear

---

### 4. Implement with TDD
```bash
/implement BE-101
```
**What it does:**
- Ensures on feature branch (creates if needed)
- Reads spec from `specs/` directory
- Follows TDD workflow (tests first)
- Runs quality gates (format, lint, typecheck)
- Commits incrementally with proper messages

**Branch safety**: Automatically checks out/creates feature branch before committing

---

### 5. Run Quality Gates
```bash
/test
```
**What it does:**
- Runs format, lint, typecheck, architecture validation
- Runs full test suite
- Auto-fixes issues when possible
- Loops until all gates pass

---

### 6. Create Pull Request
```bash
/pr BE-101
```
**What it does:**
- Creates GitHub PR with comprehensive summary
- Links to Linear issue
- Includes test plan and changes
- Adds traceability (session logs, commit history)

---

### 7. Setup Linear Team
```bash
/setup-linear-team
```
**What it does:**
- Interactive guide for creating new Linear team
- Walks through team creation, workflow states, labels
- Executes setup commands on your behalf
- Configures tp CLI integration

**When to use**: Setting up a new project with autonomous workflow

---

## 📁 Folder Structure

```
.claude/commands/
├── plan.md                    # 🎯 Primary: Decompose requirements
├── implement.md               # 🎯 Primary: TDD implementation
├── test.md                    # 🎯 Primary: Quality gates
├── setup-linear-team.md       # 🎯 Setup: New Linear team
│
├── spec-generation/           # 📦 Subsystem: Spec generation
│   ├── feature.md             #    /feature - Feature specs (use this!)
│   ├── generate-spec.md       #    Engine (called by wrappers)
│   └── [future: bug.md, chore.md, patch.md]
│
├── utilities/                 # 🔧 Reusable utilities
│   └── ensure-feature-branch.md  # Branch safety (called by /implement)
│
├── shared/                    # 📚 Shared patterns
│   └── session-logging.md     # Session management framework
│
├── issues/                    # 📋 Issue management
│   └── create-issues.md       # Issue creation (called by /plan)
│
└── [other subsystems...]
```

---

## 🔄 Complete Workflow Example

**IMPORTANT**: Run each step in a NEW context window for full session logging!

```bash
# 1. Decompose requirements (NEW context)
/plan "Add batch update operations to tp CLI"
# → Interactive Q&A
# → Generates: issue-plan-batch-operations.yaml
# → STOPS here

# 2. Review YAML
cat issue-plan-batch-operations.yaml
# → Review epic + sub-issues structure
# → Edit if needed

# 3. Create Linear issues (NEW context)
/create-issues issue-plan-batch-operations.yaml
# → Creates TASK-23 (epic) + TASK-24..28 (children)
# → Returns: {epic: "TASK-23", children: ["TASK-24", ...]}

# 4. Generate spec for each issue (NEW context for each)
/feature TASK-24  # Sub-issue 1
/feature TASK-25  # Sub-issue 2
# → Each runs deep research
# → Each creates detailed spec
# → Each has own session log

# 5. Implement (NEW context)
/implement TASK-24
# → Ensures on feature/TASK-23-batch-operations branch
# → TDD workflow
# → Quality gates
# → Commits

# 6. Test (NEW context)
/test

# 7. Create PR (NEW context)
/pr TASK-24
# → Full traceability across all sessions
```

**Why separate contexts?**
- Complete session logging for each phase
- Full observability: `agent-logs/` has session for each step
- Can pause/resume workflow at any point
- Clear separation of concerns

---

## 🎨 Workflow Philosophy

### Read-Only Workflows (No Commits)
These stay on your current branch (typically `main`):
- **`/plan`** - Generates YAML definition only (no Linear calls)
- **`/create-issues`** - Creates Linear issues from YAML (no local files)
- **`/feature`** - Writes spec files (not committed yet)
- **`/generate-spec`** - Advanced spec generation (use `/feature` instead)

**Why?** You can review each output before the next step

### Commit-Making Workflows (Branch Required)
These ensure you're on a feature branch:
- **`/implement`** - Writes code + commits → calls `/ensure-feature-branch`
- **`/pr`** - Creates PR (assumes feature branch exists)

**Safety**: Branch protection + `/ensure-feature-branch` prevents accidental main commits

---

## 📦 Subsystems Explained

### Spec Generation (`spec-generation/`)

**Use `/feature` for features** (most common):
```bash
/feature BE-101
# → Calls /generate-spec with type=feature
# → Deep research, comprehensive phases, extensive testing
```

**Future wrappers**:
- `/bug BE-102` → Focused on reproduction + fix
- `/chore BE-103` → Lightweight, minimal testing
- `/patch BE-104` → Quick targeted fixes

**Advanced**: Call `/generate-spec` directly for custom behavior:
```bash
/generate-spec BE-101 --type=feature --session-id=abc123
```

**When to use wrappers vs engine:**
- ✅ Use `/feature` (recommended) - Optimized UX for features
- ⚠️ Use `/generate-spec` (advanced) - Full control, custom types

---

## 🔧 Utilities Explained

### Branch Safety (`git/ensure-feature-branch`)

**Purpose**: Prevents commits to `main` branch

**Called by**: `/implement`, `/fix`, any commit-making workflow

**Behavior**:
- ✅ If on feature branch → proceed
- ❌ If on main/master → error with helpful guidance
- 🔄 With `--auto-create` → automatically checkout/create feature branch

**Example** (called internally by `/implement`):
```bash
/ensure-feature-branch BE-101 --auto-create
# → Finds existing feature/TASK-23-* (epic branch)
# → Or creates feature/BE-101-cache-abstraction
# → Then proceeds with implementation
```

---

## 📊 Session Logging

Every workflow execution creates a session log for full observability:

```
agent-logs/
└── 2025-10-28_generate-spec_be-101_a7f3b2/
    ├── session.json           # Metadata
    ├── 00-request.md          # User request
    ├── 01-fetch-issue.md      # Issue context
    ├── 02-research.md         # Codebase research
    ├── 03-generate-spec.md    # Spec generation
    ├── 04-update-linear.md    # Linear updates
    └── summary.md             # Final summary
```

**Three invocation modes:**
1. **Subagent** - Write into parent's session directory
2. **Linked Standalone** - New session linked to parent
3. **Pure Standalone** - Independent session

See `shared/session-logging.md` for details.

---

## 🎯 Command Guidelines

### When to Use Each Command

| Situation | Command | Notes |
|-----------|---------|-------|
| Starting new work | `/plan "feature description"` | Creates issues + specs |
| Issue needs detailed spec | `/feature ISSUE-ID` | Deep research + spec |
| Ready to code | `/implement ISSUE-ID` | TDD workflow |
| Check quality | `/test` | Run all gates |
| Ready for review | `/pr ISSUE-ID` | Create GitHub PR |

### Flags You Should Know

**`--auto-create`** (implement, ensure-feature-branch):
```bash
/implement BE-101 --auto-create
# Automatically creates/checks out feature branch
```

**`--session-id`** (generate-spec, plan):
```bash
/generate-spec BE-101 --session-id=abc123
# Links this session to parent planning session
```

**`--type`** (generate-spec):
```bash
/generate-spec BE-101 --type=bug
# Adjusts research depth and spec structure
```

---

## 🔮 Future Subsystems

Planned additions to the command structure:

```
.claude/commands/
├── code-review/              # Multi-agent code review
│   ├── security.md
│   ├── architecture.md
│   └── performance.md
│
├── deployment/               # Deployment workflows
│   ├── staging.md
│   └── production.md
│
└── testing/                  # Advanced testing
    ├── integration.md
    └── e2e.md
```

---

## 💡 Pro Tips

### 1. Batch Spec Generation
```bash
# After /plan creates issues
for issue in BE-101 BE-102 BE-103; do
  /feature $issue
done
```

### 2. Session Chaining
```bash
# Plan creates session abc123
/plan "Add caching"
# → session_id: abc123

# Link spec generation to planning
/feature BE-101 --session-id=abc123
# → Creates new session, linked to abc123

# Full workflow chain in session logs!
```

### 3. Review Before Committing
```bash
# Generate specs on main (no commits)
/plan "Add feature"
/feature BE-101

# Review the spec
cat specs/issue-BE-101-feature-name.md

# Then implement (creates branch + commits)
/implement BE-101
```

---

## 🐛 Troubleshooting

### "Cannot commit on protected branch: main"
✅ **Solution**: Use `/implement` with `--auto-create`:
```bash
/implement BE-101 --auto-create
```

### "Issue must be in Refinement status"
✅ **Solution**: Update issue status first:
```bash
tp update BE-101 --status "Refinement"
/feature BE-101
```

### "No spec found for issue"
✅ **Solution**: Generate spec first:
```bash
/feature BE-101  # Generates spec
/implement BE-101  # Now can implement
```

---

## 📚 Additional Resources

- **Session Logging**: `shared/session-logging.md` - Deep dive on observability
- **Project Config**: `.claude/config/project-config.md` - Project-specific settings
- **Architecture**: `CLAUDE.md` - Pattern Stack conventions

---

## ✨ Summary

**Primary workflows** (top-level):
- `/setup-linear-team` → Setup new Linear team (first-time setup)
- `/plan` → Decompose requirements
- `/feature` → Generate specs (use this, not /generate-spec!)
- `/implement` → Write code with TDD
- `/test` → Quality gates
- `/pr` → Create pull request

**Organized by subsystem** for clarity without clutter.

**Safe by default** with branch protection and session logging.

Happy coding! 🚀
