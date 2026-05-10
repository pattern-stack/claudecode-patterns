# Issue #20 verbatim — SDLC opinion v2: gate-mode mechanism + Status taxonomy

> **Authoritative source for PR 2 (`gate-mode-and-status-taxonomy`).** This file is a captured snapshot of [GitHub issue #20](https://github.com/pattern-stack/claudecode-patterns/issues/20) at the time the plan was approved (2026-05-10). The spec phase reads this file as source-of-truth; if the upstream issue diverges later, this snapshot wins for the purposes of the spec already approved.

> **Read alongside** `plan.yaml` (PR 2 issue body) for the planner-facing summary; this file is the unabridged opinion.

> **Note on upstream framing**: the issue's "Sequencing vs plugin restructure" and "Out of band notes for the parallel plan-of-record" sections were written before integration. Per the integrated plan: this work is PR 2 in a 6-PR linear chain (1→2→3→4→5→6). Resolution happens at `/sync-issues` time (not lazily in specifier — superseding the issue's "Out of scope: per-issue inline gate-mode at sync-issues time"). The `gate1_default` ship into `sdlc.example.yml` and the init-flow guidance landed as PR 1 + PR 3 modifications.

---

# SDLC opinion v2: gate-mode mechanism + Status taxonomy

Adds a configurable Gate-1 mode (strict vs. auto) and a recommended GitHub Project Status taxonomy to the v2 SDLC opinion. Both ship as **template-level defaults** projects can override.

This work is interdependent with the plugin-restructure stack (PRs 1–4 in the parallel plan). See **Sequencing** at the bottom.

---

## Context

v2 today: `specifier` posts strategy → sets `state:awaiting-strategy-review` → halts. Human sets `state:strategy-approved` → `implementer` proceeds.

Pain: some stacks are **mechanical** (RFC-translation, YAML definitions, vendor adapter wirings against an established pattern) — human approval is theatre. Others are **novel** (port shapes, framework changes, first-of-kind decisions) — human approval is load-bearing.

Goal: keep the gate where novelty lives, skip it cleanly where it doesn't, without the implementer ever losing its `state:strategy-approved` safety net.

---

## Decisions to lock

### 1. Status field taxonomy — 9 options

Outcome-driven (not gate-driven) so column shape ages well as Gate 1 softens.

```
Backlog → On-Deck → Planning → Ready → In Progress → In Review → Done       Blocked    Cancelled
```

| Column | Outcome boundary | Mover |
|---|---|---|
| **Backlog** | Synced from plan; no commitment yet | `/sync-issues` default |
| **On-Deck** | Committed for this wave; will be addressed | human triage |
| **Planning** | Spec being written OR strategy posted, awaiting OK | `/sdlc:design` start |
| **Ready** | Spec is acceptable to start | specifier (auto mode) or human (strict mode) |
| **In Progress** | Branch + commits, no PR | implementer |
| **In Review** | PR open | implementer |
| **Done** | Merged | GitHub |
| **Blocked** | Parked, can't progress | any agent / human |
| **Cancelled** | Won't do, never merged | human |

**Intentional dropoffs:**
- No "Strategy review" column — soft-gate friendly. Label `state:awaiting-strategy-review` stays as a *filter* but isn't a kanban swim lane.
- No "Specifying" sub-state — both spec-being-written and awaiting-review collapse to Planning.
- "Approved" → renamed "Ready" — outcome name, not gate name.

### 2. Saved board views — 4

GitHub Projects v2 has no two-axis grouping. The two-axis read comes from multiple saved views:

| View | Group by | Question it answers |
|---|---|---|
| **Workflow** (default) | Status | "Where is each issue?" |
| **By Stack** | Parent epic | "How is each stack progressing?" |
| **By Layer** | Layer (L0–L7) | "Where in the architecture is the work?" |
| **Active only** | Status, filtered to On-Deck / Planning / Ready / In Progress / In Review | working-session view |

Plugin should ship `gh` snippets in `primitives/task-management/github.md` (or a separate doc) showing how to create these.

### 3. Gate-mode mechanism — 3-level resolution

```
sdlc.yml: gate1_default: strict     ← global floor (default; safest)
  └─ plan.yaml: auto_approve: true  ← stack-level override
      └─ issue label gate:auto / gate:human  ← per-issue override (always wins)
```

**Specifier resolution order:** issue label > plan flag > sdlc default.

> **Integration note (supersedes upstream):** per the integrated plan, `/sync-issues` resolves `auto_approve` at issue-creation time and stamps `gate:auto` / `gate:human` labels on each leaf issue. Specifier reads only labels at runtime; it does NOT read `plan.yaml` directly. Resolution order at runtime: `gate:auto` label → auto; `gate:human` label → strict; no label → fall through to `sdlc.yml.gate1_default`.

**Specifier behavior:**

| Resolved mode | Posts strategy | Sets label | Sets Status | Halts |
|---|---|---|---|---|
| **strict** | yes | `state:awaiting-strategy-review` | Planning | yes |
| **auto** | yes | `state:strategy-approved` | Ready | no |

**Implementer behavior — unchanged.** Still refuses without `state:strategy-approved`. The gate is structurally preserved; auto mode just satisfies it via the agent.

### 4. Label palette additions

| Label | Color | Use |
|---|---|---|
| `gate:auto` | green (`#0E8A16`) | this issue is in auto-approve mode |
| `gate:human` | red-ish (`#B60205`) | this issue requires human Gate 1 review (overrides plan default) |

Provisioned by `bootstrap-tracker.sh` alongside existing `state:*` labels.

### 5. Per-stack guidance (worked example, wave 1)

| Stack | Mode | Why |
|---|---|---|
| `foundation` | strict | First-of-kind: build, CI, framework markers |
| `strategies` | strict | Novel L1 framework code |
| `codegen-app-patterns` | **auto** | RFC already written; specifier translates |
| `crm-domain` | **auto** | YAML definitions, mostly mechanical |
| `crm-ports` | strict | Port shapes outlive several adapters |
| `hubspot` | strict | §3.L5 parameterization decisions still open |
| `crm-app` | strict | Use-case design; cross-port writes; safety-relevant |

~2 of 7 in auto mode. Speed where mechanical; gate where novel.

---

## Files to change

After plugin restructure lands, all paths are `plugin/<...>` not `.claude/<...>`. Listed in plugin-relative form.

| File | Change |
|---|---|
| `plugin/sdlc.example.yml` | Add `gate1_default: strict` with docstring describing the override layers |
| `plugin/agents/specifier.md` | Implement gate-mode resolution + dual-path Status setting |
| `plugin/canvases/plan/instructions.yaml` + template | Add optional `auto_approve: bool` knob at plan level |
| `plugin/skills/sdlc-loop/SKILL.md` | Add Status taxonomy + gate-modes section. Update halt-recovery table to reference Ready instead of "approved". |
| `plugin/commands/design.md` | Document strict vs auto modes; how to override via plan flag or issue label |
| `plugin/primitives/task-management/github.md` | Recommend the 9 Status options. Document `gate:*` palette. Show `gh` snippets for the 4 saved views. |
| `plugin/primitives/task-management/linear.md` | Same column recommendation in Linear-shape (Linear has native workflow-state types, so the mapping is more direct) |
| `plugin/scripts/bootstrap-tracker.sh` | Provision `gate:auto` / `gate:human` labels |
| `WORKFLOW.md` | Update loop diagram — `Planning → Ready` with dual-path movement |
| `README.md` | One-line update to the loop description |

> **Integration note:** add `plugin/commands/sync-issues.md` to this list — it gains the responsibility of stamping `gate:*` labels at issue-creation time (per the resolution-timing supersession above).

---

## Sequencing vs plugin restructure

**Recommended order: PR 1 (mechanical restructure) → THIS PR → PR 2 (init) → PR 3 (nag hook) → PR 4 (docs).**

> **Integration note:** the integrated plan extends this to a 6-PR chain: PR 1 (restructure) → PR 2 (this work) → PR 3 (init) → PR 4 (nag) → PR 5 (`/sdlc:link-project`) → PR 6 (docs).

Rationale:
- Land against the new `plugin/` layout (cleaner; PR 1 doesn't have to sweep up just-landed feature changes)
- THIS PR adds `gate1_default: strict` to `plugin/sdlc.example.yml` *before* PR 2's init renders projects, so new projects pick it up automatically — no separate upgrade flow needed
- PR 4 (docs rewrite) consolidates plugin install model + this opinion in one pass — better narrative than two doc PRs

If speed matters more than cleanliness: this PR can land first against current `.claude/` layout; PR 1 sweeps it up with everything else. Acceptable but not preferred.

> **Integration note:** `gate1_default: strict` ships in PR 1's `sdlc.example.yml` and dogfood `.claude/sdlc.yml` as a dormant key — this PR (PR 2) wires the resolution code that consumes it.

---

## Drift-test additions

PR 1 introduces a fresh-install drift test. **Add to it: a two-issue gate-mode smoke run.**

| Test issue | Mode | Expected post-`/sdlc:design` state |
|---|---|---|
| Issue A | strict | `state:awaiting-strategy-review` set; Status=Planning; specifier halted |
| Issue B | auto (via plan flag) | `state:strategy-approved` set; Status=Ready; specifier completed without halt |

This proves the resolution chain (sdlc.yml → plan.yaml → label) actually works end-to-end in a fresh install.

Cheap to add; high value.

> **Integration note:** PR 1's drift-test is install-smoke only. THIS PR (PR 2) expands the drift-test with the two-issue gate-mode smoke run above. Don't land the gate-mode test ahead of PR 2's behavior.

---

## Out of scope (intentionally)

- **Upgrade flow for existing projects.** Existing projects that adopted v2 before this PR need to manually add `gate1_default: strict` to their `sdlc.yml`. Not worth a `/sdlc:upgrade` command for one key. Document in changelog.
- **Forked-canvas merge story.** Projects that already forked the plan canvas won't see the new `auto_approve` knob until they re-fork or merge. Expected v1 behavior for canvas fork-on-edit; flag in PR description.
- ~~**Per-issue inline gate-mode at sync-issues time.** `/sync-issues` doesn't read `auto_approve` to apply labels at issue-create time — specifier resolves it lazily at design time. Keeps sync simple. Could revisit if too many human-overrides accumulate.~~ *(Superseded — see Integration note in §3 above.)*
- **Auto-approve heuristics** (e.g., risk tier auto-classifier). Out of scope; trust mode is binary and human-set per stack/issue.
- ~~**Renaming `auto-approve` → `trust mode` / `self-approving`.** Naming bikeshed; not blocking. Pick one in the PR. (Author leaning: keep `auto_approve` in YAML for terseness; surface "trust mode" in human-facing docs.)~~ *(Resolved — `auto_approve` in YAML/agent code; "trust mode" in human-facing prose only.)*

---

## Known unknowns

These don't block authoring but should be confirmed during the drift-test:

1. Does Status field setting via `gh project item-edit` work from inside a plugin-shipped slash command's main-agent context? (Almost certainly yes; same context as project-local commands.)
2. Does `state:*` label change reliably trigger Status auto-move via project automation, or does specifier need to call `gh project item-edit --field-id Status` explicitly? (Suspect: explicit call required; project automation rules don't ship with the plugin.) *(Field-ID discovery is now PR 5's concern via `/sdlc:link-project`.)*
3. If a project hasn't customized Status options to match the 9-option recommendation, what's the fallback? (Recommend: specifier checks Status field option names match `Planning` / `Ready`; falls back to label-only if not. Document the recommended option set as "best results require these.")

---

## Suggested acceptance criteria for the planner

- All listed files updated; no orphan references to `Approved` / `Strategy review` columns
- `sdlc.example.yml` documents `gate1_default` with override layer docstring
- `specifier.md` shows the three-level resolution explicitly (don't bury it in agent prose)
- Drift-test runs both gate-mode paths and asserts label + Status state
- `bootstrap-tracker.sh` is idempotent on `gate:*` provisioning (existing repos can re-run safely)
- Changelog row in PR 4 docs rewrite

---

## Out of band notes for the parallel plan-of-record

Three suggestions for the planner of the plugin-restructure stack:

1. **Ship `gate1_default: strict` in `sdlc.example.yml` as part of PR 1**, even before specifier knows what to do with it. Frees this PR to focus on agent + docs without coordinating two example-config changes. *(Adopted — PR 1 ships the dormant key.)*
2. **Init flow shouldn't ask about gate mode.** Default to strict; mention the override layers in init's "next steps" output. Burning an `AskUserQuestion` slot on this is friction for a key most users won't touch. *(Adopted — PR 3 init does not ask; next-steps mentions override layers.)*
3. **Status field option recommendation should be in the init flow's "next steps" output**, since `gh` can't customize Status field options programmatically. One-line: "Customize Status field at https://github.com/orgs/{owner}/projects/{n}/settings/fields/Status to: Backlog / On-Deck / Planning / Ready / In Progress / In Review / Done / Blocked / Cancelled." *(Adopted — PR 3 init's next-steps includes a `/sdlc:link-project` pointer when `task_management: github`; PR 5 ships the link-project command which discovers field IDs and surfaces the option-name recommendations.)*
