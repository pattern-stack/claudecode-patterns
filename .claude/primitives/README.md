---
type: index
for: primitives
description: Index and conventions for the primitives directory.
---

# Primitives

Configurable context loaded by skills, commands, and agents based on `.claude/sdlc.yml`.

## Categories

| Category | Values | Purpose |
|---|---|---|
| `language/` | `typescript.md` | Toolchain, file patterns, conventions |
| `quality/` | `strict.md`, `fast.md` | Gates that must pass before merge |
| `commit/` | `conventional.md` | Commit message format |
| `task-management/` | `linear.md`, `github.md` | Tracker adapter — labels, gates, CLI |

## Resolution order

Agents resolve primitive values in this order:

1. Explicit argument or issue label (e.g. `stack:backend` → `language: backend`)
2. `.claude/sdlc.yml` project default
3. Hardcoded fallback in the primitive's own README

Agents read the resolved primitive file directly from `.claude/primitives/<category>/<value>.md` — primitives are the contract, not the agents.

## Frontmatter

Each primitive file starts with a frontmatter block for tooling and introspection:

```yaml
---
type: primitive
category: <commit | language | quality | task-management>
value: <filename without extension>
description: <one-line summary, used by tooling>
---
```

## Adding a primitive

New values land as new files in the matching directory. Agents reference them by `{value}` interpolation, so the filename is the API. Keep file shape consistent within a category — diverging shapes break agent prompts that grep across multiple values.

When a category gets a second backend (e.g. `task-management/github.md` joining `linear.md`), extract the shared contract into `<category>/README.md` and shrink the per-backend files to just the binding details.
