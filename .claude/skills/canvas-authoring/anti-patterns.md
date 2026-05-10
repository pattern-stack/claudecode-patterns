# Anti-patterns — what canvas-author surfaces proactively

The canvas-author agent watches for these patterns in any canvas it's tuning, validating, or creating. When detected, it surfaces them in the response's `## Tradeoffs` block — even if the user didn't ask. Most are not errors per se; they're decisions the user should make consciously rather than by accident.

## Structural anti-patterns

### Verbosity inflation everywhere
**Symptom:** every section's `verbosity` is `long`.
**Why bad:** the artifact becomes unreadable. Reviewers skim. The producer takes longer.
**Surface as:** "All sections are `long`. Specs become unreadable past ~3 long sections. Pick the 1-2 sections that genuinely need depth and step the rest down to `medium` or `short`."

### Required-section explosion
**Symptom:** `sections.required` has > 6 entries.
**Why bad:** every required section creates a halt path; consumers fail more often. Real authors fill in stubs to avoid halts; stubs erode the contract.
**Surface as:** "Required sections > 6 increases halt frequency and incentivizes stub-filling. Required should be the sections without which the artifact is meaningless. Consider promoting some to `optional` with a default."

### Required + small length budget
**Symptom:** `required` × `length.per_section_chars` total exceeds `length.total_chars`.
**Why bad:** required sections get crushed; producers cut content arbitrarily.
**Surface as:** "Required sections combined exceed total length cap by N chars. Either raise the total cap, lower per-section caps, or move sections to optional."

### Section rename without coupled update
**Symptom:** `template.md` has `## Approach` but `instructions.yaml` references `"Strategy"` (or vice versa).
**Why bad:** producers and consumers parse different section names; everything looks fine until runtime.
**Surface as (validate mode):** "Section name mismatch: template.md heading `<X>`, instructions.yaml references `<Y>`. Pick one and update both files."

## Visualization anti-patterns

### Mandatory diagrams in low-content sections
**Symptom:** `diagrams.required_in` includes a section whose `verbosity` is `short` or `bulleted`.
**Why bad:** the producer is forced to draw a diagram for a section that doesn't earn one. Forced diagrams = bad diagrams.
**Surface as:** "Diagrams required in `<section>` but the section's verbosity is `short` — diagrams will feel forced. Either let the producer decide via `in_sections` (allowed but not required), or step verbosity up."

### Excalidraw + line numbers
**Symptom:** `diagrams.tool: excalidraw` AND `citations.line_numbers: true`.
**Why bad:** excalidraw drawings don't have line numbers; the citation strictness is unsatisfiable in diagrammed sections.
**Surface as:** "Excalidraw drawings have no line numbers, so `citations.line_numbers: true` can't be honored in diagrammed sections. Either switch to mermaid (text-based, line-numbered), or relax `line_numbers` to optional."

### Distribution doesn't render diagrams
**Symptom:** `diagrams.tool: excalidraw` AND `tracker_comment.include_sections` overlaps with `diagrams.in_sections`.
**Why bad:** Linear (and most trackers) doesn't render excalidraw. The cross-posted comment will show a broken reference.
**Surface as:** "Sections `<list>` are eligible for excalidraw diagrams AND included in tracker comments. Linear doesn't render excalidraw — those sections will lose their diagrams in the comment. Either switch tool to mermaid, exclude those sections from the tracker comment, or accept the loss."

## Provenance anti-patterns

### Citations required but no convention to satisfy them
**Symptom:** `citations.file_paths: required` but the artifact's domain has no source files (e.g. a daily brief).
**Why bad:** the contract is unsatisfiable; producers either fake citations or get blocked.
**Surface as:** "`citations.file_paths: required` is set, but daily briefs don't reference source files. Either drop to `optional` (default) or `none`, or rename the canvas if the domain shifted."

### Mixed attribution modes
**Symptom:** `citations.attribution: per-claim` while the canvas template uses end-of-doc reference lists.
**Why bad:** producers don't know which mode to follow; output is inconsistent.
**Surface as:** "Attribution mode says `per-claim` but the template has an end-of-doc references section. Pick one mode and align the template."

## Length-budget anti-patterns

### Tracker comment cap larger than reasonable UI tolerance
**Symptom:** `tracker_comment.max_chars > 4000`.
**Why bad:** Linear/GitHub Issues let you post arbitrarily long comments, but readability collapses past ~2000 chars. Reviewers don't read.
**Surface as:** "`tracker_comment.max_chars: <N>` is technically allowed but readability collapses past ~2000. The comment is meant to be skimmable — it has the durable spec as a backing artifact for depth. Cap at 2000-3000 unless you have a specific reason."

### `truncate: hard` on artifact with required sections
**Symptom:** `length.truncate: hard` AND any `sections.required`.
**Why bad:** hard truncation can chop a required section in half, leaving the consumer with a placeholder that passes the "non-empty" check but contains incomplete content.
**Surface as:** "Hard truncation + required sections: the consumer's `non-empty` halt check can pass on truncated content. Switch to `truncate: reflow` (asks producer to fit by tightening) for safer semantics."

## Tone & style anti-patterns

### Cross-domain verbosity inheritance
**Symptom:** spec canvas shipped with `verbosity.Approach: long` because that's how research artifacts work.
**Why bad:** specs aren't research. Long Approach sections in specs slow implementers and bloat reviews.
**Surface as:** "`verbosity.Approach: long` is unusual for specs (where Approach is typically 1-2 paragraphs). If you imported this from another canvas's pattern, consider whether the domain shift changes the right value."

### Signature in internal-only artifacts
**Symptom:** `signature.text` is set on a canvas whose distribution is internal-only (no tracker / email / slack).
**Why bad:** signatures matter for cross-posted artifacts; in internal docs they're noise.
**Surface as:** "Signature is set but distribution is internal-only. Signature is mostly cosmetic for non-cross-posted artifacts. Keep if you have a reason; otherwise consider `omit`."

## Metadata anti-patterns

### Status field decoupled from real workflow
**Symptom:** `metadata.status_field.enum: ["draft", "review", "approved"]` but no part of the SDLC actually transitions the artifact between these states.
**Why bad:** status drifts from reality; consumers either ignore it or trust stale values.
**Surface as:** "Status field has values that no agent or human routinely updates — it'll drift. Either wire status transitions into a real workflow (a label sync, a hook on the consumer's halt), or document the field as cosmetic."

### Required frontmatter without producer awareness
**Symptom:** `metadata.frontmatter_extras` has `required: true` for a field the producer doesn't know how to populate.
**Why bad:** producer either fakes the value or fails at validation.
**Surface as:** "Required frontmatter field `<name>` has no derivation rule the producer can follow. Document the source (e.g. 'pulled from issue.title') or relax to optional."

## Distribution anti-patterns

### Multiple targets without explicit cap differences
**Symptom:** `tracker_comment.enabled: true` AND `email.enabled: true` AND both share the same `include_sections` and similar caps.
**Why bad:** trackers and email have different reading contexts. Identical content in both wastes the second channel.
**Surface as:** "Tracker and email both include the same sections at similar lengths. Email readers expect more context (no shared workspace); tracker readers want quick scan. Consider differentiating: tracker = headline+links, email = full readable summary."

### Distribution channel referring to non-existent section
**Symptom:** `tracker_comment.include_sections` includes a section name not in `sections.order`.
**Why bad:** silent dropout — the comment renders without the missing section, and no one notices.
**Surface as (validate mode):** "tracker_comment includes section `<X>` which isn't in `sections.order`. Either add the section or remove from include_sections. (Schema can catch this — promote when stable.)"

## Versioning anti-patterns

### Schema version bump without migration path
**Symptom:** `instructions.yaml.version: 2` introduced with renamed/removed knobs, but existing artifacts at v1 still in `.ai-docs/`.
**Why bad:** consumers reading old artifacts hit unknown-knob halts; producer fails on artifacts it should still understand.
**Surface as:** "Bumping version 1→2 with breaking change. Existing v1 artifacts will break. Either: (a) keep v1 fields in schema with `deprecated: true` and migrate gradually, (b) ship a one-shot migration script, or (c) accept the cliff and document it."

### No version pin on consumer side
**Symptom:** consumer agent reads `instructions.yaml` without checking `version`.
**Why bad:** schema bumps cause silent behavior changes downstream.
**Surface as (skill-authoring concern):** "Consumer agent should fail loudly on unknown `version`. Document the supported version range in the agent's prompt."

## How the agent uses this catalog

The agent doesn't lecture. It surfaces each detected anti-pattern as a single bullet in the response's `## Tradeoffs` block, with a one-line "fix this by …" suggestion. The user decides whether to act.

For `validate` mode specifically: the agent emits a structured findings list (red/yellow/green) where each yellow/red finding cites the anti-pattern by name from this file. That gives the user a stable vocabulary for talking about canvas health over time.
