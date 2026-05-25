# Agent Governance — the workflow layer

> **Most agent-governance tooling lives at the *infrastructure* layer: cryptographic identity, encrypted transport, sandbox rings, SLOs — a library of controls you configure and trust. This framework governs agents at the *workflow* layer: deterministic policy hooks, least-privilege role decomposition, staged human gates, and git-native auditability. Every control here is a file you can read and a behavior you can reproduce — not a claim.**

It's a showcase of what's possible when governance is *native to the SDLC loop* a coding agent actually runs. It was built solo; the surface is composable (hooks, agents, gates, canvases, primitives), so it grows the same way [`codegen-patterns`](https://github.com/pattern-stack/codegen-patterns) grows — one small declarative file at a time. With a team behind it, it goes a lot further.

Complementary to infra-layer toolkits like [`microsoft/agent-governance-toolkit`](https://github.com/microsoft/agent-governance-toolkit): same threat model, different layer.

---

## Demonstrated, not asserted

A governance claim is only worth what you can reproduce. Here's one from a real session:

An agent, mid-task, with **explicit user authorization to merge**, ran:

```
gh pr merge 141 --squash --delete-branch --admin
```

and was **denied** — by a 40-line PreToolUse hook ([`plugin/hooks/gate-guard.sh`](../plugin/hooks/gate-guard.sh)):

```
SDLC gate-guard: `gh pr merge --admin` bypasses branch protection and Gate 2
(human PR review). Merge through the normal review path, or set
SDLC_GATE_OVERRIDE=1 for a deliberate exception.
```

The agent then tried to self-authorize with an inline `SDLC_GATE_OVERRIDE=1 gh pr merge …` — **and that also failed**, because the hook is `PreToolUse`: it reads the *agent's* environment and decides *before* the command (and its inline env) ever runs. An agent **cannot** self-grant past it. The merge waited for a human. That's ASI-09 (Human-Agent Trust Exploitation) and the privilege half of ASI-03, enforced — and you can reproduce it in any repo with the plugin installed:

```bash
# with the sdlc plugin active, as an agent or a human session:
gh pr merge <n> --admin          # → denied by gate-guard
SDLC_GATE_OVERRIDE=1 gh pr merge <n> --admin   # → still denied (inline env never reaches a PreToolUse hook)
```

The override is real, but it has to be set in the *session's* environment by whoever launched it — i.e. a human, deliberately. That asymmetry is the control.

---

## The control surface

Five composable mechanisms. Each is a small declarative file; together they're the governance layer.

| Mechanism | What it does | Where |
|---|---|---|
| **Policy hooks** | Deny-by-default, fail-closed interception of dangerous actions on every tool call. `gate-guard` blocks agent pushes to `main` and `--admin` merges; override is env-gated (human-only). | [`plugin/hooks/gate-guard.sh`](../plugin/hooks/gate-guard.sh), [`plugin/hooks/hooks.json`](../plugin/hooks/hooks.json) |
| **Least-privilege agent roles** | Each role gets a deliberately scoped toolset — capability-based access control per agent. `reviewer`/`validator` have no `Write` (read-only review); `planner`/`understander`/`sdlc-author` have no `Bash` (no execution); `coordinator` may spawn **only** `implementer`+`validator` (no arbitrary recursion). | [`plugin/agents/`](../plugin/agents/) (tool scopes in each role's frontmatter) |
| **Staged human gates** | A workflow state machine — Gate 0 (plan) → 1 (strategy) → 1.5 (spec critique) → 2 (PR review) → 2.5 (post-impl diff). Agents refuse to advance without the prior gate's `state:*` approval label. | [`plugin/skills/sdlc-loop/`](../plugin/skills/sdlc-loop/), [`plugin/sdlc.example.yml`](../plugin/sdlc.example.yml) |
| **Auditable lifecycle emission** | Every session/tool lifecycle event is emitted to a local dashboard — an observable, after-the-fact trail of what each agent did. | [`plugin/hooks/emit.sh`](../plugin/hooks/emit.sh) |
| **Output guardrails + isolation** | Canvases template every artifact (specs/plans/reviews) so outputs stay in-contract; primitives standardize tracker/commit/quality integrations; worktree isolation contains blast radius. | [`plugin/canvases/`](../plugin/canvases/), [`plugin/primitives/`](../plugin/primitives/) |

---

## How it maps to the four governance pillars

Honest coverage — ✅ direct, 🟡 partial, ⬜ different layer (out of scope by design):

| Pillar (infra-layer framing) | This framework (workflow layer) | |
|---|---|---|
| **Policy Enforcement** — evaluate on every tool call, fail-closed, block denied | PreToolUse deny hooks + the gate state machine. Same shape as an OPA/Cedar engine, expressed as hooks. | ✅ |
| **Zero-Trust Identity** — DID/SPIFFE, trust scoring | Per-role capability scoping (least-privilege) is the adjacent control; identity itself rides on the host session + git/GitHub, not crypto material. | 🟡 |
| **Execution Sandboxing** — privilege rings, kill switch | No-`Bash` roles + worktree isolation + the host Bash sandbox + permission modes; `gate-guard` is a partial kill-switch on dangerous git ops. | 🟡 |
| **Reliability Engineering** — SLOs, circuit breakers | Verification gates (`validator`), critique loop, full-CI discipline, `prime`/`handoff` session continuity, a typed memory protocol. No SLOs/chaos. | 🟡 |

---

## OWASP Agentic Top 10 — honest coverage

We don't claim 10/10. We claim **deterministic, demonstrated control exactly where it matters for a coding-agent fleet** — *what the agent is allowed to do in your codebase* — and we're candid about the rest.

| # | Threat | Control in this framework | |
|---|---|---|---|
| ASI-01 | Agent Goal Hijack | Gates 0/1/1.5 + `state:strategy-approved` — an agent can't change scope without passing a gate | ✅ |
| ASI-02 | Tool Misuse & Exploitation | Per-role tool allowlists in [`plugin/agents/`](../plugin/agents/) | ✅ |
| ASI-03 | Identity & Privilege Abuse | `gate-guard` (no agent admin-merge / main-push) + capability scoping. *Privilege:* ✅ · *crypto identity:* ⬜ | 🟡 |
| ASI-04 | Agentic Supply-Chain | "Codegen is source of truth" + versioned publish/consume + falsifier gates + `@generated` provenance; no formal AI-BOM | 🟡 |
| ASI-05 | Unexpected Code Execution | No-`Bash` roles + sandbox + worktree isolation + merge gates; no rings/kill-switch | 🟡 |
| ASI-06 | Memory & Context Poisoning | Typed-memory protocol + "verify stale memory before acting" + recalled-memory-as-background-context rule; not crypto-verified | 🟡 |
| ASI-07 | Insecure Inter-Agent Comms | Structured, **auditable** artifacts (specs/tracker/task-list/SendMessage) — not E2E-encrypted; single-tenant dev threat model | ⬜ |
| ASI-08 | Cascading Agent Failures | Staged verification gates + worktree blast-radius containment + handoff continuity; no circuit breakers/SLOs | 🟡 |
| ASI-09 | Human-Agent Trust Exploitation | **Strongest** — human approval gates (Gate 2 = human merge), `gate-guard` reserving admin-merge for humans, plan-mode + question gates. *(Demonstrated above.)* | ✅ |
| ASI-10 | Rogue Agents | Containment — capability scoping + `gate-guard` + worktree isolation + auditable lifecycle emission | ✅ |

**Strongest where it counts:** ASI-01, 02, 09, 10 (+ the privilege half of 03) — the "what is this agent allowed to *do* in my repo" axis, enforced deterministically. Partial on 04/05/06/08. Different layer (by design) on 07 + cryptographic identity.

---

## Extensibility — the actual point

The surface is composable. Governance isn't a fixed feature set; it's a pattern you extend with small declarative files:

- **Add a policy** → a new rule in a hook ([`gate-guard.sh`](../plugin/hooks/gate-guard.sh) is the template: match a `CMD`, `deny` with a message, honor the override).
- **Add a capability boundary** → a new agent role with a scoped `tools:` frontmatter.
- **Add a checkpoint** → a new gate + `state:*` label in the workflow.
- **Add an output guardrail** → a new canvas (template + instructions).
- **Add an integration** → a new primitive (tracker / commit / quality adapter).

That's how it scales the way `codegen-patterns` does — via skills and small contracts, not a monolith.

## Non-goals (what this is *not*)

By design, this is the workflow layer. It does **not** provide cryptographic per-agent identity (DID/SPIFFE), encrypted inter-agent transport, an AI-BOM/supply-chain attestation system, or SLO/circuit-breaker reliability infra. Those are the infrastructure layer — pair this with a toolkit that does them. The two compose cleanly: infra controls *who an agent is and what it can reach*; this controls *what an agent is allowed to do in the SDLC loop, and when a human must say yes*.

---

*Built solo as a working spike. If we get behind it as a team, the composable surface above is where it grows.*
