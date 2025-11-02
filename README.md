# Claude Code Patterns: Autonomous Development Workflow

**Reusable template for AI-assisted development with human-in-the-loop gates**

This repository contains a production-ready workflow architecture for building software autonomously using Claude Code, with strategic human review gates.

## 🎯 What This Provides

- **Autonomous Development Workflow**: AI generates strategies → human approves → AI implements
- **100% Commit Consistency**: All commits follow conventions via git-workflow skill
- **Linear Integration**: Full issue tracking with state machine workflow
- **Quality Gates**: Automated format, lint, typecheck, test validation
- **AFK Development**: ~80% hands-off time (only review strategies + PRs)

## 📊 Workflow Architecture

```
Triage → Ideation → Backlog → Refinement (HUMAN GATE) → Ready → In Progress → In Review (HUMAN GATE) → Done
```

**Two Human Gates**:
1. **Strategy Approval** (5-10 min) - Review implementation approach in Linear
2. **PR Review** (10-30 min) - Review code quality in GitHub

Everything else: **Automated** 🤖

## 🚀 Quick Start

### 1. Copy Template to Your Project

```bash
# Clone this template
git clone https://github.com/pattern-stack/claudecode-patterns.git
cd claudecode-patterns

# Copy to your project
cp -r .claude /path/to/your/project/
cp BOOTSTRAP-PLAN.md /path/to/your/project/
cp WORKFLOW.md /path/to/your/project/
cp .env.example /path/to/your/project/
```

### 2. Configure Your Project

```bash
cd /path/to/your/project
cp .env.example .env

# Edit .env with your values:
# - PROJECT_NAME (e.g., "myapp")
# - PROJECT_TEAM_KEY (e.g., "MYAPP")
# - GITHUB_ORG, GITHUB_REPO
# - LINEAR_API_KEY (optional if set globally)
```

### 3. Set Up Linear

Create Linear project with:
- **Team key**: Your PROJECT_TEAM_KEY
- **Workflow states**: Triage, Ideation, Backlog, Refinement, Ready, In Progress, In Review, Done
- **Labels**: See `.claude/config/conventions.md` for complete taxonomy

### 4. Use the Workflow

```bash
# 1. Decompose requirement into issues
/plan:decompose "Add user authentication"

# 2. Create Linear issues
/plan:create-issues issue-plan-user-auth.yaml

# 3. Generate implementation strategies
/analyze-implementation MYAPP-1
/analyze-implementation MYAPP-2

# 4. Review strategies in Linear, add state:strategy-approved label

# 5. Implement approved issues
/implement MYAPP-1
/implement MYAPP-2

# 6. Review PRs in GitHub, merge

# Done! 🎉
```

## 📁 What's Included

### Commands (`.claude/commands/`)

| Command | Purpose | Output |
|---------|---------|--------|
| `/plan:decompose` | Break requirements into epic + issues | YAML plan |
| `/plan:create-issues` | Create Linear issues from YAML | Issue IDs |
| `/analyze-implementation` | Generate strategy for human review | Strategy comment in Linear |
| `/plan:generate-spec` | Generate detailed implementation spec | Spec file |
| `/implement` | Execute spec with TDD support | Feature branch + PR |
| `/test` | Run quality gates with auto-fix | Pass/fail status |
| `/git:commit` | Atomic commit with conventions | Git commit |
| `/git:pr` | Create PR with Linear integration | GitHub PR |

### Skills (`.claude/skills/`)

| Skill | Purpose |
|-------|---------|
| `git-workflow` | 100% commit consistency, branch management |
| `quality-gates` | Format, lint, typecheck, test automation |
| `task-patterns` | Linear API operations (tp CLI wrapper) |
| `pattern-stack-architect` | Codebase analysis, architecture guidance |

### Documentation

- **BOOTSTRAP-PLAN.md**: Complete project setup guide (1,034 lines)
- **WORKFLOW.md**: Day-to-day usage guide (1,443 lines)
- **conventions.md**: Commit format, labels, workflow states (791 lines)

## 🏗️ Architecture Principles

### 1. Clean Command Structure
```markdown
## Purpose
What the command does

## Variables
Input parameters

## Workflow
High-level steps

## Instructions
Detailed implementation (delegates to skills)

## Report
Output format
```

### 2. Skill Delegation
```markdown
# ❌ Bad (embedded bash)
Run: git commit -m "feat: add feature"

# ✅ Good (delegate to skill)
Use git-workflow skill to commit changes
```

### 3. Convention Abstraction
```markdown
# ❌ Bad (hardcoded)
Format: feat(scope): description (PROJ-123)

# ✅ Good (from .env)
Use COMMIT_FORMAT from project configuration
```

### 4. 100% Commit Consistency
Every file change committed via git-workflow skill → guarantees conventional commits

## 🎨 Customization

### Update Team Name
Edit `.env`:
```bash
PROJECT_TEAM_KEY=YOUR_TEAM
```

Issues will be: YOUR_TEAM-1, YOUR_TEAM-2, etc.

### Update Conventions
Edit `.claude/config/conventions.md`:
- Commit format
- Branch naming
- Label taxonomy
- Workflow states

Override in `.env` if needed.

### Add Custom Commands
Create new command in `.claude/commands/`:
```markdown
# my-command.md

## Purpose
...

## Instructions
- Use git-workflow skill for commits
- Use task-patterns skill for Linear
- Use quality-gates skill for validation
```

## 📊 Production Readiness

**Validated**: 8.2/10 (82% complete)

✅ **Ready for production use**:
- End-to-end workflow tested
- Zero crashes predicted
- Full Linear integration
- Git commit consistency
- Quality gates automated
- Documentation complete

⏸️ **Optional enhancements** (not blocking):
- `/implement-epic` - Batch epic implementation
- `/refine-idea` - Interactive requirement refinement

## 🤝 Contributing

This is a template repository. Fork it, customize it, make it your own!

**Improvements welcome**:
- Additional skills
- New commands
- Better documentation
- Bug fixes

## 📜 License

MIT - Use freely in your projects

## 🙏 Credits

Built for autonomous development with Claude Code by the Pattern Stack team.

**Based on**:
- Claude Code by Anthropic
- Pattern Stack framework
- Linear for issue tracking
- Conventional Commits standard

---

**Questions?** Check WORKFLOW.md for detailed usage guide or BOOTSTRAP-PLAN.md for setup instructions.
