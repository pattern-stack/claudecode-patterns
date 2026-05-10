# Feature Spec Generator

Thin wrapper that calls `/generate-spec` with feature-specific context. Used by `/plan` for feature-type issues.

## Purpose

Provides a feature-optimized interface to the underlying `/generate-spec` workflow. Features require comprehensive specs with full research, extensive testing, and detailed implementation phases.

## Variables

- `$1`: Issue identifier (e.g., BE-101, TASK-24)
- All other parameters passed through to `/generate-spec`

## Instructions

### Step 1: Validate Issue Type

```bash
ISSUE_ID="$1"

# Fetch issue to check type
ISSUE_LABELS=$(tp show $ISSUE_ID 2>/dev/null | grep "Labels:" || echo "")

# Check if this is a feature-type issue
if echo "$ISSUE_LABELS" | grep -qE "(feature|Feature|Enhancement)"; then
  # Confirmed feature type
  IS_FEATURE=true
else
  # Warn but continue (user explicitly called /feature)
  echo "⚠️  Warning: Issue labels don't indicate 'feature' type"
  echo "Proceeding with feature spec generation anyway..."
  IS_FEATURE=true
fi
```

### Step 2: Call /generate-spec with Feature Context

```bash
# Pass all arguments to /generate-spec
# Add --type=feature to signal feature-specific behavior
/generate-spec "$@" --type=feature
```

The `/generate-spec` workflow will:
- Perform deep codebase research
- Generate comprehensive implementation phases
- Include extensive testing strategy
- Define clear acceptance criteria
- Provide detailed task breakdown

### Step 3: Return Spec Path

The underlying `/generate-spec` command returns the spec path, which is passed through:

```
specs/issue-{ISSUE_ID}-{description}.md
```

## Feature-Specific Behavior

When `/generate-spec` receives `--type=feature`, it adjusts:

### Research Depth
- **Extensive**: 10-15 minutes of research
- Analyze 10+ existing files
- Identify multiple patterns
- Review similar implementations

### Implementation Plan
- **Comprehensive**: 4 phases (Foundation, Core, Integration, Testing)
- Detailed task breakdown (8-12 tasks)
- Clear sequencing and dependencies

### Testing Strategy
- **Full coverage**: Unit + Integration tests
- Edge cases explicitly listed
- Test coverage targets (80%+)
- Test file locations specified

### Validation
- **Complete**: All quality gates
- Format, lint, typecheck, validate
- Full test suite (test-ci)
- Architecture validation

## Usage Examples

### Called by /plan

```bash
# /plan detects issue type from labels
if [ "$ISSUE_TYPE" = "feature" ]; then
  /feature BE-101
fi
```

### Standalone Invocation

```bash
# User explicitly calls for feature spec
/feature BE-101

# Internally calls:
# /generate-spec BE-101 --type=feature
```

### With Session Linking

```bash
# Called from /plan with session context
/feature BE-101 --session-id=abc123

# Passes through to:
# /generate-spec BE-101 --type=feature --session-id=abc123
```

## Comparison with Other Types

| Type | Research | Phases | Testing | Use Case |
|------|----------|--------|---------|----------|
| **feature** | Deep (10-15 min) | 4 phases | Extensive | New functionality |
| **bug** | Focused (5 min) | 2 phases | Reproduction + Fix | Fix broken behavior |
| **chore** | Light (2-3 min) | 1-2 phases | Minimal | Maintenance work |
| **patch** | Targeted (<5 min) | 1 phase | Focused | Quick fixes |

## Related Commands

- **`/generate-spec`** - The underlying spec generator (called by this wrapper)
- **`/bug`** - Wrapper for bug-type issues (simpler specs)
- **`/chore`** - Wrapper for chore-type issues (lightweight specs)
- **`/patch`** - Wrapper for patch-type issues (quick fix specs)

## Integration with /plan

```markdown
### Phase 7: Spec Generation

**Step 12: Generate Type-Specific Specs**

For each issue, call appropriate wrapper based on type:

```bash
for ISSUE in $ALL_ISSUES; do
  # Detect issue type from labels
  ISSUE_TYPE=$(get_issue_type $ISSUE)

  case $ISSUE_TYPE in
    feature|Feature|Enhancement)
      /feature $ISSUE
      ;;
    bug|Bug|Bugfix)
      /bug $ISSUE
      ;;
    chore|Chore|Cleanup)
      /chore $ISSUE
      ;;
    patch|Patch|Hotfix)
      /patch $ISSUE
      ;;
    *)
      # Default to feature for unknown types
      /feature $ISSUE
      ;;
  esac
done
```
```

## Notes

- **Thin Wrapper**: This is NOT a standalone spec generator, it delegates to `/generate-spec`
- **Type-Specific**: Optimized for feature requirements (comprehensive, detailed)
- **Pass-Through**: All parameters (session, team, etc.) passed to underlying command
- **Composable**: Part of a family of type-specific wrappers

## Success Criteria

✅ Validates issue type (warns if not feature)
✅ Calls `/generate-spec` with `--type=feature`
✅ Passes through all parameters
✅ Returns spec path from underlying command
✅ Enables feature-optimized spec generation
