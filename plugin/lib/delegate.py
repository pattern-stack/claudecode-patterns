"""sdlc delegate: place a phase or agent on a machine, start Claude Code there, brief it.

#137's placement says where a role may run. This module picks among those machines (trust and fit
first, then load), starts a Claude Code agent through herdr in the machine's `workdir`, answers the
first-start dialogs the registry declares, briefs the agent with a mission whose only return path is
GitHub, and records where it went. See .ai-docs/stacks/machines/specs/139.md.

Rules for importers (bin/sdlc), as machines.py: this module prints nothing, never calls sys.exit and
does no I/O at import time. It raises `Refused` (nothing was started, no pane touched) or
`StartFailed` (a machine was chosen), and returns plain dataclasses. Every herdr call goes through
herdr.py, so tests swap in a fake `herdr` on PATH. Placement comes through machines.py's public
names only (rule 10). Python >= 3.8, stdlib only. YAML only through `machines.parse_yaml`.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import time
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, FrozenSet, Iterable, List, Mapping, Optional, Tuple

import herdr
import machines

MACHINE_WORDS = ("auto", "any", "local")        # plus a registered name
HEAVY_CAPS = ("full-suite", "browser", "docker")  # D5
BROWSER_CAP = "browser"
EFFORTS = ("low", "medium", "high", "xhigh", "max")
AGENT_NAME = r"[a-z][a-z0-9_-]{0,31}"           # herdr's rule for live agent names (fullmatch)
WORKSPACE_LABEL = "sdlc-delegate"
TAB_PREFIX = "sdlc:"
SHELLS = ("bash", "zsh", "sh", "fish", "dash")
MARKER = "❯"                               # Claude Code's selection marker
ASCII_MARKER = ">"                              # 2.1.310's figures fallback; a marker only on an option line
START_TIMEOUT = 90.0                            # seconds; --start-timeout default (compute: --timeout 90000)
PROMPT_TIMEOUT = 60.0
POLL = 0.5
GATE_KEY_PAUSE = 0.5                            # after a dialog is first seen, and between Down and Enter
CWD_WAIT = 5.0                                  # wait for a new pane's foreground_cwd to equal the workdir
KEY_SETTLE = 2.0                                # wait for the marker to move after Down
CLEAR_WAIT = 5.0                                # wait for the screen to change after Enter
MAX_ANSWERS_PER_GATE = 2
MAX_STARTUP_ROUNDS_RECORDED = 30
MISSION_MAX = 64 * 1024
STATE_RELPATH = "sdlc/delegates"                # under ${XDG_STATE_HOME:-~/.local/state}
GH_NOT_LOGGED_IN = "sdlc-delegate: gh is not logged in on {machine}"
OUTPUT_LINES = 40                               # pane lines shown after a failed start
GIT_TIMEOUT = 5.0
_REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


# ── errors and data ──────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Verdict:
    machine: str
    eligible: bool
    why: str                                    # "1 agent, limit 4" | "full: 4 agents, limit 4" | "busy: ..." | unfit_reason text
    agents: Optional[int] = None
    live_names: FrozenSet[str] = frozenset()


class Refused(Exception):
    """Nothing was started and no pane was touched (exit 1)."""

    def __init__(self, reason: str, considered: Tuple[Verdict, ...] = ()):
        super().__init__(reason)
        self.reason = reason
        self.considered = tuple(considered)


class StartFailed(Exception):
    """A machine was chosen and something failed (exit 3)."""

    def __init__(self, reason: str, machine: str, pane_id: Optional[str] = None, output: str = "",
                 pane_closed: bool = False, record_path: Optional[Path] = None,
                 close_error: Optional[str] = None):
        super().__init__(reason)
        self.reason = reason
        self.machine = machine
        self.pane_id = pane_id
        self.output = output
        self.pane_closed = pane_closed
        self.record_path = record_path
        self.close_error = close_error


class _Fail(Exception):
    """Internal: a start step failed. `closed` is true when the pane was already closed."""

    def __init__(self, reason: str, closed: bool = False):
        super().__init__(reason)
        self.reason = reason
        self.closed = closed


@dataclass(frozen=True)
class Gate:
    name: str                                   # a machines.FIRST_START_GATES name
    patterns: Tuple[str, ...]                   # lower-case substrings of the whitespace-collapsed visible screen
    options: Tuple[str, ...]                    # the dialog's own option labels; only these lines can carry a marker
    target_label: str                           # one of options


GATES: Dict[str, Gate] = {
    "trust-prompt": Gate(
        "trust-prompt",
        ("yes, i trust this folder", "is this a project you created or one you trust"),
        ("No, exit", "No, continue without these permissions", "Yes, I trust this folder"),
        "Yes, I trust this folder"),
    "fullscreen-notice": Gate(
        "fullscreen-notice",
        ("try the new fullscreen renderer",),
        ("Yes, try it", "Not now"),
        "Not now"),
}
NEVER_ANSWER: Dict[str, Tuple[str, ...]] = {
    "auto-mode-teach": ("teach auto mode about your environment",),
}


@dataclass(frozen=True)
class Tuning:
    model: Optional[str]
    effort: Optional[str]
    source: Dict[str, str]                      # knob -> "phases.<role>.model" | "phase_models.<role>" | ...


@dataclass(frozen=True)
class Decision:
    role: str
    kind: Optional[str]
    name: str
    machine: machines.Machine
    label: Optional[str]                        # herdr --machine label; None = the local server
    workdir: str                                # as passed to herdr (local: ~-expanded)
    placement: machines.Placement
    via: str                                    # "any (phase_machines.reviewer)" | "worker-1 (default target)" | "--machine NAME"
    overrides: Optional[str]                    # "<at> ('<value>')" when --machine overrides the repo's placement
    considered: Tuple[Verdict, ...]
    tuning: Tuning
    claude_args: Tuple[str, ...]                # ("--permission-mode", "auto", ["--model", m], ["--effort", e])
    browser_job: bool
    issue: Optional[int]
    repo: Optional[str]                         # "owner/name"
    mission: str
    name_explicit: bool = False
    prompt: Optional[str] = None
    warnings: Tuple[str, ...] = ()


@dataclass(frozen=True)
class PanePlan:
    action: str                                 # "create-workspace" | "reuse-pane" | "create-tab"
    workspace_id: Optional[str]                 # None when action == "create-workspace"
    tab_id: Optional[str]                       # the free pane's tab (reuse-pane), else None
    pane_id: Optional[str]                      # the free pane (reuse-pane), else None


@dataclass(frozen=True)
class Started:
    decision: Decision
    workspace_id: str
    tab_id: str
    pane_id: str                                # every call after agent start targets this
    argv: Tuple[str, ...]                       # from pane process-info (the claude process), else the intended command line
    argv_source: str                            # "process-info" | "intended"
    gates_answered: Tuple[str, ...]
    startup: Tuple[dict, ...]                   # the loop's rounds
    status: str                                 # agent_status after the brief
    record_path: Optional[Path]
    record_error: Optional[str]
    name: str = ""                              # the name the agent finally has
    briefed: bool = False
    warnings: Tuple[str, ...] = ()


# ── pure helpers ─────────────────────────────────────────────────────────────

def _norm(text: str) -> str:
    return " ".join((text or "").replace(" ", " ").split()).casefold()


def _ptext(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def tuning_for(doc: object, role: str) -> Tuning:
    """model and effort for `role`, as the phase-tuning hook reads them: grouped beats flat. Raises Refused."""
    if not isinstance(doc, dict):
        return Tuning(None, None, {})
    phases = doc.get("phases")
    grouped = phases.get(role) if isinstance(phases, dict) else None
    grouped = grouped if isinstance(grouped, dict) else {}
    values: Dict[str, Optional[str]] = {}
    source: Dict[str, str] = {}
    for knob, flat_key in (("model", "phase_models"), ("effort", "phase_effort")):
        flat = doc.get(flat_key)
        flat = flat if isinstance(flat, dict) else {}
        found = None
        for where, raw in (("phases.%s.%s" % (role, knob), grouped.get(knob)),
                           ("%s.%s" % (flat_key, role), flat.get(role))):
            if raw is None or (isinstance(raw, str) and not raw.strip()):
                continue
            found = (where, raw)
            break
        if found is None:
            values[knob] = None
            continue
        where, raw = found
        if not isinstance(raw, str):
            raise Refused("%s %s is not a string" % (where, machines.short_repr(raw)))
        text = raw.strip()
        if knob == "effort" and text not in EFFORTS:
            raise Refused("%s %s is not one of: %s" % (where, machines.short_repr(raw), ", ".join(EFFORTS)))
        values[knob] = text
        source[knob] = where
    return Tuning(values["model"], values["effort"], source)


def is_heavy(needs: machines.Needs) -> bool:
    return any(c in HEAVY_CAPS for c in needs.caps)


def is_browser_job(needs: machines.Needs) -> bool:
    return BROWSER_CAP in needs.caps


def _expand(path: str, env: Mapping[str, str]) -> str:
    home = env.get("HOME") or os.path.expanduser("~")
    if path == "~" or path.startswith("~/"):
        return home + path[1:]
    return path


def busy_reason(machine: machines.Machine, role: str, needs: machines.Needs,
                env: Optional[Mapping[str, str]] = None) -> Optional[str]:
    """Why a heavy `role` must not go to `machine` now, or None. One os.stat on this box."""
    heavy = [c for c in needs.caps if c in HEAVY_CAPS]
    if not heavy or not machine.gaming_sensitive or not machine.busy_flag:
        return None
    env = os.environ if env is None else env
    flag = _expand(machine.busy_flag, env)
    tail = "remove the file when the box is free, or delegate to another machine"
    if not flag.startswith("/"):
        return "busy: busy_flag %s is not an absolute path, so it can't be checked; write it as ~/... or /..." % \
            machines.short_repr(machine.busy_flag)
    try:
        os.stat(flag)
    except (FileNotFoundError, NotADirectoryError):
        return None
    except (OSError, ValueError) as exc:
        return "busy: could not check busy_flag %s (%s); %s" % (
            machines.short_repr(flag), getattr(exc, "strerror", None) or type(exc).__name__, tail)
    return "busy: %s exists and %s needs %s; %s" % (flag, role, ", ".join(heavy), tail)


def default_name(role: str, issue: Optional[int], taken: Iterable[str]) -> str:
    """`<role>-<issue>` made safe for herdr, with the next free suffix -2..-9. Raises Refused when all are taken."""
    taken = set(taken)
    base = "%s-%d" % (role, issue) if issue else role
    base = re.sub(r"[^a-z0-9_-]+", "-", base.lower()).strip("-")
    if not base:
        base = "agent"
    if not base[0].isalpha() or not base[0].isascii():
        base = "agent-" + base
    candidates = [base[:32]] + [base[:32 - len("-%d" % n)] + "-%d" % n for n in range(2, 10)]
    for name in candidates:
        if name not in taken:
            return name
    raise Refused("all nine default names for %s (%s .. %s) are live; pass --name or stop one" % (
        machines.short_repr(role), candidates[0], candidates[-1]))


def repo_from_remote(url: str) -> Optional[str]:
    """`owner/name` from a GitHub ssh or https remote URL, else None."""
    m = re.fullmatch(r"(?:https?://(?:[^@/]+@)?|ssh://git@|git://|git@)github\.com[:/]"
                     r"([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?", (url or "").strip())
    return "%s/%s" % (m.group(1), m.group(2)) if m else None


def match_gate(screen: str) -> Optional[str]:
    text = _norm(screen)
    for name, gate in GATES.items():
        if any(p in text for p in gate.patterns):
            return name
    return None


def never_answer(screen: str) -> Optional[str]:
    text = _norm(screen)
    for name, patterns in NEVER_ANSWER.items():
        if any(p in text for p in patterns):
            return name
    return None


def selected_option(screen: str, gate: Gate) -> Optional[str]:
    """The option on the single marked option line, else None. Labels match exactly (see the spec)."""
    labels = {_norm(o): o for o in gate.options}
    marked: List[str] = []
    for line in (screen or "").splitlines():
        text = _norm(line)
        is_marked = False
        for marker in (MARKER, ASCII_MARKER):
            if text.startswith(marker):
                text, is_marked = text[len(marker):].strip(), True
                break
        text = re.sub(r"^\d+\.\s*", "", text).strip()
        if is_marked and text in labels:
            marked.append(labels[text])
    return marked[0] if len(marked) == 1 else None


def mission_text(*, role: str, kind: Optional[str], machine: machines.Machine, workdir: str, name: str,
                 issue: Optional[int], repo: Optional[str], prompt: Optional[str]) -> str:
    where = machine.name
    head = "You were started by `sdlc delegate` as %s on %s, to do the %s work" % (name, where, role)
    if issue is not None:
        head += " for issue #%d" % issue + (" in %s" % repo if repo else "")
    lines = [
        head + ".",
        "",
        "Results come back through GitHub only: push a branch, or comment on the issue or pull request. Nothing",
        "is read back from this box afterwards, not files and not this terminal. If your task needs a comment",
        "or a pull request, first run `gh auth status`; if it fails, print exactly this line and stop:",
        GH_NOT_LOGGED_IN.format(machine=where),
        "A task that only pushes a branch skips that check. If you later cannot push or comment, say why in",
        "one final message and stop.",
        "",
        "You are in %s on %s.%s Make a new" % (
            workdir, where, " This box is disposable: anything you don't push is lost." if machine.persistence == "disposable" else ""),
        "working copy for this job at %s/%s: clone the repository there, or add a git worktree from an" % (workdir, name),
        "existing clone. If %s/%s already exists, it belongs to an earlier job:" % (workdir, name),
        "don't reuse, change or delete it; use %s/%s-2, -3, ... (the first that doesn't exist)." % (workdir, name),
        "Leave everything else in %s alone. When everything you made is pushed or posted, delete your working copy." % workdir,
    ]
    if issue is not None and repo:
        lines += ["", "Issue: gh issue view %d --repo %s" % (issue, repo)]
    if prompt is not None and prompt.strip():
        task = prompt
    elif issue is not None:
        task = ("If the sdlc plugin is installed here (the sdlc:%s agent and /sdlc: commands exist), follow the "
                "sdlc:%s agent's instructions for issue #%d. Otherwise do the %s work for issue #%d: read the "
                "issue and what it links to, then report back as above." % (role, role, issue, role, issue))
    else:
        task = "Do the %s work, then report back as above." % role
    lines += ["", "Task:", task]
    text = "\n".join(lines)
    if len(text) > MISSION_MAX:
        raise Refused("the mission is %d characters, over the %d limit; shorten --prompt" % (len(text), MISSION_MAX))
    return text


def follow_up(label: Optional[str], pane_id: str) -> Dict[str, str]:
    """The pasteable check / read / stop commands for a pane."""
    def q(*args: str) -> str:
        return " ".join(shlex.quote(a) for a in herdr.argv(label, *args))
    return {
        "check": q("agent", "get", pane_id),
        "read": q("pane", "read", pane_id, "--source", "recent-unwrapped", "--lines", "120"),
        "stop": q("pane", "close", pane_id),
    }


# ── records ──────────────────────────────────────────────────────────────────

def _state_dir(env: Optional[Mapping[str, str]]) -> Path:
    env = os.environ if env is None else env
    base = env.get("XDG_STATE_HOME")
    if not base:
        base = os.path.join(env.get("HOME") or os.path.expanduser("~"), ".local", "state")
    return Path(base) / STATE_RELPATH


def read_records(machine: str, env: Optional[Mapping[str, str]] = None) -> List[dict]:
    """Records of earlier delegations to `machine`. Tolerant: unreadable files are skipped."""
    out: List[dict] = []
    try:
        files = sorted((_state_dir(env) / machine).glob("*.json"))
    except OSError:
        return out
    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            out.append(data)
    return out


def _record_dict(s: Started, started_at: str) -> dict:
    d = s.decision
    return {
        "name": s.name, "role": d.role, "kind": d.placement.kind, "issue": d.issue, "repo": d.repo,
        "machine": d.machine.name, "herdr": d.label, "workspace_id": s.workspace_id, "tab_id": s.tab_id,
        "pane_id": s.pane_id, "workdir": d.workdir, "browser_job": d.browser_job,
        "claude_args": list(d.claude_args), "argv": list(s.argv), "argv_source": s.argv_source,
        "first_start": list(s.gates_answered), "startup": list(s.startup[:MAX_STARTUP_ROUNDS_RECORDED]),
        "briefed": s.briefed, "status": s.status, "started_at": started_at,
    }


def write_record(started: Started, env: Optional[Mapping[str, str]] = None,
                 started_at: Optional[str] = None) -> Path:
    """Write the record atomically. Raises OSError."""
    path = _state_dir(env) / started.decision.machine.name / ("%s.json" % started.name)
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = started_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(_record_dict(started, stamp), indent=2) + "\n", encoding="utf-8")
    os.replace(str(tmp), str(path))
    return path


# ── deciding ─────────────────────────────────────────────────────────────────

def _plural(n: int, word: str) -> str:
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def _project_root(config: machines.PlacementConfig, cwd: Optional[str]) -> Path:
    p = config.path
    if p is not None and p.name == "sdlc.yml" and p.parent.name == ".claude":
        return p.parent.parent
    return Path(cwd or os.getcwd())


def _repo_for(doc: object, config: machines.PlacementConfig, cwd: Optional[str]) -> Optional[str]:
    repo = doc.get("repo") if isinstance(doc, dict) else None
    if isinstance(repo, str) and _REPO.fullmatch(repo.strip()):
        return repo.strip()
    try:
        proc = subprocess.run(["git", "-C", str(_project_root(config, cwd)), "remote", "get-url", "origin"],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return repo_from_remote(proc.stdout) if proc.returncode == 0 else None


def _needs_problem(doc: object) -> str:
    if "needs" in getattr(doc, "dups", ()):
        return "is written more than once"
    if isinstance(doc, dict) and doc.get("needs") is not None and not isinstance(doc.get("needs"), dict):
        return "is not a map (got %s)" % type(doc.get("needs")).__name__
    return "is repeated or malformed"


def _filter(machine: machines.Machine, role: str, needs: machines.Needs, env: Mapping[str, str]) -> Optional[str]:
    """The delegate-only filters, in order (spec: workdir, busy flag, local herdr session)."""
    if not machine.workdir:
        return "no workdir in the registry (sdlc delegate starts agents there)"
    if not machine.is_local and not machine.workdir.startswith("/"):
        return "workdir %s must be an absolute path on a remote machine" % machines.short_repr(machine.workdir)
    busy = busy_reason(machine, role, needs, env)
    if busy:
        return busy
    if machine.is_local:
        if env.get("HERDR_ENV") != "1":
            return "this shell is not inside herdr (HERDR_ENV is not 1), so the local herdr server is not used"
    elif machine.transport.kind != "herdr" or not machine.transport.herdr:
        return "no herdr transport in the registry"
    return None


def decide(role: str, *, kind: Optional[str] = None, machine_arg: str = "auto",
           issue: Optional[int] = None, prompt: Optional[str] = None, name: Optional[str] = None,
           registry_file: Optional[str] = None, config_file: Optional[str] = None,
           env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None,
           probe_timeout: float = herdr.DEFAULT_TIMEOUT) -> Decision:
    """Step 1 (every refusal that needs no herdr call), the delegate filters, the load probes, the pick. Raises Refused."""
    env_map: Mapping[str, str] = os.environ if env is None else env
    role = machines.strip_role(role)
    placement, registry, config = machines.locate(role, kind, registry_file=registry_file,
                                                  config_file=config_file, env=env, cwd=cwd, budget=None)
    if placement.status == "off" and placement.off_cause in ("no-registry", "registry-errors", "sdlc-errors", "time-budget"):
        reason = placement.reason
        if placement.off_cause == "no-registry":
            reason += "; sdlc delegate needs a registry (see: sdlc machines)"
        raise Refused(reason)
    if config is None or not registry.usable:
        raise Refused(placement.reason)

    doc: object = {}
    if config.path is not None and config.exists:
        try:
            doc = machines.parse_yaml(config.path)
        except machines.RegistryError as exc:
            raise Refused("could not re-read %s: %s" % (config.path, exc))

    hint = "; see: sdlc machines check" if config.opted_in else ""
    needs = config.needs.get(role, machines.Needs())
    if config.needs_broken:
        raise Refused("the top-level needs in %s %s, so %s's needs can't be trusted%s" % (
            config.path, _needs_problem(doc), machines.short_repr(role), hint))
    if not needs.ok:
        raise Refused("needs.%s has errors in: %s%s" % (role, machines.shown_list(sorted(needs.invalid)), hint))

    tuning = tuning_for(doc, role)
    repo = _repo_for(doc, config, cwd)
    if issue is not None and not repo:
        raise Refused("can't tell which GitHub repository issue #%d is in; set repo: <owner>/<name> in .claude/sdlc.yml" % issue)

    # The candidates.
    warnings: List[str] = []
    rejected: List[Tuple[str, str]]
    if machine_arg == "auto":
        if placement.status == "unplaceable":
            raise Refused(placement.reason)
        if placement.status == "off":
            raise Refused("sdlc.yml places nothing, so --machine auto has nowhere to send %s; place it "
                          "(phase_machines, agent_machines, default_machine) or name a machine with --machine" % role)
        names = list(placement.candidates)
        rejected = list(placement.rejected)
        if placement.status == "fallback":
            warnings.append(placement.reason)
        req = placement.requested
        if placement.status == "placed" and req is not None and req.error is None and req.value == placement.target:
            via = "%s (%s)" % (placement.target, req.at)
        else:
            via = "%s (default target)" % placement.target
            if placement.status == "fallback":
                via += ", fallback"
        overrides = None
    else:
        names, rejected, text = machines.evaluate(machine_arg, registry, needs)
        if not names:
            raise Refused(text or "no machine fits")
        via = "--machine %s" % machine_arg
        req = placement.requested
        overrides = ("%s (%s)" % (req.at, machines.short_repr(req.value))
                     if req is not None and req.value is not None and req.error is None else None)

    verdicts: List[Verdict] = []
    eligible: List[Tuple[int, machines.Machine, Optional[str], Verdict]] = []
    for idx, mname in enumerate(names):
        m = registry.get(mname)
        why = machines.unfit_reason(m, needs) if m is not None else "machine %s is not in the registry" % machines.short_repr(mname)
        if why is None and m is not None:
            why = _filter(m, role, needs, env_map)
        if why is not None or m is None:
            verdicts.append(Verdict(mname, False, why or "not usable"))
            continue
        label = None if m.is_local else m.transport.herdr
        try:
            agents = herdr.agent_list(label, timeout=probe_timeout)
        except herdr.HerdrError as exc:
            verdicts.append(Verdict(mname, False, "unreachable: %s" % exc.detail))
            continue
        live = frozenset(a.get("name") for a in agents if isinstance(a, dict) and isinstance(a.get("name"), str))
        n = len(agents)
        limit = m.limits.agents
        if limit is not None and n >= limit:
            verdicts.append(Verdict(mname, False, "full: %s, limit %d" % (_plural(n, "agent"), limit), n, live))
            continue
        shown = "%s, limit %s" % (_plural(n, "agent"), "-" if limit is None else limit)
        if is_browser_job(needs) and m.limits.browser_jobs is not None:
            pairs = set((a.get("name"), a.get("pane_id")) for a in agents if isinstance(a, dict))
            jobs = sum(1 for r in read_records(m.name, env) if r.get("browser_job") is True
                       and (r.get("name"), r.get("pane_id")) in pairs)
            if jobs >= m.limits.browser_jobs:
                verdicts.append(Verdict(mname, False, "full: %s, limit %d" % (_plural(jobs, "browser job"), m.limits.browser_jobs), n, live))
                continue
            shown += ", %s, limit %d" % (_plural(jobs, "browser job"), m.limits.browser_jobs)
        v = Verdict(mname, True, shown, n, live)
        verdicts.append(v)
        eligible.append((idx, m, label, v))
    considered = tuple(verdicts) + tuple(Verdict(k, False, w) for k, w in rejected)
    if not eligible:
        raise Refused("no machine can take %s now: %s" % (role, "; ".join("%s: %s" % (v.machine, v.why) for v in verdicts)),
                      considered)

    _idx, machine, label, winner = min(eligible, key=lambda e: (e[3].agents or 0, e[0]))
    chosen = tuple(replace(v, why=v.why + "   <- picked") if v is winner else v for v in considered)
    if name is not None:
        if name in winner.live_names:
            raise Refused("agent name %s is already live on %s" % (machines.short_repr(name), machine.name), chosen)
        final = name
    else:
        final = default_name(role, issue, winner.live_names)
    workdir = _expand(machine.workdir or "", env_map) if machine.is_local else (machine.workdir or "")

    args: List[str] = ["--permission-mode", "auto"]
    if tuning.model:
        args += ["--model", tuning.model]
    if tuning.effort:
        args += ["--effort", tuning.effort]
    mission = mission_text(role=role, kind=placement.kind, machine=machine, workdir=workdir, name=final,
                           issue=issue, repo=repo, prompt=prompt)
    return Decision(role, placement.kind or kind, final, machine, label, workdir, placement, via, overrides, chosen,
                    tuning, tuple(args), is_browser_job(needs), issue, repo, mission, name is not None, prompt,
                    tuple(warnings))


# ── the pane ─────────────────────────────────────────────────────────────────

def _same_dir(a: Any, b: str) -> bool:
    return isinstance(a, str) and (a.rstrip("/") or "/") == (b.rstrip("/") or "/")


def choose_pane(decision: Decision, *, timeout: float = herdr.DEFAULT_TIMEOUT) -> PanePlan:
    """Read-only: reuse a free pane of ours, else make a tab (or the workspace). Raises StartFailed on a herdr error."""
    label = decision.label
    try:
        workspace = next((w for w in herdr.workspace_list(label, timeout=timeout)
                          if w.get("label") == WORKSPACE_LABEL), None)
        if workspace is None:
            return PanePlan("create-workspace", None, None, None)
        wid = workspace.get("workspace_id")
        tabs = {t.get("tab_id"): t for t in herdr.tab_list(label, wid, timeout=timeout)}
        panes = herdr.pane_list(label, wid, timeout=timeout)
        live = set(a.get("pane_id") for a in herdr.agent_list(label, timeout=timeout) if isinstance(a, dict))
        per_tab: Dict[Any, int] = {}
        for p in panes:
            per_tab[p.get("tab_id")] = per_tab.get(p.get("tab_id"), 0) + 1
        for p in panes:
            tab = tabs.get(p.get("tab_id"))
            pid = p.get("pane_id")
            if tab is None or not str(tab.get("label") or "").startswith(TAB_PREFIX) or per_tab.get(p.get("tab_id")) != 1:
                continue
            if pid in live or not _same_dir(p.get("foreground_cwd"), decision.workdir):
                continue
            fg = herdr.pane_foreground(label, pid, timeout=timeout)
            if fg and all(n in SHELLS for n in fg):
                return PanePlan("reuse-pane", wid, p.get("tab_id"), pid)
        return PanePlan("create-tab", wid, None, None)
    except herdr.HerdrError as exc:
        raise StartFailed("herdr failed on %s: %s" % (decision.machine.name, exc.detail), decision.machine.name)


def plan_commands(decision: Decision, plan: PanePlan, *, start_timeout: float = START_TIMEOUT) -> List[str]:
    """--dry-run: each mutating command start() would run, pasteable, with <new-pane>/<new-tab> placeholders."""
    label, name, wd = decision.label, decision.name, decision.workdir

    def q(*args: str) -> str:
        return " ".join(shlex.quote(a) for a in herdr.argv(label, *args))

    tab_label = TAB_PREFIX + name
    if plan.action == "create-workspace":
        pane, out = "<new-pane>", [q("workspace", "create", "--label", WORKSPACE_LABEL, "--cwd", wd, "--no-focus"),
                                   q("tab", "rename", "<new-tab>", tab_label)]
    elif plan.action == "reuse-pane":
        pane, out = plan.pane_id or "<pane>", [q("tab", "rename", plan.tab_id or "<tab>", tab_label)]
    else:
        pane, out = "<new-pane>", [q("tab", "create", "--workspace", plan.workspace_id or "<workspace>",
                                     "--label", tab_label, "--cwd", wd, "--no-focus")]
    out.append(q("agent", "start", name, "--kind", "claude", "--pane", pane, "--timeout",
                 str(int(start_timeout * 1000)), "--", *decision.claude_args))
    declared = [g for g in decision.machine.first_start if g in GATES]
    out.append("then, for each dialog on pane %s that is declared (%s): pane send-keys %s down (unless the "
               "selection is already on the target), then enter" % (pane, ", ".join(declared) or "none", pane))
    prompt = " ".join(shlex.quote(a) for a in herdr.argv(label, "agent", "prompt", pane)) + ' "$MISSION" ' + \
        "--wait --until working --until blocked --timeout %d" % int(PROMPT_TIMEOUT * 1000)
    out.append(prompt)
    return out


# ── starting ─────────────────────────────────────────────────────────────────

class _Startup:
    """One start: the pane, the first-start loop, the keys."""

    def __init__(self, decision: Decision, pane_id: str, sleep: Callable[[float], None],
                 clock: Callable[[], float]):
        self.d = decision
        self.label = decision.label
        self.machine = decision.machine
        self.pane = pane_id
        self.sleep = sleep
        self.clock = clock
        self.t0 = clock()
        self.rounds: List[dict] = []
        self.answered: List[str] = []
        self.actions: List[str] = []

    def read(self) -> str:
        return herdr.pane_read(self.label, self.pane, source="visible")

    def entry(self) -> Optional[dict]:
        for a in herdr.agent_list(self.label):
            if isinstance(a, dict) and a.get("pane_id") == self.pane:
                return a
        return None

    def note(self, dialog: Optional[str], selected: Optional[str], action: str, entry: Optional[dict]) -> None:
        if len(self.rounds) >= MAX_STARTUP_ROUNDS_RECORDED:
            return
        e = entry or {}
        self.rounds.append({
            "t": round(self.clock() - self.t0, 2), "dialog": dialog, "selected": selected, "action": action,
            "name": e.get("name"), "agent_status": e.get("agent_status"),
            "interactive_ready": e.get("interactive_ready"), "launch_pending": e.get("launch_pending"),
        })

    def _precheck(self, screen: str, gate: str) -> bool:
        return match_gate(screen) == gate and never_answer(screen) is None

    def send(self, key: str) -> None:
        herdr.pane_send_keys(self.label, self.pane, [key])
        self.actions.append(key)

    def answer(self, gate_name: str, deadline: float) -> str:
        """At most one Down and one Enter, each after a fresh read. 'entered' | 'no-selection' | 'skipped'."""
        gate = GATES[gate_name]
        self.actions = []
        self.sleep(GATE_KEY_PAUSE)
        screen = self.read()
        if not self._precheck(screen, gate_name):
            return "skipped"
        sel = selected_option(screen, gate)
        if sel is None:
            return "no-selection"
        if sel != gate.target_label:
            screen = self.read()
            if not self._precheck(screen, gate_name) or selected_option(screen, gate) != sel:
                return "skipped"
            self.send("down")
            end = min(self.clock() + KEY_SETTLE, deadline)
            while True:
                screen = self.read()
                if never_answer(screen) is not None or match_gate(screen) != gate_name:
                    return "skipped"
                now = selected_option(screen, gate)
                if now != sel or self.clock() >= end:
                    break
                self.sleep(POLL)
            if now != gate.target_label:
                raise _Fail("after Down the selection is %s, not %s; nothing more was sent" % (
                    machines.short_repr(now), machines.short_repr(gate.target_label)))
            self.sleep(GATE_KEY_PAUSE)
        screen = self.read()
        if not self._precheck(screen, gate_name) or selected_option(screen, gate) != gate.target_label:
            return "skipped"
        self.send("enter")
        end = min(self.clock() + CLEAR_WAIT, deadline)
        while self.clock() < end:
            self.sleep(POLL)
            screen = self.read()
            if match_gate(screen) != gate_name or selected_option(screen, gate) != gate.target_label:
                break
        return "entered"

    def first_start(self, start_timeout: float) -> dict:
        """Answer the declared dialogs until the agent is ready. Returns its `agent list` entry. Raises _Fail."""
        deadline = self.clock() + start_timeout
        answers: Dict[str, int] = {}
        unreadable: Optional[str] = None
        while True:
            if self.clock() > deadline:
                raise _Fail("could not read the selection on %s" % unreadable if unreadable
                            else "agent was not ready within %gs" % start_timeout)
            screen = self.read()
            nv = never_answer(screen)
            if nv:
                self.note(nv, None, "never-answered", None)
                raise _Fail("%s is showing; it is never answered automatically: answer it once by hand on %s" % (
                    nv, self.machine.name))
            gate = match_gate(screen)
            if gate:
                if gate not in self.machine.first_start:
                    self.note(gate, None, "undeclared", None)
                    raise _Fail("the screen shows %s, which %s doesn't declare; add it to first_start in the registry" % (
                        gate, self.machine.name))
                if answers.get(gate, 0) >= MAX_ANSWERS_PER_GATE:
                    self.note(gate, None, "capped", None)
                    raise _Fail("%s still showing after %d answers" % (gate, MAX_ANSWERS_PER_GATE))
                selected = selected_option(screen, GATES[gate])
                result = self.answer(gate, deadline)
                self.note(gate, selected, ",".join(self.actions) if result == "entered" else
                          ("skipped" if result == "skipped" else result), None)
                if result == "entered":
                    answers[gate] = answers.get(gate, 0) + 1
                    unreadable = None
                    if gate not in self.answered:
                        self.answered.append(gate)
                else:
                    unreadable = gate if result == "no-selection" else None
                    self.sleep(POLL)
                continue
            unreadable = None
            entry = self.entry()
            self.note(None, None, "read", entry)
            if (entry and entry.get("agent") == "claude" and entry.get("agent_status") in ("idle", "done")
                    and entry.get("interactive_ready") is not False):
                return entry
            self.sleep(POLL)


def _wait_cwd(d: Decision, ws: str, pane: str, sleep: Callable[[float], None],
              clock: Callable[[], float]) -> None:
    """A new pane must report the workdir as its foreground_cwd, else it is closed before agent start."""
    end = clock() + CWD_WAIT
    seen: Any = None
    while True:
        for p in herdr.pane_list(d.label, ws):
            if p.get("pane_id") == pane:
                seen = p.get("foreground_cwd")
                if _same_dir(seen, d.workdir):
                    return
        if clock() >= end:
            break
        sleep(POLL)
    reason = "workdir %s doesn't exist on %s (the new pane opened in %s)" % (d.workdir, d.machine.name, seen)
    try:
        herdr.pane_close(d.label, pane)
    except herdr.HerdrError as exc:
        raise _Fail("%s; could not close pane %s (%s): %s" % (
            reason, pane, exc.detail, follow_up(d.label, pane)["stop"]))
    raise _Fail(reason, closed=True)


def _intended_argv(d: Decision) -> Tuple[str, ...]:
    return ("claude",) + d.claude_args


def start(decision: Decision, plan: PanePlan, *, start_timeout: float = START_TIMEOUT, keep_failed: bool = False,
          env: Optional[Mapping[str, str]] = None,
          sleep: Callable[[float], None] = time.sleep,
          clock: Callable[[], float] = time.monotonic) -> Started:
    """Carry the plan out: pane, agent start, first-start loop, brief, record. Raises StartFailed."""
    d = decision
    label = d.label
    machine_name = d.machine.name
    pane: Optional[str] = None
    ws: Optional[str] = None
    tab: Optional[str] = None
    session: Optional[_Startup] = None
    name = d.name
    argv: Tuple[str, ...] = ()
    argv_source = "intended"
    reason: Optional[str] = None
    closed = False
    try:
        tab_label = TAB_PREFIX + name
        if plan.action == "create-workspace":
            made = herdr.workspace_create(label, WORKSPACE_LABEL, d.workdir)
            ws, tab, pane = (made["workspace"].get("workspace_id"), made["tab"].get("tab_id"),
                             made["root_pane"].get("pane_id"))
            if not (ws and tab and pane):
                raise herdr.HerdrError("unexpected output")
            _wait_cwd(d, ws, pane, sleep, clock)
            herdr.tab_rename(label, tab, tab_label)
        elif plan.action == "reuse-pane":
            ws, tab, pane = plan.workspace_id, plan.tab_id, plan.pane_id
            if not (ws and tab and pane):
                raise _Fail("internal error: incomplete pane plan")
            herdr.tab_rename(label, tab, tab_label)
        else:
            made = herdr.tab_create(label, plan.workspace_id or "", tab_label, d.workdir)
            ws, tab, pane = plan.workspace_id, made["tab"].get("tab_id"), made["root_pane"].get("pane_id")
            if not (ws and tab and pane):
                raise herdr.HerdrError("unexpected output")
            _wait_cwd(d, ws, pane, sleep, clock)

        session = _Startup(d, pane, sleep, clock)
        taken = set(next((v.live_names for v in d.considered if v.machine == machine_name and v.eligible), frozenset()))
        tries = 0
        while True:
            try:
                herdr.agent_start(label, name, pane, args=d.claude_args, start_timeout=start_timeout)
                break
            except herdr.HerdrError as exc:
                if exc.code == "agent_not_ready":
                    break
                if exc.code == "agent_name_taken" and not d.name_explicit and tries < 2:
                    tries += 1
                    taken.add(name)
                    try:
                        name = default_name(d.role, d.issue, taken)
                    except Refused as r:
                        raise _Fail(r.reason)
                    continue
                raise
        entry = session.first_start(start_timeout)
        if entry.get("name") != name:
            herdr.agent_rename(label, pane, name)
        try:
            for proc in herdr.pane_processes(label, pane):
                pargs = proc.get("argv")
                if proc.get("name") == "claude" and isinstance(pargs, list) and pargs:
                    argv, argv_source = tuple(str(a) for a in pargs), "process-info"
                    break
        except herdr.HerdrError:
            pass
        if not argv:
            argv = _intended_argv(d)
    except _Fail as exc:
        reason, closed = exc.reason, exc.closed
    except herdr.HerdrError as exc:
        reason = "herdr failed on %s: %s" % (machine_name, exc.detail)

    if reason is not None:
        output = ""
        close_error = None
        if pane and not closed:
            try:
                output = herdr.pane_read(label, pane, source="recent-unwrapped", lines=OUTPUT_LINES)
            except herdr.HerdrError:
                output = ""
            if not keep_failed:
                try:
                    herdr.pane_close(label, pane)
                    closed = True
                except herdr.HerdrError as exc:
                    close_error = exc.detail
        raise StartFailed(reason, machine_name, pane, output, closed, None, close_error)

    assert pane is not None and ws is not None and tab is not None and session is not None
    if name != d.name:
        d = replace(d, name=name, mission=mission_text(
            role=d.role, kind=d.kind, machine=d.machine, workdir=d.workdir, name=name, issue=d.issue,
            repo=d.repo, prompt=d.prompt))
    started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    state = Started(d, ws, tab, pane, argv, argv_source, tuple(session.answered), tuple(session.rounds),
                    "unknown", None, None, name, False, ())

    def save(s: Started) -> Started:
        try:
            return replace(s, record_path=write_record(s, env, started_at), record_error=None)
        except OSError as exc:
            return replace(s, record_path=None, record_error=getattr(exc, "strerror", None) or str(exc))

    state = save(state)
    failure: Optional[str] = None
    status = "unknown"
    briefed = False
    try:
        for attempt in (1, 2):
            try:
                result = herdr.agent_prompt(label, pane, d.mission, until=("working", "blocked"),
                                            timeout=PROMPT_TIMEOUT)
                got = result.get("agent_status") if isinstance(result, dict) else None
                status = got if isinstance(got, str) and got else "unknown"
                briefed = True
                break
            except herdr.HerdrError as exc:
                if attempt == 1 and exc.code in ("agent_blocked", "agent_not_ready"):
                    session.first_start(start_timeout)
                    state = replace(state, gates_answered=tuple(session.answered), startup=tuple(session.rounds))
                    continue
                raise
    except _Fail as exc:
        failure = exc.reason
    except herdr.HerdrError as exc:
        failure = "briefing failed on %s: %s" % (machine_name, exc.detail)
    warnings: Tuple[str, ...] = ()
    if briefed and status == "blocked":
        warnings = ("%s is blocked on a dialog; read it with: %s" % (name, follow_up(label, pane)["read"]),)
    state = save(replace(state, briefed=briefed, status=status, warnings=warnings,
                         gates_answered=tuple(session.answered), startup=tuple(session.rounds)))
    if failure is not None:
        raise StartFailed(failure, machine_name, pane, "", False, state.record_path)
    return state
