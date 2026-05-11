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
    @just --list --list-submodules

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

# Remove stale Claude Code agent worktrees under
# .claude/worktrees/. Refuses to remove worktrees
# with uncommitted changes (use `git worktree
# remove --force <path>` manually for those, after
# inspecting). Runs `git worktree prune` at the
# end to drop registry entries for already-deleted
# dirs.
clean-worktrees:
    #!/usr/bin/env bash
    set -euo pipefail
    paths=$(git worktree list --porcelain | awk '/^worktree.*\.claude\/worktrees\// {print $2}')
    if [[ -z "$paths" ]]; then
      echo "No worktrees under .claude/worktrees/ to clean."
      git worktree prune
      exit 0
    fi
    while IFS= read -r path; do
      echo "→ $path"
      if git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet && [[ -z $(git -C "$path" status --porcelain) ]]; then
        git worktree remove "$path" && echo "  removed"
      else
        echo "  SKIPPED — has uncommitted changes (run \`git worktree remove --force '$path'\` to force)"
      fi
    done <<< "$paths"
    git worktree prune
    echo "done."

# Plugin-supplied recipes — namespaced under
# `sdlc::`. `.claude/sdlc.justfile` is a
# symlink → `${CLAUDE_PLUGIN_DIR}/sdlc.justfile`
# created by /sdlc:setup (and committed in
# this repo for dogfooding).
mod sdlc '.claude/sdlc.justfile'
