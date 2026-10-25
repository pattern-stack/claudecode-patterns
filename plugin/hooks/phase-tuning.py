#!/usr/bin/env python3
"""phase-tuning.py — logic for the phase-tuning PreToolUse hook.

Reads a PreToolUse event on stdin, resolves per-phase spawn tuning from
.claude/sdlc.yml, and prints a PreToolUse payload when it has something to say:
`updatedInput` rewrites the Agent/TeamCreate arguments (tuning), and
`additionalContext` carries a placement hint.

The hint: when the repo places the spawned role on another machine, the spawn
still runs on this box (a subagent can't change machines). The hook never sets
a permission decision (D3: a hint, never a deny), so the user's permission rules
still apply. It only tells the coordinator that the NEXT run of the role should
start on the placed machine (`sdlc delegate <role> --issue <n>`). Placement is
looked up through plugin/lib/machines.py, imported lazily and only when
sdlc.yml mentions `machine` at all.

Fails open on ANY error (no tuning change, no hint, exit 0): a tuning layer must
never wedge a spawn. That includes placement: no registry, a broken registry or
sdlc.yml, an import failure, a lookup that raises or calls sys.exit, and a lookup
that outlasts HOOK_DEADLINE. See phase-tuning.sh for the full contract. The
tuning scanner is deliberately dependency-free (no PyYAML): the config blocks are
flat `role: value` maps under a top-level key, which a small scanner parses.
"""
import time
_T0 = time.monotonic()  # the deadline's clock: the first statement after the docstring

import contextlib
import io
import json
import os
import shlex
import signal
import sys
import threading

NULLS = ("null", "Null", "NULL", "~")   # unquoted YAML nulls read as unset
HINT_MAX_CHARS = 2000                   # over this the herdr line is dropped; still over -> no hint
VALUE_MAX = 200                         # reason cut here; a longer command value drops the herdr line
ANY_SHOWN = 3                           # `any` candidates named before " and <k> more"
HOOK_DEADLINE = 3.5                     # seconds from _T0: above LOOKUP_BUDGET + import, below the 5 s hook timeout


def fail_open():
    # Emit nothing; the spawn proceeds exactly as issued.
    sys.exit(0)


def _clean(v):
    """Drop an inline comment ( ' # ...' ), then surrounding whitespace."""
    h = v.find(" #")
    if h != -1:
        v = v[:h]
    return v.strip()


def scalar(raw):
    """Read a YAML scalar: comment and whitespace stripped. None means unset: an
    empty value or an UNQUOTED null (null, Null, NULL, ~). Surrounding quotes are
    stripped, so a quoted "null" stays the string null."""
    v = _clean(raw)
    if v == "" or v in NULLS:
        return None
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1].strip()
    return v if v != "" else None


def read_block(lines, key):
    """Return {subkey: value} for a top-level `key:` map whose entries are
    indented `subkey: value` lines. Minimal YAML — no anchors/flow/nesting —
    which is all these knobs ever use. A commented-out `# key:` never matches
    (we only accept an uncommented key at column 0), so a fully-commented block
    stays inert. A blank or null value is unset."""
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
        val = scalar(val)
        if val is not None:
            out[sub.strip()] = val
    return out


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def read_nested_block(lines, key):
    """Return {role: {knob: value}} for a two-level `key:` block:

        phases:
          coordinator:
            model: opus
            effort: high
          reviewer: { model: opus, effort: high }   # inline flow map also OK

    Role vs knob is decided by indent, never by the value. The role indent is
    the indent of the block's first entry. A line at or left of it is a role
    entry and always closes the role before it:
      - `name: {...}` closed on its line is an inline role (leaves no role open);
      - `name: {` unclosed is a multi-line flow map: ignored, fails closed;
      - `name:` with a blank or null value opens role `name`;
      - `name: <scalar>` is not a role map; no role is open until the next entry.
    Within an open role the knob indent is the indent of its first deeper line.
    Only lines at exactly that indent are knobs (blank/null = unset, a `{` value
    skipped); deeper lines belong to a nested map and are ignored."""
    out = {}
    in_block = False
    role = None
    role_indent = None
    knob_indent = None
    for line in lines:
        stripped = line.strip()
        if line[:1] not in (" ", "\t") and stripped and not stripped.startswith("#"):
            if in_block:
                break
            head = stripped.split(":", 1)[0].strip()
            in_block = (head == key)
            role = None
            role_indent = None
            knob_indent = None
            continue
        if not in_block:
            continue
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            continue
        ind = _indent(line)
        if role_indent is None:
            role_indent = ind
        name, rest = stripped.split(":", 1)
        name = name.strip()
        clean = _clean(rest)
        if ind <= role_indent:
            role = None
            knob_indent = None
            if clean.startswith("{"):
                if clean.endswith("}"):
                    # inline flow map: role: { model: opus, effort: high }
                    body = clean.strip("{}").strip()
                    knobs = {}
                    for pair in body.split(","):
                        if ":" in pair:
                            k, v = pair.split(":", 1)
                            v = scalar(v)
                            if v is not None:
                                knobs[k.strip()] = v
                    if knobs:
                        out[name] = knobs
                # else: a multi-line flow map, ignored (fails closed)
            elif clean == "" or clean in NULLS:
                role = name  # role header; its knobs follow on deeper lines
                out.setdefault(role, {})
            # else: a scalar role entry; no role is open
        elif role is not None:
            if knob_indent is None:
                knob_indent = ind
            if ind == knob_indent and not clean.startswith("{"):
                v = scalar(rest)
                if v is not None:
                    out[role][name] = v
    return {r: k for r, k in out.items() if k}


def may_place(lines):
    """Cheap gate. Every placement opt-in key contains `machine`, so a file with no
    non-comment line mentioning it can't opt in, and the hook never imports
    machines.py for it. A false positive only costs a lookup."""
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "machine" in line:
            return True
    return False


def timing(tool_name, tool_input):
    """'running' when the hook is sure the spawn persists (TeamCreate, or an Agent
    with run_in_background true); else 'ran'. The unset case is ambiguous in
    Claude Code, and 'ran' is the wording that is safe when wrong."""
    if tool_name == "TeamCreate":
        return "running"
    if tool_name == "Agent" and tool_input.get("run_in_background") is True:
        return "running"
    return "ran"


class _Deadline(BaseException):
    """BaseException, so no `except Exception` downstream can absorb it."""


def _on_alarm(signum, frame):
    raise _Deadline()


def _armed_hint(tool_name, raw_role, role, project_dir, spawn):
    """Arm the deadline, look the role up, format the hint. The timer is always
    disarmed (first) and the old handler restored (second) before this returns,
    and only when this call actually armed them.

    Accepted: an alarm landing in subprocess.Popen's fork-to-exec window (where
    machines.py's preexec_fn applies RLIMIT_AS) raises before run() holds the
    child, so that one yq child is orphaned. The window is well under a
    millisecond, and the orphan has DEVNULL stdin and a 1 GiB memory limit."""
    armed = False
    old = None
    try:
        if hasattr(signal, "setitimer") and threading.current_thread() is threading.main_thread():
            old = signal.signal(signal.SIGALRM, _on_alarm)
            armed = True
            signal.setitimer(signal.ITIMER_REAL, max(0.05, HOOK_DEADLINE - (time.monotonic() - _T0)))
        sys.dont_write_bytecode = True
        lib = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
        sys.path.insert(0, lib)
        with contextlib.redirect_stdout(io.StringIO()):
            import machines
            placement, registry, _cfg = machines.locate(
                role, None, project_dir=project_dir, budget=machines.LOOKUP_BUDGET)
            return format_hint(tool_name, raw_role, role, placement, registry,
                               timing(tool_name, spawn))
    finally:
        if armed:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old if old is not None else signal.SIG_DFL)


def placement_hint(tool_name, raw_role, role, project_dir, spawn):
    """The outer guard: any failure, SystemExit and the deadline included, is no
    hint. sys.stdout is saved and restored, because an alarm inside
    redirect_stdout's __enter__/__exit__ would leave it on the StringIO and emit()
    would then print into nothing."""
    real = sys.stdout
    try:
        return _armed_hint(tool_name, raw_role, role, project_dir, spawn)
    except KeyboardInterrupt:
        raise
    except BaseException:
        return None
    finally:
        sys.stdout = real


def _cap(text, n):
    return text if len(text) <= n else text[:n - 3] + "..."


def format_hint(tool_name, raw_role, role, placement, registry, when):
    """Pure. Decision table -> None | remote hint (ran / running) | nowhere hint."""
    p = placement
    if p.status == "off" or p.requested is None:
        return None
    if p.status in ("placed", "fallback"):
        if p.local or not p.machine:
            return None
        remote = True
    elif p.status == "unplaceable":
        remote = False
    else:
        return None
    if len(role) > VALUE_MAX or len(raw_role) > VALUE_MAX:
        return None
    what = "Agent subagent" if tool_name == "Agent" else "TeamCreate teammate"
    as_what = "as an Agent subagent" if tool_name == "Agent" else "as a TeamCreate teammate"
    reason = _cap(str(p.reason).replace("**", "").replace("`", ""), VALUE_MAX)
    head = "sdlc machines: %s." % reason
    if not remote:
        text = (head + "\nThis %s runs on this box anyway: the hook never blocks a spawn, and sdlc delegate "
                "would refuse this role too. Fix the placement or needs.%s in sdlc.yml; sdlc machines check "
                "lists every refusal." % (what, role))
        return text if len(text) <= HINT_MAX_CHARS else None

    local = registry.local.name
    m = p.machine
    q_role = shlex.quote(role)
    delegate = "  sdlc delegate %s --issue <n>" % q_role
    tail = ("Results come back through GitHub (a pushed branch or a PR comment), so ask for that in the "
            "brief. Explain: sdlc machines where %s" % role)
    any_line = None
    if len(p.candidates) > 1:
        shown = list(p.candidates[:ANY_SHOWN])
        more = len(p.candidates) - len(shown)
        any_line = "sdlc delegate picks the least loaded of %s%s" % (
            ", ".join(shown), " and %d more" % more if more else "")
    herdr_line = None
    mach = registry.get(m)
    if mach is not None and mach.transport.kind == "herdr" and mach.transport.herdr:
        label, workdir = mach.transport.herdr, mach.workdir
        vals = [label, raw_role] + ([workdir] if workdir else [])
        if all(len(v) <= VALUE_MAX for v in vals):
            ql = shlex.quote(label)
            herdr_line = ("Without sdlc delegate: herdr --machine %s tab create --no-focus%s, then herdr "
                          "--machine %s agent start %s-<n> --kind claude --pane <pane id from tab create> "
                          "-- --agent %s, then herdr --machine %s agent prompt %s-<n> '<brief>'." % (
                              ql, " --cwd %s" % shlex.quote(workdir) if workdir else "", ql, q_role,
                              shlex.quote(raw_role), ql, q_role))

    def build(with_herdr):
        if when == "ran":
            body = [head,
                    "%s already ran here, on this box ('%s'), %s: a subagent can't change machines. "
                    "Its result stands; don't run this call again." % (role, local, as_what),
                    "sdlc.yml places %s on '%s': start the next %s there, as a herdr agent, with:" % (
                        role, m, role),
                    delegate]
        else:
            body = [head,
                    "%s is running here now, on this box ('%s'), %s: a subagent can't change machines." % (
                        role, local, as_what),
                    "Either let it finish and use its result, then start the next %s on '%s'; or stop it "
                    "and start this job on '%s' instead. Never both." % (role, m, m),
                    "To start %s on '%s' as a herdr agent:" % (role, m),
                    delegate]
        if any_line:
            body.append(any_line)
        if with_herdr and herdr_line:
            body.append(herdr_line)
        body.append(tail)
        return "\n".join(body)

    text = build(True)
    if len(text) > HINT_MAX_CHARS:
        text = build(False)
    return text if len(text) <= HINT_MAX_CHARS else None


def emit(merged, hint):
    """Print at most one JSON object; key order hookEventName, updatedInput,
    additionalContext. Never a permission decision."""
    out = {"hookEventName": "PreToolUse"}
    if merged:
        out["updatedInput"] = merged
    if hint:
        out["additionalContext"] = hint
    print(json.dumps({"hookSpecificOutput": out}))


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

    merged = dict(tool_input)
    merged.update(inject)

    # Placement hint (D3: a hint, never a deny). Own guard; never raises.
    hint = None
    if may_place(lines):
        hint = placement_hint(data.get("tool_name", ""), raw_role, role, project_dir, tool_input)

    if not inject and not hint:
        fail_open()
    emit(merged if inject else None, hint)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        fail_open()
