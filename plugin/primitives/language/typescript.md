---
type: primitive
category: language
value: typescript
status: active
description: Toolchain, file patterns, and conventions for the TypeScript stack used in this repo (bun, ESM, layer-first hexagonal layout).
---

# TypeScript Language Primitive

Toolchain and conventions for the dugs-agents repo. ESM throughout, bun-only runtime, workspace layout under `packages/*/*` and `apps/*`.

## File patterns

- Source: `**/*.ts`, `**/*.tsx`
- Tests: `**/*.test.ts`, `**/*.test.tsx` (when configured)
- Config: `tsconfig.json`, `package.json`, `.tool-versions`

## Toolchain

| Tool | Command | Status |
|---|---|---|
| Typecheck | `bunx tsc --noEmit` | Active (root + per-package as added) |
| Format / Lint | — | Deferred (no biome/eslint configured yet) |
| Tests | — | Deferred (no vitest/bun:test configured yet) |
| Build | per-package `bun run build` | Per-package, when output is shipped |

When lint/test gates are added, update `quality/strict.md` to make them blocking.

## Conventions

- **`"type": "module"`** — ESM only, `nodenext` resolution.
- **`strict: true`, `noUncheckedIndexedAccess: true`** — non-negotiable.
- **No `any`** — use `unknown` + type guards or proper generics. No `as` to escape inference unless boundary-converting.
- **Bun, not npm/pnpm/yarn.** All scripts run via `bun` or `bunx`.
- **Workspace globs** — `apps/*`, `packages/*/*`. Layer-first hexagonal layout (see CLAUDE.md § Packages layout).
- **Package names** — `<unit>-<layer>` form, e.g. `@dugs-agents/pm-domain`, `@dugs-agents/linear-adapter`.

## Strategy considerations

When planning TypeScript work in this repo:
- Place new code by **architectural layer first**: `domain/<context>/`, `ports/`, `adapters/<vendor>/`, `surfaces/<context>/`, `expositions/<unit>/`.
- Cross-context utilities go in `framework/<piece>/` only after extraction is justified.
- Generated code (when `entities/` is in use) lands in `apps/backend/src/generated/` — never hand-edit; modify YAML or templates.
- Upstream-able fixes to `@agentic-patterns/*` or `@pattern-stack/codegen` belong in their source repos, linked locally via `just upstream-*`.
