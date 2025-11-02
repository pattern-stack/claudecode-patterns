# Session Logging - Workflow Observability

Standardized session logging for workflow commands. Each execution creates a session directory with full traceability.

## Purpose

Provide observability into AI workflow executions:
- What was requested and what was produced
- Commands executed and their outputs
- Files created/modified
- Results and outcomes

## Session Structure

```
agent-logs/
├── {session-id}/                    # Self-contained session directory
│   ├── session.json                 # Metadata and artifacts
│   ├── input.json                   # Original request
│   ├── execution.log                # Command output (optional for long workflows)
│   └── summary.md                   # Final summary
└── sessions.json                    # Index of all sessions
```

## Invocation Modes

Commands support **two modes** with different session behaviors:

### Mode 1: Standalone (Default)

**When**: User invokes command directly

**Behavior**: Creates new top-level session directory

**Example**:
```bash
/plan:generate-spec TEMPO-123
```

**Result**:
```
agent-logs/2025-11-02_generate-spec_tempo-123_a7f3b2/
├── session.json
├── input.json
└── summary.md
```

### Mode 2: Subagent

**When**: Command is called BY another command

**Parameters**: `--parent-session-dir=<path>`

**Behavior**: Writes into parent's session directory as subdirectory

**Example**:
```bash
# /plan internally calls /create-issues
/plan:create-issues issue-plan.yaml --parent-session-dir=agent-logs/abc123
```

**Result**:
```
agent-logs/abc123/                    # Parent session
├── create-issues/                    # Subagent logs here
│   ├── input.yaml
│   ├── execution.log
│   └── output.json
└── session.json                      # Parent tracks subagent
```

## Session ID Format

```
{date}_{workflow}_{description}_{hash}
```

**Examples:**
- `2025-11-02_plan_redis-caching_a7f3b2`
- `2025-11-02_generate-spec_tempo-123_def456`
- `2025-11-02_implement_tempo-101_8c9d1e`

**Generate**:
```bash
WORKFLOW="plan"
DESCRIPTION="redis-caching"  # From user request, kebab-case, max 30 chars
HASH=$(openssl rand -hex 3)
SESSION_ID="$(date +%Y-%m-%d)_${WORKFLOW}_${DESCRIPTION}_${HASH}"
```

## session.json Schema

Simplified schema focused on artifacts and workflow status:

```json
{
  "session_id": "2025-11-02_plan_redis-caching_a7f3b2",
  "workflow": "plan",
  "started_at": "2025-11-02T19:30:00Z",
  "completed_at": "2025-11-02T19:45:00Z",
  "status": "completed",
  "user_request": "Add Redis caching to user service",

  "artifacts": {
    "issues_created": ["TEMPO-100", "TEMPO-101"],
    "specs_generated": ["specs/issue-TEMPO-100-epic.md"],
    "files_modified": ["app/atoms/cache/redis.py"],
    "commits": ["abc123"]
  },

  "errors": []
}
```

## Usage in Commands

### Step 1: Initialize Session

Add at workflow start:

```markdown
## Session Initialization

```bash
# Check for parent session (subagent mode)
if [ -n "$PARENT_SESSION_DIR" ]; then
  SESSION_DIR="$PARENT_SESSION_DIR/{workflow-name}"
  mkdir -p "$SESSION_DIR"
else
  # Standalone mode - create new session
  WORKFLOW="{workflow-name}"
  DESCRIPTION="{from-user-request}"  # Kebab-case, max 30 chars
  HASH=$(openssl rand -hex 3)
  SESSION_ID="$(date +%Y-%m-%d)_${WORKFLOW}_${DESCRIPTION}_${HASH}"
  SESSION_DIR="agent-logs/$SESSION_ID"
  mkdir -p "$SESSION_DIR"

  # Initialize session.json
  cat > $SESSION_DIR/session.json <<EOF
{
  "session_id": "$SESSION_ID",
  "workflow": "$WORKFLOW",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "in_progress",
  "user_request": "{original-request}",
  "artifacts": {},
  "errors": []
}
EOF

  # Initialize sessions.json index if doesn't exist
  [ ! -f agent-logs/sessions.json ] && echo '[]' > agent-logs/sessions.json
fi

# Save input
cat > $SESSION_DIR/input.json <<EOF
{
  "workflow": "$WORKFLOW",
  "arguments": {COMMAND_ARGUMENTS}
}
EOF
```
```

### Step 2: Track Artifacts

Update session.json as work progresses:

```markdown
## Artifact Tracking

```bash
# After creating artifacts, update session.json
jq '.artifacts.issues_created += ["TEMPO-123"]' \
  $SESSION_DIR/session.json > $SESSION_DIR/session.json.tmp
mv $SESSION_DIR/session.json.tmp $SESSION_DIR/session.json
```
```

### Step 3: Finalize Session

At workflow end:

```markdown
## Session Finalization

```bash
# Create summary
cat > $SESSION_DIR/summary.md <<EOF
# Workflow Summary

Session: $SESSION_ID
Workflow: {workflow-name}
Status: {completed|failed}

## Request
{original-request}

## Artifacts Created
{list all issues, files, commits}

## Results
{final outcomes}
EOF

# Update session.json status
jq '.status = "completed" | .completed_at = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' \
  $SESSION_DIR/session.json > $SESSION_DIR/session.json.tmp
mv $SESSION_DIR/session.json.tmp $SESSION_DIR/session.json

# Display location
echo "✅ Session logged: $SESSION_DIR"
```
```

## Error Handling

On workflow error:

```bash
# Log error
jq '.status = "failed" | .errors += [{
  "message": "'$ERROR_MSG'",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}]' $SESSION_DIR/session.json > $SESSION_DIR/session.json.tmp
mv $SESSION_DIR/session.json.tmp $SESSION_DIR/session.json

echo "❌ Workflow failed. See $SESSION_DIR for details."
```

## Implementation Checklist

To add session logging to a workflow command:

- [ ] Add session initialization at start
- [ ] Track artifacts as they're created
- [ ] Handle errors with logging
- [ ] Create summary at end
- [ ] Support `--parent-session-dir` parameter for subagent mode
- [ ] Test both standalone and subagent modes

## Notes

- **Lightweight**: Use simple bash, no heavy dependencies
- **Human-readable**: Markdown and JSON for easy reading
- **Machine-parseable**: session.json enables programmatic analysis
- **Isolated**: Each session is self-contained
- **Optional**: Logging can be disabled with `--no-logging` flag
