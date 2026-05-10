# Stack anatomy

Every multi-issue plan defines a **stack**. All artifacts for that stack co-locate under `.ai-docs/stacks/<slug>/`. The slug is the planner's chosen kebab-case identifier (3-5 words).

## Layout

```
.ai-docs/stacks/<slug>/
├── plan.yaml                  # planner output; source of truth for slug + issue list
├── <topic>.md                 # stack-scoped research from understander
├── <other-topic>.md
└── specs/
    ├── <issue-key>.md         # specifier output; one per issue in the stack
    └── <other-key>.md
```

Plus cross-cutting research (informs multiple stacks, or no stack yet exists):
```
.ai-docs/research/<topic>.md
```

Plus legacy specs (issues that predate the stack convention):
```
.ai-docs/specs/<issue-key>.md     # only for ABC-102..ABC-106 era; not for new work
```

**Source of truth for paths:** `.claude/sdlc.yml` `artifact_paths`. Agents read paths from there — never hardcoded.

## How agents discover the stack

Agents do **not** receive the slug as a parameter. They discover it.

| Agent | Discovery method | Why |
|---|---|---|
| **Understander** | Chooses `<slug>` (kebab-case from request) | Decides where to write — stack-scoped or cross-cutting |
| **Planner** | Reads existing `plan.yaml` if present at the chosen slug; else creates fresh | Owns `plan.slug` field — load-bearing for downstream agents |
| **Specifier** | Globs `.ai-docs/stacks/*/plan.yaml`, finds issue key in `issues[]` | Determines where the spec lands |
| **Implementer** | `find .ai-docs/stacks -name "<key>.md" -path "*/specs/*"` | Falls back to legacy path if not found |
| **Coordinator** | Same as implementer | Falls back to legacy path |

The slug is set once (by the planner) and propagated implicitly via the filesystem layout. **Don't rename a stack mid-flight** without updating `plan.slug` AND the `[plan-key:...]` markers in any synced Linear issues.

## Artifact flow

```
request
  │
  ├──→ understander writes:
  │       .ai-docs/stacks/<slug>/<topic>.md     (stack-scoped)
  │       OR  .ai-docs/research/<topic>.md     (cross-cutting)
  │
  ▼
planner writes:
       .ai-docs/stacks/<slug>/plan.yaml
  │
  ▼
/sync-issues files Linear issues, embeds [plan-key:<slug>/<key>] in description
  │
  ▼ per issue
specifier writes:
       .ai-docs/stacks/<slug>/specs/<key>.md
       + posts Linear comment (≤ 2000 chars)
       + adds state:awaiting-strategy-review
  │
  ▼ (human reviews comment, adds state:strategy-approved)
implementer reads spec, branches <owner>/<key>-<slug>, commits, opens PR
  │
  ▼
validator reads branch, runs gates, posts PR comment
```

## Stack-scoped vs cross-cutting

| Type | Location | Trigger |
|---|---|---|
| Stack-scoped research | `.ai-docs/stacks/<slug>/<topic>.md` | A specific stack is in scope; understander defaults here when slug is known |
| Cross-cutting research | `.ai-docs/research/<topic>.md` | Research informs multiple stacks, or no stack yet exists |
| Stack-scoped spec | `.ai-docs/stacks/<slug>/specs/<key>.md` | All new specs |
| Legacy spec | `.ai-docs/specs/<key>.md` | Only for issues predating the convention (ABC-102..ABC-106) |

When reading research from any agent: try stack-scoped first (if a slug is in scope), fall back to cross-cutting. The understander, specifier, and coordinator all follow this priority.

## Idempotence

`/sync-issues` is idempotent because it embeds `[plan-key:<slug>/<key>]` in each Linear issue's description. Re-running:

- Updates existing issues' title/description (preserves human-set labels — only `needs:*` labels are managed by sync).
- Creates new issues for keys not yet seen.
- Does not delete anything. Removing an issue from the YAML does not remove it from Linear.

The local YAML is **not** modified by sync — it remains the source of truth for the next sync.

## Renaming caveats

Don't rename `<slug>` after Linear sync. The `[plan-key:<slug>/<key>]` markers in Linear pin the slug. If you rename `plan.slug` and re-sync:

- Existing issues' markers won't match → sync creates duplicates.
- The old folder still exists on disk → no auto-cleanup.

If you must rename:
1. Rename the folder: `mv .ai-docs/stacks/<old>/ .ai-docs/stacks/<new>/`
2. Update `plan.slug` in `plan.yaml`.
3. Update each Linear issue's description to swap `[plan-key:<old>/...]` → `[plan-key:<new>/...]`.
4. Re-run `/sync-issues` to verify no duplicates were created.

In practice: get the slug right the first time. The planner picks it; if you don't like it, ask the planner to rename **before** the first `/sync-issues` runs.

## Stack lifecycle

| Phase | Stack state |
|---|---|
| Pre-plan | Folder doesn't exist |
| `/plan` first turn | `plan.yaml` created; slug pinned |
| Iteration | `plan.yaml` rewritten in full each turn (previous version in git) |
| Approval | `plan.yaml` final; chat says "approved" |
| `/sync-issues` | Linear filings happen; folder unchanged |
| `/design` per issue | `specs/<key>.md` added one at a time |
| Post-merge | Folder remains as documentation; nothing prunes it |

The folder is durable documentation. Treat `.ai-docs/stacks/<slug>/` as a permanent artifact of how the work was decomposed and reasoned about, even after every issue ships.
