#!/usr/bin/env bash
# bootstrap.sh — provision the SDLC label palette in the active tracker.
# Colocated with the task-management primitive (port + adapter docs).
#
# Idempotent: re-running is safe (existing labels are skipped, not overwritten).
# Reads task_management from .claude/sdlc.yml; halts if Linear/Jira (only github
# is supported today — those vendors have native equivalents or different setup).
#
# Provisioned labels (see plugin/primitives/task-management/github.md for the
# rationale per group):
#   state:planned                 — synced from plan; not yet started
#   state:awaiting-strategy-review — strict-mode specifier posted strategy
#   state:strategy-approved        — Gate-1 satisfied (human-set OR auto-mode)
#   state:blocked                  — coordinator self-blocked on Gate-1 timeout
#   gate:auto                      — issue is in auto-approve mode
#   gate:human                     — issue forces strict mode (overrides plan)
#
# Usage:  bash plugin/primitives/task-management/bootstrap.sh
# Exit:   0 = OK, 1 = vendor unsupported, 2 = config error / missing tooling
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SDLC="$PROJECT_ROOT/.claude/sdlc.yml"

if [[ ! -f "$SDLC" ]]; then
  echo "❌ Missing $SDLC — run /sdlc:setup first" >&2
  exit 2
fi
if ! command -v yq >/dev/null 2>&1; then
  echo "❌ yq not installed (brew install yq)" >&2
  exit 2
fi

TM="$(yq -r '.task_management // ""' "$SDLC")"
case "$TM" in
  github) ;;
  linear|jira)
    echo "ℹ️  task_management=$TM — bootstrap.sh is github-only today."
    echo "   Linear: gate semantics live in workflow states; provision via Linear UI."
    echo "   Jira: similar — use Jira project workflow."
    exit 1
    ;;
  *)
    echo "❌ Unknown task_management='$TM' in $SDLC" >&2
    exit 2
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh CLI not installed" >&2
  exit 2
fi

# Ensure we're authenticated against the right repo
REPO="$(yq -r '.repo // ""' "$SDLC")"
if [[ -z "$REPO" ]]; then
  echo "❌ Missing 'repo:' in $SDLC (required for task_management: github)" >&2
  exit 2
fi

# Provision a label idempotently. gh label create returns non-zero if the label
# exists; we swallow that and report = (existed) vs + (created).
provision() {
  local name="$1"
  local color="$2"
  local desc="$3"
  if gh -R "$REPO" label create "$name" --color "$color" --description "$desc" >/dev/null 2>&1; then
    echo "  + $name"
  else
    echo "  = $name (exists)"
  fi
}

echo "Provisioning SDLC labels in $REPO..."
echo ""
echo "state:* (lifecycle):"
provision "state:planned"                  "CFD3D7" "Synced from plan; not yet started"
provision "state:awaiting-strategy-review" "FBCA04" "Strict-mode specifier posted strategy; awaiting human Gate-1 approval"
provision "state:strategy-approved"        "0E8A16" "Gate-1 satisfied (human-set or auto-mode)"
provision "state:blocked"                  "B60205" "Coordinator self-blocked on Gate-1 timeout"

echo ""
echo "gate:* (Gate-1 mode override):"
provision "gate:auto"                      "0E8A16" "Issue is in auto-approve mode (Gate 1 satisfied by specifier without human review)"
provision "gate:human"                     "B60205" "Issue requires human Gate 1 review (overrides plan auto_approve default)"

echo ""
echo "Done. To override gate mode per-issue, apply gate:auto or gate:human."
echo "Per-stack defaults live in plan.yaml (auto_approve: true|false)."
echo "Project-wide default is sdlc.yml.gate1_default."
