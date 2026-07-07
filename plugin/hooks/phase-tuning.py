#!/usr/bin/env python3
"""phase-tuning.py — logic for the phase-tuning PreToolUse hook.

Reads a PreToolUse event on stdin, resolves per-phase spawn tuning from
.claude/sdlc.yml, and — only when it actually changes something — prints a
PreToolUse `updatedInput` payload that rewrites the Agent/TeamCreate arguments.

Fails open on ANY error (no output, exit 0): a tuning layer must never wedge a
spawn. See phase-tuning.sh for the full contract. Deliberately dependency-free
(no PyYAML): the four config blocks are flat `role: value` maps under a
top-level key, which a ~20-line scanner parses reliably.
"""
import sys
import os
import json


def fail_open():
    # Emit nothing; the spawn proceeds exactly as issued.
    sys.exit(0)


def strip_value(v):
    """Drop an inline comment ( ' # ...' ), then surrounding quotes/space."""
    h = v.find(" #")
    if h != -1:
        v = v[:h]
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1]
    return v.strip()


def read_block(lines, key):
    """Return {subkey: value} for a top-level `key:` map whose entries are
    indented `subkey: value` lines. Minimal YAML — no anchors/flow/nesting —
    which is all these knobs ever use. A commented-out `# key:` never matches
    (we only accept an uncommented key at column 0), so a fully-commented block
    stays inert."""
    out = {}
    in_block = False
    for line in lines:
        stripped = line.strip()
        # A top-level key sits at column 0 (no indent).
        if line[:1] not in (" ", "\t") and stripped and not stripped.startswith("#"):
            if in_block:
                break  # next top-level key ends our block
            head = stripped.split(":", 1)[0].strip()
            in_block = (head == key)
            continue
        if not in_block:
            continue
        if not stripped or stripped.startswith("#"):
            continue  # blank / commented entry
        if ":" not in stripped:
            continue
        sub, val = stripped.split(":", 1)
        val = strip_value(val)
        if val != "":
            out[sub.strip()] = val
    return out


def read_nested_block(lines, key):
    """Return {role: {knob: value}} for a two-level `key:` block:

        phases:
          coordinator:
            model: opus
            effort: high
          reviewer: { model: opus, effort: high }   # inline flow map also OK

    A role header is an indented `role:` line with no scalar value; a knob is a
    deeper `knob: value` line under the current role. An inline `role: {a: b}`
    is parsed too. Same minimal-YAML discipline as read_block (no PyYAML)."""
    out = {}
    in_block = False
    role = None
    for line in lines:
        stripped = line.strip()
        if line[:1] not in (" ", "\t") and stripped and not stripped.startswith("#"):
            if in_block:
                break
            head = stripped.split(":", 1)[0].strip()
            in_block = (head == key)
            role = None
            continue
        if not in_block:
            continue
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            continue
        name, rest = stripped.split(":", 1)
        name = name.strip()
        rest_stripped = strip_value(rest)
        if rest_stripped.startswith("{"):
            # inline flow map: role: { model: opus, effort: high }
            body = rest_stripped.strip("{}").strip()
            knobs = {}
            for pair in body.split(","):
                if ":" in pair:
                    k, v = pair.split(":", 1)
                    v = strip_value(v)
                    if v != "":
                        knobs[k.strip()] = v
            if knobs:
                out[name] = knobs
            role = None
        elif rest_stripped == "":
            # role header; its knobs follow on deeper-indented lines
            role = name
            out.setdefault(role, {})
        elif role is not None:
            # knob under the current role
            out[role][name] = rest_stripped
    return {r: k for r, k in out.items() if k}


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        fail_open()

    if data.get("tool_name", "") not in ("Agent", "TeamCreate"):
        fail_open()

    tool_input = data.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        fail_open()

    # Role = subagent_type (Agent) / agent_type (TeamCreate), namespace stripped.
    raw_role = tool_input.get("subagent_type") or tool_input.get("agent_type") or ""
    role = raw_role.rsplit(":", 1)[-1].strip()
    if not role:
        fail_open()

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    sdlc_path = os.path.join(project_dir, ".claude", "sdlc.yml")
    if not os.path.isfile(sdlc_path):
        fail_open()

    try:
        with open(sdlc_path, "r") as f:
            lines = f.read().splitlines()
    except Exception:
        fail_open()

    # Preferred grouped schema: `phases.<role>.<knob>`. Flat `phase_<knob>.<role>`
    # blocks (shipped in 0.2.17) stay honored as a backward-compat fallback;
    # grouped wins per-knob when both are present.
    grouped = read_nested_block(lines, "phases").get(role, {})
    models = read_block(lines, "phase_models")
    efforts = read_block(lines, "phase_effort")
    maxturns = read_block(lines, "phase_max_turns")
    worktrees = read_block(lines, "phase_worktree")

    def truthy(v):
        return str(v).strip().lower() in ("true", "yes", "1")

    def resolve(knob, flat_map):
        # grouped phases.<role>.<knob> first, then flat phase_<knob>.<role>.
        v = grouped.get(knob)
        return v if v is not None else flat_map.get(role)

    # Global `worktree.enabled: true` is the legacy knob; it means the same as
    # `phases.implementer.worktree: true`, so the hook honors it too — all
    # worktree policy resolves here rather than half in command prose.
    global_worktree = truthy(read_block(lines, "worktree").get("enabled", ""))
    model = resolve("model", models)
    effort = resolve("effort", efforts)
    max_turns = resolve("max_turns", maxturns)
    worktree_val = grouped.get("worktree")
    if worktree_val is None:
        worktree_val = worktrees.get(role)
    role_worktree = truthy(worktree_val) or (role == "implementer" and global_worktree)

    inject = {}
    if "model" not in tool_input and model is not None:
        inject["model"] = model
    if "effort" not in tool_input and effort is not None:
        inject["effort"] = effort
    if "maxTurns" not in tool_input and max_turns is not None:
        try:
            inject["maxTurns"] = int(max_turns)
        except (ValueError, TypeError):
            pass
    if "isolation" not in tool_input and role_worktree:
        inject["isolation"] = "worktree"

    if not inject:
        fail_open()

    merged = dict(tool_input)
    merged.update(inject)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "updatedInput": merged,
        }
    }))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        fail_open()
