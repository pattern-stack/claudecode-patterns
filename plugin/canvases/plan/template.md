# Pure-structural skeleton for a stack plan.
# Renaming or reordering fields here means updating instructions.yaml and the schema.
# Tokens are {{name}} and {{nested.name}}; the planner substitutes per-stack.

plan:
  slug: {{plan.slug}}
  summary: {{plan.summary}}
  milestone: {{plan.milestone}}

  epic_title: {{plan.epic_title}}
  epic_body: |
    {{plan.epic_body}}

  # repo: {{plan.repo}}                     # optional; defaults to sdlc.yml.repo
  # stack:                                  # optional stack topology
  #   base: {{plan.stack.base}}
  #   depends_on: {{plan.stack.depends_on}}
  # auto_approve: {{plan.auto_approve}}     # OPTIONAL: stack-level Gate-1 mode override.
                                            # When true, /sync-issues stamps `gate:auto` on each
                                            # leaf at creation; specifier auto-approves at design.
                                            # Per-issue override via gate:auto / gate:human label.

issues:
  - key: {{issue.key}}
    title: {{issue.title}}
    layer: {{issue.layer}}                  # OPTIONAL: L0..L7
    # milestone: {{issue.milestone}}        # OPTIONAL: overrides plan.milestone
    depends_on: {{issue.depends_on}}
    parallel_with: {{issue.parallel_with}}
    labels: {{issue.labels}}
    description: |
      {{issue.description}}
