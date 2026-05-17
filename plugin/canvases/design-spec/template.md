---
spec_format: {{spec_format_version}}
status: {{status}}
surface: {{surface_slug}}
author: {{author}}
date: {{date}}
related: {{related}}
---

# {{surface_name}} — design spec

## Locked decisions

_(Numbered list. Each is a one-sentence assertion + a one-sentence justification. No "TBD", no "we should consider". Auditors grade against these verbatim. If a decision needs revisiting, that's a new spec — not an edit.)_

{{locked_decisions}}

## Themes declared

_(Every theme the auditor must verify. Minimum {{themes_minimum}}. If only 1 is declared, the theme-swap acceptance criterion is waived but the auditor MUST note this in its report.)_

{{themes}}

## Phases

_(Each phase ships in one PR. List in order. Each phase has its own block below.)_

{{phase_index}}

---

## Phase {{phase_number}} — {{phase_name}}

### Deliverables

_(Concrete artifacts. File-level. Atom contracts go here.)_

#### Tokens

_(CSS custom properties added to theme files. Each entry: name + type + scope.)_

{{tokens}}

#### Atoms

_(For each new atom: name, file path, TS interface (verbatim, no abbreviations), 3-line behavior note.)_

{{atoms}}

#### Showcase route

_(A `/_showcase` route lists every new atom in its variants. Dev-only (`import.meta.env.DEV`). Used by the auditor for screenshot capture. Spec the entries here.)_

{{showcase_entries}}

### Acceptance criteria

_(Falsifiable. Each AC is gradable by typecheck, lint, runtime check, or visual diff. Universal AC are listed here per `instructions.yaml.universal_ac`; spec-declared AC follow below.)_

#### Universal AC

{{universal_ac}}

#### Spec-declared AC

{{spec_ac}}

### Out of scope for this phase

_(Things the auditor should NOT surface as findings. Use sparingly — overuse hides real gaps.)_

{{phase_out_of_scope}}

---

<!--
Append additional `## Phase {{N}} — {{name}}` blocks above for each phase
in the spec. The phase index at the top of the document must enumerate them
in order. Each phase is its own implementer dispatch and its own audit pass.
-->
