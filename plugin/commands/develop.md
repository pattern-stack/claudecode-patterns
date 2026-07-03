---
description: Topology A — work one issue end-to-end with a flat team of split-pane teammates. Composes the team from sdlc.yml develop_team plus the issue's needs:* labels. Accepts a tracker issue key OR an approved spec path.
argument-hint: [issue-key | spec-path]
allowed-tools: Read, Glob, Bash, TeamCreate, SendMessage, mcp__plugin_linear_linear__get_issue
primitives:
  required:
    - task_management
    - language
    - quality_profile
status: active
topology: A
consumes: [issue, spec, label]
produces: [team]
gates:
  enforces: [strategy-approved]
  sets: []
---

# /develop

Single-issue execution in **Topology A**: implementer + validator (and any per-issue extras) run as peer split-pane teammates of the main session. Use when human eyes per step matter (UI verification, data validation, debugging).

For batched AFK throughput across many issues, use `/orchestrate` instead.

> **Workflow judgment** — for `/develop` vs `/orchestrate`, halt recovery from any teammate, or what to do when the validator fails, see the [`sdlc-loop`](../skills/sdlc-loop/SKILL.md) skill.

## Working tree state (pre-rendered)

Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`

## Usage

```
/develop <ISSUE-KEY>      # resolve the issue from the tracker, enforce Gate 1, spawn team
/develop <SPEC-PATH>      # "we planned, now build" — spec already approved, jump to Implement
```

`$1`: **either** a tracker issue key (e.g. `ABC-101`) **or** a path to an approved spec file (e.g. `.ai-docs/stacks/foo/specs/abc-101.md`). Step 0 disambiguates.

## Dependencies

| Component | Type | Purpose |
|---|---|---|
| `task-management/{adapter}` | primitive | Issue resolution, gate label semantics (`{adapter}` = `sdlc.yml.task_management`) |
| `implementer` | agent | Default member of `develop_team` |
| `validator` | agent | Default member of `develop_team` |
| `browser-pilot` / `tester` / `designer` | agent | Spawned per `needs:*` labels (`browser-pilot` ships with the plugin since the design-loop port; `tester` / `designer` are project-vendored) |
| `design-grader` (+ `browser-pilot`) | agent (composed-design mode, spec-only for v2) | Spawned when issue carries `needs:design` — runs between implementer commit and validator. See [`/design-loop` SKILL.md § Composed mode](../skills/design-loop/SKILL.md#composed-mode-develop-with-needsdesign). |

## Steps

### Step 0: Disambiguate the argument (issue key vs spec path)

`$1` is a **spec path** if it ends in `.md` AND the file exists on disk (check with `Read`/`Glob`). Otherwise treat it as a **tracker issue key**.

- **Spec-path entry** ("we planned, now build"): the human is handing you an already-approved spec — the common path out of `/plan` → `/design` → human approval. **Skip Understand/Plan/Spec entirely; jump to Implement.**
  1. Read the spec. Recover the issue key from its frontmatter (`issue:` / `key:`) if present; otherwise derive it from the filename (`<issue-key-lowercase>.md`), or proceed key-less if the spec carries no tracker linkage.
  2. **Gate 1 with a spec path is satisfied by the human handing you the path** — passing an approved spec file *is* the approval signal. Do not re-fetch a `state:strategy-approved` label unless you resolved an issue key in (1) and a tracker is configured; if you did, still enforce Step 3 against it as a backstop.
  3. Proceed to Step 4 (compose roster) and brief the implementer with the spec path directly.
- **Issue-key entry**: continue to Step 1.

> This step is the fix for the "I have an approved spec, now build" path. Without it, a free-text/spec invocation falls through to the full loop from Phase 1 — wasted agent runs.

### Step 1: Resolve config

1. Read `.claude/sdlc.yml`. Capture:
   - `develop_team`: base roster
   - `task_management`, `language`, `quality_profile`: pass-through
   - `worktree.enabled`: whether to spawn the implementer in an isolated worktree (Step 5)
   - `phase_models`: optional per-agent model overrides applied at spawn (Step 5)

### Step 2: Resolve issue (issue-key entry only)

Read `$1` via the **configured tracker's** get-issue path — resolve the adapter from `sdlc.yml.task_management` (do not assume Linear):
- `github`: `gh issue view <n> --json title,body,labels` (or REST `gh api repos/<owner>/<repo>/issues/<n>`).
- `linear`: `mcp__plugin_linear_linear__get_issue`.
- `jira`: per `.claude/primitives/task-management/jira.md` (stub).

Capture:
- Title, description, and the spec link. **Resolve the spec path per `sdlc.yml.artifact_paths`** — search in order, same as the phase agents:
  1. **Stack-co-located** (preferred): `find .ai-docs/stacks -name "<issue-key-lowercase>.md" -path "*/specs/*"` → `artifact_paths.stack_spec`.
  2. **Legacy** (fallback): `artifact_paths.legacy_spec` (`.ai-docs/specs/<issue-key-lowercase>.md`).
  Do **not** hardcode a spec path here — `/plan`, `/design`, the `specifier`, and the `implementer` all resolve through `artifact_paths`, and this command must agree with them or the planned-spec → develop handoff silently breaks.
- All labels — particularly `state:*` and `needs:*`.

### Step 3: Enforce Gate 1 (issue-key entry only)

If `state:strategy-approved` is **not** present:
- Print: `⏸  $1 is not state:strategy-approved. Run /design $1 first, or have the human approve in the tracker.`
- Halt. Do not spawn anything.

If `state:blocked`:
- Print: `⏸  $1 is state:blocked. Resolve the blocker before /develop.`
- Halt.

### Step 4: Compose roster

Roster = `sdlc.yml.develop_team` ∪ (issue's `needs:*` labels mapped to agents).

> Spec-path entry has no labels to read — roster is just `sdlc.yml.develop_team` unless you resolved an issue key in Step 0 and fetched its labels.

Mapping (extend in `.claude/primitives/task-management/{adapter}.md` § needs:* labels):
- `needs:browser-pilot` → `browser-pilot`
- `needs:tester` → `tester`
- `needs:designer` → `designer`
- `needs:design` → `design-grader` (composed-mode design loop, spec references only for v2). Also implies `browser-pilot` — add it to the roster if not already present.

If a `needs:*` label maps to an agent file that does not yet exist, warn but do not fail — log "skipping <name>: agent not vendored" and continue.

### Step 4a: needs:design composed-mode wiring

When `needs:design` is present in the roster:

1. Verify the issue's spec references a parent design reference. Look for a `Design reference:` line or `design_reference:` frontmatter key pointing to `.ai-docs/design/<slug>/reference.md`. Spec-only for v2 — if the reference is a `.figma-url` or image, warn and proceed without the grader (figma/screenshot composed mode deferred to v3).
2. After the implementer reports its commit + showcase URL, dispatch `design-grader` (context: fork) with: reference path, surface (from `surface.txt` or the issue's spec), commit SHA, round=1, the open PR's number for posting.
3. If grader returns `FIXES`: dispatch `design-builder` (fix mode) with the findings list, then re-spawn `design-grader`. Cap at 3 rounds (matches `validator_max_iterations`). On exhaustion, surface and halt.
4. If grader returns `BLOCKED`: halt and surface the sub-code (per [`design-reference` canvas](../canvases/design-reference/README.md) § Verdicts).
5. On `READY`, hand back to the standard validator gate. The grader's findings are visible in the PR comment; Gate 2.5 (`/sdlc:review`) and Gate 3 (validator) still fire normally.

Composed mode does NOT run the standalone loop's per-round user-gate — the PR-review and validator-pass gates carry that role.

### Step 5: Spawn the team

`TeamCreate` with the resolved roster. Each agent becomes a teammate addressable via `SendMessage`. Hand off the issue key + **resolved spec path** to `implementer` first; the rest are co-present for ad-hoc questions and per-step verification.

**Model policy** — for each teammate, resolve its model from `sdlc.yml.phase_models.<agent-name>` (bare role name, e.g. `implementer`). If set, pass `model: <value>` at spawn — the same spawn-time override channel as `isolation`. If unset (or `phase_models` absent), omit the override and let the agent's own frontmatter `model:` default stand. Never fork an agent def to change its model — that decision lives in `sdlc.yml`.

**Worktree isolation** — if `sdlc.yml.worktree.enabled: true`, spawn the `implementer` with `isolation: "worktree"` so its edits land in an isolated git worktree, not the shared tree. This is the in-repo half of the isolation guarantee; for **cross-repo** work (validating against or generating into a sibling repo) see [`dual-worktree-strategy.md` § Cross-repo isolation](../../.claude/docs/dual-worktree-strategy.md) — never mutate a sibling repo's working tree another agent may own.

### Step 6: Return

Print the team handle and the addressable teammate names. The human and the orchestrator (this session) drive the loop from here — there is no further automation in this command.

## What this command automates — and what it does not

So the audit-trail / tracker expectations are honest (no silent gaps):

| Concern | Who does it | Automated by `/develop`? |
|---|---|---|
| Spawn the team | this command | ✅ yes |
| Branch + commits + PR | `implementer` (Step 8 of its agent def) | ✅ yes — **provided the implementer has tracker/`gh` access**. In a sandboxed/headless spawn with no `gh` + no MCP, it cannot write to the tracker; surface that in the team's first exchange rather than assuming it happened. |
| Tracker label / status moves | `specifier` (Gate 1) + adapter | ⚠️ happens upstream in `/design`, not here |
| Validator report → PR/tracker comment | `validator` (Step 5 of its agent def) | ✅ yes (same access caveat) |
| **Shared task-list progress** | **the lead (this session)** | ❌ **not the teammates** — see below |
| Session logs (`session.json` / `execution.log` / `summary.md`) committed to git | nobody, by default | ❌ the `session` canvas describes the *shape*; nothing auto-commits these. If you want them in git, the lead commits them. |

**Shared task-list ownership (decisive, to kill the old ambiguity):** the lead owns the shared Task list. Teammates (`implementer`, `validator`, …) do **not** update it — they report progress via their **output envelope** (`status:` field). The lead reconciles task state from those envelopes. Do not set teammates as task `owner`s and instruct them to mark in_progress/completed; they won't, and the list goes stale. This is stated as a hard constraint in the `implementer`/`validator` agent defs.

**Trusting teammate results (harness caveat):** a teammate that died on an API/transport error (`API Error: Overloaded`) can surface to you with `status: completed` at the task-notification level. Before treating any phase as done, **read the teammate's output envelope `status:` field** — and sanity-check the result (an empty/implausibly-short result or an error string in the body means it failed, regardless of the notification). Re-spawn on `failed`/empty. See `.ai-docs/research/upstream-cc-completed-vs-failed.md` (filed upstream).

## Human Gates

| After Step | Gate | Approval Criteria |
|---|---|---|
| (already enforced) | Gate 1 | Set on the issue in the tracker before calling `/develop` — **or** satisfied by handing `/develop` an approved spec path (Step 0) |
| Implementer opens PR | Gate 2 — PR review | Standard GitHub review |

**Gate enforcement is not purely advisory.** The plugin ships a `PreToolUse` `gate-guard.sh` hook that hard-blocks the two never-correct merge-bypass actions — `git push` to `main`/`master` and `gh pr merge --admin` — so "human gate before merge" survives a long autonomous loop instead of depending on the lead remembering. The hook denies; it does not nag. (Override for a deliberate exception: `SDLC_GATE_OVERRIDE=1`.)

## Output

```
Team spawned for <ISSUE-KEY | spec>: <slug>
Spec: <resolved path per artifact_paths>
Roster: implementer, validator[, browser-pilot, ...]
Address teammates with: SendMessage to <name>
```

## Error Handling

- **Gate 1 missing** (issue-key entry): see Step 3.
- **`$1` is a spec path that doesn't exist**: it's not a valid spec path and not a plausible issue key → print the two usage forms and halt.
- **`needs:*` label maps to non-existent agent**: warn, skip, continue.
- **Spec file missing** (issue-key entry, no spec resolved): the implementer will halt on first contact; surface that in the team's first exchange rather than failing this command (the team is already useful for re-running `/design`).
