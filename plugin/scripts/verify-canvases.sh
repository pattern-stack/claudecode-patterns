#!/usr/bin/env bash
# Verify every canvas's instructions.yaml validates against its sibling
# instructions.schema.json (JSON Schema, draft-07 / 2020-12).
#
# Scans BOTH plugin canvases (the defaults) and project canvases (overrides).
# Project canvases at ${CLAUDE_PROJECT_DIR}/.claude/canvases/<name>/ override
# plugin canvases at ${CLAUDE_PLUGIN_DIR}/canvases/<name>/ via fork-on-edit.
# Each canvas is validated independently — overrides are not merged.
#
# Usage:  just sdlc::verify-canvases   (or bash plugin/scripts/verify-canvases.sh)
# Exit:   0 = all OK, 1 = validation failure(s), 2 = config / tooling error
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PLUGIN_CANVASES="$PLUGIN_ROOT/canvases"
PROJECT_CANVASES="$PROJECT_ROOT/.claude/canvases"

# Build the scan list. Skip project canvases dir if it's a symlink resolving to
# the plugin's canvases (dogfood case — same files, no point scanning twice).
SCAN_DIRS=()
[[ -d "$PLUGIN_CANVASES" ]] && SCAN_DIRS+=("$PLUGIN_CANVASES")
if [[ -d "$PROJECT_CANVASES" ]]; then
  if [[ -L "$PROJECT_CANVASES" ]] && [[ "$(readlink -f "$PROJECT_CANVASES")" == "$(readlink -f "$PLUGIN_CANVASES")" ]]; then
    : # symlink → plugin; already covered
  else
    SCAN_DIRS+=("$PROJECT_CANVASES")
  fi
fi

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  echo "ℹ️  No canvases found at $PLUGIN_CANVASES or $PROJECT_CANVASES — nothing to verify"
  echo "Checked: 0  Skipped: 0  Errors: 0"
  exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "❌ yq not installed (brew install yq)" >&2
  exit 2
fi
if ! command -v bunx >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  echo "❌ neither bunx nor npx available — needed to run ajv-cli" >&2
  exit 2
fi

# Pick a runner for ajv-cli. Prefer bunx (project standard), fall back to npx.
# Note: do NOT pass --bun — that makes bun treat the data file as code to build.
if command -v bunx >/dev/null 2>&1; then
  RUNNER=(bunx ajv-cli)
else
  RUNNER=(npx --yes ajv-cli)
fi

# Detect ajv --spec flag from a schema's $schema URI.
# Falls back to draft7 (the most permissive default in ajv-cli v5).
detect_spec() {
  local schema="$1"
  local uri
  uri="$(yq -r '."$schema" // ""' "$schema" 2>/dev/null || true)"
  case "$uri" in
    *2020-12*) echo "draft2020" ;;
    *2019-09*) echo "draft2019" ;;
    *draft-07*|*draft-7*|"") echo "draft7" ;;
    *) echo "draft7" ;;
  esac
}

# Per-run temp dir (auto-cleaned on exit). Files inside keep a real `.json`
# extension so ajv-cli routes them to its JSON parser.
TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

errors=0
checked=0
skipped=0

# Iterate every artifact directory that has an instructions.yaml across all
# scanned canvas roots (plugin + project overrides).
shopt -s nullglob
INSTRUCTIONS=()
for d in "${SCAN_DIRS[@]}"; do
  for f in "$d"/*/instructions.yaml; do
    INSTRUCTIONS+=("$f")
  done
done
for inst in "${INSTRUCTIONS[@]}"; do
  dir="$(dirname "$inst")"
  name="$(basename "$dir")"
  schema="$dir/instructions.schema.json"

  if [[ ! -f "$schema" ]]; then
    echo "⚠️  $name: no instructions.schema.json — skipping"
    ((skipped+=1))
    continue
  fi

  # Convert YAML to JSON for ajv. Filename must end in .json so ajv-cli parses it correctly.
  json="$TMPDIR_RUN/$name.instructions.json"
  if ! yq -o=json '.' "$inst" >"$json" 2>/dev/null; then
    echo "❌ $name: instructions.yaml is not valid YAML"
    ((errors+=1)) || true
    continue
  fi

  # Validate. ajv-cli exits non-zero on validation failure; capture output either way.
  # Pick --spec from the schema's declared $schema so draft-07 / 2020-12 each get
  # their proper meta-schema.
  spec="$(detect_spec "$schema")"
  output="$("${RUNNER[@]}" validate \
              --spec="$spec" \
              --strict=false \
              -s "$schema" \
              -d "$json" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    echo "✅ $name"
    ((checked+=1))
  else
    echo "❌ $name: validation failed"
    echo "$output" | sed 's/^/     /' | head -20
    ((errors+=1)) || true
  fi
done

echo ""
echo "Checked: $checked  Skipped: $skipped  Errors: $errors"
[[ "$errors" -eq 0 ]] || exit 1
