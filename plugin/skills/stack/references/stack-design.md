# Designing a stack

How to decide what goes in each layer. Read this before running `gh stack init`.

## Plan the layers before writing code

A stack is a dependency chain: if code in one layer depends on code in another, the dependency must
live in the same branch or a lower one. That is far cheaper to satisfy by planning than by
restructuring later — there is no non-interactive in-place reorder, so fixing the order means
`unstack` and `init` again.

Decide the layers first, then write code into them:

```
(main) <- billing/schema <- billing/api <- billing/ui <- billing/integration
```

- `billing/schema` — shared types, migrations, schema
- `billing/api` — routes and services that use the schema
- `billing/ui` — components that call the routes
- `billing/integration` — tests exercising the whole feature

Illustrative only — infer the topic and layer names from the actual task.

The failure mode to avoid is writing everything on one branch and splitting it afterwards. If a task
is large enough to warrant a stack, create the stack at the start. (If you have already built the
monolith, that is a re-slice, not a design problem — collapse and re-slice by file manifest, then
adopt with `gh stack init b1 b2 …`.)

## The dependency order this project uses

For a typical full-stack feature, layers land in this order, bottom to top:

```
schema / migrations → shared types → domain logic → infrastructure
→ application services → presentation / API → frontend → wiring + tests
```

Two rules make the slices reviewable:

- **Disjoint files per branch.** A file edited in two layers guarantees conflicts on every cascade.
  When a file genuinely spans layers, the lower layer owns it and the upper layer extends it — never
  both editing the same region.
- **Defer DI / module wiring to the go-live layer.** Registering a service in the container from the
  layer that defines it makes every branch below it a behavior change. Bind a no-op (or leave it
  unregistered) and wire it in the last slice, so the stack stays dark until it is meant to be live.

## Branch naming

Prefer a shared topic prefix plus the layer's concern — `billing/schema`, `billing/api`,
`billing/ui`. This keeps related branches recognizable without generic names that could belong to
any stack. **Repository and user naming conventions take precedence; follow them instead.**

Names are used exactly as given — nothing is prepended or transformed, slashes are kept, so
`gh stack add refactor/foo` creates a branch literally named `refactor/foo`.

Passing `-m` without a branch name generates a date-and-slug name (`03-24-add_api_routes`). Prefer
naming the branch yourself.

## Staging changes deliberately

Use `git add` and `git commit` directly rather than the `add -Am` shortcut — the point is control
over which changes land in which branch. With several modified files in the tree, stage the subset
belonging to the current layer, commit it, then create the next branch and stage the rest there:

```bash
git add src/db/schema.ts src/db/migrations/0007_billing.sql
git commit -m "Add billing schema"

gh stack add billing/api
git add src/api/billing/*.ts
git commit -m "Add billing routes"
```

Multiple commits per branch are fine. What matters is that every commit in a branch serves the same
concern. Remember `gh stack add <branch>` without `-Am` does not touch the working tree — uncommitted
changes carry over, so commit or stash first if the new layer should start clean.

## When to add a layer

Add a branch when you start a **different concern that depends on what you have built so far**.
Signals:

- Moving from backend to frontend, or from core logic to tests or documentation
- The next changes have a different reviewer audience
- The current branch's diff is already large enough to review on its own

A layer that cannot be described in one sentence is usually two layers.

## One stack, one story

A stack should read as a coherent progression: a reviewer walks the PRs bottom to top and watches the
feature get built.

- **One stack** when every branch serves the same feature or project, even across different concerns.
- **A separate stack** for unrelated work — a different feature, an unrelated bug fix, an independent
  refactor. Don't mix efforts into one stack just because you worked on both. Stacks are strictly
  linear (one parent, at most one child), so parallel work *needs* its own stack.
- A trivial incidental fix can ride along. Once it grows into its own project, it deserves its own
  stack.

## New work goes ON the active stack

When a stack is checked out, new work lands on it — usually the top (`gh stack top` then
`gh stack add`) — not on a fresh trunk-based branch. "Logically independent" argues that placement is
*flexible*, not that the work belongs outside. A branch outside the stack is a loose end that
`submit`, `rebase`, `sync` and `merge` will not manage.
