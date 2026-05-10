#!/bin/bash
# validate-env.sh
# Validates .env file exists and contains required variables
#
# Usage: source .claude/commands/lib/validate-env.sh || exit 1
#
# This script:
# 1. Checks that .env file exists
# 2. Sources .env to make variables available
# 3. Validates all required variables are set
# 4. Provides actionable error messages if validation fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
  echo -e "${RED}ERROR: .env file not found${NC}"
  echo ""
  echo "Create from template:"
  echo "  cp .env.example .env"
  echo "  # Edit .env with your values"
  echo ""
  echo "Location: $(pwd)/.env"
  exit 1
fi

# Source .env to load variables
source .env

# Define required variables (Linear keys are optional - will use global env)
REQUIRED_VARS=(
  "GITHUB_ORG"
  "GITHUB_REPO"
  "GITHUB_BASE_BRANCH"
  "PROJECT_NAME"
  "PROJECT_TEAM_KEY"
  "PROJECT_STACK"
  "COMMIT_FORMAT"
  "BRANCH_PREFIX_FEATURE"
  "BRANCH_PREFIX_BUG"
  "BRANCH_PREFIX_CHORE"
  "BRANCH_PREFIX_EPIC"
)

# Optional variables (show warnings if not set locally)
OPTIONAL_VARS=(
  "LINEAR_API_KEY"
  "LINEAR_TEAM_ID"
  "LINEAR_ORG_ID"
)

# Validate each required variable is set and non-empty
MISSING_VARS=()
EMPTY_VARS=()

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR+x}" ]; then
    # Variable is not set
    MISSING_VARS+=("$VAR")
  elif [ -z "${!VAR}" ]; then
    # Variable is set but empty (still a problem)
    EMPTY_VARS+=("$VAR")
  fi
done

# Check optional variables and show warnings
OPTIONAL_WARNINGS=()
for VAR in "${OPTIONAL_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    OPTIONAL_WARNINGS+=("$VAR")
  fi
done

# Report any missing or empty required variables
if [ ${#MISSING_VARS[@]} -gt 0 ] || [ ${#EMPTY_VARS[@]} -gt 0 ]; then
  echo -e "${RED}ERROR: .env validation failed${NC}"
  echo ""

  if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "Missing required variables:"
    for VAR in "${MISSING_VARS[@]}"; do
      echo "  - $VAR"
    done
    echo ""
  fi

  if [ ${#EMPTY_VARS[@]} -gt 0 ]; then
    echo "Variables set but empty:"
    for VAR in "${EMPTY_VARS[@]}"; do
      echo "  - $VAR"
    done
    echo ""
  fi

  echo "See .env.example for reference:"
  echo "  cat .env.example"
  exit 1
fi

# Warn about missing optional variables
if [ ${#OPTIONAL_WARNINGS[@]} -gt 0 ]; then
  echo -e "${YELLOW}WARNING: Optional Linear integration keys not set:${NC}"
  for VAR in "${OPTIONAL_WARNINGS[@]}"; do
    echo "  - $VAR"
  done
  echo ""
  echo -e "${YELLOW}Commands will use global environment variables or tp CLI global config.${NC}"
  echo -e "${YELLOW}Set these in .env to override global configuration.${NC}"
  echo ""
fi

# Success - variables are now available in calling script
echo -e "${GREEN}Configuration validated${NC}"
