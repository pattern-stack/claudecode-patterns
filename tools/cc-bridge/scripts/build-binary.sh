#!/usr/bin/env bash
#
# build-binary.sh — produce a single-file `cc-bridge-<platform>` binary.
#
# Unlike cc-viewer, there's no SPA to bundle. One step: bun build --compile.
#
# Usage:
#   ./scripts/build-binary.sh                  # native target (auto-detect)
#   ./scripts/build-binary.sh darwin-arm64     # explicit target
#
# Bun targets:
#   bun-darwin-arm64  bun-darwin-x64
#   bun-linux-x64     bun-linux-arm64
#   bun-windows-x64

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
OUT="build/cc-bridge-${TARGET}"

mkdir -p build

echo "  bun build --compile --target=${BUN_TARGET}"
bun build \
  --compile \
  --minify \
  --sourcemap=none \
  --target="${BUN_TARGET}" \
  src/index.ts \
  --outfile "${OUT}"

echo ""
echo "  done -> ${ROOT}/${OUT}"
ls -lh "${OUT}"
