# Justfile — repo root
#
# Plugin recipes (verify, canvases, canvas-dev,
# canvas-seller, etc.) come from the `sdlc`
# plugin via the `mod` directive below. They
# invoke as `just sdlc::<recipe>` (e.g.
# `just sdlc::verify`).
#
# After `/plugin install sdlc`, run
# `/sdlc:setup` to scaffold this Justfile in
# a fresh project. This file IS the dogfood
# version, eating our own setup.

default:
    @just --list

# Launch Claude Code with this repo's plugin
# loaded directly from the working tree (no
# install, no symlinks). Edits to plugin/
# files surface live; run `/reload-plugins`
# inside the session to pick them up without
# restart. Per claude-platform docs:
# --plugin-dir overrides any same-name
# marketplace install for the session, so
# dogfooding here doesn't conflict with users
# who installed `sdlc` via `/plugin install`.
dev:
    claude --plugin-dir ./plugin

# Plugin-supplied recipes — namespaced under
# `sdlc::`. `.claude/sdlc.justfile` is a
# symlink → `${CLAUDE_PLUGIN_DIR}/sdlc.justfile`
# created by /sdlc:setup (and committed in
# this repo for dogfooding).
mod sdlc '.claude/sdlc.justfile'
