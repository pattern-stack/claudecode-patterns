# /analyze-implementation

Generate implementation strategy for a Linear issue with human approval gate.

## Purpose

Analyze a Linear issue and generate a comprehensive, high-level implementation strategy without writing any code. The strategy is posted to Linear for human review and approval before implementation proceeds.

This enables an autonomous workflow:
1. AI generates strategies for issues in batch
2. Human reviews strategies in Linear
3. Human adds `state:strategy-approved` label when satisfied
4. AI implements approved issues via `/implement`

## Usage

```bash
/analyze-implementation TEMPO-123
```

## Parameters

- `issue_id`: Linear issue ID (e.g., TEMPO-123)
- `--parent-session-dir`: Optional parent session directory for subagent mode

## Prerequisites

Validates .env configuration using validate-env.sh script:

```bash
source .claude/commands/lib/validate-env.sh || exit 1
```

This ensures:
- .env file exists
- Required variables are set (PROJECT_TEAM_KEY, GITHUB_*, etc.)
- Optional Linear keys show warnings if not configured

## Variables

```bash
ISSUE_ID="$1"
PARENT_SESSION_DIR="${2}"  # Optional: --parent-session-dir=<path>
```

## Workflow

### Step 0: Parse Arguments

Extract issue ID and check for parent session directory:

```bash
# Parse issue ID
ISSUE_ID="$1"

if [ -z "$ISSUE_ID" ]; then
  echo "❌ Usage: /analyze-implementation TEMPO-123"
  exit 1
fi

# Parse optional parent session directory
PARENT_SESSION_DIR=""
for arg in "$@"; do
  case $arg in
    --parent-session-dir=*)
      PARENT_SESSION_DIR="${arg#*=}"
      shift
      ;;
  esac
done
```

---

### Step 1: Session Initialization

Follow `.claude/commands/shared/session-logging.md` for initialization:
- Standalone mode: Create `agent-logs/{session-id}/`
- Subagent mode: Use `$PARENT_SESSION_DIR/analyze-implementation/`
- Workflow name: `analyze-implementation`
- Description: Issue ID (e.g., `tempo-123`)

---

### Step 2: Fetch Issue Details

Use task-patterns skill to retrieve issue information from Linear.

**Instructions to Claude**:

> Use the task-patterns skill to fetch issue $ISSUE_ID.
>
> Extract and provide:
> - Issue title
> - Issue description
> - Current status
> - Labels (especially stack: and layer: labels)
> - Any existing comments
>
> Store the results in variables for use in strategy generation.

**Expected Outputs**:
- `ISSUE_TITLE`: Issue title
- `ISSUE_DESCRIPTION`: Issue description
- `ISSUE_STATUS`: Current status
- `STACK_LABEL`: Backend, Frontend, or Full Stack
- `LAYER_LABELS`: Layer labels (atoms, features, molecules, organisms)

---

### Step 3: Analyze Codebase

Use pattern-stack-architect skill to analyze codebase and identify similar patterns.

**Instructions to Claude**:

> Use the pattern-stack-architect skill to analyze the codebase for patterns relevant to this issue.
>
> Consider:
> - What layer(s) will this issue touch? (atoms/features/molecules/organisms)
> - Are there similar implementations we can reference?
> - What Pattern Stack patterns should be used? (BasePattern, CatalogPattern, etc.)
> - What Field() definitions will be needed?
> - What services, entities, or workflows already exist that we can extend?
>
> Based on the issue description and labels, identify:
> 1. **Affected files** - Which files will need to be created or modified?
> 2. **Architecture approach** - High-level technical approach (2-3 sentences)
> 3. **Dependencies** - Other issues or Pattern Stack patterns needed
> 4. **Testing strategy** - What needs unit vs integration testing

**Expected Outputs**:
- List of new files to create
- List of existing files to modify
- Architecture approach description
- Dependencies list
- Testing strategy description

---

### Step 4: Generate Strategy Document

Create a detailed strategy document following the project format.

**Instructions to Claude**:

> Generate a comprehensive implementation strategy document.
>
> **Format**: Markdown file
> **Location**: Determine based on stack label:
> - `stack:backend` → `application/backend/specs/strategy-$ISSUE_ID.md`
> - `stack:frontend` → `application/frontend/specs/strategy-$ISSUE_ID.md`
> - `stack:fullstack` → `specs/strategy-$ISSUE_ID.md`
>
> **Structure**:
> ```markdown
> # Implementation Strategy: $ISSUE_ID
>
> **Issue**: $ISSUE_ID - $ISSUE_TITLE
> **Analyzed**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
> **Stack**: $STACK_LABEL
> **Status**: Awaiting Strategy Review
>
> ## Summary
>
> {1-2 sentence summary of what this issue accomplishes}
>
> ## Approach
>
> {High-level technical approach - 2-4 sentences describing the solution}
>
> ## Architecture Impact
>
> **Layer**: {atoms/features/molecules/organisms}
>
> **New Files**:
> - `path/to/file.py` - Brief description
> - `path/to/test_file.py` - Test coverage
>
> **Modified Files**:
> - `path/to/existing.py` - What changes are needed
>
> ## Dependencies
>
> **Issues**:
> - Depends on: {other issue IDs if any, or "None"}
>
> **Pattern Stack**:
> - {Relevant patterns: BasePattern, CatalogPattern, Field(), etc.}
>
> **External**:
> - {Any external dependencies or libraries needed}
>
> ## Testing Strategy
>
> **Unit Tests**:
> - {What needs unit testing}
>
> **Integration Tests**:
> - {What needs integration testing}
>
> **Coverage Target**: 80%+ (90%+ preferred)
>
> ## Implementation Sequence
>
> 1. {Step 1 - typically start with atoms/foundation}
> 2. {Step 2}
> 3. {Step 3}
> 4. {Step 4 - typically end with tests}
>
> ## Open Questions
>
> - {Question 1 - things that need clarification}
> - {Question 2}
>
> ## Estimated Complexity
>
> {Low/Medium/High} ({hours estimate})
>
> **Rationale**: {Brief explanation of complexity rating}
>
> ---
>
> ## Approval
>
> To proceed with implementation:
> 1. Review this strategy
> 2. Address open questions in Linear comments
> 3. Add label `state:strategy-approved` to $ISSUE_ID in Linear
> 4. Run `/implement $ISSUE_ID`
> ```
>
> Write this file to the appropriate location based on the stack label.

**Track Artifact**: Update session artifacts per `.claude/commands/shared/session-logging.md` (Step 2: Track Artifacts)

---

### Step 5: Commit Strategy Document

Use git-workflow skill to commit the strategy document.

**Instructions to Claude**:

> Use git-workflow skill to commit changes:
> - Type: docs
> - Scope: planning
> - Message: add implementation strategy for $ISSUE_ID
> - Issue: $ISSUE_ID
>
> This commits the strategy document to the current branch.

**Track Artifact**: Update session artifacts per `.claude/commands/shared/session-logging.md` (Step 2: Track Artifacts)

---

### Step 6: Generate Linear Comment

Create a Linear comment with the strategy in the format specified in BOOTSTRAP-PLAN.md.

**Instructions to Claude**:

> Generate a Linear comment containing the implementation strategy.
>
> **Format** (must match this structure exactly):
> ```markdown
> ## 🤖 Implementation Strategy
>
> **Issue**: $ISSUE_ID - $ISSUE_TITLE
> **Analyzed**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
>
> ### Approach
> {High-level technical approach - 2-3 sentences}
>
> ### Architecture Impact
> **Layer**: {atoms/features/molecules/organisms}
>
> **New Files**:
> - {file paths with brief descriptions}
>
> **Modified Files**:
> - {file paths with changes needed}
>
> ### Dependencies
> - Depends on: {other issues if any, or "None"}
> - Pattern Stack: {relevant patterns}
>
> ### Testing Strategy
> - Unit: {what to unit test}
> - Integration: {what to integration test}
>
> ### Implementation Sequence
> 1. {Step 1}
> 2. {Step 2}
> 3. {Step 3}
>
> ### Open Questions
> - {Question 1}
> - {Question 2}
>
> ### Estimated Complexity
> {Low/Medium/High} ({hours estimate})
>
> ---
> Add label state:strategy-approved when ready to proceed
> ```
>
> Store this in a variable `STRATEGY_COMMENT` for posting to Linear.

---

### Step 7: Post to Linear

Use task-patterns skill to post the strategy comment and update issue state.

**Instructions to Claude**:

> Use task-patterns skill to perform these operations on $ISSUE_ID:
>
> 1. **Post comment** with the strategy content
> 2. **Add label**: `state:awaiting-strategy-review`
> 3. **Update status**: Set to "Refinement"
>
> Execute these in sequence:
> ```bash
> # Post comment
> tp comment $ISSUE_ID "$STRATEGY_COMMENT"
>
> # Add label
> tp update $ISSUE_ID --add-labels "state:awaiting-strategy-review"
>
> # Update status to Refinement
> tp update $ISSUE_ID --status "Refinement"
> ```
>
> Capture the comment URL if provided by tp CLI.

**Track Artifact**: Update session artifacts per `.claude/commands/shared/session-logging.md` (Step 2: Track Artifacts)

---

### Step 8: Session Finalization

Follow `.claude/commands/shared/session-logging.md` (Step 3: Finalize Session):
- Create `summary.md` with artifacts and results
- Update session.json status to "completed"
- Include next steps for human review

---

### Step 9: Display Report

Show user-friendly summary of what was accomplished.

**Instructions to Claude**:

> Display a clear report summarizing the analysis:
>
> ```
> ✅ Implementation Strategy Generated
>
> **Issue**: $ISSUE_ID - $ISSUE_TITLE
>
> **Strategy Location**: $STRATEGY_FILE
> **Linear Comment**: $LINEAR_COMMENT_URL
> **Commit**: $COMMIT_HASH
>
> **Status**: Awaiting strategy review
> **Label Added**: state:awaiting-strategy-review
>
> ## Next Steps
>
> 1. Review the strategy in Linear
> 2. Address open questions in comments
> 3. Add label `state:strategy-approved` when ready
> 4. Run `/implement $ISSUE_ID` to begin implementation
>
> ## Strategy Summary
>
> {Display 2-3 sentence summary of the approach}
>
> **Complexity**: {Low/Medium/High} ({hours})
> **Layer**: {atoms/features/molecules/organisms}
>
> Session: $SESSION_DIR
> ```

---

## Error Handling

### Issue Not Found

```bash
if [ $? -ne 0 ]; then
  echo "❌ Failed to fetch issue $ISSUE_ID from Linear"
  jq '.status = "failed" | .errors += [{
    "message": "Issue not found or inaccessible",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]' "$SESSION_DIR/session.json" > "$SESSION_DIR/session.json.tmp"
  mv "$SESSION_DIR/session.json.tmp" "$SESSION_DIR/session.json"
  exit 1
fi
```

### Invalid Stack Label

```bash
if [ -z "$STACK_LABEL" ]; then
  echo "⚠️  Warning: No stack: label found on issue"
  echo "Strategy will be created in project root specs/"
  STACK_LABEL="unknown"
fi
```

### Git Commit Failure

```bash
if [ $? -ne 0 ]; then
  echo "❌ Failed to commit strategy document"
  jq '.status = "failed" | .errors += [{
    "message": "Git commit failed",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]' "$SESSION_DIR/session.json" > "$SESSION_DIR/session.json.tmp"
  mv "$SESSION_DIR/session.json.tmp" "$SESSION_DIR/session.json"
  exit 1
fi
```

### Linear API Failure

```bash
if [ $? -ne 0 ]; then
  echo "⚠️  Warning: Failed to post to Linear"
  echo "Strategy document committed but comment not posted"
  echo "Manual action required: Post strategy to Linear issue"
  jq '.errors += [{
    "message": "Linear comment posting failed",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]' "$SESSION_DIR/session.json" > "$SESSION_DIR/session.json.tmp"
  mv "$SESSION_DIR/session.json.tmp" "$SESSION_DIR/session.json"
fi
```

---

## Implementation Notes

### Skill Delegation Pattern

This command delegates ALL operations to skills:
- **task-patterns skill**: All Linear operations (fetch, comment, label, status)
- **pattern-stack-architect skill**: Codebase analysis and architecture guidance
- **git-workflow skill**: All git operations (commit)

The command itself is pure workflow orchestration with no embedded bash beyond session logging.

### Strategy File Location Logic

```bash
case "$STACK_LABEL" in
  *backend*|*Backend*)
    STRATEGY_DIR="application/backend/specs"
    ;;
  *frontend*|*Frontend*)
    STRATEGY_DIR="application/frontend/specs"
    ;;
  *)
    STRATEGY_DIR="specs"
    ;;
esac

STRATEGY_FILE="$STRATEGY_DIR/strategy-${ISSUE_ID}.md"
mkdir -p "$STRATEGY_DIR"
```

### Session Logging Integration

This command uses the simplified session logging pattern:
- **Standalone mode**: Creates new top-level session in `agent-logs/`
- **Subagent mode**: Writes into parent's session directory

Example usage as subagent:
```bash
/analyze-implementation TEMPO-123 --parent-session-dir=agent-logs/2025-11-02_plan_xyz_abc123
```

### Human Gate Pattern

The label `state:awaiting-strategy-review` acts as a gate:
1. AI cannot proceed to implementation without `state:strategy-approved`
2. Human reviews strategy in Linear (async)
3. Human adds `state:strategy-approved` when satisfied
4. AI then runs `/implement` which checks for approval label

This enables:
- Batch strategy generation: AI generates strategies for multiple issues
- Async review: Human reviews all strategies in Linear
- Selective implementation: Human approves only what makes sense

---

## Examples

### Example 1: Backend Feature

```bash
/analyze-implementation TEMPO-42
```

**Output**:
```
✅ Implementation Strategy Generated

Issue: TEMPO-42 - Add Redis caching layer

Strategy Location: application/backend/specs/strategy-TEMPO-42.md
Linear Comment: https://linear.app/tempo/issue/TEMPO-42
Commit: abc123def

Status: Awaiting strategy review
Label Added: state:awaiting-strategy-review

Next Steps:
1. Review strategy in Linear
2. Add label state:strategy-approved when ready
3. Run /implement TEMPO-42

Strategy Summary:
Create Redis cache adapter in atoms layer, add caching to UserService in
features layer. Use Pattern Stack Field() for cache config.

Complexity: Medium (4-5 hours)
Layer: atoms, features

Session: agent-logs/2025-11-02_analyze-implementation_tempo-42_a7f3b2
```

---

### Example 2: Frontend Component

```bash
/analyze-implementation TEMPO-88
```

**Output**:
```
✅ Implementation Strategy Generated

Issue: TEMPO-88 - Create deal timeline component

Strategy Location: application/frontend/specs/strategy-TEMPO-88.md
Linear Comment: https://linear.app/tempo/issue/TEMPO-88
Commit: def456abc

Status: Awaiting strategy review
Label Added: state:awaiting-strategy-review

Strategy Summary:
Build Timeline organism component using Card atoms and ActivityItem molecules.
Integrate with useActivities hook for data fetching.

Complexity: Low (2-3 hours)
Layer: organisms

Session: agent-logs/2025-11-02_analyze-implementation_tempo-88_b8e4c3
```

---

### Example 3: As Subagent

```bash
# Called by /plan command
/analyze-implementation TEMPO-101 --parent-session-dir=agent-logs/2025-11-02_plan_auth_xyz123
```

**Result**:
Strategy logs written to `agent-logs/2025-11-02_plan_auth_xyz123/analyze-implementation/`

---

## Benefits

1. **Autonomous Planning**: AI can analyze multiple issues in batch
2. **Human Gate**: Strategy approval prevents costly implementation mistakes
3. **Async Workflow**: Human reviews in Linear on their schedule
4. **Full Traceability**: Strategy document + Linear comment + git commit
5. **Pattern Consistency**: Leverages pattern-stack-architect skill
6. **Clean Separation**: No code generation, pure strategy

---

## Related Commands

- `/plan:3-generate-spec` - Generates detailed specs (more detailed than strategy)
- `/implement` - Implements issues with approved strategies
- `/test` - Runs quality gates after implementation

---

## Configuration

No configuration required. Uses:
- `.env` for git conventions (via git-workflow skill)
- `.tp/config.json` for Linear team settings (via task-patterns skill)

---

## Troubleshooting

### "Label not found: state:awaiting-strategy-review"

Create the label in Linear:
```bash
tp labels create "state:awaiting-strategy-review" \
  --description "Strategy posted, awaiting human review" \
  --team TEMPO
```

### "Strategy file already exists"

The command will overwrite existing strategy files. This is by design to allow
re-analysis if requirements change.

### "No stack: label on issue"

Add a stack label before running:
```bash
tp update TEMPO-123 --add-labels "stack:backend"
```

Or the command will default to creating strategy in project root `specs/`.

---

**Command Size**: ~300 lines
**Complexity**: Medium
**Dependencies**: task-patterns skill, pattern-stack-architect skill, git-workflow skill
