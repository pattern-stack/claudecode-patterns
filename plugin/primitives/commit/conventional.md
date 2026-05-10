---
type: primitive
category: commit
value: conventional
status: active
description: Conventional Commits 1.0 message format with issue-key scope.
---

# Conventional Commits Primitive

Commit message format for this repo. Mirrors the Conventional Commits 1.0 spec.

## Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | When to use |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Maintenance (deps, config, tooling) |
| `ci` | CI/CD changes |
| `style` | Formatting only, no code change |

## Scope

Use the package, app, or area affected. For Linear-tracked work, prefer the issue key as scope:

```
feat(ap-12): add task-management Linear adapter
fix(rfc-0004): clarify Gate 1 mechanics
chore(infra): bump process-compose to 1.7
```

`(scope)` may be omitted when the change is repo-wide.

## Body

Explain *why*, not *what* — the diff already shows what. One paragraph max for routine work.

## Strategy implications

When planning commits:
- One type per commit (don't mix `feat` + `fix`).
- Group related changes; split unrelated ones.
- Linear issue key as scope when work is tracked — auto-links the commit to the issue in Linear's UI.
- Branch convention pairs with this: `dugshub/<slug>` (or `dugshub/<stack>/N-<desc>` when stacked via `st`).
