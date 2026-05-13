#!/usr/bin/env bash
#
# build-binary.sh — produce a single-file `cc-viewer-<platform>` binary.
#
# Steps:
#   1. vite build               -> tools/cc-viewer/viewer/dist/
#   2. codegen-static.ts        -> tools/cc-viewer/server/src/static-bundle.ts
#   3. bun build --compile      -> tools/cc-viewer/build/cc-viewer-<platform>
#
# Usage:
#   ./scripts/build-binary.sh                  # native target (auto-detect)
#   ./scripts/build-binary.sh darwin-arm64     # explicit target
#
# Bun targets:
#   bun-darwin-arm64  bun-darwin-x64
#   bun-linux-x64     bun-linux-arm64
#   bun-windows-x64
#
# Always restores the static-bundle stub on exit so the working tree stays
# clean and typecheck still works without rebuilding.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH=x64 ;;
    aarch64|arm64) ARCH=arm64 ;;
  esac
  TARGET="${OS}-${ARCH}"
fi
BUN_TARGET="bun-${TARGET}"
OUT="build/cc-viewer-${TARGET}"

mkdir -p build

cleanup() {
  # Restore stub so generated import statements don't leak into a clean tree.
  rm -f server/src/static-bundle.ts
  bash scripts/write-stub-bundle.sh
}
trap cleanup EXIT

echo "  [1/3] vite build"
(cd viewer && bun run build >/dev/null)

echo "  [2/3] codegen-static.ts"
bun scripts/codegen-static.ts

echo "  [3/3] bun build --compile --target=${BUN_TARGET}"
bun build \
  --compile \
  --minify \
  --sourcemap=none \
  --target="${BUN_TARGET}" \
  server/src/index.ts \
  --outfile "${OUT}"

echo ""
echo "  done -> ${ROOT}/${OUT}"
ls -lh "${OUT}"
