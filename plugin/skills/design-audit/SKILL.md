---
name: design-audit
description: Audit-only design pass. Grader runs once against a built surface; no builder dispatch, no fix loop. Thin wrapper around `/design-loop --mode=audit`. Use when you want a design quality check on a PR or branch without iterating.
disable-model-invocation: true
argument-hint: "[--reference=<path>] [--surface=<path-or-url>] [--target=<pr|branch|sha>]"
arguments: [reference, surface, target]
allowed-tools: Bash(git *) Bash(gh *) Bash(curl *) Read Glob Grep Agent

status: beta
topology: [design-loop]
consumes: [design-reference, surface]
produces: [verdict, findings, comment]
gates:
  enforces: []
  sets: []
---

# Design Audit

Audit-only entrypoint. Calls `/design-loop --mode=audit` with the same arguments. No builder dispatch, no fix loop, no termination strategy — just one grader pass and post findings.

## Use when

- A PR / branch has shipped UI and you want a design check before merge.
- You want to assess visual debt on already-merged code.
- A teammate's PR needs a design review and you want a structured findings comment.

For full epic-driven design work, use [`/design-loop`](../design-loop/SKILL.md) directly.

## Inputs

| Arg | Required | Notes |
|---|---|---|
| `--reference` | yes | Path to `.ai-docs/design/<slug>/reference.*`. Reference type auto-detected. |
| `--surface` | yes | Path or URL where the build lives. |
| `--target` | no | PR number / branch name / SHA. If a PR, the grader posts findings as a PR comment. If branch/SHA only, findings are printed. |

## Choreography

Resolves target → invokes `/design-loop --mode=audit --reference=... --surface=...`. The loop's `--mode=audit` switch:
1. Skips the builder dispatch entirely (no commits made).
2. Runs the grader once.
3. Posts findings via the `image-posting` primitive.
4. Does NOT run any fix-loop.
5. Returns the grader's verdict.

This skill exists for menu discoverability and arg convenience — there's no logic here that isn't in `/design-loop`.

## Constraints

- Do NOT modify code. Read-only end-to-end.
- Do NOT call the builder. Audit means one grader pass, period.

## Related

- [`/design-loop`](../design-loop/SKILL.md) — full loop; this skill calls it with `--mode=audit`
- [`design-grader`](../../agents/design-grader.md) — the agent that runs
- [`design-reference` canvas](../../canvases/design-reference/README.md) — the contract
