#!/usr/bin/env bash
#
# write-stub-bundle.sh — write an empty static-bundle.ts stub if missing.
#
# Run from any cwd. Idempotent: if a file already exists, leaves it alone
# (codegen-static.ts emits a much larger module that includes the stub's
# exports). Called from `prepare` so dev / typecheck work without first
# running a full SPA build.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/server/src/static-bundle.ts"

[[ -f "$TARGET" ]] && exit 0

cat > "$TARGET" <<'EOF'
// AUTO-GENERATED stub — overwritten by scripts/codegen-static.ts at build time.
// Empty bundle = no SPA served from Hono; useful for dev (vite serves SPA on
// its own port) and for typecheck on a fresh checkout.

export interface StaticEntry {
  readonly path: string;
  readonly mime: string;
}

export const STATIC_BUNDLE: Readonly<Record<string, StaticEntry>> = {};

export const SPA_FALLBACK: StaticEntry | undefined = undefined;
EOF
