# Handoff — 2026-05-10

## What just shipped

**Stack `sdlc-plugin-distribution` (epic #22, all 6 PRs merged):** the repo is now an installable Claude Code plugin named `sdlc`.

| PR | Issue | What |
|---|---|---|
| #35 | #28 | Vendor `.claude/<dir>/` → `plugin/<dir>/`; manifest + marketplace.json; dogfood symlinks; install-smoke drift-test CI |
| #48 | #23 | Gate-mode mechanism (strict / auto / "trust mode") + 9-option Status taxonomy. `/sync-issues` stamps `gate:auto`/`gate:human` at issue-creation; specifier reads labels only at runtime |
| #49 | #24 | `/sdlc:setup` AskUserQuestion-driven onboarding (renamed from `init` to avoid collision with native `/init`) |
| #50 | #25 | UserPromptSubmit nag hook surfacing `/sdlc:setup` when sdlc.yml is missing |
| #51 | #26 | Tracker-discovery as SessionStart hook + dispatcher (replaces the originally-planned `/sdlc:link-project` after review pushback). Colocated under `plugin/primitives/task-management/` (sets precedent for domain-modular plugin architecture) |
| #52 | #27 | README Quickstart rewrite (`/plugin install` + `/sdlc:setup`); changelog rows for Install + Gate-1 mode; plugin-development section; branch-naming convention codified in `linear.md` / `github.md` primitives |

Plus bootstrap PR #21 (switched dogfood to `task_management: github`, added github primitive + port README, landed the plan + issue-20-source snapshot).

## Open follow-ups

- **#41** — Add Node + tooling dep checks for plugin runtime. Surfaced from PR #38's review (Node availability concern). Includes proposed `/sdlc:setup` early-check + a future `/sdlc:doctor` command.
- **Pre-existing issues** (untouched this session): #18 (typed `consumes`/`produces` registry), #19 (`AskUserQuestion+preview` ecosystem-wide), #12 (full canvas-aware audit + validator-report canvas).
- **Pre-existing unmerged stack** (not ours): #42–#47 — "remote control / `/implement` command" work. Different stack; ignore for our scope.

## Architectural decisions that matter for future sessions

1. **Plugin is at `plugin/`**, repo root has `marketplace.json` + dogfood `.claude/` (symlinks to `plugin/<dir>/`). Live edits to plugin contents flow through symlinks; fresh-install behavior tested via CI drift-test (`.github/workflows/plugin-drift-test.yml`).

2. **`sdlc.yml` lives at project root** (`.claude/sdlc.yml`); `gate1_default: strict` ships there as the global Gate-1 default. Override chain: `sdlc.yml.gate1_default` → `plan.yaml.auto_approve` → issue `gate:auto`/`gate:human` (most-specific wins). `/sync-issues` translates plan-level intent to per-issue labels at creation time; specifier reads only labels at runtime.

3. **Tracker context is auto-discovered**, not hand-configured. `SessionStart` hook runs `plugin/primitives/task-management/discover.sh` → writes `.claude/.session/tracker-context.md` → specifier `@`-mentions it. Pluggable per `task_management:` (github active; linear stub for v2; jira not implemented). Empty file → agents degrade to label-only.

4. **Scripts colocate with primitives.** `plugin/primitives/task-management/{discover.sh, bootstrap.sh}` (not `plugin/scripts/`). Sets precedent: domain-specific scripts live under `primitives/<domain>/`; `plugin/scripts/` is for cross-cutting (verify-canvases, verify-tool-groups, list-canvases). Headed toward v2 domain-modules architecture but not refactored yet.

5. **Branch-naming convention.** Codified in `plugin/primitives/task-management/{github,linear}.md`:
   - Standalone: `<user>/<n>-<slug>` (e.g. `dugshub/23-gate-modes`)
   - Stacked: `<user>/<stack>/<N>-<slug>` (e.g. `dugshub/plugin-layout/2-gate-modes`)
   - Slug rules: max 3 words, kebab-case, noun phrases, no `pr-N-` / `issue-NN` prefixes (issue + PR carry that already)

## Operational footguns observed this session

- **`st branch rename` deletes the old remote branch** → GitHub auto-closes the PR. Recovery: snapshot bodies, run `gh pr create` manually, patch `~/.claude/stacks/<repo>.json` to update PR-number mapping. The `--no-pr-update` flag only skips PR-title sync, not the remote-branch-rename. **Use `st rename` only on un-pushed branches or accept PR-renumber.**

- **st state lives at `~/.claude/stacks/<repo>.json`** (found via `st --ai`). Direct JSON editing is fine when recovering from misalignment.

- **`gh pr create` bypasses st's local registry** — PRs created this way aren't tracked by `st status`. Always use `st submit` for stack-aware tracking from the start.

- **`Closes #N` only auto-links when the PR's base is the default branch.** Stacked PRs targeting an upstream branch leave `closingIssuesReferences` empty; the link activates retroactively as upstream PRs merge (rebase cascade). For immediate visual association, manually link via the "Development" sidebar widget on github.com (UI only; no API for this).

## What's next (suggested)

- **#41** is the natural next pickup if continuing this thread. Smallest scope: add `which node` check to `/sdlc:setup`; document Node + gh + yq + just deps in README "Prerequisites." Bigger scope: `/sdlc:doctor` command.
- **Linear primitive Status mapping** (the working hypothesis from #51's spec) — exists but never validated against a real Linear project. Pick up when someone runs the loop with `task_management: linear`.
- **The "remote control" stack (#42–#47)** is separate work; defer.

## Working tree

Clean on `main`. Local branches for the merged stack deleted. No lingering uncommitted changes.

## Commands you'd want to know

```bash
git checkout main && git pull       # already done; main at 182e040
gh issue list --state open          # 4 of our own (#41, #19, #18, #12) + 6 unrelated (#42-#47, #20)
st status                           # "No tracked stacks" (plugin-layout cleaned up)
just sdlc::verify                   # green — 4 canvases + 7 agents
```
