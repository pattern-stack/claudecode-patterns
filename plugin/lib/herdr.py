"""Thin adapter over the `herdr` CLI.

This issue (#136) ships only `agent_list`, which `sdlc machines check --probe` uses. #139 extends
this file with tab/pane creation, `agent start`, `prompt` and `send-keys` next to it.

Tests drive it through a fake `herdr` on PATH (see plugin/lib/machines.test.sh), which is also the
technique #139 uses. Python >= 3.8, stdlib only. No printing, no sys.exit.
"""
from __future__ import annotations

import json
import shutil
import subprocess
from typing import List, Optional


class HerdrError(Exception):
    """A herdr call failed. `detail` is one line fit to show a user."""

    def __init__(self, detail: str, returncode: Optional[int] = None):
        super().__init__(detail)
        self.detail = detail
        self.returncode = returncode


def available() -> bool:
    return shutil.which("herdr") is not None


def _first_line(text: str) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def agent_list(machine: Optional[str] = None, *, timeout: float = 15.0) -> List[dict]:
    """Return the agents herdr reports, on `machine` (a herdr label) or on the local server.

    Raises HerdrError if herdr is missing, exits non-zero, times out, or prints an unexpected shape.
    """
    cmd = ["herdr"]
    if machine is not None:
        cmd += ["--machine", machine]
    cmd += ["agent", "list"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise HerdrError("herdr not found on PATH")
    except subprocess.TimeoutExpired:
        raise HerdrError("timed out after %gs" % timeout)
    except OSError as exc:
        raise HerdrError(str(exc))
    if proc.returncode != 0:
        raise HerdrError(
            _first_line(proc.stderr) or "herdr exited %d" % proc.returncode, proc.returncode
        )
    try:
        agents = json.loads(proc.stdout)["result"]["agents"]
    except (ValueError, KeyError, TypeError):
        raise HerdrError("unexpected output")
    if not isinstance(agents, list):
        raise HerdrError("unexpected output")
    return agents
