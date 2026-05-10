#!/usr/bin/env bash
# Reconcile .claude/canvases/*/ on disk against .claude/sdlc.yml's canvases:
# block, and emit a compact one-line-per-canvas table. Designed to be safe
# inside `!`-injected pre-rendered context blocks at agent launch.
#
# Output columns: NAME  VERSION  PATH  STATUS
#   STATUS = "registered" | "unregistered ⚠"
#
# Usage:  bash scripts/list-canvases.sh
# Exit:   0 = always (this is a read-only projection, not a verifier).
#         Run scripts/verify-canvases.sh for schema validation.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SDLC="$PROJECT_ROOT/.claude/sdlc.yml"
CANVASES_DIR="$PLUGIN_ROOT/canvases"

if ! command -v yq >/dev/null 2>&1; then
  echo "yq not installed (brew install yq) — can't read sdlc.yml" >&2
  exit 0
fi

# Collect names registered in sdlc.yml.canvases (last-block wins per YAML).
registered="$(yq -r '.canvases | keys | .[]' "$SDLC" 2>/dev/null | sort -u || true)"

shopt -s nullglob
rows=()
for dir in "$CANVASES_DIR"/*/; do
  name="$(basename "$dir")"
  inst="$dir/instructions.yaml"
  if [[ ! -f "$inst" ]]; then
    rows+=("$name|—|$dir|no instructions.yaml ⚠")
    continue
  fi
  version="$(yq -r '.version // "?"' "$inst" 2>/dev/null || echo "?")"
  if echo "$registered" | grep -qx "$name"; then
    status="registered"
  else
    status="unregistered ⚠"
  fi
  rows+=("$name|v$version|plugin/canvases/$name/|$status")
done

# Render. Use column if available for alignment; otherwise raw pipe-separated.
if command -v column >/dev/null 2>&1; then
  printf '%s\n' "NAME|VERSION|PATH|STATUS" "${rows[@]}" | column -t -s '|'
else
  printf '%-20s %-8s %-40s %s\n' "NAME" "VERSION" "PATH" "STATUS"
  for row in "${rows[@]}"; do
    IFS='|' read -r n v p s <<<"$row"
    printf '%-20s %-8s %-40s %s\n' "$n" "$v" "$p" "$s"
  done
fi
