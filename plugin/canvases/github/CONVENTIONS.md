# GitHub family — cross-canvas conventions

Reference data and anti-pattern catalog for canvases under `plugin/canvases/github/`. Every canvas in this family draws from this doc instead of restating the same enums and parser constraints. The `canvas-author` agent loads this file as context whenever it's tuning, validating, or authoring a canvas in this family.

Most rules here are not arbitrary style — they are **parser-sensitive** in GitHub's UI or in this plugin's tooling. Getting them wrong silently breaks tracker linkage, Project rollups, or `/sync-issues` reconciliation.

---

## 1. Closing-keyword format (PR bodies)

GitHub recognizes 9 closing keywords. The plugin canonicalizes to **`Closes`** for consistency; the others are accepted but not emitted.

| Variants | Form |
|---|---|
| `close` / `closes` / `closed` | Canonical: `Closes` |
| `fix` / `fixes` / `fixed` | Accepted; not emitted |
| `resolve` / `resolves` / `resolved` | Accepted; not emitted |

### Same-repo

```
Closes #17
```

### Cross-repo

```
Closes owner/repo#60
```

### The format constraint that bites in practice

The keyword **MUST be immediately followed by the reference**. Any intervening prose breaks the parser. These look like closing lines but GitHub ignores them:

```
Closes upstream tracker: pattern-stack/dealbrain-integrations#60.   ❌ (prose before ref)
Closes PR A of pattern-stack/dealbrain-integrations#61.             ❌ (prose before ref)
This PR closes #17 as part of the rollout.                          ❌ (prose before ref)
Closes #17, #18, #19.                                               ❌ (only #17 parses; multiple-on-one-line)
```

Right shape:

```
Closes #17
Closes #18
Closes #19
```

Each on its own line.

### Squash-merge subtlety

When a PR is squash-merged, the **commit message at merge time** is what GitHub parses for the close hook — usually the PR title + body when configured. Body edits AFTER merge:
- DO retroactively populate the Project board's **Linked pull requests** column (the linkage propagates).
- Do NOT re-fire the close hook (the issue is already closed).

For stacked PRs in particular: list every `Closes #N` in the **leaf PR body BEFORE opening it**. Edits to the body after stack rebases don't propagate.

---

## 2. Reference form policy (surface-aware)

Two goals pull against each other. GitHub renders a **bare** `#N` / `owner/repo#N` reference as a **live preview chip** — an open/closed/merged state icon plus a hovercard showing the title — but a bare reference loses its meaning the moment the text is read off GitHub (Slack, email, an exported doc). So pick the form by **where the artifact is read**, not by habit.

**GitHub-native surfaces — issue bodies, PR bodies, issue/PR comments, review comments.**
Use the **bare autolink**: `#N` same-repo, `owner/repo#N` cross-repo. This is what produces the preview the reader expects on GitHub. Wrapping it as a markdown link — `[#N](url)` — *suppresses* the chip: it renders as ordinary link text with no state icon. (A bare full URL also collapses to a chip, but the short form reads cleaner.)

```markdown
Blocked by #364 · supersedes owner/repo#60 · shipped in #372
```

**Cross-posted / exported surfaces — Slack, email, external docs, anything that may be copied off GitHub.**
Use the **full markdown link with the URL inline**, so the reference survives the move:

```markdown
…shipped via [PR #364](https://github.com/pattern-stack/codegen-patterns/pull/364) …
…at commit [`8f6c87b`](https://github.com/pattern-stack/dealbrain-integrations/commit/8f6c87bdbdfbaec2bbe8317cfb136e9faab5b5a5) …
…tracked in [#60](https://github.com/pattern-stack/dealbrain-integrations/issues/60) …
```

Rule of thumb: **posted onto GitHub → bare autolink (you get the preview); may be read off GitHub → link it in full.** When you can't tell, the full link is the safe default — it never breaks; it only forgoes the inline chip.

> **Closing keywords (§1) are exempt from this choice** — `Closes #N` / `Closes owner/repo#N` MUST use the bare reference form regardless of surface, because the close-hook parser only recognizes the bare ref (a `[#N](url)` markdown link does not fire it).

---

## 3. REST-for-tracker-writes

GitHub's `gh` CLI has two API budgets: **GraphQL (5000/hr)** and **REST (5000/hr)** — separate pools. Most `gh` subcommands (`gh issue view`, `gh issue comment`, `gh pr edit`) hit GraphQL. Tracker writes (comments, labels, body edits, PR creation) should prefer REST to spare GraphQL for traversals + Project queries:

```bash
# Preferred (REST)
gh api repos/OWNER/REPO/issues/N/comments -f body="..."
gh api repos/OWNER/REPO/issues/N -X PATCH -f state=closed
gh api repos/OWNER/REPO/pulls/N -X PATCH -F body=@/tmp/new-body.md

# Avoid for bulk writes (GraphQL pool)
gh issue comment N --body "..."
gh issue close N
gh pr edit N --body "..."
```

Diagnostics: `just gh-rate` shows both pools. `just gh-gql -f query='...'` logs GraphQL cost on stderr.

Heredoc bodies via `-f body="$(cat <<'EOF' ... EOF)"` or `-F body=@/path/to/file` handle multiline + markdown reliably.

---

## 4. Permalink-with-SHA pattern

When a tracker comment cites a doc that lives in the repo, link the **commit-SHA permalink** — not a branch or `main` link. The branch may rebase; `main` shifts under the link. The SHA is forever.

```markdown
Spec at [.ai-docs/stacks/crm-domain/specs/18.md](https://github.com/pattern-stack/dealbrain-integrations/blob/8f6c87bdbdfbaec2bbe8317cfb136e9faab5b5a5/.ai-docs/stacks/crm-domain/specs/18.md)
```

Workflow: after writing the spec, commit it on a branch, push, then patch the tracker comment with the commit-SHA permalink. This is how the specifier agent operates; canvas-rendered comments must do the same.

---

## 5. Layer enum

```
L0  Codegen substrate (NestJS+Drizzle scaffold, subsystems)
L1  Integration framework (markers, decorators, strategies)
L2  Domain (entities, value objects, BaseDomainEntity)
L3  Ports (lean vendor-agnostic interfaces)
L4  Vendor clients (transport + decorator stack)
L5  Adapters (port impls per vendor)
L6  Surfaces (vendor-bound port composition)
L7  Domain side (ApplicationServices → use cases → expositions)
```

Single source of truth for the `layer:` knob on `issue-body` and `epic-body` canvases. Mirrors `canvases/plan/instructions.yaml` `layer.enum`. Sets the **Layer** custom field on GitHub Projects v2.

This enum is project-specific (Integration framework convention). Other consumers of the plugin will substitute their own layer model — keep this list as the *example* and overlay per project via the project's `sdlc.yml`.

---

## 6. Gate + state label set

From `plugin/primitives/task-management/github.md`. Provisioned via `bash plugin/primitives/task-management/bootstrap.sh`.

**`state:*` (lifecycle):**

| Label | Color | Meaning |
|---|---|---|
| `state:planned` | — | Synced from plan; not yet started |
| `state:awaiting-strategy-review` | yellow | Strict-mode specifier posted strategy, awaiting human Gate-1 approval |
| `state:strategy-approved` | green | Gate-1 satisfied (human-set or auto-mode) |
| `state:blocked` | red | Coordinator self-blocked on Gate-1 timeout |

**`gate:*` (Gate-1 mode override):**

| Label | Color | Effect |
|---|---|---|
| `gate:auto` | `#0E8A16` (green) | Specifier posts strategy + sets `state:strategy-approved` directly; no halt |
| `gate:human` | `#B60205` (red) | Specifier halts at `state:awaiting-strategy-review` |

Resolution at runtime (specifier reads issue labels only): `gate:auto` → auto; `gate:human` → strict; no `gate:*` → fall through to `sdlc.yml.gate1_default`.

`needs:*` labels (`needs:browser-pilot`, `needs:tester`, `needs:designer`) are created on demand the first time `/develop` encounters one — no fixed enum.

---

## 7. Conventional commit types

From `plugin/primitives/commit/conventional.md`. PR title prefix = commit type (because squash-merge uses the title).

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

Scope is the package, app, or issue key: `feat(#12): …`, `fix(rfc-0004): …`, `chore(infra): …`. Repo-wide changes may omit scope.

---

## 8. Issue Type enum

From `plugin/primitives/task-management/github.md`. Detected at first use:

- **Org repos** — native GitHub Issue Types (`Project`, `Epic`, `Task`). Project is created via GraphQL; Epic and Task come from GitHub's default set.
- **User repos** — fallback labels (`type:project` purple `#6F42C1`, `type:epic` blue `#0366D6`, `type:task` gray `#6E7681`). Created on demand by `set-type`.

Used as the `kind` knob on `epic-body` (accepts `epic | project`) and as the implicit "task" mode on `issue-body` (leaves are always tasks).

---

## 9. Status field options (Projects v2)

The 9-option outcome-driven taxonomy. Configure via the GitHub Project UI — `gh` CLI cannot create Status options programmatically.

| Status | Outcome boundary | Mover |
|---|---|---|
| **Backlog** | Synced from plan; no commitment yet | `/sync-issues` default |
| **On-Deck** | Committed for this wave; will be addressed | human triage |
| **Planning** | Spec being written OR strategy posted, awaiting OK | `/sdlc:design` start |
| **Ready** | Spec is acceptable to start (Gate-1 satisfied) | specifier (auto mode) or human (strict mode) |
| **In Progress** | Branch + commits, no PR | implementer |
| **In Review** | PR open | implementer |
| **Done** | Merged | GitHub |
| **Blocked** | Parked, can't progress | **only the coordinator** self-blocks; humans set otherwise |
| **Cancelled** | Won't do, never merged | human |

Status moves are intentional but **soft** — agents check Status alongside labels and halt with one short reason rather than failing hard if the lane isn't what they expected.

---

## 10. Plan markers (idempotency tokens for /sync-issues)

From `plugin/canvases/plan/instructions.yaml` `markers:` block. The exact string is searched by `/sync-issues` via `find-by-marker(<marker>)` to determine "have I already synced this leaf?" Drift breaks reconciliation.

```
[plan-epic:<plan.slug>]        ← in epic body
[plan-key:<plan.slug>/<key>]   ← in leaf body
```

The `epic-body` canvas renders `[plan-epic:...]` as a structured field. The `issue-body` canvas renders `[plan-key:...]` likewise. Hand-edits to drop or reformat these markers will silently break the next `/sync-issues` run.

---

## 11. Branch + commit conventions

From `plugin/primitives/task-management/github.md`:

| Form | Shape |
|---|---|
| Standalone branch | `<user>/<n>-<slug>` (e.g. `dug/12-pm-domain`) |
| Stacked branch (via `st`) | `<user>/<stack-slug>/<N>-<slug>` (e.g. `dug/plugin-layout/2-gate-modes`) |
| Commit scope | `feat(#<n>): …` |
| PR title | `<type>(#<n>): …` (squash-merge uses this as commit msg) |

Slug is terse — 3 words max, kebab-case, noun-phrased, no `pr-N-` / `issue-NN` prefixes. The issue key + PR number are durable identifiers; the slug is for human skimmability.

---

## 12. Anti-pattern catalog

What `canvas-author` surfaces when tuning, validating, or authoring a github-family canvas — even if the user didn't ask.

### A. Closing-keyword with prose between keyword and reference
**Symptom:** `Closes upstream tracker: X#N`, `Closes PR A of X#N`, `This PR closes #N`.
**Why bad:** GitHub's parser ignores any `Closes` line where the next token after the keyword isn't a bare reference. The issue won't auto-close on merge, and the Project board's **Linked pull requests** column won't populate.
**Surface as:** "Closing-keyword line has prose between `Closes` and the reference. Render as bare `Closes X#N` on its own line. The descriptive text can go elsewhere in the body."

### B. Multiple `Closes` on one line
**Symptom:** `Closes #17, #18, #19` or `Closes #17 and #18`.
**Why bad:** Only the first reference parses.
**Surface as:** "Multiple closing references on one line — only `#17` will parse. Render each on its own line."

### C. Same-repo Closes pointing cross-repo
**Symptom:** PR in `repo-a` has `Closes #60` intending to close an issue in `repo-b`.
**Why bad:** GitHub resolves bare `#N` against the PR's own repo. Silent miss.
**Surface as:** "Cross-repo Closes needs the `owner/repo#N` form. Bare `#60` resolves against this repo, not the target."

### D. Missing `[plan-key:...]` on /sync-issues-managed issue
**Symptom:** Issue body created by hand (not via `/sync-issues`) lacks the marker.
**Why bad:** Next `/sync-issues` run can't find the issue via `find-by-marker` and may create a duplicate.
**Surface as:** "Issue body is missing `[plan-key:<slug>/<key>]`. If this issue is managed by `/sync-issues`, the marker is the reconciliation token — without it, a re-sync creates a duplicate."

### E. Missing layer label on a task
**Symptom:** Task issue has no `L0..L7` value in its **Layer** custom field.
**Why bad:** Drops out of the "By Layer" Project view. Wave-rollup reports lose precision.
**Surface as:** "Task has no Layer set — won't appear in the By Layer Project view. Set via the canvas's `layer` knob."

### F. Body edits to merged PRs assumed to re-trigger close hooks
**Symptom:** Adding `Closes #N` to a merged PR body to "auto-close" an issue.
**Why bad:** The close hook fires only at merge time. Body edits after merge DO propagate the Linked PRs column linkage (good for visibility) but do NOT close the issue.
**Surface as:** "Body edits to merged PRs update the Linked PRs column but don't re-fire the close hook. If the issue still needs closing, close it explicitly."

### G. Title prefix lost on squash-merge UI rewrite
**Symptom:** PR opened with title `feat(#12): …` but squash-merged via the GitHub UI with a default-title checkbox that overwrites with the first commit message.
**Why bad:** The merge commit ends up with a non-conventional title; changelog generators miss it.
**Surface as:** "Squash-merge UI defaults can overwrite the PR title with the first commit's message. Keep the PR title's `<type>(#<n>):` prefix; verify the merge-commit message before merging."

### H. Closing references rendered as freeform prose by the producer
**Symptom:** Producer agent constructs the `Closes` line via string concatenation rather than a typed input passed to the canvas template.
**Why bad:** Open invitation to anti-pattern A. The whole point of the canvas's `closing_references` knob is that the producer ships a typed list and the template renders parser-safe lines.
**Surface as:** "Producer is constructing closing-references as a markdown string. The canvas's `closing_references` knob is typed — pass `[{number: 17}]` not `"Closes #17"`. This eliminates the format-drift class of bugs."

---

## Provenance

- Closing-keyword format: empirically derived from [pattern-stack/dealbrain-integrations#60](https://github.com/pattern-stack/dealbrain-integrations/issues/60) close-hook miss (2026-05-13)
- URL-everywhere policy: project memory `feedback_always-link-urls`
- REST-for-tracker-writes: project memory `reference_gh-cli-rate-limit-pools` + `CLAUDE.md` § GitHub API budget
- Permalink-with-SHA pattern: project memory `feedback_spec-doc-commit`
- Squash-merge close-hook semantics: project memory `feedback_leaf-closes-references`
- Layer enum: `plugin/canvases/plan/instructions.yaml` `layer.enum`
- Gate + state labels: `plugin/primitives/task-management/github.md`
- Conventional commit types: `plugin/primitives/commit/conventional.md`
- Issue Type enum + Status options: `plugin/primitives/task-management/github.md`
- Plan markers: `plugin/canvases/plan/instructions.yaml` `markers.{epic,leaf}`
- Branch + commit conventions: `plugin/primitives/task-management/github.md`
