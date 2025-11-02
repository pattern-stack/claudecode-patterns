# Linear Team Setup Checklist

Quick reference checklist for setting up a new Linear team. See [LINEAR_TEAM_SETUP.md](./LINEAR_TEAM_SETUP.md) for detailed instructions.

---

## Pre-Setup Decisions

- [ ] **Project Name**: _________________ (e.g., "DealBrain")
- [ ] **Team Key**: _________________ (e.g., "DEAL" - 2-5 uppercase chars)
- [ ] **Team Name**: _________________ (e.g., "DealBrain Development")

---

## Step 1: Create Team

**Option A: Using tp CLI (Recommended)**

```bash
# Create team with cycles and triage
tp team create YOUR_KEY "Your Team Name" \
  --description "Your team description" \
  --cycles \
  --cycle-duration 14 \
  --triage

# OR use a template
tp team apply-template engineering --key YOUR_KEY --name "Your Team Name"

# Get Team ID
tp team show YOUR_KEY
```

- [ ] Team created via `tp team create` or `tp team apply-template`
- [ ] Team ID copied from `tp team show YOUR_KEY`

**Option B: Using Linear Web UI**

- [ ] Go to Linear → Settings → Teams → "Create Team"
- [ ] Enter Team Name: _________________
- [ ] Enter Team Key: _________________
- [ ] Copy Team ID (UUID): _________________

---

## Step 2: Configure Workflow States

In Linear → Settings → Teams → [YOUR_KEY] → Workflow:

**Minimal Workflow (Recommended):**
- [ ] 1. Backlog (set as default for new issues)
- [ ] 2. Refinement
- [ ] 3. Ready
- [ ] 4. In Progress
- [ ] 5. In Review
- [ ] 6. Done (mark as "completed")

**Optional states to add:**
- [ ] Triage (before Backlog)
- [ ] Ideation (between Triage and Backlog)
- [ ] Canceled (mark as "canceled")

---

## Step 3: Update `.env` Configuration

```bash
# If .env doesn't exist
cp .env.example .env
```

Edit `.env` and set:
- [ ] `LINEAR_API_KEY=lin_api_xxxxx`
- [ ] `LINEAR_TEAM_ID=` (Team UUID from Step 1)
- [ ] `LINEAR_ORG_ID=` (optional)
- [ ] `GITHUB_ORG=your-org`
- [ ] `GITHUB_REPO=your-repo`
- [ ] `PROJECT_NAME=YourProject`
- [ ] `PROJECT_TEAM_KEY=YOUR-KEY`
- [ ] `PROJECT_STACK=fullstack` (or backend/frontend)

---

## Step 4: Configure tp CLI

```bash
# Set team filter and default
tp config teams YOUR_KEY
tp config set defaultTeam YOUR_KEY

# Verify
tp config show
```

- [ ] `tp config teams [YOUR_KEY]` ran successfully
- [ ] `tp config set defaultTeam [YOUR_KEY]` ran successfully
- [ ] `tp config show` displays correct team
- [ ] `tp team show [YOUR_KEY]` works

---

## Step 5: Create Labels

**Option A: Use setup script (fastest)**

```bash
./.claude/scripts/setup-linear-labels.sh YOUR_KEY
```

- [ ] Script ran without errors
- [ ] Verify: `tp labels list --team YOUR_KEY` shows all labels

**Option B: Apply template**

```bash
tp labels templates
tp labels apply-template task-patterns --team YOUR_KEY
```

**Labels to verify exist:**
- [ ] Structure: `issue`, `subissue`, `epic`
- [ ] Stack: `stack:backend`, `stack:frontend`, `stack:fullstack`
- [ ] Work: `work:infrastructure`, `work:feature`, `work:enhancement`, `work:bugfix`
- [ ] Layers: `layer:atoms`, `layer:features`, `layer:molecules`, `layer:organisms`
- [ ] State: `state:awaiting-strategy-review`, `state:strategy-approved`

---

## Step 6: GitHub Integration

In Linear → Settings → Integrations → GitHub:

- [ ] Connect GitHub integration
- [ ] Select repository: `your-org/your-repo`
- [ ] Enable bi-directional sync
- [ ] Enable auto-close issues on PR merge
- [ ] Configure branch naming (optional)

---

## Step 7: GitHub Branch Protection

In GitHub → Settings → Branches:

- [ ] Add branch protection rule for `main`
- [ ] ✅ Require pull request before merging
- [ ] ✅ Require approvals: 1 (or 0 for solo)
- [ ] ✅ Dismiss stale approvals
- [ ] ✅ Restrict who can push
- [ ] Save changes

---

## Step 8: Verification Tests

```bash
# Test 1: Team access
tp team show YOUR_KEY

# Test 2: List labels
tp labels list --team YOUR_KEY

# Test 3: Create test issue
tp add "Test issue - setup verification" --team YOUR_KEY

# Test 4: Show issue
tp show YOUR_KEY-1

# Test 5: Update issue status
tp update YOUR_KEY-1 --status "Backlog"

# Test 6: Add labels
tp update YOUR_KEY-1 --add-labels "issue,stack:fullstack,work:infrastructure"

# Test 7: Clean up (optional)
tp update YOUR_KEY-1 --status "Canceled"
```

**Verification Checklist:**
- [ ] All test commands ran successfully
- [ ] Test issue appeared in Linear
- [ ] Status updates worked
- [ ] Labels applied correctly

---

## Step 9: Create Initial Issues (Optional)

```bash
# Create foundation epic
tp add "Epic: Project Foundation and Setup"
tp update YOUR_KEY-1 --add-labels "epic,stack:fullstack,work:infrastructure"

# Create initial tasks
tp add "Set up project structure"
tp add "Configure development environment"
tp add "Set up CI/CD pipeline"

# Link to epic
tp link-parent YOUR_KEY-2 YOUR_KEY-1
tp link-parent YOUR_KEY-3 YOUR_KEY-1
tp link-parent YOUR_KEY-4 YOUR_KEY-1

# Label tasks
for issue in YOUR_KEY-2 YOUR_KEY-3 YOUR_KEY-4; do
  tp update $issue --add-labels "subissue,stack:fullstack,work:infrastructure"
done
```

- [ ] Epic created
- [ ] Children created and linked
- [ ] All labeled correctly

---

## Step 10: Commit Configuration

```bash
# Commit tp config (safe to commit)
git add .tp/config.json
git commit -m "chore: configure tp CLI for YOUR_KEY team"

# Verify .env is NOT committed (should be git-ignored)
git status .env  # Should show nothing

# Commit setup script and docs
git add .claude/scripts/setup-linear-labels.sh
git add .claude/docs/LINEAR_TEAM_SETUP.md
git add .claude/docs/LINEAR_SETUP_CHECKLIST.md
git commit -m "docs: add Linear team setup guide and scripts"
```

- [ ] `.tp/config.json` committed
- [ ] `.env` confirmed git-ignored
- [ ] Setup scripts committed
- [ ] Documentation committed

---

## Success Criteria

All boxes checked:
- [ ] ✅ Team created in Linear with workflow states
- [ ] ✅ Labels created and organized
- [ ] ✅ tp CLI configured for new team
- [ ] ✅ GitHub integration enabled
- [ ] ✅ Branch protection enabled
- [ ] ✅ Test issue created and verified
- [ ] ✅ Configuration committed to git

---

## Next Steps

1. **Test the workflow**:
   ```bash
   /plan:decompose "Your first feature"
   /plan:create-issues issue-plan-your-first-feature.yaml
   ```

2. **Build your first epic**:
   - Create issues in Linear or via `/plan:create-issues`
   - Run `/analyze-implementation YOUR_KEY-X` to generate strategies
   - Add `state:strategy-approved` label after review
   - Run `/implement YOUR_KEY-X` to implement

3. **Enjoy autonomous development**! 🚀

---

**See Also:**
- [LINEAR_TEAM_SETUP.md](./LINEAR_TEAM_SETUP.md) - Detailed setup guide
- [BOOTSTRAP-PLAN.md](../../BOOTSTRAP-PLAN.md) - Complete bootstrap strategy
- `.claude/skills/task-patterns/SKILL.md` - tp CLI reference

---

**Pro Tips:**

- Use `LOG_LEVEL=info` for verbose tp output: `LOG_LEVEL=info tp labels list`
- Check configuration anytime: `tp config show`
- List all teams: `tp team list`
- Search labels: `tp labels search "backend"`
- View issue hierarchy: `tp show YOUR_KEY-1` (shows parent/children)
- Bulk operations: Use bash loops with `tp update`

**Common Gotchas:**

- 🚫 Forgot to add stack label → Commands will error
- 🚫 Wrong team key → `tp team list` to find correct key
- 🚫 Labels not found → Re-run label setup script
- 🚫 Can't commit to main → Use feature branch + PR workflow
- 🚫 .env committed → Add to `.gitignore` immediately!
