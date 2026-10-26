"""Thin adapter over the `herdr` CLI.

One function per herdr verb that `sdlc machines check --probe` (#136) and `sdlc delegate` (#139) use:
agent_list, workspace_list/create, tab_list/create/rename, pane_list/processes/foreground/read/
send_keys/close, agent_start/prompt/rename. Every function reads its verb's output the way the
0.9.5 CLI prints it: JSON for the list/create/process-info verbs, plain text for `pane read`, and only
the exit code for send-keys, close, rename and `agent start`. `HerdrError.code` carries herdr's own
error code ("agent_not_ready", "agent_name_taken", ...) when it printed a JSON error.

Tests drive it through a fake `herdr` on PATH (plugin/lib/fake-herdr.py, used by delegate.test.sh;
machines.test.sh has a smaller one). Python >= 3.8, stdlib only. No printing, no sys.exit.
"""
from __future__ import annotations

import json
import shutil
import subprocess
from typing import List, Optional, Sequence

DEFAULT_TIMEOUT = 15.0


class HerdrError(Exception):
    """A herdr call failed. `detail` is one line fit to show a user; `code` is herdr's error code, if any."""

    def __init__(self, detail: str, returncode: Optional[int] = None, code: Optional[str] = None):
        super().__init__(detail)
        self.detail = detail
        self.returncode = returncode
        self.code = code


def available() -> bool:
    return shutil.which("herdr") is not None


def argv(machine: Optional[str], *args: str) -> List[str]:
    """The command line for `herdr [--machine M] args...` (also used to print --dry-run commands)."""
    cmd = ["herdr"]
    if machine is not None:
        cmd += ["--machine", machine]
    return cmd + [str(a) for a in args]


def _first_line(text: str) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def _error_from(stderr: str, returncode: int) -> HerdrError:
    """herdr's JSON error ({"error": {"code", "message"}, "id"}), else its first stderr line."""
    # The JSON error is the last line that starts with `{`; a warning line may come before it.
    for line in reversed((stderr or "").splitlines()):
        if not line.strip().startswith("{"):
            continue
        try:
            err = json.loads(line)["error"]
            code, message = err.get("code"), err.get("message")
            if isinstance(code, str) and code:
                first = _first_line(message) if isinstance(message, str) else ""
                return HerdrError("%s: %s" % (code, first) if first else code, returncode, code)
        except (ValueError, KeyError, TypeError, AttributeError):
            pass
        break
    return HerdrError(_first_line(stderr) or "herdr exited %d" % returncode, returncode)


def _run(machine: Optional[str], args: Sequence[str], timeout: float) -> str:
    """Run one herdr command; return stdout as text. Raises HerdrError on any failure."""
    try:
        proc = subprocess.run(argv(machine, *args), stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=timeout)
    except FileNotFoundError:
        raise HerdrError("herdr not found on PATH")
    except subprocess.TimeoutExpired:
        raise HerdrError("timed out after %gs" % timeout)
    except OSError as exc:
        raise HerdrError(str(exc))
    if proc.returncode != 0:
        raise _error_from(proc.stderr, proc.returncode)
    return proc.stdout


def _call(machine: Optional[str], args: Sequence[str], timeout: float) -> dict:
    """_run plus `json.loads(stdout)["result"]`."""
    out = _run(machine, args, timeout)
    try:
        result = json.loads(out)["result"]
    except (ValueError, KeyError, TypeError):
        raise HerdrError("unexpected output")
    if not isinstance(result, dict):
        raise HerdrError("unexpected output")
    return result


def _list(result: dict, key: str) -> List[dict]:
    items = result.get(key)
    if not isinstance(items, list):
        raise HerdrError("unexpected output")
    return [i for i in items if isinstance(i, dict)]


def _entry(result: dict, *keys: str) -> dict:
    """The sub-objects a create verb must return, e.g. workspace/tab/root_pane."""
    out = {}
    for key in keys:
        value = result.get(key)
        if not isinstance(value, dict):
            raise HerdrError("unexpected output")
        out[key] = value
    return out


def agent_list(machine: Optional[str] = None, *, timeout: float = DEFAULT_TIMEOUT) -> List[dict]:
    """Return the agents herdr reports, on `machine` (a herdr label) or on the local server."""
    return _list(_call(machine, ["agent", "list"], timeout), "agents")


def workspace_list(machine: Optional[str], *, timeout: float = DEFAULT_TIMEOUT) -> List[dict]:
    return _list(_call(machine, ["workspace", "list"], timeout), "workspaces")


def workspace_create(machine: Optional[str], label: str, cwd: str, *, timeout: float = DEFAULT_TIMEOUT) -> dict:
    """{workspace, tab, root_pane}; the workspace is not focused."""
    result = _call(machine, ["workspace", "create", "--label", label, "--cwd", cwd, "--no-focus"], timeout)
    return _entry(result, "workspace", "tab", "root_pane")


def workspace_rename(machine: Optional[str], workspace_id: str, label: str, *,
                     timeout: float = DEFAULT_TIMEOUT) -> None:
    _run(machine, ["workspace", "rename", workspace_id, label], timeout)


def tab_list(machine: Optional[str], workspace_id: str, *, timeout: float = DEFAULT_TIMEOUT) -> List[dict]:
    return _list(_call(machine, ["tab", "list", "--workspace", workspace_id], timeout), "tabs")


def tab_create(machine: Optional[str], workspace_id: str, label: str, cwd: str, *,
               timeout: float = DEFAULT_TIMEOUT) -> dict:
    """{tab, root_pane}; the tab is not focused."""
    result = _call(machine, ["tab", "create", "--workspace", workspace_id, "--label", label, "--cwd", cwd,
                             "--no-focus"], timeout)
    return _entry(result, "tab", "root_pane")


def tab_rename(machine: Optional[str], tab_id: str, label: str, *, timeout: float = DEFAULT_TIMEOUT) -> None:
    _run(machine, ["tab", "rename", tab_id, label], timeout)


def pane_list(machine: Optional[str], workspace_id: str, *, timeout: float = DEFAULT_TIMEOUT) -> List[dict]:
    return _list(_call(machine, ["pane", "list", "--workspace", workspace_id], timeout), "panes")


def pane_processes(machine: Optional[str], pane_id: str, *, timeout: float = DEFAULT_TIMEOUT) -> List[dict]:
    """The foreground processes of a pane: dicts with `name`, `argv`, ..."""
    result = _call(machine, ["pane", "process-info", "--pane", pane_id], timeout)
    info = result.get("process_info")
    procs = info.get("foreground_processes") if isinstance(info, dict) else None
    if not isinstance(procs, list):
        raise HerdrError("unexpected output")
    return [p for p in procs if isinstance(p, dict)]


def pane_foreground(machine: Optional[str], pane_id: str, *, timeout: float = DEFAULT_TIMEOUT) -> List[str]:
    return [str(p.get("name")) for p in pane_processes(machine, pane_id, timeout=timeout)]


def pane_read(machine: Optional[str], pane_id: str, *, source: str = "visible", lines: Optional[int] = None,
              timeout: float = DEFAULT_TIMEOUT) -> str:
    """The pane's text, exactly as `pane read ... --format text` prints it. Never parsed."""
    args = ["pane", "read", pane_id, "--source", source]
    if lines is not None:
        args += ["--lines", str(int(lines))]
    args += ["--format", "text"]
    return _run(machine, args, timeout)


def pane_send_keys(machine: Optional[str], pane_id: str, keys: Sequence[str], *,
                   timeout: float = DEFAULT_TIMEOUT) -> None:
    _run(machine, ["pane", "send-keys", pane_id] + list(keys), timeout)


def pane_close(machine: Optional[str], pane_id: str, *, timeout: float = DEFAULT_TIMEOUT) -> None:
    _run(machine, ["pane", "close", pane_id], timeout)


def agent_start(machine: Optional[str], name: str, pane_id: str, *, kind: str = "claude",
                args: Sequence[str] = (), start_timeout: float = 90.0) -> None:
    """Start an agent in an existing pane. Success is exit 0; the body is not read."""
    cmd = ["agent", "start", name, "--kind", kind, "--pane", pane_id, "--timeout", str(int(start_timeout * 1000))]
    if args:
        cmd += ["--"] + list(args)
    _run(machine, cmd, start_timeout + DEFAULT_TIMEOUT)


def agent_prompt(machine: Optional[str], target: str, text: str, *,
                 until: Sequence[str] = ("working", "blocked"), timeout: float = 60.0) -> dict:
    """Submit a prompt and wait. Returns the agent object (result.agent, else result), or {} when the body isn't JSON."""
    cmd = ["agent", "prompt", target, text, "--wait"]
    for state in until:
        cmd += ["--until", state]
    cmd += ["--timeout", str(int(timeout * 1000))]
    out = _run(machine, cmd, timeout + DEFAULT_TIMEOUT)
    try:
        result = json.loads(out)["result"]
    except (ValueError, KeyError, TypeError):
        return {}
    if not isinstance(result, dict):
        return {}
    agent = result.get("agent")
    return agent if isinstance(agent, dict) else result


def agent_rename(machine: Optional[str], target: str, name: str, *, timeout: float = DEFAULT_TIMEOUT) -> None:
    _run(machine, ["agent", "rename", target, name], timeout)
