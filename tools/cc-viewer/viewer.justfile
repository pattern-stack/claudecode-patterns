# cc-viewer recipes — invoked as `just viewer::<name>` from the repo root.

# Install workspace deps (idempotent).
install:
    cd tools/cc-viewer && bun install

# Vite + Bun dev loop. SPA on :5173 with API proxied to the Bun server
# on :3993 (configured in tools/cc-viewer/viewer/vite.config.ts).
dev:
    #!/usr/bin/env bash
    set -euo pipefail
    cd tools/cc-viewer
    bun run dev:server & SERVER=$!
    trap "kill $SERVER 2>/dev/null" EXIT
    bun run dev:viewer

# Typecheck both workspaces (server + viewer).
typecheck:
    cd tools/cc-viewer && bun run typecheck

# Produce a native single-file binary at tools/cc-viewer/build/cc-viewer-<platform>.
# Pass a target explicitly to cross-compile:
#   just viewer::build linux-x64
build target='':
    cd tools/cc-viewer && bash scripts/build-binary.sh {{target}}

# Wipe local build artifacts.
clean:
    rm -rf tools/cc-viewer/build tools/cc-viewer/viewer/dist
