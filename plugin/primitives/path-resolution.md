---
type: primitive-port
category: meta
status: active
description: Resolution rule for plugin-shipped overridable resources (canvases, primitives). Agents resolve project-first, then fall back to the plugin default.
---

# Path Resolution — fork-on-edit semantics

After the plugin install, two locations exist for canvases and primitives:

| Resource | Project (override) | Plugin (default) |
|---|---|---|
| Canvas | `.claude/canvases/<name>/` | `${CLAUDE_PLUGIN_DIR}/canvases/<name>/` |
| Primitive | `.claude/primitives/<category>/<name>.md` | `${CLAUDE_PLUGIN_DIR}/primitives/<category>/<name>.md` |

## Rule

**Project wins.** When an agent reads a canvas or primitive, it tries the project path first; if absent, it falls back to the plugin path. Each canvas / primitive file is independent — overrides aren't merged.

## Lifecycle

- Plugin install lays down defaults at `${CLAUDE_PLUGIN_DIR}/...`.
- User keeps `.claude/sdlc.yml` (project config) at the project path.
- `canvas-author` writes to the project path on edit (fork-on-edit). Once a canvas is forked, future reads see the project version.
- To revert to the plugin default, delete the project copy.

## Dogfood note

In this repo, `.claude/canvases/` and `.claude/primitives/` are **symlinks** → `../plugin/canvases/` and `../plugin/primitives/`. There is effectively no override layer in dogfood — both paths point to the same files. End-user installs without overrides will read from `${CLAUDE_PLUGIN_DIR}/...` directly.

## Agent-prompt convention

Agent prompts may reference `.claude/canvases/<name>/template.md` and similar paths informationally. At runtime, agents resolve via the rule above. PR 2+ of the `sdlc-plugin-distribution` stack rewrites prose references in specific agents as those files are touched — PR 1 ships the rule; subsequent PRs apply it.

## Out of scope

- Merging project + plugin canvas instructions (e.g. inheriting knob defaults). Future v2 concern.
- Project-level primitive composition. Today, project primitive files fully replace plugin ones.
