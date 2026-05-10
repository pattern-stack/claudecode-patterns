---
description: Generate detailed implementation spec from approved strategy
argument-hint: <issue-id> [--type=TYPE] [--team=KEY] [--no-logging]
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
  - Skill
---

# Generate Implementation Spec

Generate detailed, implementation-ready specification from an approved implementation strategy.

## Purpose

Transform approved implementation strategy into detailed spec with:
- File-level implementation guidance
- Code patterns and references
- Testing strategy
- Validation commands

**Key Philosophy**: Detailed specs require approved strategy foundation. Strategy guides architectural approach, spec provides tactical implementation details.

## Usage

```bash
/plan:generate-spec TEMPO-123
/plan:3-generate-spec TEMPO-123 --team TEMPO
```

## Variables

- `$1`: Issue identifier (e.g., TEMPO-123)
- `--type=<type>`: Issue type (feature|bug|chore|patch) - adjusts spec depth (optional, default: feature)
- `--team=<key>`: Override team (default: from config)
- `--parent-session-dir=<path>`: Subagent mode - write to parent's session directory (optional)
- `--no-logging`: Disable session logging (optional)

## Configuration Validation

Before executing, validate .env configuration:

```bash
source .claude/commands/lib/validate-env.sh || exit 1
```

This ensures:
- .env file exists
- Required variables are set (PROJECT_TEAM_KEY, GITHUB_*, etc.)
- Optional Linear keys show warnings if not configured

## Prerequisites

**REQUIRED**:
1. Issue must have label `state:strategy-approved`
2. Issue must have approved strategy comment (from `/analyze-implementation`)
3. Issue must be in Refinement status

**If prerequisites not met**: Error and exit with instructions to run `/analyze-implementation` first.

## Instructions

### Phase 0: Session Initialization

**If `--no-logging` flag is set, skip all session logging.**

#### Step 1: Determine Mode and Initialize Session

```bash
ISSUE_ID="$1"
```

## Session Initialization

Follow `.claude/commands/shared/session-logging.md` for initialization:
- Standalone mode: Create `agent-logs/{session-id}/`
- Subagent mode: Use `$PARENT_SESSION_DIR/generate-spec/`
- Workflow name: `generate-spec`
- Description: Issue ID (e.g., `tempo-123`)

---

## Phase 1: Verify Prerequisites

Use task-patterns skill to fetch issue and verify prerequisites.

#### Step 2: Fetch Issue Details

```markdown
Use task-patterns skill to fetch issue $ISSUE_ID
```

Extract from issue:
- **Title**: Issue title
- **Description**: Full description
- **Labels**: All labels (must include `state:strategy-approved` and `stack:*`)
- **Status**: Must be "Refinement"
- **Parent**: Parent epic (for context)

#### Step 3: Verify Strategy Approved

```bash
# Check for state:strategy-approved label
if ! echo "$LABELS" | grep -q "state:strategy-approved"; then
  echo "❌ ERROR: Issue must have label 'state:strategy-approved'"
  echo ""
  echo "Run strategy analysis first:"
  echo "  /analyze-implementation $ISSUE_ID"
  exit 1
fi

# Verify status using task-patterns skill
Use task-patterns skill to check if issue status is "Refinement"
If not, display error and suggest: tp update $ISSUE_ID --status 'Refinement'
```

#### Step 4: Fetch Approved Strategy

```markdown
Use task-patterns skill to fetch comments for $ISSUE_ID
```

Find most recent comment with header `🤖 Implementation Strategy`.

```bash
# Extract strategy content using task-patterns skill
Use task-patterns skill to find comment with header "🤖 Implementation Strategy"
If not found, display error and suggest: /analyze-implementation $ISSUE_ID
```

#### Step 5: Determine Stack and Paths

```bash
# Extract stack label
STACK=$(echo "$LABELS" | grep -o 'stack:[a-z]*' | cut -d: -f2)

case "$STACK" in
  backend)
    CODEBASE_PATH="application/backend/app"
    SPEC_PATH="application/backend/specs"
    ;;
  frontend)
    CODEBASE_PATH="application/frontend/src"
    SPEC_PATH="application/frontend/specs"
    ;;
  fullstack)
    CODEBASE_PATH="."
    SPEC_PATH="specs"
    ;;
  *)
    echo "❌ ERROR: No valid stack label found: $STACK"
    echo "Issue must have: stack:backend, stack:frontend, or stack:fullstack"
    exit 1
    ;;
esac

echo "Stack: $STACK"
echo "Codebase: $CODEBASE_PATH"
echo "Spec location: $SPEC_PATH"
```

### Phase 2: Analyze Codebase

Use pattern-stack-architect skill (for backend) or codebase exploration (for frontend) to identify implementation patterns.

#### Step 6: Identify Affected Files

```markdown
Use pattern-stack-architect skill to analyze codebase for $ISSUE_ID

Context:
- Stack: $STACK
- Strategy: $STRATEGY
- Issue description: $DESCRIPTION

Identify:
- Files to modify
- Files to create
- Similar implementations to reference
- Relevant patterns to follow
```

For frontend or general exploration:

```bash
# Find relevant files based on issue domain
Glob "$CODEBASE_PATH/**/*{domain}*.{py,tsx,ts}"

# Search for similar patterns
Grep "{relevant-pattern}" --path "$CODEBASE_PATH" --output_mode files_with_matches

# Read similar implementations
Read {discovered-files}
```

#### Step 7: Understand Project Patterns

```bash
# Read architectural documentation
Read CLAUDE.md
Read $CODEBASE_PATH/../README.md  # If exists

# Understand testing conventions
Glob "$CODEBASE_PATH/**/*.test.{py,ts,tsx}"
Glob "$CODEBASE_PATH/**/test_*.py"

# Read test examples
Read {test-file-example}
```

### Phase 3: Generate Detailed Spec

#### Step 8: Create Implementation Spec

Generate spec file using strategy as foundation, adding detailed implementation guidance.

**Spec Structure**:

```markdown
# {Issue Type}: {Issue Title}

## Metadata
- **Issue**: `{ISSUE_ID}`
- **Stack**: `{STACK}`
- **Generated**: {timestamp}
- **Session**: `{SESSION_ID}`
- **Strategy**: Approved {date}

## Issue Context

### Problem Statement
{From issue description}

### Solution Approach
{From approved strategy}

### Success Criteria
{From issue description}

## Approved Strategy Summary

{Strategy overview from strategy comment - key architectural decisions}

## Implementation Plan

### Phase 1: {Phase Name}
{From strategy, with added detail}

**Tasks**:
1. **{Task Name}**
   - File: `{file-path}`
   - Action: {specific action}
   - Pattern: {pattern to follow from codebase analysis}
   - Reference: `{similar-file}:{line-range}`

### Phase 2: {Phase Name}
{Continue for all phases from strategy}

### Phase N: Testing
{Testing phase based on type}

## Detailed Task Breakdown

### Task 1: {Task Name}

**File**: `{file-path}`

**Action**: {Specific change to make}

**Implementation Guidance**:
```{language}
{Pseudocode or structure based on codebase patterns}
```

**Reference**: Similar implementation at `{file}:{line}`

**Tests**: {What to test and how}

{Continue for all tasks}

## File Changes

### Files to Modify

#### `{file-path}`
**Why**: {Reason}

**Changes**:
- {Change 1}
- {Change 2}

**Estimated lines**: ~{count}

### Files to Create

#### `{new-file-path}`
**Why**: {Purpose}

**Structure**: Based on `{similar-file}`

```{language}
{File outline}
```

## Testing Strategy

### Unit Tests

**File**: `{test-file-path}`

**Test Cases**:
1. **{Test case name}**
   - Setup: {setup}
   - Action: {action}
   - Assert: {expected}

### Integration Tests
{If applicable}

### Edge Cases
1. **{Edge case}**: {Expected behavior}

## Validation Commands

**Backend**:
```bash
cd application/backend
uv run format      # Auto-fix
uv run lint        # Check
uv run typecheck   # Check
uv run test        # Run tests
uv run ci          # All gates
```

**Frontend**:
```bash
cd application/frontend
npm run lint       # Check + auto-fix
npm run type-check # Check
npm run test       # Run tests
npm run ci         # All gates
```

## Dependencies

### Existing Dependencies
- `{package}`: {How used}

### New Dependencies Needed
{If any}
- `{package}`: {Why needed}

## Implementation Notes

### Important Considerations
{From codebase analysis - gotchas, constraints}

### Code Patterns to Follow
{Patterns discovered in codebase}

### References
- `{file}:{line}` - {What to reference}

## Ready for Implementation

This spec is complete and ready for `/implement` workflow.
```

#### Step 9: Save Spec File

```bash
# Generate spec filename
SPEC_NAME=$(echo "$ISSUE_TITLE" | \
  tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9]/-/g' | \
  sed 's/--*/-/g' | \
  sed 's/^-//' | \
  sed 's/-$//' | \
  cut -c1-50)

SPEC_FILE="$SPEC_PATH/issue-${ISSUE_ID}-${SPEC_NAME}.md"

# Create spec directory if needed
mkdir -p "$SPEC_PATH"

# Write spec
Write "$SPEC_FILE" "{spec content}"

echo "✅ Spec created: $SPEC_FILE"
```

### Phase 4: Commit and Update Linear

#### Step 10: Commit Spec

```markdown
Use git-workflow skill to commit changes:
- Type: docs
- Scope: specs
- Message: add implementation spec for {ISSUE_ID}
- Issue: {ISSUE_ID}
```

#### Step 11: Update Linear

```markdown
Use task-patterns skill to post comment to {ISSUE_ID}:

---
✅ Implementation spec generated!

📄 **Spec**: {SPEC_FILE}

## What's Next
This issue is now Ready for implementation:
```bash
/implement {ISSUE_ID}
```

## Spec Contents
- ✅ Detailed implementation plan (based on approved strategy)
- ✅ Task breakdown with file references
- ✅ Testing strategy
- ✅ Validation commands
- ✅ Code patterns and references

Generated via /plan:generate-spec workflow
Session: {SESSION_ID}
---
```

```markdown
Use task-patterns skill to update {ISSUE_ID} status to "Ready"
```

```markdown
Use task-patterns skill to remove label "state:strategy-approved" from {ISSUE_ID}
Use task-patterns skill to add label "state:spec-ready" to {ISSUE_ID}
```

### Phase 5: Finalize Session

#### Step 12: Create Summary

```bash
cat > "$SESSION_DIR/summary.md" <<EOF
# Generate Spec Summary

**Session**: $SESSION_ID
**Issue**: $ISSUE_ID
**Completed**: $(date)

## What Was Done

### 1. Prerequisites Verified
- ✅ Strategy approved label verified
- ✅ Approved strategy comment found
- ✅ Status verified (Refinement)

### 2. Codebase Analyzed
- Files analyzed: {count}
- Patterns identified: {list}
- Similar implementations found: {list}

### 3. Spec Generated
- **File**: $SPEC_FILE
- **Lines**: {count}
- **Tasks**: {count}
- **Files to modify**: {count}

### 4. Git and Linear Updated
- ✅ Spec committed
- ✅ Comment added with spec link
- ✅ Status changed: Refinement → Ready
- ✅ Labels updated

## Next Steps

Issue $ISSUE_ID is Ready for implementation:

\`\`\`bash
/implement $ISSUE_ID
\`\`\`

## Session Data

Full session: $SESSION_DIR/session.json
EOF

# Finalize session.json
jq '. + {
  "status": "completed",
  "completed_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "artifacts": {
    "spec_file": "'$SPEC_FILE'",
    "session_logs": "'$SESSION_DIR'"
  }
}' "$SESSION_DIR/session.json" > "$SESSION_DIR/session.json.tmp"
mv "$SESSION_DIR/session.json.tmp" "$SESSION_DIR/session.json"
```

#### Step 13: Report Results

```bash
echo "
✅ Spec Generated Successfully!

📄 **Spec**: $SPEC_FILE
🔗 **Issue**: https://linear.app/{workspace}/issue/$ISSUE_ID
📊 **Session**: $SESSION_DIR/

## Summary

- ✅ Strategy verified and used as foundation
- ✅ Researched {file-count} files
- ✅ Generated {task-count} implementation tasks
- ✅ Defined {test-count} test cases
- ✅ Updated issue status: Refinement → Ready

## Issue $ISSUE_ID is Ready for Implementation

Next step:
\`\`\`bash
/implement $ISSUE_ID
\`\`\`

Or review the spec:
\`\`\`bash
cat $SPEC_FILE
\`\`\`

Session logs: $SESSION_DIR/
"
```

## Error Handling

### Missing Strategy Approval

```markdown
❌ ERROR: Issue must have approved strategy

Issue $ISSUE_ID does not have label 'state:strategy-approved'

Required workflow:
1. Run: /analyze-implementation $ISSUE_ID
2. Review and approve strategy
3. Then: /plan:generate-spec $ISSUE_ID
```

### Invalid Status

```markdown
❌ ERROR: Issue must be in Refinement status

Current status: {status}

To fix:
  tp update $ISSUE_ID --status "Refinement"
```

### No Stack Label

```markdown
❌ ERROR: No valid stack label found

Issue must have one of:
- stack:backend
- stack:frontend
- stack:fullstack

To fix:
  tp update $ISSUE_ID --add-labels "stack:backend"
```

## Type-Specific Behavior

The `--type` parameter adjusts spec depth:

| Type | Research Time | Testing Depth | Use Case |
|------|---------------|---------------|----------|
| feature | 10-15 min | Extensive (unit + integration, 80%+ coverage) | New functionality |
| bug | 5 min | Focused (reproduction + fix validation) | Fix broken behavior |
| chore | 2-3 min | Minimal (basic validation) | Maintenance work |
| patch | <5 min | Focused (affected area only) | Quick fixes |

## Notes

- **Strategy-First**: This command requires approved strategy (from `/analyze-implementation`)
- **Skill Delegation**: All Linear/git operations via skills (task-patterns, git-workflow)
- **Codebase Agnostic**: Works with any stack (Python, TypeScript, Go, etc.)
- **Session Logging**: Full traceability of spec generation process
- **Idempotent**: Can re-run to regenerate spec (overwrites existing)

## Success Criteria

✅ Issue fetched and prerequisites verified
✅ Strategy approved label present
✅ Approved strategy comment found
✅ Codebase analyzed for patterns
✅ Detailed spec generated using strategy as foundation
✅ Spec committed via git-workflow skill
✅ Issue updated with spec link
✅ Issue moved to Ready status
✅ Labels updated (strategy-approved removed, spec-ready added)
✅ Session fully logged
