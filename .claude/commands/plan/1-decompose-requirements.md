---
description: Decompose requirements into YAML issue plan
argument-hint: <task-description> [--auto-accept|--team=KEY]
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Skill
  - TodoWrite
---

# Plan - Requirements Decomposition

Transform user requirements into structured YAML definition for Linear issues.

## Purpose

Interactive planning that generates structured YAML for Linear issue creation. Deep analysis → thoughtful decomposition → structured YAML. **YAML only** - no Linear issues created.

## Variables

- `$1`: Task description (required)
- `--auto-accept`: Skip approval, generate YAML immediately
- `--team=<key>`: Override team from .env

## Session Initialization

Follow `.claude/commands/shared/session-logging.md` for initialization:
- Standalone mode: Create `agent-logs/{session-id}/`
- Subagent mode: Use `$PARENT_SESSION_DIR/decompose/`
- Workflow name: `plan-decompose`

## Instructions

### Phase 1: Load Configuration

**Step 1: Read .env** - Get `PROJECT_TEAM_KEY`, `PROJECT_STACK`, `COMMIT_FORMAT`. Override team with `--team` flag if provided.

**Step 2: Read Config** - Read `.claude/config/project-config.md` for layer rules, label conventions, domain model.

---

### Phase 2: Deep Analysis

**Step 3: Understand Requirement** - Parse `$1`: what's requested, detail level, domain, constraints

**Step 4: Ultrathink** - Use `<ultrathink>` for: problem, stakeholders, criteria, constraints, layers, dependencies, risks

**Step 5: Ask Questions** - Until crystal clear: scope, architecture layer, stack, approach, constraints, dependencies, testing

---

### Phase 3: Label Discovery

**Step 6: Discover Labels** - Use task-patterns skill to list labels for team. Identify: Stack (REQUIRED), Type, Layer, Domain, Priority, TDD.

**Step 7: Determine Stack** - Backend (APIs/services/DB), Frontend (UI/components), Fullstack (end-to-end, decompose to backend+frontend subs). Rule: User touches → frontend, Data persists → backend, Both → fullstack.

---

### Phase 4: Decomposition

**Step 8: Break Down (use `<ultrathink>`)**

Epic: High-level feature, full description (problem/approach/criteria/subs), labels (`type:epic`, stack, layer, domain, priority), status `Refinement`.

Sub-Issues: ATOMIC units, ONE deliverable each, sequence (foundation → implementation → integration → testing), fullstack = backend subs first.

**Step 9: Assign Labels** - Stack (REQUIRED), Type, Layer, Domain, TDD, Priority. Rules: Epic with mixed subs = `stack:fullstack`, backend work = `stack:backend`, frontend = `stack:frontend`. ONE stack label per issue.

---

### Phase 5: Proposal & Approval

**Step 10: Present** - Show epic, sub-issues, labels, branch name, spec locations

**Step 11: Approve** - Unless `--auto-accept`, ask "Does this decomposition look correct?" and iterate

---

### Phase 6: Generate YAML

**Step 12: Create YAML** - Generate `issue-plan-{kebab-case}.yaml`:

```yaml
epic:
  title: "Epic: {title}"
  description: |
    {Problem statement}
    {Solution approach}
    {Success criteria}
    {Sub-issues list}
  labels: [{actual labels from discovery}]
  status: Refinement
  children:
    - title: "{sub-issue title}"
      description: |
        {Details}
        Parent: {Auto-set}
      labels: [{sub labels}]
      status: Refinement
```

Use actual labels, full descriptions, status `Refinement`.

**Step 13: Save** - Write to project root: `issue-plan-{kebab-case}.yaml`

---

### Phase 7: Commit

**Step 14: Commit** - Use git-workflow skill: type `docs`, scope `planning`, message "add issue decomposition plan for {feature}", files `issue-plan-{name}.yaml`, no issue ID

---

## Session Finalization

Follow `.claude/commands/shared/session-logging.md`: create `summary.md`, update `session.json` with completed status/artifacts, display location.

## Final Report

Display:
- Plan file location
- Epic structure tree
- Next steps: (1) `/plan:2-create-issues {yaml}`, (2) `/plan:3-generate-spec {ISSUE-ID}` for each, (3) `/implement {ISSUE-ID}`
- Note: Run each in NEW context for session logging and traceability

## Notes

- **Modular**: YAML generation only
- **Session Logging**: Separate contexts for traceability
- **Skill Delegation**: task-patterns for Linear, git-workflow for commits
- **Configuration-Driven**: .env conventions, not hardcoded
- **Interactive**: Ultrathink + clarifying questions
