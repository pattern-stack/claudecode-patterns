---
description: Create Linear epic + sub-issues from YAML/JSON
argument-hint: <definition-file> [--team=KEY] [--dry-run]
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
---

# Create Issues from Definition

Create a Linear epic with sub-issues from a structured YAML/JSON definition file.

## Purpose

Automates the mechanical work of creating Linear issues from a decomposed plan. Separates issue **creation** (mechanical) from issue **planning** (strategic).

## Usage

```bash
/plan:2-create-issues issue-plan-user-auth.yaml
/plan:2-create-issues issue-plan-caching.yaml --team TEMPO
/plan:2-create-issues my-epic.yaml --dry-run
```

## Variables

- `$1`: Path to definition file (YAML or JSON)
- `--team=<KEY>`: Team to create issues in (optional, defaults to .env PROJECT_TEAM_KEY)
- `--dry-run`: Show what would be created without making API calls

## Prerequisites

Validates .env configuration using validate-env.sh script:

```bash
source .claude/commands/lib/validate-env.sh || exit 1
```

This ensures:
- .env file exists
- Required variables are set (GITHUB_ORG, PROJECT_TEAM_KEY, etc.)
- Optional Linear keys show warnings if not configured

## Definition Format

```yaml
epic:
  title: "Epic: Feature name"
  description: "Multi-line epic description"
  labels: [Epic, stack:backend, work:feature]
  status: Ready  # Optional

  children:
    - title: "Sub-task 1: Component name"
      description: "Detailed description"
      labels: [type:task, stack:backend]
      status: Ready
```

## Workflow

### Step 1: Load Configuration

Read team from .env `PROJECT_TEAM_KEY` (or override with `--team` flag)
Validate team is set, exit if missing

### Step 2: Read and Validate Definition

Read YAML/JSON file
Validate structure has epic with title, description, children

Use task-patterns skill to validate labels exist in team

### Step 3: Dry Run Check

If `--dry-run` flag is set:
- Display what would be created (epic + children)
- Show labels that would be applied
- Exit without creating issues

### Step 4: Create Epic

Use task-patterns skill to create epic issue with:
- Title from YAML epic.title
- Description from YAML epic.description
- Labels from YAML epic.labels

Capture epic issue ID (e.g., TEMPO-100)

If epic has status field:
  Use task-patterns skill to update epic status

### Step 5: Create Children

For each child in epic.children:

1. Use task-patterns skill to create child issue with:
   - Title from child.title
   - Description from child.description with appended "Parent: {epic_id}"

2. Capture child issue ID

3. Use task-patterns skill to link child to epic parent

4. If child has labels:
   - Use task-patterns skill to add labels to child

5. If child has status:
   - Use task-patterns skill to update child status

Store all created child IDs in array

### Step 6: Report Results

Display summary:
```
✅ Created Epic: TEMPO-100 - "Epic: User Authentication"
✅ Created Children:
   - TEMPO-101 - "Implement JWT tokens"
   - TEMPO-102 - "Add password hashing"
   - TEMPO-103 - "Create login endpoint"

Next: /plan:3-generate-spec TEMPO-101
```

Generate JSON output:
```json
{
  "epic": "TEMPO-100",
  "children": ["TEMPO-101", "TEMPO-102", "TEMPO-103"]
}
```

## Error Handling

**Label Not Found**: Use task-patterns skill to list available labels, show missing labels
**Label Conflicts**: Log warning, apply first valid label, continue
**API Failures**: Log error, return partial results
**Missing Config**: Exit with error message

## Notes

- **Skill Delegation**: All tp commands delegated to task-patterns skill
- **Configuration**: Uses .env PROJECT_TEAM_KEY, overridable via --team flag
- **Team Agnostic**: Works with any Linear team
