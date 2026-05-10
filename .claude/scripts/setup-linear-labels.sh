#!/bin/bash
# Linear Label Setup Script for New Team
# Usage: ./setup-linear-labels.sh TEAM_KEY
#
# This script creates all labels defined in BOOTSTRAP-PLAN.md
# Run this ONCE after creating your team in Linear Web UI

set -e

TEAM_KEY="${1:-DEAL}"

echo "Creating labels for team: $TEAM_KEY"
echo "======================================="

# Issue Structure Labels
echo ""
echo "Creating Issue Structure labels..."
tp labels create "issue" \
  --description "Regular standalone issue" \
  --team "$TEAM_KEY" || echo "  ✓ issue (already exists)"

tp labels create "subissue" \
  --description "Child of an epic" \
  --team "$TEAM_KEY" || echo "  ✓ subissue (already exists)"

tp labels create "epic" \
  --description "Parent container with children" \
  --team "$TEAM_KEY" || echo "  ✓ epic (already exists)"

# Issue Type Labels
echo ""
echo "Creating Issue Type labels..."
tp labels create "issue-type:bug" \
  --description "Bug fixes and corrections" \
  --team "$TEAM_KEY" || echo "  ✓ issue-type:bug (already exists)"

tp labels create "issue-type:chore" \
  --description "Maintenance and tooling" \
  --team "$TEAM_KEY" || echo "  ✓ issue-type:chore (already exists)"

tp labels create "issue-type:documentation" \
  --description "Documentation updates" \
  --team "$TEAM_KEY" || echo "  ✓ issue-type:documentation (already exists)"

# Work Labels
echo ""
echo "Creating Work labels..."
tp labels create "work:architecture" \
  --description "Architecture and design work" \
  --team "$TEAM_KEY" || echo "  ✓ work:architecture (already exists)"

tp labels create "work:infrastructure" \
  --description "Infrastructure and setup" \
  --team "$TEAM_KEY" || echo "  ✓ work:infrastructure (already exists)"

tp labels create "work:feature" \
  --description "New feature implementation" \
  --team "$TEAM_KEY" || echo "  ✓ work:feature (already exists)"

tp labels create "work:enhancement" \
  --description "Enhancement to existing feature" \
  --team "$TEAM_KEY" || echo "  ✓ work:enhancement (already exists)"

tp labels create "work:bugfix" \
  --description "Bug fix implementation" \
  --team "$TEAM_KEY" || echo "  ✓ work:bugfix (already exists)"

# Stack Labels
echo ""
echo "Creating Stack labels..."
tp labels create "stack:backend" \
  --description "Backend work (Python, FastAPI, database)" \
  --team "$TEAM_KEY" || echo "  ✓ stack:backend (already exists)"

tp labels create "stack:frontend" \
  --description "Frontend work (React, TypeScript, UI)" \
  --team "$TEAM_KEY" || echo "  ✓ stack:frontend (already exists)"

tp labels create "stack:fullstack" \
  --description "Work spanning both backend and frontend" \
  --team "$TEAM_KEY" || echo "  ✓ stack:fullstack (already exists)"

# Layer Labels (Pattern Stack Architecture)
echo ""
echo "Creating Layer labels (Pattern Stack)..."
tp labels create "layer:atoms" \
  --description "Atoms layer - Domain-agnostic utilities" \
  --team "$TEAM_KEY" || echo "  ✓ layer:atoms (already exists)"

tp labels create "layer:features" \
  --description "Features layer - Data services (CRUD)" \
  --team "$TEAM_KEY" || echo "  ✓ layer:features (already exists)"

tp labels create "layer:molecules" \
  --description "Molecules layer - Business logic and orchestration" \
  --team "$TEAM_KEY" || echo "  ✓ layer:molecules (already exists)"

tp labels create "layer:organisms" \
  --description "Organisms layer - User interfaces (APIs, CLI)" \
  --team "$TEAM_KEY" || echo "  ✓ layer:organisms (already exists)"

# State Labels (Workflow Metadata)
echo ""
echo "Creating State labels (workflow metadata)..."
tp labels create "state:awaiting-strategy-review" \
  --description "Strategy posted, waiting for human approval" \
  --team "$TEAM_KEY" || echo "  ✓ state:awaiting-strategy-review (already exists)"

tp labels create "state:strategy-approved" \
  --description "Strategy approved, ready for spec generation" \
  --team "$TEAM_KEY" || echo "  ✓ state:strategy-approved (already exists)"

tp labels create "state:blocked" \
  --description "Blocked by external dependency or decision" \
  --team "$TEAM_KEY" || echo "  ✓ state:blocked (already exists)"

tp labels create "state:needs-clarification" \
  --description "Requires clarification before proceeding" \
  --team "$TEAM_KEY" || echo "  ✓ state:needs-clarification (already exists)"

# Priority Labels
echo ""
echo "Creating Priority labels..."
tp labels create "priority:critical" \
  --description "Critical priority - immediate attention" \
  --team "$TEAM_KEY" || echo "  ✓ priority:critical (already exists)"

tp labels create "priority:high" \
  --description "High priority" \
  --team "$TEAM_KEY" || echo "  ✓ priority:high (already exists)"

tp labels create "priority:medium" \
  --description "Medium priority" \
  --team "$TEAM_KEY" || echo "  ✓ priority:medium (already exists)"

tp labels create "priority:low" \
  --description "Low priority" \
  --team "$TEAM_KEY" || echo "  ✓ priority:low (already exists)"

echo ""
echo "======================================="
echo "✓ Label setup complete for team: $TEAM_KEY"
echo ""
echo "Verify labels with:"
echo "  tp labels list --team $TEAM_KEY"
