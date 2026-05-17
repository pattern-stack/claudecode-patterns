---
name: design-audit
description: Audit shipped UI against a design spec — captures screenshots, grades against locked decisions and acceptance criteria, posts findings to a PR. Use when the user invokes `/design-audit` on a PR or branch, asks for a visual quality check on shipped code, or wants design findings posted as a PR comment.
disable-model-invocation: true
argument-hint: "[pr-or-branch] [spec-path]"
arguments: [target, spec_path]
allowed-tools: Bash(git *) Bash(gh *) Bash(curl *) Read Glob Grep Agent

# === Project SDLC overlay ===
status: beta
topology: [design-loop]
consumes: [design-spec, build]
produces: [verdict, findings, comment]
gates:
  enforces: []
  sets: []
---

# Design Audit

Audit-only workflow. Grades a shipped or in-flight UI surface against a design spec and posts findings. No spec authoring, no implementation, no validation gates — just the audit step from [`/design-loop`](../design-loop/SKILL.md), runnable standalone.

Use this when:

- A UI delta came out of `/develop` (or hand-coded) and you want a design-quality check before merge.
- You want to assess visual debt on already-merged code.
- A teammate's PR needs a design review and you want a structured findings report.

For full epic-driven design work, use `/design-loop` instead.

## Spec contract

The spec must conform to the [`design-spec` canvas](../../canvases/design-spec/README.md). Read the canvas once at the start to know what the auditor will grade against — `spec_format_version`, locked-decisions rules, universal AC, themes. Do NOT inline the contract.

Resolution chain for the canvas:

1. Project: `.claude/canvases/design-spec/instructions.yaml`
2. Plugin: `${CLAUDE_PLUGIN_DIR}/canvases/design-spec/instructions.yaml`

## Prerequisites

- `git` and `gh` CLI available (`gh auth status` exits 0).
- `image-posting` primitive's `verify-prereqs` op returns `ok: true`.
- `browser-pilot` agent present.
- `design-auditor` agent present.

Path resolution: agents found via Claude Code's standard plugin overlay.

## Inputs

| Arg | Required | Meaning |
|---|---|---|
| `target` | yes | A PR number (e.g., `47`), a branch name, or a commit SHA. The skill will check out / fetch as needed. |
| `spec_path` | yes | Path to a design spec to grade against. Must conform to the `design-spec` canvas. |

## Choreography

### 1. Resolve target

- If `target` is a PR number: `gh pr checkout {target}` in a worktree (or current tree if clean).
- If `target` is a branch name: `git fetch && git checkout {target}`.
- If `target` is a SHA: detached checkout.

Capture: PR number (if any), branch name, head SHA.

### 2. Verify spec format

Read the spec's `spec_format` frontmatter. Compare against `instructions.yaml.spec_format_version`. On mismatch, refuse with:

> *"Spec format version mismatch: spec is v{N}, package is v{M}. Upgrade the spec or pin the package."*

### 3. Locate showcase route

The spec declares a `/_showcase` route. Verify it exists in the target's frontend build (a quick `grep -r '_showcase' frontend/src/` or HTTP-check the dev server). If not, the audit cannot proceed in standard mode — fall back to feature-page audit and note this in the report header.

### 4. Audit

Spawn `design-auditor` (`context: fork`). Pass:
- `spec_path`
- `commit_sha` (head SHA)
- `showcase_url` (or feature-page list as fallback)
- `themes` (declared themes from the spec)
- `target` for posting: `{ pr }` if a PR exists; `{ branch }` if only a branch; absent if SHA-only.

The auditor uses `browser-pilot` for screenshots and the `image-posting` primitive for posting findings. It grades against:

- Locked decisions (verbatim)
- Universal AC from the canvas (only `enabled: true` items; theme-swap auto-disables when themes count < `theme_swap_required_when_count_gte`)
- Spec-declared AC for each present phase
- Visual polish (advisory)
- Out-of-scope observations

### 5. Post / print

- If `target` is a PR: the auditor posts via `image-posting` primitive. Title: `## Design audit — phase {N} — commit {short-sha}`.
- If `target` is a branch or SHA without a PR: the auditor returns the report; this skill prints it. Offer to file an issue with the findings if useful.

### 6. Stop

This is audit-only. Do not dispatch fixes. Do not run validation gates. Findings are advisory; the user (or a follow-up `/design-loop` run) decides what to act on.

## Reporting format

The auditor's posted comment follows this shape (the auditor renders it; this skill does not):

```markdown
## Design audit — phase {N} — commit {short-sha}

**Spec:** `{spec_path}`
**Themes audited:** {names}
**Date:** {YYYY-MM-DD}

### Both-themes overview
{side-by-side screenshot table — embedded via image-posting placeholders}

### Definitely broken (N)
1. {finding} — `{file}:{line}` — {screenshot ref} — fix: {recommendation}
...

### Visual polish (N)
{same format}

### Out of scope (noticed but not graded)
- {thing}

### Recommended fix order
1. ...
```

## Constraints

- Do NOT modify code. Read-only.
- Do NOT grade against criteria not in the spec or the canvas's `universal_ac`. Out-of-scope observations go in their own block, clearly labeled.
- Do NOT post findings without screenshots — every "definitely broken" item requires visual evidence.
- Do NOT skip themes. If the spec declares N themes, audit all N.
- Do NOT invoke `gh-attach-image.mjs` directly; always go through the `image-posting` primitive.
- Do NOT inline contract text from outside the canvas.

## Related

- [`design-spec` canvas](../../canvases/design-spec/README.md) — the contract
- [`image-posting` primitive](../../primitives/image-posting/README.md) — how screenshots get attached
- [`design-auditor`](../../agents/design-auditor.md), [`browser-pilot`](../../agents/browser-pilot.md) — phase agents
- [`/design-loop`](../design-loop/SKILL.md) — full design pass; audit is one of its steps
- [`/develop`](../../commands/develop.md) — composed-mode entrypoint via `needs:design`
