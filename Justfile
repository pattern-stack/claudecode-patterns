# Justfile — repo root
#
# Plugin recipes (verify, canvases, canvas-dev, canvas-seller, etc.) come from
# the `sdlc` plugin via the `mod` directive below. They invoke as
# `just sdlc::<recipe>` (e.g. `just sdlc::verify`).
#
# After `/plugin install sdlc`, run `/sdlc:setup` to scaffold this Justfile in
# a fresh project. This file IS the dogfood version, eating our own setup.

default:
    @just --list

# Plugin-supplied recipes — namespaced under `sdlc::`.
# `.claude/sdlc.justfile` is a symlink → `${CLAUDE_PLUGIN_DIR}/sdlc.justfile`
# created by /sdlc:setup (and committed in this repo for dogfooding).
mod sdlc '.claude/sdlc.justfile'
