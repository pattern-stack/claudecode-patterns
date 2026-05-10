<!--
The envelope artifact is YAML, not markdown. The fenced block below IS the
template — producers extract the content between the ```yaml fences,
substitute {{tokens}}, and emit. The .md extension preserves the canvas
convention (`template.md`) while keeping the fenced content YAML-parseable.
-->

```yaml
phase: {{phase}}                          # understander | planner | specifier | implementer | validator | coordinator
issue: {{issue}}                          # tracker key (e.g. ABC-101) | null
stack: {{stack}}                          # plan slug | null
status: {{status}}                        # complete | halted | failed | in-progress
artifact:
  path: {{artifact_path}}                 # relative path on disk OR url (PR / dashboard)
  type: {{artifact_type}}                 # research | plan | spec | branch+pr | report | status
  size: {{artifact_size}}                 # chars or LOC; null if not applicable
gate_action:
  enforces: {{gate_enforces}}             # gate labels this halts on (list)
  sets: {{gate_sets}}                     # gate labels this sets (list)
headline: "{{headline}}"                  # one-line outcome (≤120 chars)
body: |
  {{body}}                                # 2-5 paragraph markdown summary (≤5000 chars)
attention:
  surfaces: {{attention_surfaces}}        # subset of: chat | tracker | slack | log | pr
  dm: {{attention_dm}}                    # explicit attention asks (handles or empty list)
next:
  command: {{next_command}}               # e.g. "/sync-issues" | "/develop ABC-101" | null
  reason: "{{next_reason}}"               # why this is the next step
metadata:
  duration_seconds: {{duration_seconds}}  # wall time for this phase run
  model: {{model}}                        # model id (e.g. claude-opus-4-7)
  cost_usd: {{cost_usd}}                  # estimated cost; null if unknown
```
