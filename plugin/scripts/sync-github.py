#!/usr/bin/env python3
"""
================================================================================
  TEMPORARY — github-only sync runtime for /sync-issues.
================================================================================

  WHY THIS EXISTS:
    The /sync-issues command is designed as an adapter-neutral procedure (see
    .claude/primitives/task-management/README.md). At runtime today it is
    hand-executed by an LLM step-by-step against the active adapter's bindings.
    That works but is slow and brittle for the github path, which is pure shell
    and could just run as a script.

  WHY IT IS TEMPORARY:
    The proper home for cross-adapter sync runtime is the TaskManagementToolbox,
    which will implement BOTH github and linear adapters behind the port
    contract. This script does NOT do that — it is github-only, because the
    linear adapter binds to MCP tools that are not callable from a shell script.
    Shipping linear support here would require re-implementing the Linear API
    surface (auth + GraphQL) which belongs in the Toolbox.

  CONSEQUENCE:
    There is a real domain gap between the linear path (LLM-driven, MCP) and the
    github path (this script, shell). Until the Toolbox ships, do NOT generalize
    this script — it is a deliberate shortcut.

  DELETE WHEN:
    TaskManagementToolbox ships a cross-adapter implementation. At that point:
      1. Update .claude/commands/sync-issues.md to point at the Toolbox runtime.
      2. Delete this file.
      3. Delete any references from sdlc.yml or skill docs.

  OUT OF SCOPE (intentional gaps vs full port contract):
    - state:* labels (owned by agents/human at runtime, not sync)
    - Project v2 field moves (requires /sdlc:link-project cache; not yet shipped)
    - set-type / Issue Types (owner-type detection complexity)
    - milestone assignment (rare; can be done manually)
    - layer custom field (rare; can be done manually)
================================================================================
"""

import json
import subprocess
import sys
from pathlib import Path


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True)


def gh_json(*args):
    return json.loads(gh(*args).stdout)


def yaml_load(path):
    """Parse a YAML file via `yq` (no PyYAML dep) and return as Python dict."""
    return json.loads(subprocess.run(
        ["yq", "-o=json", ".", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout)


def find_by_marker(repo, marker):
    result = gh_json("issue", "list", "--repo", repo, "--search", f"{marker} in:body",
                     "--state", "all", "--json", "number", "--limit", "1")
    return result[0]["number"] if result else None


def create_issue(repo, title, body, labels):
    label_args = []
    for lbl in labels:
        label_args += ["--label", lbl]
    result = gh("issue", "create", "--repo", repo, "--title", title, "--body", body, *label_args)
    return int(result.stdout.strip().rsplit("/", 1)[-1])


def update_issue(repo, num, title, body):
    gh("issue", "edit", str(num), "--repo", repo, "--title", title, "--body", body)


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: sync-github.py <plan.yaml>")

    plan_path = Path(sys.argv[1])
    plan = yaml_load(plan_path)
    sdlc = yaml_load(Path(".claude/sdlc.yml"))

    repo = plan["plan"].get("repo") or sdlc["repo"]
    slug = plan["plan"]["slug"]
    auto_approve = plan["plan"].get("auto_approve")  # True | False | None

    print(f"Plan:  {plan_path}")
    print(f"Repo:  {repo}")
    print(f"Slug:  {slug}\n")

    # --- Epic (idempotent by marker) ---
    epic_marker = f"[plan-epic:{slug}]"
    epic_num = find_by_marker(repo, epic_marker)
    epic_body = plan["plan"]["epic_body"].rstrip() + f"\n\n{epic_marker}"
    if epic_num is None:
        epic_num = create_issue(repo, plan["plan"]["epic_title"], epic_body, [])
        print(f"Epic created: #{epic_num}  \"{plan['plan']['epic_title']}\"")
    else:
        update_issue(repo, epic_num, plan["plan"]["epic_title"], epic_body)
        print(f"Epic exists:  #{epic_num}  (updated)")

    # --- Leaves (idempotent by marker) ---
    print(f"\nLeaves ({len(plan['issues'])}):")
    key_to_num = {}
    for issue in plan["issues"]:
        key = issue["key"]
        marker = f"[plan-key:{slug}/{key}]"
        body = issue["description"].rstrip() + f"\n\n{marker}"
        labels = list(issue.get("labels") or [])
        if auto_approve is True:
            labels.append("gate:auto")
        elif auto_approve is False:
            labels.append("gate:human")

        existing = find_by_marker(repo, marker)
        if existing is None:
            num = create_issue(repo, issue["title"], body, labels)
            print(f"  Created  {key}  → #{num}")
        else:
            update_issue(repo, existing, issue["title"], body)
            num = existing
            print(f"  Updated  {key}  → #{num}")
        key_to_num[key] = num

    # --- Sub-issues via GraphQL addSubIssue ---
    epic_node = gh_json("issue", "view", str(epic_num), "--repo", repo, "--json", "id")["id"]
    wired = 0
    for num in key_to_num.values():
        child_node = gh_json("issue", "view", str(num), "--repo", repo, "--json", "id")["id"]
        try:
            gh("api", "graphql",
               "-f", "query=mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{id}}}",
               "-F", f"p={epic_node}", "-F", f"c={child_node}")
            wired += 1
        except subprocess.CalledProcessError:
            pass  # idempotent — already wired (GraphQL returns error on duplicate)
    print(f"\nSub-issues wired: {wired}/{len(key_to_num)}")

    # --- depends_on (append "Depends on: #N, #N" to body, idempotent) ---
    dep_count = 0
    for issue in plan["issues"]:
        deps = issue.get("depends_on") or []
        if not deps:
            continue
        num = key_to_num[issue["key"]]
        dep_nums = [key_to_num[d] for d in deps if d in key_to_num]
        if not dep_nums:
            continue
        dep_line = "Depends on: " + ", ".join(f"#{n}" for n in dep_nums)
        cur_body = gh_json("issue", "view", str(num), "--repo", repo, "--json", "body")["body"]
        if dep_line not in cur_body:
            new_body = cur_body.rstrip() + f"\n\n{dep_line}\n"
            gh("issue", "edit", str(num), "--repo", repo, "--body", new_body)
            dep_count += 1
    print(f"Blocking relations applied: {dep_count}")

    print(f"\nDone. Next: /design <issue-key>")


if __name__ == "__main__":
    main()
