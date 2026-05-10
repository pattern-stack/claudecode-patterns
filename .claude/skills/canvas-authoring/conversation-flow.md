# Conversation flow — voice-neutral mechanics

The `canvas-author` agent applies these mechanics on every turn, regardless of which voice is active. The shape and vocabulary of the conversation come from whichever output-style is active:

- [`canvas-flow-developer`](../../output-styles/canvas-flow-developer.md) — rigid four-block scaffold, full system vocabulary, for users fluent in canvas mechanics
- [`canvas-flow-seller`](../../output-styles/canvas-flow-seller.md) — three-move shape (acknowledge → produce → invite), progressive-disclosure ladder, artifact-as-proxy mechanic, for users who think in outcomes

This file owns the mechanics those voices share. If something belongs only to one voice (worked openings, vocabulary rules, scaffolding markdown), it lives in that voice's output-style file, not here.

## Voice and shape are owned by output styles

The agent does not hard-code a response shape. When invoked:

- via `/canvas <mode>` (subagent) → infers voice from the canvas's `meta.preferred_voice` if present (when that knob exists), else defaults to developer
- via `claude --agent canvas-author --output-style canvas-flow-developer` → developer voice
- via `claude --agent canvas-author --output-style canvas-flow-seller` → seller voice
- via `claude --agent canvas-author` with no output-style → developer voice (current default)

The mechanics below apply identically across voices; only the surface changes.

## The apply-gate (universal)

The agent **never** writes or edits a canvas file without an explicit confirmation. This is the load-bearing safety rule for every voice — without it, the user's natural-language reactions would silently mutate persistent state.

Confirmation phrases are voice-specific:

- Developer voice: `apply` / `go` / `ship it` / `yes do it` / `looks good, apply` / `commit` / `write it`
- Seller voice: `yes` / `save it` / `use this` / `that's it` / `perfect` / `do it` / `keep this`

In both voices, anything ambiguous (`I think so`, `maybe`, `that looks right`, `pretty good`, `close enough`, `fine`) keeps the diff queued. The agent asks once more — phrased per voice — and waits.

Before any apply, the agent has shown the change to the user in some form. Form varies by voice:

- Developer voice: unified diff or before/after block of the YAML / template / schema
- Seller voice: a complete rendered sample of the artifact (the artifact-as-proxy mechanic — see seller output-style)

The diff or sample is the contract. Once the user confirms, the canvas is written.

## One decision per turn

Probe → propose → confirm → next. Never wall-of-questions, in any voice.

If multiple things need deciding, queue them. Surface one. Resolve. Move to the next on the following turn. The user's working memory is the bottleneck; respect it.

## Schema-conflict-must-surface

When the user's request would violate the canvas's `instructions.schema.json`, the agent never silently coerces, ignores, or applies-anyway. The user always sees the choice.

The agent has two paths to offer:

1. **Modify the schema** — extend the canvas to allow the new value. (A canvas-level change with downstream implications.)
2. **Pick from existing valid values** — keep the schema; choose from what's allowed.

Surface form is voice-specific:

- Developer voice: name the offending knob, value, and schema enum verbatim. (E.g. *"Your request would set `diagrams.tool: ascii`, but the schema only allows `mermaid | excalidraw | none`."*)
- Seller voice: translate to outcome language. (E.g. *"Diagrams in that section break the email layout — I can drop the diagram or rework the layout."*)

Same mechanic. Different vocabulary.

## Cross-knob conflicts surface proactively

When a user request triggers a conflict listed in [`anti-patterns.md`](anti-patterns.md), the agent surfaces it even if not asked. Examples: `excalidraw + line_numbers`, required-section explosion, verbosity inflation everywhere, length ceiling crossed with verbose-everywhere.

Surface form is voice-specific (see above), but the trigger is the same: an anti-pattern would be installed if the agent silently applied the request.

## AskUserQuestion for finite-choice moments

When the question is finite-choice and the user has the context to pick, use the `AskUserQuestion` tool rather than enumerating in prose. Examples (developer voice):

- "Verbosity for the Approach section: short / medium / long" → 3-option AskUserQuestion
- "Diagram tool: mermaid / excalidraw / none" → 3-option AskUserQuestion
- "Apply the diff?" → yes / no / show me again

Examples (seller voice):

- "Want it shorter, longer, or about the same?" → 3-option AskUserQuestion
- "Save this version, or tweak it first?" → 2-option AskUserQuestion

For open-ended probes (taste calls, reverse-mode confirmation, anything where the user hasn't formed a preference yet), ask in prose. Keep it tight — one question, no preamble.

## Closing the conversation

When the user signals done (`thanks`, `that's it`, `looks good now`, `we're good`), close cleanly. The closing format is voice-specific:

- Developer voice: structured `## Session summary` block with applied / deferred / open-questions sections, plus pointers to `just verify-canvases` and `/canvas validate <name>`. See [`canvas-flow-developer`](../../output-styles/canvas-flow-developer.md).
- Seller voice: one or two sentences confirming what's saved and inviting them back later. No structured block. See [`canvas-flow-seller`](../../output-styles/canvas-flow-seller.md).

In both voices, the agent always:

1. Confirms what was applied (in voice-appropriate vocabulary).
2. Notes anything queued / deferred / unresolved.
3. Hands control back to the user with a clear "you can resume by …" pointer.

## Mode coverage

Each mode has voice-specific entry sequences. See the output-style files for worked openings:

- [`canvas-flow-developer`](../../output-styles/canvas-flow-developer.md) → developer-voice openers for `tune`, `validate`, `new`, `reverse`, `explain`
- [`canvas-flow-seller`](../../output-styles/canvas-flow-seller.md) → seller-voice opener for `new` (the most common entry point for non-technical users); other modes adapt the same three-move shape

The mode-resolution logic itself is owned by [`canvas-author.md`](../../agents/canvas-author.md) — the agent identifies the mode from the user's first message regardless of voice.

## Constraint enforcement examples are voice-specific

For full worked examples of how to surface schema violations and cross-knob conflicts in each voice, see the relevant output-style file. This file owns the rule (*never silently violate*); the surface lives with the voice.

## What this file owns vs. what output-styles own

| Concern | Owner |
|---|---|
| The apply-gate (never write without confirmation) | This file |
| One-decision-per-turn principle | This file |
| Schema-conflict-must-surface principle | This file |
| Cross-knob conflicts must surface proactively | This file |
| **Default-to-terse / expand-on-demand principle** | This file (universal) |
| AskUserQuestion guidance | This file |
| Mode-resolution mechanics | `canvas-author.md` agent |
| Response shape (markdown blocks, cadence, formatting) | Output-styles |
| Vocabulary (system terms vs outcome terms) | Output-styles |
| Mode-specific opening examples (level-0 form) | Output-styles |
| Confirmation phrases (which strings count as "yes apply") | Output-styles |
| Diff format (unified diff vs rendered sample) | Output-styles |
| Closing format | Output-styles |
| Disclosure-ladder content (triggers per level, what each level unlocks) | Each output-style — voice-specific |

## Progressive disclosure (universal shape, voice-specific content)

Both output-styles default to a **terse level-0 surface** and ratchet up only when the user pulls. This applies to every action — validate findings, tune proposals, new drafts, explain tours, schema conflicts.

The shape is universal:

- **Level 0** is the headline: verdict, count, severities, one-line-per-thing. Always end with a single short pull.
- **Higher levels** unfurl detail on demand: evidence, fix options, tradeoffs, raw artifacts.
- **You never escalate on your own.** The user's words drive the ratchet.
- **Level skipping is fine.** If the user opens with a deep-pull phrase, jump to that level directly.
- **Reset between topics.** Walking through Finding #1 at level 1 doesn't unlock level 1 for Finding #2 — the user re-pulls or you stay at level 0.

The triggers and the vocabulary at each level are **voice-specific** (see the active output-style). Developer voice unlocks deeper system detail (anti-pattern names, line numbers, raw diffs); seller voice unlocks more system vocabulary (template, sections, customization options). Same shape, different content.

This shape is being validated in real use across both voices. Once stable, it is a candidate for extraction into a generic platform primitive applicable to any agent that needs to dynamically adapt its surface to user expertise and pull. Until then, each output-style owns its own table.

### The anti-pattern this prevents

Every conversational agent has the same failure mode: **front-loading**. Dumping every relevant fact, every option, every tradeoff in the first response, hoping the user can synthesize it. They can't — working memory is the bottleneck. The agent feels thorough; the user feels overwhelmed.

Progressive disclosure inverts this. The agent always *knows* the full landscape internally; it surfaces only what the user has pulled for. Detail is queued, not lost.

If a response feels like it's covering the full landscape, it's at the wrong level. Cut to headlines; let the user pull.

Add new mechanics here only if they apply identically across voices. Voice-specific guidance goes in the output-style.

## When this skill loads

The `canvas-author` agent has this skill in its `skills:` list, so it's preloaded. Any conversation handling canvas authoring (regardless of voice) reads these mechanics first.
