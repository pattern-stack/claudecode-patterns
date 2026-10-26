#!/usr/bin/env python3
"""A stateful fake `herdr` for plugin/lib/delegate.test.sh. Linked onto PATH as `herdr`.

State lives in $FAKE_HERDR_DIR: scenario.json (what to simulate, keyed by machine label, "" = the local
server), state.json (workspaces, tabs, panes, agents, screens), calls.jsonl (every call), keys.jsonl
(every key, with the dialog and marked option on screen when it arrived) and prompts.jsonl.

Output follows herdr 0.9.5's CLI: JSON {"id", "result"} for the list/create/process-info/prompt verbs, plain
text for `pane read`, nothing for send-keys / pane close / tab rename / agent rename / agent start (all exit 0),
JSON errors on stderr (exit 1), and herdr's text error for an unknown machine (exit 2).

Scenario keys per machine: agents (count of busy agents), unreachable, hang, workspaces, gates, idle_with_gate,
unnamed_after_gate, focus_target, marker_stuck, stuck, redraw_lag, swap_before_enter, marker_glyph, missing_cwd,
no_process_argv, raw_screen, start_error, prompt_error, prompt_error_once (+ prompt_gate), name_taken_once, lag_enter_only, torn_reads, swap_at_read, augment_at_read, late_dialog, done_agents, resolve_cwd.
"""
import json
import os
import sys
import time

DIR = os.environ.get("FAKE_HERDR_DIR", "")
GATE_TARGET = {"trust-prompt": "Yes, I trust this folder", "fullscreen-notice": "Not now"}

DIALOGS = {
    "trust-prompt": ("Quick safety check: Is this a project you created or one you trust?\n\n /w\n",
                     ["No, exit", "Yes, I trust this folder"], False),
    "fullscreen-notice": ("Try the new fullscreen renderer?\n", ["Yes, try it", "Not now"], True),
    "trust-elevated": ("Quick safety check: Is this a project you created or one you trust?\n\n /w\n"
                       " This folder pre-approves permissions or configures MCP servers.\n",
                       ["No, continue without these permissions", "Yes, I trust this folder"], False),
    "auto-mode-teach": ("Teach auto mode about your environment?\n", ["Yes", "Not now", "Don't show again"], True),
    "unknown": ("Some unfamiliar dialog\n", ["Okay"], True),
}


def path(name):
    return os.path.join(DIR, name)


def load(name, default):
    try:
        with open(path(name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save(name, data):
    with open(path(name), "w") as f:
        json.dump(data, f)


def append(name, obj):
    with open(path(name), "a") as f:
        f.write(json.dumps(obj) + "\n")


def fail(code, message, cmd):
    sys.stderr.write(json.dumps({"error": {"code": code, "message": message}, "id": cmd}) + "\n")
    sys.exit(1)


def out(cmd, result):
    sys.stdout.write(json.dumps({"id": cmd, "result": result}) + "\n")
    sys.exit(0)


class Fake:
    def __init__(self, label, scen):
        self.label = label
        self.scen = scen
        state = load("state.json", {})
        if label not in state:
            state[label] = self.initial()
        self.all = state
        self.s = state[label]

    def initial(self):
        s = {"next": 11, "workspaces": [], "tabs": [], "panes": [], "agents": [], "used": {}}
        for i in range(int(self.scen.get("agents", 0))):
            s["agents"].append({"name": "busy%d" % (i + 1), "pane_id": "w9:p%d" % (i + 1), "agent": "claude",
                                "agent_status": "working", "interactive_ready": True, "workspace_id": "w9",
                                "tab_id": "w9:t%d" % (i + 1)})
        for i in range(int(self.scen.get("done_agents", 0))):
            s["agents"].append({"name": "done%d" % (i + 1), "pane_id": "w8:p%d" % (i + 1), "agent": "claude",
                                "agent_status": "done", "interactive_ready": True, "workspace_id": "w8",
                                "tab_id": "w8:t%d" % (i + 1)})
        for wi, ws in enumerate(self.scen.get("workspaces", [])):
            wid = "w%d" % (wi + 1)
            s["workspaces"].append({"workspace_id": wid, "label": ws.get("label", "")})
            for ti, tab in enumerate(ws.get("tabs", [])):
                tid = "%s:t%d" % (wid, ti + 1)
                s["tabs"].append({"tab_id": tid, "workspace_id": wid, "label": tab.get("label", "")})
                for pi, pane in enumerate(tab.get("panes", [])):
                    pid = "%s:p%d%d" % (wid, ti + 1, pi + 1)
                    s["panes"].append({"pane_id": pid, "tab_id": tid, "workspace_id": wid,
                                       "foreground_cwd": pane.get("cwd", "/"), "fg": pane.get("fg", "bash"),
                                       "dialog": None, "remaining": [], "marker": 0})
                    if pane.get("agent"):
                        s["agents"].append({"name": pane["agent"], "pane_id": pid, "agent": "claude",
                                            "agent_status": "idle", "interactive_ready": True,
                                            "workspace_id": wid, "tab_id": tid})
        return s

    def commit(self):
        self.all[self.label] = self.s
        save("state.json", self.all)

    # ── lookups ──
    def pane(self, pid):
        return next((p for p in self.s["panes"] if p["pane_id"] == pid), None)

    def agent(self, target):
        return next((a for a in self.s["agents"] if a.get("pane_id") == target or
                     (a.get("name") is not None and a.get("name") == target)), None)

    def new_id(self):
        n = self.s["next"]
        self.s["next"] = n + 1
        return n

    # ── dialogs ──
    def default_marker(self, dialog):
        if dialog == "fullscreen-notice" and self.scen.get("focus_target"):
            return 1
        return 0

    def show(self, pane, dialog):
        pane["dialog"] = dialog
        pane["marker"] = self.default_marker(dialog)

    def render(self, pane, torn=False):
        dialog = pane.get("dialog")
        glyph = "none" if torn else self.scen.get("marker_glyph", "❯")
        if dialog:
            title, options, numbered = DIALOGS[dialog]
            lines = [title]
            for i, label in enumerate(options):
                mark = " "
                if i == pane.get("marker", 0) and glyph != "none":
                    mark = glyph
                lines.append(" %s %s%s" % (mark, "%d. " % (i + 1) if numbered else "", label))
            return "\n".join(lines) + "\n"
        agent = next((a for a in self.s["agents"] if a.get("pane_id") == pane["pane_id"]), None)
        if agent is not None and pane.get("fg") == "claude":
            return "Claude Code v2.1.310\n\n❯ \n"
        return "$ \n"

    def selected(self, pane):
        if not pane.get("dialog"):
            return None
        return DIALOGS[pane["dialog"]][1][pane.get("marker", 0)]

    def make_ready(self, pane):
        a = self.agent_on(pane)
        if a is None:
            return
        a["agent_status"] = "idle"
        if self.scen.get("unnamed_after_gate"):
            a["name"] = None
            a["interactive_ready"] = None
        else:
            a["interactive_ready"] = True

    def agent_on(self, pane):
        return next((a for a in self.s["agents"] if a.get("pane_id") == pane["pane_id"]), None)

    def advance(self, pane):
        if pane["remaining"]:
            self.show(pane, pane["remaining"].pop(0))
        else:
            pane["dialog"] = None
            self.make_ready(pane)

    def press(self, pane, key):
        dialog = pane.get("dialog")
        append("keys.jsonl", {"pane": pane["pane_id"], "key": key, "dialog": dialog, "selected": self.selected(pane)})
        if not dialog:
            return
        lag = int(self.scen.get("redraw_lag", 0))
        if lag and (key == "enter" or not self.scen.get("lag_enter_only")):
            pane["lag"] = lag
            pane["old_screen"] = self.render(pane)
        if self.scen.get("torn_reads"):
            pane["torn"] = int(self.scen["torn_reads"])
        if key == "down":
            if not self.scen.get("marker_stuck"):
                pane["marker"] = min(pane["marker"] + 1, len(DIALOGS[dialog][1]) - 1)
        elif key == "enter":
            picked = self.selected(pane)
            if dialog == "trust-prompt" and picked == "No, exit":
                pane["dialog"] = None
                pane["remaining"] = []
                pane["fg"] = "bash"
                self.s["agents"] = [a for a in self.s["agents"] if a.get("pane_id") != pane["pane_id"]]
            elif self.scen.get("stuck"):
                pane["marker"] = 0
            else:
                self.advance(pane)

    def read(self, pane, source):
        if self.scen.get("raw_screen") is not None:
            return self.scen["raw_screen"]
        swap = self.scen.get("swap_before_enter")
        if source == "visible":
            pane["vreads"] = pane.get("vreads", 0) + 1
            at = self.scen.get("swap_at_read")
            if at and pane["vreads"] == int(at["n"]):
                self.show(pane, at["to"])
                pane["marker"] = 0
        if swap and pane.get("swap_armed"):
            pane["swap_armed"] = False
            pane["swapped"] = True
            self.show(pane, swap["to"])
            pane["marker"] = 0
        if pane.get("lag", 0) > 0 and source == "visible":
            pane["lag"] -= 1
            return pane.get("old_screen", self.render(pane))
        if pane.get("torn", 0) > 0 and source == "visible":
            pane["torn"] -= 1
            return self.render(pane, torn=True)
        text = self.render(pane)
        add = self.scen.get("augment_at_read")
        if add and source == "visible" and pane["vreads"] >= int(add["n"]):
            text += DIALOGS[add["text"]][0] + "\n".join(" %s" % o for o in DIALOGS[add["text"]][1]) + "\n"
        if swap and source == "visible" and not pane.get("swapped") and pane.get("dialog") in GATE_TARGET \
                and self.selected(pane) == GATE_TARGET[pane["dialog"]]:
            pane["target_reads"] = pane.get("target_reads", 0) + 1
            if pane["target_reads"] >= int(swap.get("after_target_reads", 1)):
                pane["swap_armed"] = True
        return text

    # ── entries ──
    def agent_entry(self, a):
        pane = self.pane(a["pane_id"]) or {}
        e = dict(a)
        e["foreground_cwd"] = pane.get("foreground_cwd")
        e["launch_pending"] = False
        return e


def main():
    args = sys.argv[1:]
    label = ""
    if args[:1] == ["--machine"]:
        label, args = args[1], args[2:]
    append("calls.jsonl", {"machine": label, "argv": args})
    scenario = load("scenario.json", {})
    if label not in scenario or scenario[label].get("unreachable"):
        sys.stderr.write("error: unknown machine '%s'; use `herdr machine list`\n" % label)
        sys.exit(2)
    scen = scenario[label]
    if scen.get("hang"):
        time.sleep(30)
    f = Fake(label, scen)
    group, verb = (args + ["", ""])[:2]
    rest = args[2:]
    cmd = "cli:%s:%s" % (group, verb)

    def opt(name, default=None):
        return rest[rest.index(name) + 1] if name in rest and rest.index(name) + 1 < len(rest) else default

    if (group, verb) == ("agent", "list"):
        out(cmd, {"type": "agent_list", "agents": [f.agent_entry(a) for a in f.s["agents"]]})
    elif (group, verb) == ("workspace", "list"):
        res = []
        for w in f.s["workspaces"]:
            tabs = [t for t in f.s["tabs"] if t["workspace_id"] == w["workspace_id"]]
            panes = [p for p in f.s["panes"] if p["workspace_id"] == w["workspace_id"]]
            res.append({"workspace_id": w["workspace_id"], "label": w["label"], "tab_count": len(tabs),
                        "pane_count": len(panes)})
        out(cmd, {"type": "workspace_list", "workspaces": res})
    elif (group, verb) == ("tab", "list"):
        wid = opt("--workspace")
        res = [dict(t, pane_count=len([p for p in f.s["panes"] if p["tab_id"] == t["tab_id"]]))
               for t in f.s["tabs"] if t["workspace_id"] == wid]
        out(cmd, {"type": "tab_list", "tabs": res})
    elif (group, verb) == ("pane", "list"):
        wid = opt("--workspace")
        res = []
        for p in f.s["panes"]:
            if p["workspace_id"] == wid:
                item = {k: p[k] for k in ("pane_id", "tab_id", "workspace_id", "foreground_cwd")}
                a = f.agent_on(p)
                if a is not None:
                    item["agent"] = "claude"
                res.append(item)
        out(cmd, {"type": "pane_list", "panes": res})
    elif (group, verb) in (("workspace", "create"), ("tab", "create")):
        n = f.new_id()
        cwd = "/" if scen.get("missing_cwd") else opt("--cwd", "/")
        if scen.get("resolve_cwd"):
            cwd = os.path.realpath(cwd)       # herdr reports the process cwd, which the kernel resolves
        if verb == "create" and group == "workspace":
            wid = "w%d" % n
            f.s["workspaces"].append({"workspace_id": wid, "label": opt("--label", "")})
        else:
            wid = opt("--workspace")
            if not any(w["workspace_id"] == wid for w in f.s["workspaces"]):
                fail("workspace_not_found", "no workspace %s" % wid, cmd)
        tid, pid = "%s:t%d" % (wid, n), "%s:p%d" % (wid, n)
        f.s["tabs"].append({"tab_id": tid, "workspace_id": wid, "label": opt("--label", "")})
        f.s["panes"].append({"pane_id": pid, "tab_id": tid, "workspace_id": wid, "foreground_cwd": cwd,
                             "fg": "bash", "dialog": None, "remaining": [], "marker": 0})
        f.commit()
        result = {"type": "%s_created" % group, "tab": {"tab_id": tid, "workspace_id": wid},
                  "root_pane": {"pane_id": pid, "tab_id": tid, "workspace_id": wid}}
        if group == "workspace":
            result["workspace"] = {"workspace_id": wid, "label": opt("--label", "")}
        out(cmd, result)
    elif (group, verb) == ("tab", "rename"):
        for t in f.s["tabs"]:
            if t["tab_id"] == rest[0]:
                t["label"] = " ".join(rest[1:])
        f.commit()
    elif (group, verb) == ("pane", "close"):
        pane = f.pane(rest[0])
        if pane is None:
            fail("pane_not_found", "no pane %s" % rest[0], cmd)
        f.s["panes"] = [p for p in f.s["panes"] if p["pane_id"] != pane["pane_id"]]
        f.s["agents"] = [a for a in f.s["agents"] if a.get("pane_id") != pane["pane_id"]]
        if not any(p["tab_id"] == pane["tab_id"] for p in f.s["panes"]):
            f.s["tabs"] = [t for t in f.s["tabs"] if t["tab_id"] != pane["tab_id"]]
        f.commit()
    elif (group, verb) == ("pane", "process-info"):
        pane = f.pane(opt("--pane"))
        if pane is None:
            fail("pane_not_found", "no pane %s" % opt("--pane"), cmd)
        a = f.agent_on(pane)
        if scen.get("late_dialog") and a is not None and not pane.get("late_done") and not pane.get("dialog"):
            pane["late_done"] = True                 # a dialog drawn after the agent was ready, status stays idle
            f.show(pane, scen["late_dialog"])
            pane["remaining"] = []
            f.commit()
        if a is not None and pane.get("fg") == "claude":
            proc = {"name": "claude", "pid": 4242}
            if not scen.get("no_process_argv"):
                proc["argv"] = ["claude"] + list(pane.get("agent_args", []))
        else:
            proc = {"name": pane.get("fg", "bash"), "pid": 4241, "argv": [pane.get("fg", "bash")]}
        out(cmd, {"type": "pane_process_info", "process_info": {"pane_id": pane["pane_id"],
                                                                "foreground_processes": [proc]}})
    elif (group, verb) == ("pane", "read"):
        pane = f.pane(rest[0])
        if pane is None:
            fail("pane_not_found", "no pane %s" % rest[0], cmd)
        text = f.read(pane, opt("--source", "recent"))
        f.commit()
        sys.stdout.write(text)
        sys.exit(0)
    elif (group, verb) == ("pane", "send-keys"):
        pane = f.pane(rest[0])
        if pane is None:
            fail("pane_not_found", "no pane %s" % rest[0], cmd)
        for key in rest[1:]:
            f.press(pane, key)
        f.commit()
    elif (group, verb) == ("agent", "start"):
        name = rest[0]
        pane = f.pane(opt("--pane"))
        sep = rest.index("--") if "--" in rest else len(rest)
        if pane is None:
            fail("pane_not_found", "no pane %s" % opt("--pane"), cmd)
        if scen.get("start_error"):
            fail(scen["start_error"], "start failed", cmd)
        used = f.s["used"]
        if scen.get("name_taken_once") and not used.get("name_taken"):
            used["name_taken"] = True
            f.commit()
            fail("agent_name_taken", "name %s is taken" % name, cmd)
        if f.agent(name) is not None:
            fail("agent_name_taken", "name %s is taken" % name, cmd)
        gates = list(scen.get("gates", []))
        pane["fg"] = "claude"
        pane["agent_args"] = rest[sep + 1:]
        pane["remaining"] = gates
        pane["dialog"] = None
        unnamed = bool(scen.get("unnamed_after_gate"))
        agent = {"name": None if unnamed else name, "pane_id": pane["pane_id"], "agent": "claude",
                 "agent_status": "unknown", "interactive_ready": False, "workspace_id": pane["workspace_id"],
                 "tab_id": pane["tab_id"]}
        f.s["agents"].append(agent)
        if gates:
            f.show(pane, pane["remaining"].pop(0))
            if scen.get("idle_with_gate"):
                agent["agent_status"] = "idle"
                agent["interactive_ready"] = True
                f.commit()
                sys.exit(0)
            f.commit()
            fail("agent_not_ready", "agent is not ready: a startup dialog is showing", cmd)
        f.make_ready(pane)
        f.commit()
    elif (group, verb) == ("agent", "get"):
        a = f.agent(rest[0])
        pane = f.pane(a["pane_id"]) if a else None
        if a is None or (rest[0] == a.get("name") and pane and pane.get("dialog")):
            fail("agent_not_found", "no agent %s" % rest[0], cmd)
        out(cmd, {"type": "agent_info", "agent": f.agent_entry(a)})
    elif (group, verb) == ("agent", "rename"):
        a = f.agent(rest[0])
        if a is None:
            fail("agent_not_found", "no agent %s" % rest[0], cmd)
        a["name"] = rest[1]
        if a.get("interactive_ready") is None:
            a["interactive_ready"] = True
        f.commit()
    elif (group, verb) == ("agent", "prompt"):
        a = f.agent(rest[0])
        if a is None:
            fail("agent_not_found", "no agent %s" % rest[0], cmd)
        pane = f.pane(a["pane_id"])
        used = f.s["used"]
        if scen.get("prompt_error"):
            fail(scen["prompt_error"], "prompt failed", cmd)
        once = scen.get("prompt_error_once")
        if once and not used.get("prompt_once"):
            used["prompt_once"] = True
            if scen.get("prompt_gate") and pane is not None:
                f.show(pane, scen["prompt_gate"])
                pane["remaining"] = []
                a["agent_status"] = "blocked"
            f.commit()
            fail(once, "prompt refused", cmd)
        if a.get("agent_status") == "blocked":
            fail("agent_blocked", "agent is blocked on a dialog", cmd)
        # Like real herdr: a dialog it did not classify as blocked takes the text.
        append("prompts.jsonl", {"machine": label, "target": rest[0], "pane_id": a["pane_id"], "text": rest[1],
                                 "argv": args, "into_dialog": pane.get("dialog") if pane is not None else None})
        a["agent_status"] = "working"
        f.commit()
        out(cmd, {"type": "agent_prompted", "agent": f.agent_entry(a)})
    else:
        sys.stderr.write("fake herdr: unsupported: %s\n" % " ".join(args))
        sys.exit(2)


main()
