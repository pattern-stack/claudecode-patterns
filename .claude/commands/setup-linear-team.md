# Setup Linear Team

Guide user through setting up a new Linear team for autonomous development workflow.

## Purpose

Interactive guide for creating and configuring a new Linear team with workflow states, labels, and tp CLI integration.

## Prerequisites

- Linear workspace with admin access
- tp CLI installed and authenticated
- Project repository initialized

## Instructions

1. **Read the setup documentation**:
   - Read `.claude/docs/LINEAR_TEAM_SETUP.md` for detailed steps
   - Read `.claude/docs/LINEAR_SETUP_CHECKLIST.md` for quick reference

2. **Guide the user interactively**:
   - Ask for their project details (Project Name, Team Key, Team Name)
   - Walk through each setup step:
     - Team creation (via `tp team create` or template)
     - Workflow state configuration (Linear Web UI)
     - Label creation (via setup script)
     - tp CLI configuration
     - GitHub integration
     - Verification

3. **Execute commands as needed**:
   - Run `tp team create` commands with user's values
   - Execute the label setup script
   - Run verification commands
   - Help troubleshoot any issues

4. **Provide next steps**:
   - Show how to create their first epic
   - Explain the autonomous workflow
   - Reference workflow documentation

## Key Resources

- Detailed guide: `.claude/docs/LINEAR_TEAM_SETUP.md`
- Quick checklist: `.claude/docs/LINEAR_SETUP_CHECKLIST.md`
- Label setup script: `.claude/scripts/setup-linear-labels.sh`
- Bootstrap plan: `BOOTSTRAP-PLAN.md`

## Note

Keep the interaction conversational and helpful. The docs contain all the technical details - your job is to guide the user through them smoothly and execute commands on their behalf.
