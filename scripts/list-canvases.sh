#!/usr/bin/env bash
# Reconcile .claude/artifacts/*/ on disk against .claude/sdlc.yml's artifacts:
# block, and emit a compact one-line-per-canvas table. Designed to be safe
# inside `!`-injected pre-rendered context blocks at agent launch.
#
# Output columns: NAME  VERSION  PATH  STATUS
#   STATUS = "registered" | "unregistered ⚠"
#
# Usage:  bash scripts/list-canvases.sh
# Exit:   0 = always (this is a read-only projection, not a verifier).
#         Run scripts/verify-artifacts.sh for schema validation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDLC="$ROOT/.claude/sdlc.yml"
ARTIFACTS_DIR="$ROOT/.claude/artifacts"

if ! command -v yq >/dev/null 2>&1; then
  echo "yq not installed (brew install yq) — can't read sdlc.yml" >&2
  exit 0
fi

# Collect names registered in sdlc.yml.artifacts (last-block wins per YAML).
registered="$(yq -r '.artifacts | keys | .[]' "$SDLC" 2>/dev/null | sort -u || true)"

shopt -s nullglob
rows=()
for dir in "$ARTIFACTS_DIR"/*/; do
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
  rows+=("$name|v$version|.claude/artifacts/$name/|$status")
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
