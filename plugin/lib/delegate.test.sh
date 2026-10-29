#!/usr/bin/env bash
# Tests for `sdlc delegate`: plugin/lib/delegate.py, plugin/lib/herdr.py, plugin/lib/fake-herdr.py, plugin/bin/sdlc.
# Plain bash + python3 (PyYAML and/or yq for the YAML cases). No network, no real herdr: PATH holds python3, the
# fake `herdr` and, for the yq backend, `yq`.
# Run: nice -n 19 bash plugin/lib/delegate.test.sh   (exits 0 only when every case that ran passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE"
SDLC="$(cd "$HERE/../bin" && pwd)/sdlc"
FAKE="$HERE/fake-herdr.py"
PY="$(command -v python3)"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/cwd"
unset SDLC_MACHINES XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_PROJECT_DIR HERDR_ENV
export PYTHONDONTWRITEBYTECODE=1

# ── backends ────────────────────────────────────────────────────────────────
HAVE_PYYAML=0; HAVE_YQ=0
"$PY" -c 'import yaml' 2>/dev/null && HAVE_PYYAML=1
command -v yq >/dev/null 2>&1 && HAVE_YQ=1
mkdir -p "$TMP/noyaml/yaml"; echo 'raise ImportError("hidden for the test")' > "$TMP/noyaml/yaml/__init__.py"
# PATH directories: python3 + the fake herdr (+ yq for the yq backend); and one with no herdr.
mkdir -p "$TMP/pybin" "$TMP/pyyq" "$TMP/nohdr"
ln -s "$PY" "$TMP/pybin/python3"; ln -s "$FAKE" "$TMP/pybin/herdr"
ln -s "$PY" "$TMP/pyyq/python3"; ln -s "$FAKE" "$TMP/pyyq/herdr"
[ "$HAVE_YQ" = 1 ] && ln -s "$(command -v yq)" "$TMP/pyyq/yq"
ln -s "$PY" "$TMP/nohdr/python3"

if [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ]; then
  [ "$HAVE_PYYAML" = 1 ] && ok "required backend present: PyYAML" || bad "required backend missing: PyYAML"
  [ "$HAVE_YQ" = 1 ] && ok "required backend present: yq" || bad "required backend missing: yq"
fi
BACKENDS=()
[ "$HAVE_PYYAML" = 1 ] && BACKENDS+=(py)
[ "$HAVE_YQ" = 1 ] && BACKENDS+=(yq)
B1="${BACKENDS[0]:-}"

# ── Part A: the pure functions (no herdr, no YAML backend) ──────────────────
echo "A  the pure functions"
PARTA="$TMP/parta.py"
cat > "$PARTA" <<'PYEOF'
import inspect, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from pathlib import Path
import delegate as dg
import herdr as hd
import machines as m

TRUST = "Quick safety check: Is this a project you created or one you trust?\n\n /w\n ❯ No, exit\n   Yes, I trust this folder\n"
TRUST_ON_TARGET = TRUST.replace("❯ No, exit", "  No, exit").replace("   Yes, I trust", " ❯ Yes, I trust")
FS = "Try the new fullscreen renderer?\n ❯ 1. Yes, try it\n   2. Not now\n"
FS_DOWN = "Try the new fullscreen renderer?\n   1. Yes, try it\n ❯ 2. Not now\n"
AUTO = "Teach auto mode about your environment?\n ❯ 1. Yes\n   2. Not now\n   3. Don't show again\n"
GATE_FS = dg.GATES["fullscreen-notice"]
GATE_TR = dg.GATES["trust-prompt"]


def machine(name, **kw):
    t = m.Transport("local") if kw.pop("local", False) else m.Transport("herdr", name)
    return m.Machine(name, t, **kw)


def raises(fn, text):
    try:
        fn()
    except dg.Refused as exc:
        return text in exc.reason
    return False


def reg():
    ws = machine("workstation", local=True, workdir="/ws", caps=("edit",))
    w1 = machine("worker-1", workdir="/w1", caps=("edit",))
    ctl = machine("control", assignable=False)
    return m.Registry(Path("/r.yaml"), "flag", True, {x.name: x for x in (ws, w1, ctl)}, [])


def nested(depth):
    return {("k%d" % i): (nested(depth - 1) if depth else "x" * 200) for i in range(10)}


r = reg()
mach_d = machine("worker-1", workdir="/w1", persistence="disposable")
mach_p = machine("worker-1", workdir="/w1", persistence="durable")
ARGS = dict(role="reviewer", kind="phase", workdir="/w1", name="reviewer-139", issue=139, repo="o/r")
M1 = dg.mission_text(machine=mach_d, prompt="PROMPT-TEXT", **ARGS)
M2 = dg.mission_text(machine=mach_p, prompt=None, **ARGS)

rows = [
    ("A1 tuning: grouped beats flat", lambda: (lambda t: t.model == "fable")(
        dg.tuning_for({"phases": {"r": {"model": "fable"}}, "phase_models": {"r": "opus"}}, "r"))),
    ("A2 tuning: flat only; neither", lambda: dg.tuning_for({"phase_effort": {"r": "low"}}, "r").effort == "low"
        and dg.tuning_for({}, "r") == dg.Tuning(None, None)),
    ("A3 tuning: null and blank are unset", lambda: dg.tuning_for({"phases": {"r": {"model": None, "effort": " "}}}, "r")
        == dg.Tuning(None, None)),
    ("A4 tuning: bad effort and model refuse", lambda: raises(lambda: dg.tuning_for({"phases": {"r": {"effort": "huge"}}}, "r"),
        "is not one of: low, medium, high, xhigh, max") and raises(lambda: dg.tuning_for({"phases": {"r": {"model": 3}}}, "r"),
        "phases.r.model")),
    ("A5 is_heavy / is_browser_job", lambda: [dg.is_heavy(m.Needs(caps=c)) for c in (("browser",), ("docker",), ("full-suite",), ("edit",), ())]
        == [True, True, True, False, False] and dg.is_browser_job(m.Needs(caps=("browser",)))
        and not dg.is_browser_job(m.Needs(caps=("docker",)))),
    ("A6 default_name", lambda: dg.default_name("reviewer", 139, set()) == "reviewer-139"
        and dg.default_name("reviewer", 139, {"reviewer-139"}) == "reviewer-139-2"
        and dg.default_name("Browser Pilot!", None, set()) == "browser-pilot"
        and dg.default_name("9lives", None, set()) == "agent-9lives"
        and (lambda n: __import__("re").fullmatch(dg.AGENT_NAME, n) and len(n) <= 32)(
            dg.default_name("x" * 40, None, {"x" * 32}))
        and raises(lambda: dg.default_name("r", None, {"r"} | {"r-%d" % i for i in range(2, 10)}), "live")),
    ("A7 repo_from_remote", lambda: [dg.repo_from_remote(u) for u in (
        "git@github.com:o/r.git", "https://github.com/o/r", "https://github.com/o/r.git", "ssh://git@github.com/o/r",
        "https://gitlab.com/o/r")] == ["o/r", "o/r", "o/r", "o/r", None]),
    ("A8 match_gate and never_answer", lambda: [dg.match_gate(s) for s in (TRUST.upper().replace(" ", "  "), FS.upper(), AUTO, "❯ ")]
        == ["trust-prompt", "fullscreen-notice", None, None]
        and [dg.never_answer(s) for s in (TRUST, FS, AUTO.upper().replace(" ", "  "), "❯ ")]
        == [None, None, "auto-mode-teach", None]),
    ("A8b selected_option", lambda: dg.selected_option(TRUST, GATE_TR) == "No, exit"
        and dg.selected_option(FS_DOWN, GATE_FS) == "Not now"),
    ("A8c selected_option ignores non-option lines; exact labels", lambda:
        dg.selected_option("❯ hello\n❯ Not now please\n" + FS, GATE_FS) == "Yes, try it"
        and dg.selected_option("Try the new fullscreen renderer?\n ❯ 1. YES,  TRY IT\n   2. Not now\n", GATE_FS) == "Yes, try it"
        and dg.selected_option("❯ Not now\n" + FS_DOWN, GATE_FS) is None
        and dg.selected_option("Try the new fullscreen renderer?\n   1. Yes, try it\n   2. Not now\n", GATE_FS) is None),
    ("A8d selected_option with the ASCII marker", lambda:
        dg.selected_option("Try the new fullscreen renderer?\n   1. Yes, try it\n > 2. Not now\n", GATE_FS) == "Not now"
        and dg.selected_option("Try the new fullscreen renderer?\n> hello\n   1. Yes, try it\n   2. Not now\n", GATE_FS) is None),
    ("A9 mission_text with issue, repo, disposable, prompt", lambda: all(s in M1 for s in (
        "as reviewer-139 on", "GitHub only", "gh auth status", dg.GH_NOT_LOGGED_IN.format(machine="worker-1"),
        "push a branch, or comment", "/w1/reviewer-139", "don't reuse, change or delete it", "delete your working copy",
        "gh issue view 139 --repo o/r", "disposable", "PROMPT-TEXT")) and len(M1) <= dg.MISSION_MAX),
    ("A10 mission_text default task; durable machine", lambda: "sdlc:reviewer" in M2 and "issue #139" in M2
        and "disposable" not in M2),
    ("A11 GATES match FIRST_START_GATES", lambda: set(dg.GATES) == set(m.FIRST_START_GATES)
        and not set(dg.NEVER_ANSWER) & set(dg.GATES)
        and all(g.target_label in g.options for g in dg.GATES.values())),
    ("A12 machines.evaluate is pinned", lambda: list(inspect.signature(m.evaluate).parameters) == ["target", "registry", "needs"]
        and m.evaluate("any", r, m.Needs())[0][0] == "workstation"
        and m.evaluate("worker-9", r, m.Needs())[2] == "'worker-9' is not in the registry; did you mean 'worker-1'?"
        and m.evaluate("control", r, m.Needs())[2] == "machine 'control' is not assignable"
        and m.evaluate("local", r, m.Needs())[0] == ["workstation"]),
    ("A13 machines.short_repr is pinned", lambda: all(
        m.short_repr(v) == m._r(v) and len(m.short_repr(v)) <= 2000 for v in ("x" * 5000, nested(6)))),
    ("A8e never_answer matches the dialog title, not release notes or /auto-mode-setup text", lambda:
        dg.never_answer("Teach auto mode about your environment?\n") == "auto-mode-teach"
        and dg.never_answer("Release notes: reads your project and recent sessions to teach auto mode about your environment, "
                            "now also the repo\n") is None
        and dg.never_answer("/auto-mode-setup  Teach auto mode about your environment.\n") is None),
    ("A14 the elevated trust dialog is never answered", lambda:
        dg.never_answer("Quick safety check: Is this a project you created or one you trust?\n"
                        " ❯ No, continue without these permissions\n   Yes, I trust this folder\n") == "trust-elevated"
        and "No, continue without these permissions" not in dg.GATES["trust-prompt"].options
        and dg.never_answer(TRUST) is None),
    ("A15 the mission is counted in bytes", lambda: raises(lambda: dg.mission_text(
        machine=mach_d, prompt="é" * 40000, **ARGS), "bytes")),
    ("A16 herdr finds the JSON error after a warning line", lambda: hd._error_from(
        'warning: something\n{"error": {"code": "agent_not_ready", "message": "x"}, "id": "i"}\n', 1).code == "agent_not_ready"
        and hd._error_from("error: unknown machine 'x'\n", 2).code is None),
]
print("rows: %d" % len(rows))
bad = 0
for name, fn in rows:
    try:
        good = bool(fn())
    except Exception as exc:  # a crash is a failure with its reason
        good, name = False, "%s (%s: %s)" % (name, type(exc).__name__, exc)
    print(("ok: " if good else "FAIL: ") + name)
    bad += 0 if good else 1
sys.exit(1 if bad else 0)
PYEOF
OUT=$(timeout 120 "$PY" -I "$PARTA" "$LIB" 2>&1); RC=$?
NROWS=$(printf '%s\n' "$OUT" | sed -n 's/^rows: //p')
while IFS= read -r line; do
  case "$line" in "ok: "*) ok "${line#ok: }" ;; "FAIL: "*) bad "${line#FAIL: }" ;; esac
done <<< "$OUT"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^ok: ')" = "${NROWS:-x}" ] && ok "Part A: all ${NROWS} rows passed" || { bad "Part A: exit $RC"; printf '%s\n' "$OUT" | head -20; }

# ── Part B: the CLI against the fake herdr ──────────────────────────────────
if [ "$HAVE_PYYAML" = 0 ] && [ "$HAVE_YQ" = 0 ]; then
  echo "skip: neither PyYAML nor yq is available, so the CLI rows need a YAML backend and are skipped"
  echo; echo "delegate: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit
fi

REGF="$TMP/reg.yaml"
FXD="$TMP/fx"; mkdir -p "$FXD"
reg_file() {   # reg_file FILE [sed-expr]   : the five-machine registry, optionally edited
  cat > "$1" <<EOF
machines:
  workstation:
    transport: local
    workdir: $TMP/ws
    caps: [edit, test, browser]
    secrets: dev
    busy_flag: $TMP/busy
  worker-1:
    transport: {herdr: worker-1}
    workdir: /w1
    caps: [edit, test, browser, docker, full-suite]
    limits: {agents: 4, browser_jobs: 2}
    first_start: [trust-prompt, fullscreen-notice]
    persistence: disposable
  worker-2:
    transport: {herdr: worker-2}
    workdir: /w2
    caps: [edit, test, browser, docker, full-suite]
    limits: {agents: 4, browser_jobs: 2}
    first_start: [trust-prompt, fullscreen-notice]
    persistence: disposable
  control: {role: control-plane, assignable: false}
  broken:
    transport: {herdr: broken}
    workdir: /wb
    limits: {cores: 0}
EOF
  [ -z "${2:-}" ] || sed -i "$2" "$1"
}
reg_file "$REGF"
cfg() {   # cfg NAME  (yaml on stdin) -> $FXD/NAME.yml
  cat > "$FXD/$1.yml"; echo "$FXD/$1.yml"
}
CFG_ANY="$(cfg any <<'YML'
repo: owner/repo
phase_machines: {reviewer: any}
phases: {reviewer: {model: fable, effort: xhigh}}
YML
)"
CFG_W1="$(cfg w1 <<'YML'
repo: owner/repo
phase_machines: {reviewer: worker-1}
YML
)"

ROW=0
HENV=1
XENV=()
newrow() {   # newrow ['{"worker-1": {...}}'] : a fresh fake, fresh HOME, the default scenario merged with the overlay
  ROW=$((ROW+1)); export FAKE_HERDR_DIR="$TMP/fh/$ROW"; mkdir -p "$FAKE_HERDR_DIR"
  rm -rf "$TMP/home"; mkdir -p "$TMP/home"; HENV=1; XENV=(); OUT=""; ERR=""; RC=0
  "$PY" -c '
import json, sys
base = {"": {"agents": 2}, "worker-1": {"agents": 3}, "worker-2": {"agents": 1}}
for k, v in json.loads(sys.argv[1] or "{}").items():
    if v is None:
        base.pop(k, None)
    else:
        base.setdefault(k, {}).update(v)
json.dump(base, open(sys.argv[2], "w"))' "${1:-}" "$FAKE_HERDR_DIR/scenario.json"
}
# cli BACKEND args... : run sdlc from $TMP/cwd under a 120 s guard; OUT, ERR, RC
cli() {
  local be=$1; shift
  local p="$TMP/pybin" pp=""
  [ "$be" = yq ] && { p="$TMP/pyyq"; pp="$TMP/noyaml"; }
  [ "$be" = nohdr ] && p="$TMP/nohdr"
  local e=(); [ "$HENV" = 1 ] && e=(HERDR_ENV=1)
  OUT=$(cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$p" PYTHONPATH="$pp" ${e[@]+"${e[@]}"} ${XENV[@]+"${XENV[@]}"} \
        "$PY" "$SDLC" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
D() {   # D BACKEND CONFIG args... : sdlc delegate with the registry and config
  local be=$1 cfgf=$2; shift 2
  cli "$be" delegate "$@" --registry "${REGU:-$REGF}" --config "$cfgf"
}
has()  { case "$OUT"$'\n'"$ERR" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
hasnt() { ! has "$1"; }
t()    { local label=$1; shift; if "$@"; then ok "$label"; else bad "$label"; printf '      rc=%s out: %s\n      err: %s\n' "$RC" "$(printf '%s' "$OUT" | head -6)" "$(printf '%s' "$ERR" | head -8)"; fi; }
rc_is() { [ "$RC" = "$1" ]; }
first_is() { [ "$(printf '%s\n' "$OUT" | head -1)" = "$1" ]; }

PYLIB='
import json, os, re, sys
d = os.environ["FAKE_HERDR_DIR"]
def rd(n):
    try:
        return [json.loads(l) for l in open(os.path.join(d, n)) if l.strip()]
    except OSError:
        return []
calls = rd("calls.jsonl")
for c in calls:
    c["j"] = " ".join(c["argv"])
keys = rd("keys.jsonl"); prompts = rd("prompts.jsonl")
def n(rx, m=None): return sum(1 for c in calls if re.search(rx, c["j"]) and (m is None or c["machine"] == m))
def inorder(*rxs):
    i = 0
    for c in calls:
        if i < len(rxs) and re.search(rxs[i], c["j"]): i += 1
    return i == len(rxs)
MUT = re.compile(r"^(agent (start|prompt|rename)|workspace create|tab (create|rename)|pane (close|send-keys))")
def mut(): return [c for c in calls if MUT.search(c["j"])]
def first(rx):
    return next((c for c in calls if re.search(rx, c["j"])), None)
def pane():
    c = first(r"^agent start"); return c["argv"][c["argv"].index("--pane") + 1] if c else None
TARGET = {"trust-prompt": "Yes, I trust this folder", "fullscreen-notice": "Not now"}
def kok(declared=("trust-prompt", "fullscreen-notice")):
    for k in keys:
        if k["dialog"] is None or k["dialog"] not in declared or k["dialog"] not in TARGET:
            return False
        if k["key"] == "enter" and k["selected"] != TARGET[k["dialog"]]:
            return False
    return True
'
chk()  { local code=$1; "$PY" -I -c "${PYLIB}
sys.exit(0 if ($code) else 1)"; }
val()  { local code=$1; "$PY" -I -c "${PYLIB}
print($code)"; }
nocalls() { [ ! -s "$FAKE_HERDR_DIR/calls.jsonl" ]; }
STATE="$TMP/home/.local/state/sdlc/delegates"

# One kind of row: declared gates, then the key invariant.
K() { t "invariant K holds" chk 'kok()'; }

echo "B  the CLI against the fake herdr"

echo "D1 fit + load picking [both]"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  newrow; D $be "$CFG_ANY" reviewer --issue 139
  t "[$be] exit 0, first line names worker-2" bash -c '[ "$1" = 0 ] && [ "$(printf "%s\n" "$2" | head -1)" = "reviewer-139: worker-2" ]' _ "$RC" "$OUT"
  t "[$be] considered: local, worker-1 and worker-2 loads" bash -c 'for s in "workstation: 2 agents" "worker-1: 3 agents, limit 4" "worker-2: 1 agent, limit 4   <- picked"; do case "$1" in *"$s"*) ;; *) exit 1;; esac; done' _ "$OUT"
  t "[$be] considered: control and broken refused" bash -c 'case "$1" in *"control: machine '"'"'control'"'"' is not assignable"*) ;; *) exit 1;; esac; case "$1" in *"broken: machine '"'"'broken'"'"' has registry errors in:"*) ;; *) exit 1;; esac' _ "$OUT"
  t "[$be] every call after the probes carries --machine worker-2" chk 'all(c["machine"] == "worker-2" for c in calls if not c["j"].startswith("agent list"))'
done

echo "D2 tie goes to fit order"
newrow '{"":{"agents":1},"worker-1":{"agents":1},"worker-2":{"agents":1}}'; D $B1 "$CFG_ANY" reviewer --issue 139
t "workstation is picked, with no --machine on its calls" bash -c '[ "$1" = 0 ] && [ "$(printf "%s\n" "$2" | head -1)" = "reviewer-139: workstation" ]' _ "$RC" "$OUT"
t "the local calls carry no --machine" chk 'all(c["machine"] == "" for c in calls if not c["j"].startswith("agent list"))'

echo "D3 a full machine is skipped"
newrow '{"":{"agents":9},"worker-2":{"agents":4}}'; D $B1 "$CFG_ANY" reviewer --issue 139
t "worker-1 is picked" first_is "reviewer-139: worker-1"
t "worker-2 is full" has "worker-2: full: 4 agents, limit 4"

echo "D4 an unreachable machine is skipped"
newrow '{"":{"agents":9},"worker-2":{"unreachable":true}}'; D $B1 "$CFG_ANY" reviewer --issue 139
t "(a) exit 0 on worker-1" first_is "reviewer-139: worker-1"
t "(a) worker-2 is unreachable with herdr's text" has "worker-2: unreachable: error: unknown machine 'worker-2'"
newrow '{"":{"agents":9},"worker-2":{"hang":true}}'
OUT=$(timeout 120 env PATH="$TMP/pybin" HERDR_ENV=1 HOME="$TMP/home" "$PY" -I - "$LIB" "$REGF" "$CFG_ANY" <<'PYEOF' 2>&1
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import delegate, herdr
d = delegate.decide("reviewer", issue=139, registry_file=sys.argv[2], config_file=sys.argv[3], probe_timeout=3,
                    env={"HERDR_ENV": "1", "HOME": "/nonexistent"})
print(d.machine.name)
print([v.why for v in d.considered if v.machine == "worker-2"][0])
PYEOF
); RC=$?; ERR=""
t "(b) a hanging machine times out and worker-1 is picked" bash -c 'printf "%s\n" "$1" | grep -qx worker-1 && printf "%s\n" "$1" | grep -q "unreachable: timed out after 3s"' _ "$OUT"

echo "D5 everything full or unreachable"
newrow '{"worker-1":{"agents":4},"worker-2":{"unreachable":true}}'; HENV=0; D $B1 "$CFG_ANY" reviewer --issue 139
t "exit 1 with all three reasons" bash -c '[ "$1" = 1 ]' _ "$RC"
t "refused: no machine can take reviewer now" has "refused: no machine can take reviewer now"
t "local, full and unreachable reasons" bash -c 'for s in "this shell is not inside herdr" "full: 4 agents, limit 4" "unreachable"; do case "$2" in *"$s"*) ;; *) exit 1;; esac; done' _ "$RC" "$ERR"
t "no mutating verb was called" chk 'not mut()'

echo "D6 compute is refused"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139 --machine control
t "exit 1, not assignable, no herdr call" bash -c '[ "$1" = 1 ]' _ "$RC"
t "machine 'control' is not assignable" has "machine 'control' is not assignable"
t "calls is empty" nocalls
echo "D6b any unassignable machine is refused, also when the repo places nothing"
NOPLACE="$(cfg noplace <<'YML'
repo: owner/repo
YML
)"
newrow; D $B1 "$NOPLACE" reviewer --issue 139 --machine control
t "exit 1 with the same reason and no calls" bash -c '[ "$1" = 1 ]' _ "$RC"
t "reason" has "machine 'control' is not assignable"
t "calls is empty" nocalls

echo "D7 unknown and not-ok machines"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-9
t "unknown: exit 1, did you mean" bash -c '[ "$1" = 1 ]' _ "$RC"
t "'worker-9' is not in the registry; did you mean 'worker-2'?" has "'worker-9' is not in the registry; did you mean 'worker-2'?"
D $B1 "$CFG_ANY" reviewer --issue 139 --machine broken
t "broken: has registry errors in:" has "has registry errors in:"
t "calls is empty" nocalls

echo "D8 needs refuse an explicit machine, opted in or not"
NEEDS_KEEPS="$(cfg nk <<'YML'
repo: owner/repo
needs: {reviewer: {keeps: [datasets]}}
YML
)"
newrow; D $B1 "$NEEDS_KEEPS" reviewer --issue 139 --machine worker-1
t "exit 1, lacks keeps: datasets, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"
t "lacks keeps" has "lacks keeps: datasets"
t "calls is empty" nocalls

echo "D9 broken needs refuse, opted in or not"
N_A="$(cfg na <<'YML'
repo: owner/repo
needs: {reviewer: {secrets: staging}}
YML
)"
N_B="$(cfg nb <<'YML'
repo: owner/repo
needs: {reviewer: [edit]}
needs: {reviewer: [test]}
YML
)"
N_C="$(cfg nc <<'YML'
repo: owner/repo
needs: browser
YML
)"
N_D="$(cfg nd <<'YML'
repo: owner/repo
phase_machines: {reviewer: any}
needs: {reviewer: {secrets: staging}}
YML
)"
newrow; D $B1 "$N_A" reviewer --issue 139 --machine worker-1
t "(a) needs.reviewer has errors in: secrets" has "needs.reviewer has errors in: secrets"
t "(a) no sdlc machines check hint" hasnt "sdlc machines check"
t "(a) rc 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "(a) calls is empty" nocalls
newrow; D $B1 "$N_B" reviewer --issue 139 --machine worker-1
t "(b) the top-level needs in ... is written more than once" bash -c 'case "$1" in *"the top-level needs in "*"is written more than once"*) ;; *) exit 1;; esac' _ "$ERR"
t "(b) rc 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "(b) calls is empty" nocalls
newrow; D $B1 "$N_C" reviewer --issue 139 --machine worker-1
t "(c) is not a map (got str)" has "is not a map (got str)"
t "(c) rc 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "(c) calls is empty" nocalls
newrow; D $B1 "$N_D" reviewer --issue 139 --machine worker-1
t "(d) the (a) text plus the hint" has "needs.reviewer has errors in: secrets; see: sdlc machines check"
t "(d) rc 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "(d) calls is empty" nocalls

echo "D10 off causes"
newrow; EMPTYH="$TMP/emptyhome"; mkdir -p "$EMPTYH"
OUT=$(cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV -u SDLC_MACHINES PATH="$TMP/pybin" HOME="$EMPTYH" HERDR_ENV=1 "$PY" "$SDLC" delegate reviewer --issue 1 --config "$CFG_ANY" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
t "no registry: exit 1 with the registry hint" bash -c '[ "$1" = 1 ]' _ "$RC"
t "no machine registry + sdlc delegate needs a registry" bash -c 'case "$1" in *"no machine registry"*"sdlc delegate needs a registry"*) ;; *) exit 1;; esac' _ "$ERR"
t "calls is empty" nocalls
TWO="$TMP/two.yaml"; printf 'machines:\n  a: {transport: local}\n  b: {transport: local}\n' > "$TWO"
newrow; REGU="$TWO" D $B1 "$CFG_ANY" reviewer --issue 1
t "two local machines: the registry has errors" has "the registry has errors"
t "two local machines: exit 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "calls is empty" nocalls
BADCFG="$(cfg badcfg <<'YML'
phase_machines: [
YML
)"
newrow; D $B1 "$BADCFG" reviewer --issue 1
t "unparseable sdlc.yml: sdlc.yml has errors" has "sdlc.yml has errors"
t "exit 1, no calls" bash -c '[ "$1" = 1 ]' _ "$RC"; t "calls is empty" nocalls

echo "D11 not opted in: auto refuses, an explicit machine works"
newrow; D $B1 "$NOPLACE" reviewer --issue 1
t "auto: exit 1, sdlc.yml places nothing" bash -c '[ "$1" = 1 ]' _ "$RC"
t "sdlc.yml places nothing" has "sdlc.yml places nothing"
t "calls is empty" nocalls
D $B1 "$NOPLACE" reviewer --issue 1 --machine worker-2
t "explicit machine: exit 0 on worker-2" first_is "reviewer-1: worker-2"

echo "D12 the busy flag"
BUSYCFG="$(cfg busy <<'YML'
repo: owner/repo
phase_machines: {validator: any, reviewer: any}
needs: {validator: [browser]}
YML
)"
newrow '{"worker-1":{"agents":4},"worker-2":{"agents":4}}'; touch "$TMP/busy"; D $B1 "$BUSYCFG" validator --issue 1
t "heavy role, flag present: exit 1" bash -c '[ "$1" = 1 ]' _ "$RC"
t "workstation: busy: ... remove the file" has "workstation: busy: $TMP/busy exists and validator needs browser; remove the file when the box is free, or delegate to another machine"
rm -f "$TMP/busy"; newrow '{"worker-1":{"agents":4},"worker-2":{"agents":4}}'; D $B1 "$BUSYCFG" validator --issue 1
t "flag removed: exit 0 on workstation" first_is "validator-1: workstation"
newrow '{"worker-1":{"agents":4},"worker-2":{"agents":4}}'; touch "$TMP/busy"; D $B1 "$BUSYCFG" reviewer --issue 1
t "non-heavy role with the flag present: workstation is picked" first_is "reviewer-1: workstation"
newrow; D $B1 "$BUSYCFG" validator --issue 1 --machine workstation
t "explicit --machine workstation, heavy, flag present: exit 1" bash -c '[ "$1" = 1 ]' _ "$RC"
t "busy" has "busy: $TMP/busy exists"
t "no herdr call for the local server" chk 'n(r".", "") == 0'
rm -f "$TMP/busy"

echo "D12b busy-flag paths"
echo "x" > "$TMP/afile"
LONG="$(printf 'a%.0s' $(seq 1 5000))"
for variant in rel ENOTDIR LONG; do
  case $variant in
    rel) V='s#busy_flag: .*#busy_flag: rel/flag#' ;;
    ENOTDIR) V="s#busy_flag: .*#busy_flag: $TMP/afile/flag#" ;;
    LONG) V="s#busy_flag: .*#busy_flag: /$LONG#" ;;
  esac
  reg_file "$TMP/reg-$variant.yaml" "$V"
  newrow; REGU="$TMP/reg-$variant.yaml" D $B1 "$BUSYCFG" validator --issue 1 --machine workstation
  case $variant in
    rel) t "(a) a relative flag is busy" has "is not an absolute path" ;;
    ENOTDIR) t "(b) ENOTDIR is not busy: exit 0 on workstation" first_is "validator-1: workstation" ;;
    LONG) t "(c) ENAMETOOLONG is busy: could not check busy_flag" has "could not check busy_flag" ;;
  esac
done

echo "D13 browser jobs"
BROWSER_CFG="$(cfg browser <<'YML'
repo: owner/repo
needs: {validator: [browser]}
YML
)"
newrow '{"worker-1":{"agents":3}}'
mkdir -p "$STATE/worker-1"
echo '{"name":"busy1","pane_id":"w9:p1","browser_job":true}' > "$STATE/worker-1/busy1.json"
echo '{"name":"busy2","pane_id":"w9:p2","browser_job":true}' > "$STATE/worker-1/busy2.json"
echo '{"name":"busy3","pane_id":"w9:p9","browser_job":true}' > "$STATE/worker-1/busy3.json"
echo 'not json' > "$STATE/worker-1/junk.json"
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1
t "two live browser jobs: exit 1, full: 2 browser jobs, limit 2" bash -c '[ "$1" = 1 ]' _ "$RC"
t "full: 2 browser jobs, limit 2" has "full: 2 browser jobs, limit 2"
D $B1 "$BROWSER_CFG" reviewer --issue 1 --machine worker-1
t "a non-browser role on worker-1: exit 0" first_is "reviewer-1: worker-1"

echo "D14 no workdir; local outside herdr"
reg_file "$TMP/reg-nowd.yaml" '/transport: local/{n;d}'
newrow; REGU="$TMP/reg-nowd.yaml" D $B1 "$CFG_ANY" reviewer --issue 139
t "workstation: no workdir in the registry" has "workstation: no workdir in the registry"
t "no local-server call" chk 'n(r".", "") == 0'
newrow; HENV=0; D $B1 "$CFG_ANY" reviewer --issue 139
t "workstation: this shell is not inside herdr" has "workstation: this shell is not inside herdr"
t "no local-server call" chk 'n(r".", "") == 0'

echo "D15 first start, 0 dialogs"
newrow; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0, first start: none shown, no send-keys" bash -c '[ "$1" = 0 ]' _ "$RC"
t "first start: none shown" has "first start: none shown"
t "no send-keys call" chk 'n(r"send-keys") == 0'

echo "D16 first start, 1 dialog"
newrow '{"worker-1":{"gates":["trust-prompt"]}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0" bash -c '[ "$1" = 0 ]' _ "$RC"
t "in order: start, read, down, read, enter, prompt" chk 'inorder(r"^agent start", r"^pane read \S+ --source visible --format text", r"send-keys \S+ down", r"^pane read", r"send-keys \S+ enter", r"^agent prompt \S+")'
t "first start: trust-prompt answered" has "first start: trust-prompt answered"
K

echo "D17 first start, 2 dialogs"
newrow '{"worker-1":{"gates":["trust-prompt","fullscreen-notice"]}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0, two down/enter pairs" chk 'n(r"send-keys \S+ down") == 2 and n(r"send-keys \S+ enter") == 2'
t "first start names both" has "first start: trust-prompt, fullscreen-notice answered"
K

echo "D18 answer cap"
newrow '{"worker-1":{"gates":["trust-prompt"],"stuck":true}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "exit 3" bash -c '[ "$1" = 3 ]' _ "$RC"
t "trust-prompt still showing after 2 answers" has "trust-prompt still showing after 2 answers"
t "the pane output shows the dialog" has "Yes, I trust this folder"
t "left behind: nothing (pane closed)" bash -c 'case "$1" in *"left behind: nothing (pane "*" closed)"*) ;; *) exit 1;; esac' _ "$ERR"
t "pane close was called; exactly 2 down and 2 enter" chk 'n(r"^pane close") == 1 and n(r"send-keys \S+ down") == 2 and n(r"send-keys \S+ enter") == 2'
K

echo "D19 undeclared or unknown dialog"
reg_file "$TMP/reg-nofs.yaml" 's/first_start: \[trust-prompt, fullscreen-notice\]/first_start: []/'
newrow '{"worker-1":{"gates":["trust-prompt"]}}'; REGU="$TMP/reg-nofs.yaml" D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(a) exit 3 with doesn't declare" bash -c '[ "$1" = 3 ]' _ "$RC"
t "(a) doesn't declare" has "doesn't declare"
t "(a) no key was sent" chk 'len(keys) == 0'
newrow '{"worker-1":{"gates":["unknown"]}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 4
t "(b) exit 3 with was not ready within 4s" bash -c '[ "$1" = 3 ]' _ "$RC"
t "(b) was not ready within 4s" has "was not ready within 4s"
t "(b) no key was sent" chk 'len(keys) == 0'

echo "D20 --keep-failed"
newrow '{"worker-1":{"gates":["trust-prompt"],"stuck":true}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20 --keep-failed
t "exit 3, no pane close" bash -c '[ "$1" = 3 ]' _ "$RC"
t "no pane close call" chk 'n(r"^pane close") == 0'
t "left behind: pane, with the stop command" bash -c 'case "$1" in *"left behind: pane "*) ;; *) exit 1;; esac; case "$1" in *"stop:"*"pane close"*) ;; *) exit 1;; esac' _ "$ERR"
K

echo "D21 agent arguments"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139
t "worker-2: ends -- --permission-mode auto --model fable --effort xhigh" chk '(lambda a: a[a.index("--"):] == ["--", "--permission-mode", "auto", "--model", "fable", "--effort", "xhigh"] and a[a.index("--kind") + 1] == "claude" and a[a.index("--timeout") + 1] == "90000" and "--pane" in a)(first(r"^agent start")["argv"])'
newrow; D $B1 "$CFG_W1" reviewer --issue 139
t "no tuning: ends -- --permission-mode auto" chk '(lambda a: a[a.index("--"):] == ["--", "--permission-mode", "auto"])(first(r"^agent start")["argv"])'
FLATGROUP="$(cfg fg <<'YML'
repo: owner/repo
phase_machines: {reviewer: worker-1}
phase_models: {reviewer: opus}
phases: {reviewer: {model: fable}}
YML
)"
newrow; D $B1 "$FLATGROUP" reviewer --issue 139
t "grouped model beats the flat one" chk '"--model" in first(r"^agent start")["argv"] and first(r"^agent start")["argv"][first(r"^agent start")["argv"].index("--model") + 1] == "fable"'

echo "D22 bad tuning refuses before any herdr call"
BADEFF="$(cfg badeff <<'YML'
repo: owner/repo
phase_machines: {reviewer: worker-1}
phases: {reviewer: {effort: huge}}
YML
)"
newrow; D $B1 "$BADEFF" reviewer --issue 139
t "exit 1, the effort is named, calls empty" bash -c '[ "$1" = 1 ]' _ "$RC"
t "phases.reviewer.effort 'huge' is not one of" has "phases.reviewer.effort 'huge' is not one of: low, medium, high, xhigh, max"
t "calls is empty" nocalls

echo "D23 the mission"
printf 'TASK-FROM-FILE: summarise the diff\n' > "$TMP/task.md"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139 --prompt @"$TMP/task.md"
t "exit 0" bash -c '[ "$1" = 0 ]' _ "$RC"
t "the prompt targets the pane and carries the mission" chk 'len(prompts) == 1 and prompts[0]["target"] == pane() and all(s in prompts[0]["text"] for s in ("GitHub only", "gh auth status", "/w2/reviewer-139", "issue #139 in owner/repo", "TASK-FROM-FILE"))'
t "the prompt call waits for working or blocked" chk '(lambda a: "--wait" in a and a.count("--until") == 2 and "working" in a and "blocked" in a)(prompts[0]["argv"])'

echo "D24 usage"
newrow
D $B1 "$CFG_ANY" reviewer;                                         t "no --issue and no --prompt: exit 2" rc_is 2
D $B1 "$CFG_ANY" reviewer --prompt @/nope;                         t "--prompt @/nope: exit 2" rc_is 2
D $B1 "$CFG_ANY" reviewer --issue 1 --name 'Bad!';                 t "--name Bad!: exit 2" rc_is 2
D $B1 "$CFG_ANY" reviewer --issue 1 --start-timeout 3;             t "--start-timeout 3: exit 2" rc_is 2
D $B1 "$CFG_ANY" reviewer --issue 0;                               t "--issue 0: exit 2" rc_is 2
D $B1 "$CFG_ANY" 'sdlc:' --issue 1;                                t "role sdlc: exit 2" rc_is 2
t "none of them called herdr" nocalls

echo "D25 an issue without a repo"
NOREPO="$(cfg norepo <<'YML'
phase_machines: {reviewer: worker-1}
YML
)"
newrow; D $B1 "$NOREPO" reviewer --issue 139
t "exit 1: can't tell which GitHub repository" has "can't tell which GitHub repository"
t "rc 1 and calls empty" bash -c '[ "$1" = 1 ]' _ "$RC"; t "calls is empty" nocalls
newrow; D $B1 "$CFG_W1" reviewer --issue 139
t "with repo: set, exit 0" rc_is 0

echo "D26 dry run"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139 --dry-run
t "exit 0; first line ends (dry run: nothing started)" bash -c '[ "$1" = 0 ] && printf "%s\n" "$2" | head -1 | grep -q "(dry run: nothing started)$"' _ "$RC" "$OUT"
t "would run / workspace create / agent start / dialog step / mission" bash -c 'for s in "would run:" "workspace create --label" "sdlc-delegate.<nonce>" "workspace rename" "<new-workspace>" "agent start reviewer-139 --kind claude" "--permission-mode auto" "then, for each dialog" "mission:" "GitHub only"; do case "$1" in *"$s"*) ;; *) echo "missing: $s" >&2; exit 1;; esac; done' _ "$OUT"
t "only read-only verbs were called" chk 'not mut()'
t "no record file exists" bash -c '[ ! -e "$1" ]' _ "$TMP/home/.local/state/sdlc"

echo "D27 the record"
newrow; D $B1 "$CFG_ANY" reviewer --issue 139
REC="$TMP/home/.local/state/sdlc/delegates/worker-2/reviewer-139.json"
t "record exists with the fields" bash -c '[ -f "$1" ] && "$2" -I -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert d[\"machine\"]==\"worker-2\" and d[\"herdr\"]==\"worker-2\" and d[\"pane_id\"] and isinstance(d[\"startup\"], list)
assert d[\"argv\"]==[\"claude\",\"--permission-mode\",\"auto\",\"--model\",\"fable\",\"--effort\",\"xhigh\"], d[\"argv\"]
assert d[\"argv_source\"]==\"process-info\" and d[\"browser_job\"] is False and d[\"briefed\"] is True and d[\"status\"]==\"working\"
" "$1"' _ "$REC" "$PY"
t "the record: line gives that path" has "record:      $REC"
t "check, read and stop address worker-2 and the pane" bash -c 'P=$(printf "%s\n" "$1" | sed -n "s/^  where:.*pane //p"); for k in check read stop; do printf "%s\n" "$1" | grep "^  $k:" | grep -q -- "--machine worker-2" || exit 1; printf "%s\n" "$1" | grep "^  $k:" | grep -q -- "$P" || exit 1; done' _ "$OUT"
newrow; XENV=(XDG_STATE_HOME="$TMP/st"); D $B1 "$CFG_ANY" reviewer --issue 139
t "XDG_STATE_HOME moves the record" test -f "$TMP/st/sdlc/delegates/worker-2/reviewer-139.json"
rm -rf "$TMP/st"

echo "D28 workspace and pane reuse"
WS_B='{"worker-2":{"agents":0,"workspaces":[{"label":"sdlc-delegate","tabs":[{"label":"sdlc:old","panes":[{"cwd":"/w2","fg":"bash"}]}]}]}}'
newrow '{"worker-2":{"agents":0}}'; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(a) workspace create with a temporary label, renamed to sdlc-delegate, then the tab rename" chk 'inorder(r"^workspace create --label sdlc-delegate\.[0-9a-f]+ --cwd /w2 --no-focus", r"^workspace rename \S+ sdlc-delegate$", r"^tab rename \S+ sdlc:reviewer-139")'
newrow "$WS_B"; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(b) a free pane is reused: no tab create, tab renamed" chk 'n(r"^tab create") == 0 and n(r"^workspace create") == 0 and n(r"^tab rename \S+ sdlc:reviewer-139") == 1'
newrow '{"worker-2":{"agents":0,"workspaces":[{"label":"sdlc-delegate","tabs":[{"label":"sdlc:old","panes":[{"cwd":"/w2","fg":"node"}]}]}]}}'; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(c) a pane running node is not reused: tab create" chk 'n(r"^tab create --workspace \S+ --label sdlc:reviewer-139\.[0-9a-f]+ --cwd /w2 --no-focus") == 1 and n(r"^tab rename \S+ sdlc:reviewer-139$") == 1'
newrow '{"worker-2":{"agents":0,"workspaces":[{"label":"sdlc-delegate","tabs":[{"label":"sdlc:old","panes":[{"cwd":"/w2","fg":"bash","agent":"old1"}]}]}]}}'; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(d) a pane with a live agent is not reused: tab create" chk 'n(r"^tab create") == 1'
newrow '{"worker-2":{"agents":0,"workspaces":[{"label":"sdlc","tabs":[{"label":"sdlc:old","panes":[{"cwd":"/w2","fg":"bash"}]}]}]}}'; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(e) a workspace labelled sdlc is not used: workspace create" chk 'n(r"^workspace create --label sdlc-delegate") == 1 and n(r"^tab create") == 0'

echo "D29 names"
LIVE_NAME='{"worker-2":{"agents":0,"workspaces":[{"label":"other","tabs":[{"label":"x","panes":[{"cwd":"/elsewhere","fg":"claude","agent":"reviewer-139"}]}]}]}}'
newrow "$LIVE_NAME"; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(a) a live default name takes -2" first_is "reviewer-139-2: worker-2"
newrow "$LIVE_NAME"; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2 --name reviewer-139
t "(b) an explicit live --name: exit 1, already live" bash -c '[ "$1" = 1 ]' _ "$RC"
t "already live" has "already live"
newrow '{"worker-2":{"agents":0,"name_taken_once":true}}'; D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-2
t "(c) agent_name_taken once: a second start with reviewer-139-2 on the same pane" chk 'n(r"^agent start reviewer-139 ") == 1 and n(r"^agent start reviewer-139-2 ") == 1 and len({c["argv"][c["argv"].index("--pane") + 1] for c in calls if c["j"].startswith("agent start")}) == 1'
t "(c) exit 0" rc_is 0
t "(c) the tab label follows the final name" chk 'n(r"^tab rename \S+ sdlc:reviewer-139-2$") == 1'

echo "D30 brief failures"
newrow '{"worker-1":{"prompt_error":"agent_prompt_stalled"}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(a) exit 3, no pane close, left behind: pane" bash -c '[ "$1" = 3 ]' _ "$RC"
t "(a) no pane close" chk 'n(r"^pane close") == 0'
t "(a) left behind: pane" has "left behind: pane "
t "(a) the record has briefed false" bash -c '"$1" -I -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))[\"briefed\"] is False else 1)" "$2"' _ "$PY" "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
newrow '{"worker-1":{"prompt_error_once":"agent_blocked","prompt_gate":"fullscreen-notice"}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(b) one more dialog round, then a second agent prompt; exit 0" bash -c '[ "$1" = 0 ]' _ "$RC"
t "(b) two agent prompt calls" chk 'n(r"^agent prompt") == 2'
t "(b) the dialog was answered once" chk 'n(r"send-keys \S+ enter") == 1'
K

echo "D31 herdr missing"
newrow; cli nohdr delegate reviewer --issue 139 --registry "$REGF" --config "$CFG_ANY"
t "exit 1; every candidate is unreachable: herdr not found on PATH" bash -c '[ "$1" = 1 ]' _ "$RC"
t "unreachable: herdr not found on PATH" has "unreachable: herdr not found on PATH"

echo "D33 an unnamed agent with null readiness"
newrow '{"worker-1":{"gates":["trust-prompt"],"unnamed_after_gate":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0" rc_is 0
t "agent rename <P> reviewer-139 exactly once, before the prompt" chk 'n(r"^agent rename \S+ reviewer-139$") == 1 and inorder(r"^agent rename", r"^agent prompt")'
t "the record shows name: null in startup" bash -c '"$1" -I -c "import json,sys; sys.exit(0 if any(r.get(\"name\") is None and r.get(\"interactive_ready\") is None and r.get(\"action\")==\"read\" for r in json.load(open(sys.argv[1]))[\"startup\"]) else 1)" "$2"' _ "$PY" "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
K

echo "D34 the selection check"
newrow '{"worker-1":{"gates":["trust-prompt"],"marker_stuck":true}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "exit 3: after Down the selection is" bash -c '[ "$1" = 3 ]' _ "$RC"
t "after Down the selection is" has "after Down the selection is"
t "exactly one down and zero enter" chk 'n(r"send-keys \S+ down") == 1 and n(r"send-keys \S+ enter") == 0'
K

echo "D35 the selection is already on the target"
newrow '{"worker-1":{"gates":["fullscreen-notice"],"focus_target":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0; one enter and no down" chk 'n(r"send-keys \S+ enter") == 1 and n(r"send-keys \S+ down") == 0'
t "exit 0" rc_is 0
K

echo "D36 a stale screen"
newrow '{"worker-1":{"gates":["trust-prompt"],"redraw_lag":2}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0; exactly one down/enter pair" chk 'n(r"send-keys \S+ down") == 1 and n(r"send-keys \S+ enter") == 1'
t "exit 0" rc_is 0
K

echo "D37 the auto-mode prompt is never answered"
newrow '{"worker-1":{"gates":["auto-mode-teach"]}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "exit 3: is never answered automatically" has "is never answered automatically"
t "exit 3 and no keys" bash -c '[ "$1" = 3 ]' _ "$RC"; t "no key was sent" chk 'len(keys) == 0'
t "the pane output names the dialog" has "Teach auto mode about your environment"

echo "D38 a dialog while herdr says idle"
newrow '{"worker-1":{"gates":["trust-prompt"],"idle_with_gate":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0; answered before agent prompt" chk 'n(r"send-keys \S+ down") == 1 and n(r"send-keys \S+ enter") == 1 and inorder(r"^agent start", r"send-keys \S+ enter", r"^agent prompt")'
t "exit 0" rc_is 0
K

echo "D39 pane read is text"
SCREENJSON='{"result": {"read": {"text": "x"}}}'
newrow "{\"worker-1\":{\"gates\":[\"trust-prompt\"]}}"
OUT=$(timeout 120 env PATH="$TMP/pybin" "$PY" -I - "$LIB" <<'PYEOF' 2>&1
import json, os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr
made = herdr.workspace_create("worker-1", "x", "/w1")
pane = made["root_pane"]["pane_id"]
try:
    herdr.agent_start("worker-1", "t", pane)
except herdr.HerdrError as exc:
    assert exc.code == "agent_not_ready", exc.code
screen = herdr.pane_read("worker-1", pane)
assert isinstance(screen, str) and screen.startswith("Quick safety check"), repr(screen)
print("trust-ok")
sc = json.load(open(os.path.join(os.environ["FAKE_HERDR_DIR"], "scenario.json")))
sc["worker-1"]["raw_screen"] = '{"result": {"read": {"text": "x"}}}'
json.dump(sc, open(os.path.join(os.environ["FAKE_HERDR_DIR"], "scenario.json"), "w"))
raw = herdr.pane_read("worker-1", pane)
assert raw == '{"result": {"read": {"text": "x"}}}' and isinstance(raw, str), repr(raw)
print("json-ok")
PYEOF
); RC=$?; ERR=""
t "(a) the trust screen comes back unchanged as str" has "trust-ok"
t "(b) a screen that is valid JSON is returned unchanged" has "json-ok"
t "the call has --format text" chk 'n(r"^pane read \S+ --source visible --format text$") == 2'

echo "D40 a dialog replaced before Enter"
newrow '{"worker-1":{"gates":["trust-prompt"],"swap_before_enter":{"to":"auto-mode-teach","after_target_reads":1}}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(a) exit 3, never answered automatically" has "is never answered automatically"
t "(a) one down on trust-prompt and no enter" chk 'n(r"send-keys \S+ down") == 1 and n(r"send-keys \S+ enter") == 0 and [k["dialog"] for k in keys] == ["trust-prompt"]'
newrow '{"worker-1":{"gates":["trust-prompt"],"swap_before_enter":{"to":"fullscreen-notice","after_target_reads":1}}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(b) exit 0" rc_is 0
t "(b) the only enter is on fullscreen-notice with Not now selected" chk '[(k["dialog"], k["selected"]) for k in keys if k["key"] == "enter"] == [("fullscreen-notice", "Not now")]'
K
newrow '{"worker-1":{"gates":["fullscreen-notice"],"focus_target":true,"swap_before_enter":{"to":"auto-mode-teach","after_target_reads":2}}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(c) exit 3, never answered automatically" has "is never answered automatically"
t "(c) no keys at all" chk 'len(keys) == 0'

echo "D41 the argv fallback"
newrow '{"worker-1":{"no_process_argv":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0; argv_source intended" bash -c '[ "$1" = 0 ] && "$2" -I -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d[\"argv_source\"]==\"intended\" and d[\"argv\"]==[\"claude\",\"--permission-mode\",\"auto\"] else 1)" "$3"' _ "$RC" "$PY" "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
t "the claude: line shows the same" has "claude:      claude --permission-mode auto"

echo "D42 no readable selection never hangs"
newrow '{"worker-1":{"gates":["trust-prompt"],"marker_glyph":"none"}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 4
t "exit 3 (not a timeout kill): could not read the selection on trust-prompt" bash -c '[ "$1" = 3 ]' _ "$RC"
t "could not read the selection on trust-prompt, with the screen" bash -c 'case "$1" in *"could not read the selection on trust-prompt"*"Yes, I trust this folder"*) ;; *) exit 1;; esac' _ "$ERR"
t "zero keys" chk 'len(keys) == 0'

echo "D43 the ASCII marker"
newrow '{"worker-1":{"gates":["trust-prompt","fullscreen-notice"],"marker_glyph":">"}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0; one down/enter pair per dialog" chk 'n(r"send-keys \S+ down") == 2 and n(r"send-keys \S+ enter") == 2'
t "exit 0" rc_is 0
K

echo "D44 the workdir is missing on the worker"
newrow '{"worker-1":{"missing_cwd":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(a) exit 3: workdir /w1 doesn't exist on worker-1 (the new pane opened in /)" has "workdir /w1 doesn't exist on worker-1 (the new pane opened in /)"
t "(a) exit 3" rc_is 3
t "(a) the pane was closed; no agent start" chk 'n(r"^pane close") == 1 and n(r"^agent start") == 0'
t "(a) no record" bash -c '! find "$1" -name "*.json" 2>/dev/null | grep -q .' _ "$TMP/home/.local/state/sdlc"
newrow '{"worker-1":{"missing_cwd":true,"workspaces":[{"label":"sdlc-delegate","tabs":[{"label":"sdlc:x","panes":[{"cwd":"/other","fg":"bash"}]}]}]}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(b) tab create path: the same message" has "workdir /w1 doesn't exist on worker-1 (the new pane opened in /)"
t "(b) tab create, pane close, no agent start" chk 'n(r"^tab create") == 1 and n(r"^pane close") == 1 and n(r"^agent start") == 0'

echo "D45 a remote workdir must be absolute"
reg_file "$TMP/reg-relwd.yaml" 's#workdir: /w1#workdir: work#'
newrow; REGU="$TMP/reg-relwd.yaml" D $B1 "$CFG_ANY" reviewer --issue 139 --machine worker-1
t "exit 1: workdir 'work' must be an absolute path on a remote machine" has "workdir 'work' must be an absolute path on a remote machine"
t "rc 1 and calls empty" bash -c '[ "$1" = 1 ]' _ "$RC"; t "calls is empty" nocalls

echo "D47 a late redraw after Enter never gets a second Enter"
LAGW='{"worker-1":{"gates":["fullscreen-notice","trust-prompt"],"focus_target":true,"lag_enter_only":true,"redraw_lag":12}}'
newrow "$LAGW"; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 60
t "(a) fullscreen then trust, redraw lags past CLEAR_WAIT: exit 0" rc_is 0
t "(a) exactly one Enter per dialog" chk 'n(r"send-keys \S+ enter") == 2'
K
newrow '{"worker-1":{"gates":["trust-prompt","fullscreen-notice"],"lag_enter_only":true,"redraw_lag":12}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 60
t "(b) trust then fullscreen, redraw lags past CLEAR_WAIT: exit 0" rc_is 0
t "(b) exactly one Enter per dialog" chk 'n(r"send-keys \S+ enter") == 2'
K
newrow '{"worker-1":{"gates":["trust-prompt"],"lag_enter_only":true,"redraw_lag":60}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 12
t "(c) a screen that never redraws: exit 3, did not respond to Enter" has "did not respond to Enter"
t "(c) exit 3" rc_is 3
t "(c) one Enter in total" chk 'n(r"send-keys \S+ enter") == 1'
K

echo "D48 Ctrl-C and SIGTERM leave no pane behind"
set -m
bg_delegate() {   # bg_delegate SIGNAL [extra args] : a delegate stuck on an unknown dialog, signalled once started
  local sig=$1; shift
  newrow '{"worker-1":{"agents":0,"gates":["unknown"]}}'
  ( cd "$TMP/cwd" && exec env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate reviewer --issue 139 \
      --registry "$REGF" --config "$CFG_W1" --start-timeout 60 "$@" >"$TMP/out" 2>"$TMP/err" ) &
  local pid=$! i
  for i in $(seq 1 100); do chk 'n(r"^agent start") >= 1' && break; sleep 0.2; done
  sleep 1; kill -s "$sig" "$pid"; wait "$pid"; RC=$?
  OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
NOPANES='not json.load(open(d + "/state.json")).get("worker-1", {}).get("panes") and not json.load(open(d + "/state.json")).get("worker-1", {}).get("agents")'
bg_delegate INT
t "SIGINT: exit 130" rc_is 130
t "SIGINT: no pane or agent is left" chk "$NOPANES"
t "SIGINT: the pane was closed without reading its output" chk 'n(r"recent-unwrapped") == 0 and n(r"^pane close") == 1'
t "SIGINT: left behind: nothing (pane closed)" bash -c 'case "$1" in *"left behind: nothing (pane "*" closed)"*) ;; *) exit 1;; esac' _ "$ERR"
bg_delegate TERM
t "SIGTERM: exit 143" rc_is 143
t "SIGTERM: no pane or agent is left" chk "$NOPANES"
bg_delegate INT --keep-failed
t "SIGINT with --keep-failed: exit 130, the pane stays with a stop: line" bash -c '[ "$1" = 130 ] && case "$2" in *"left behind: pane "*"stop:"*"pane close"*) ;; *) exit 1;; esac' _ "$RC" "$ERR"
t "SIGINT with --keep-failed: a record with status failed is written" bash -c '"$1" -I -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))[\"status\"]==\"failed\" else 1)" "$2"' _ "$PY" "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
set +m

echo "D49 an unexpected exception exits 3 and leaves no pane"
cat > "$TMP/inject.py" <<'PYEOF'
import importlib.machinery, importlib.util, json, os, sys, io
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
loader = importlib.machinery.SourceFileLoader("sdlcbin", sys.argv[2])
spec = importlib.util.spec_from_loader("sdlcbin", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
args = ["delegate", "reviewer", "--issue", "139", "--registry", sys.argv[3], "--config", sys.argv[4]]


def boom(*a, **k):
    raise RuntimeError("injected")


real = mod.herdr.pane_processes
mod.herdr.pane_processes = boom                      # after the agent is ready, before the brief
rc1 = mod.main(args)
mod.herdr.pane_processes = real
real_decide = mod.delegate.decide
mod.delegate.decide = boom                           # before anything is started
rc2 = mod.main(args)
d = os.environ["FAKE_HERDR_DIR"]
st = json.load(open(os.path.join(d, "state.json"))).get("worker-1", {})
print("rc", rc1, rc2, "panes", len(st.get("panes", [])), "agents", len(st.get("agents", [])))
PYEOF
newrow '{"worker-1":{"agents":0}}'
OUT=$(cd "$TMP/cwd" && timeout 120 env PATH="$TMP/pybin" HERDR_ENV=1 "$PY" -I "$TMP/inject.py" "$LIB" "$SDLC" "$REGF" "$CFG_W1" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
t "injected exceptions: exit 3 (never 1), and no pane or agent is left" has "rc 3 3 panes 0 agents 0"
t "the unexpected error is reported" has "unexpected error: RuntimeError: injected"

echo "D50 a brief that certainly did not arrive leaves nothing behind"
newrow '{"worker-1":{"prompt_error":"agent_blocked"}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "exit 3; the pane is closed and there is no record" bash -c '[ "$1" = 3 ]' _ "$RC"
t "pane close was called" chk 'n(r"^pane close") == 1'
t "left behind: nothing" has "left behind: nothing (pane"
t "no record file" bash -c '[ ! -e "$1" ]' _ "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
newrow '{"worker-1":{"prompt_error":"agent_blocked"}}'; D $B1 "$CFG_W1" reviewer --issue 139 --keep-failed
t "--keep-failed keeps the pane and the record" bash -c '[ "$1" = 3 ] && [ -f "$2" ]' _ "$RC" "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"

echo "D51 the elevated trust dialog is never answered"
newrow '{"worker-1":{"gates":["trust-elevated"]}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "exit 3, never answered automatically" has "is never answered automatically"
t "exit 3" rc_is 3
t "no key was sent" chk 'len(keys) == 0'
t "the screen is shown" has "No, continue without these permissions"

echo "D52 a dialog added next to a gate, or swapped before Down, gets no key"
newrow '{"worker-1":{"gates":["trust-prompt"],"augment_at_read":{"n":2,"text":"auto-mode-teach"}}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(a) auto-mode prompt beside the gate: exit 3, never answered, zero keys" has "is never answered automatically"
t "(a) zero keys" chk 'len(keys) == 0'
newrow '{"worker-1":{"gates":["trust-prompt"],"swap_at_read":{"n":3,"to":"auto-mode-teach"}}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(b) dialog swapped before Down: exit 3, never answered, zero keys" has "is never answered automatically"
t "(b) zero keys" chk 'len(keys) == 0'

echo "D53 a dialog after ready is never typed into"
newrow '{"worker-1":{"late_dialog":"fullscreen-notice"}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(a) a declared late dialog is answered first: exit 0" rc_is 0
t "(a) the mission never went into a dialog" chk 'len(prompts) == 1 and all(p["into_dialog"] is None for p in prompts) and inorder(r"send-keys \S+ enter", r"^agent prompt")'
K
newrow '{"worker-1":{"late_dialog":"auto-mode-teach"}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 20
t "(b) a late never-answer dialog: exit 3, no prompt, no key" chk 'len(prompts) == 0 and len(keys) == 0'
t "(b) never answered automatically" has "is never answered automatically"

echo "D54 a half-drawn frame after Down is retried"
newrow '{"worker-1":{"gates":["trust-prompt"],"torn_reads":2}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 30
t "exit 0; one Down and one Enter" chk 'n(r"send-keys \S+ down") == 1 and n(r"send-keys \S+ enter") == 1'
t "exit 0" rc_is 0
K

echo "D55 workdir paths: symlinks, relative local workdirs"
mkdir -p "$TMP/ws"; ln -sfn "$TMP/ws" "$TMP/ws-link"
reg_file "$TMP/reg-link.yaml" "s#workdir: $TMP/ws#workdir: $TMP/ws-link#"
newrow '{"":{"agents":2,"resolve_cwd":true}}'; REGU="$TMP/reg-link.yaml" D $B1 "$CFG_ANY" reviewer --issue 139 --machine workstation
t "a local workdir with a symlink matches the resolved pane cwd" first_is "reviewer-139: workstation"
reg_file "$TMP/reg-relws.yaml" 's#workdir: .*/ws$#workdir: rel/ws#'
newrow; REGU="$TMP/reg-relws.yaml" D $B1 "$CFG_ANY" reviewer --issue 139 --machine workstation
t "a relative local workdir is refused up front" has "workdir 'rel/ws' must be an absolute path"
t "no herdr call" nocalls
newrow '{"worker-1":{"missing_cwd":true}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "the cwd failure says a remote workdir must be canonical" has "must be its canonical path"
newrow '{"worker-1":{"missing_cwd":true}}'; D $B1 "$CFG_W1" reviewer --issue 139 --keep-failed
t "(--keep-failed) exit 3 and no pane close" bash -c '[ "$1" = 3 ]' _ "$RC"
t "(--keep-failed) no pane close call" chk 'n(r"^pane close") == 0'

echo "D56 one delegate at a time per machine"
cat > "$TMP/holdlock.py" <<'PYEOF'
import sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import delegate
env = {"HOME": sys.argv[2]}
if sys.argv[3] == "refuse":
    import fcntl, os
    from pathlib import Path
    path = delegate._state_dir(env) / "worker-1" / ".lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    held = open(str(path), "a")
    fcntl.flock(held, fcntl.LOCK_EX)
    try:
        with delegate.machine_lock("worker-1", env, wait=0.5):
            print("no-refusal")
    except delegate.Refused as exc:
        print("refused:", exc.reason)
else:
    with delegate.machine_lock("worker-1", env):
        print("held", flush=True)
        time.sleep(float(sys.argv[3]))
PYEOF
newrow
OUT=$(timeout 60 "$PY" -I "$TMP/holdlock.py" "$LIB" "$TMP/home" refuse 2>&1); RC=$?; ERR=""
t "a held lock makes the second run refuse as busy after a bounded wait" has "refused: worker-1 is busy: another sdlc delegate"
newrow
( timeout 60 "$PY" -I "$TMP/holdlock.py" "$LIB" "$TMP/home" 3 >"$TMP/held.out" 2>&1 ) &
HOLD=$!
for i in $(seq 1 50); do grep -q held "$TMP/held.out" 2>/dev/null && break; sleep 0.1; done
T0=$SECONDS; D $B1 "$CFG_W1" reviewer --issue 139; T1=$SECONDS; wait $HOLD
t "a second run waits for the lock, then starts (exit 0)" rc_is 0
t "it waited" bash -c '[ $(( $2 - $1 )) -ge 2 ]' _ "$T0" "$T1"
newrow '{"worker-1":{"agents":3}}'
conc() {   # conc N : one background delegate to worker-1 for issue N
  ( cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate reviewer --issue "$1" \
      --registry "$REGF" --config "$CFG_W1" --machine worker-1 >"$TMP/c$1.out" 2>"$TMP/c$1.err"; echo $? >"$TMP/c$1.rc" ) &
}
rm -f "$TMP"/c13?.rc
conc 139; conc 138; wait
RCS="$(cat "$TMP/c139.rc" "$TMP/c138.rc" | sort | tr '\n' ' ')"
OUT="$RCS"; ERR="$(cat "$TMP/c139.err" "$TMP/c138.err")"
t "two concurrent runs for the last slot: exactly one starts, the other is refused" has "0 1 "
t "the loser says the machine is full" has "full"
t "nobody closed the winner's pane" chk 'n(r"^pane close") == 0 and n(r"^agent start") == 1'

echo "D57 finished agents count until they are stopped"
newrow '{"worker-1":{"agents":0,"done_agents":4}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "4 done agents fill a limit of 4: exit 1" rc_is 1
t "the refusal is decide()'s own, from the considered line (not the recheck's)" has "no machine can take reviewer now: worker-1: full: 4 agents, limit 4"
t "it is not the recheck's text" hasnt "is now full"
newrow '{"worker-1":{"agents":0,"done_agents":3}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "3 done agents leave a slot" first_is "reviewer-139: worker-1"

echo "D58 usage and the override line"
newrow
D $B1 "$CFG_W1" reviewer --prompt ""; t "--prompt \"\" is a usage error" rc_is 2
D $B1 "$CFG_W1" reviewer --issue 139 --machine worker-1
t "--machine equal to the repo's own placement: no overrides line" hasnt "overrides"
newrow; D $B1 "$CFG_W1" reviewer --issue 139 --machine worker-2
t "--machine different from it: overrides ... ('worker-1')" has "overrides phase_machines.reviewer ('worker-1')"

echo "D59 a second signal during cleanup still leaves no pane"
bgrun() {   # bgrun SCENARIO WAIT_REGEX 'SIG [SIG2]' [delegate args] : signal a delegate once the herdr call WAIT_REGEX was made
  local scen=$1 rx=$2 sigs=$3; shift 3
  newrow "$scen"
  ( cd "$TMP/cwd" && exec env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate reviewer --issue 139 \
      --registry "$REGF" --config "$CFG_W1" --start-timeout 60 "$@" >"$TMP/out" 2>"$TMP/err" ) &
  local pid=$! i s n=0
  for i in $(seq 1 100); do chk "n(r'$rx') >= 1" && break; sleep 0.2; done
  for s in $sigs; do sleep 1; kill -s "$s" "$pid" 2>/dev/null; done
  wait "$pid"; RC=$?
  OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
set -m
SLOWCLOSE='{"worker-1":{"agents":0,"gates":["unknown"],"slow_close":3}}'
for pair in "INT INT 130" "TERM TERM 143" "TERM INT 130" "INT TERM 143"; do
  set -- $pair
  bgrun "$SLOWCLOSE" '^agent start' "$1 $2"
  t "$1 then $2 during a slow cleanup: exit $3" rc_is "$3"
  t "$1 then $2: no pane or agent is left" chk "$NOPANES"
  t "$1 then $2: left behind: nothing (pane closed)" bash -c 'case "$1" in *"left behind: nothing (pane "*" closed)"*) ;; *) exit 1;; esac' _ "$ERR"
done
set +m

echo "D60 a status line that redraws every frame doesn't count as a changed dialog"
TICK1='{"worker-1":{"gates":["fullscreen-notice","trust-prompt"],"focus_target":true,"lag_enter_only":true,"redraw_lag":20,"ticker":true}}'
newrow "$TICK1"; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 60
t "(a) fullscreen then trust, lagging redraw plus a ticker: exit 0" rc_is 0
t "(a) one Enter per dialog, each on its target" chk 'n(r"send-keys \S+ enter") == 2 and [(k["dialog"], k["selected"]) for k in keys if k["key"] == "enter"] == [("fullscreen-notice", "Not now"), ("trust-prompt", "Yes, I trust this folder")]'
K
newrow '{"worker-1":{"gates":["trust-prompt","fullscreen-notice"],"lag_enter_only":true,"redraw_lag":20,"ticker":true}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 60
t "(b) trust then fullscreen, same: exit 0, one Enter per dialog on its target" chk 'n(r"send-keys \S+ enter") == 2 and [(k["dialog"], k["selected"]) for k in keys if k["key"] == "enter"] == [("trust-prompt", "Yes, I trust this folder"), ("fullscreen-notice", "Not now")]'
t "(b) exit 0" rc_is 0
K
newrow '{"worker-1":{"gates":["fullscreen-notice"],"focus_target":true,"prompt_error_once":"agent_blocked","prompt_gate":"fullscreen-notice"}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 30
t "(c) the remembered Enter is forgotten once the dialog is gone: a dialog that comes back the same is answered (exit 0, two Enters)" chk 'n(r"send-keys \S+ enter") == 2'
t "(c) exit 0" rc_is 0

echo "D61 which brief failures leave the pane"
newrow '{"worker-1":{"fail_visible_read_n":2}}'; D $B1 "$CFG_W1" reviewer --issue 139
t "(a) the late screen read fails before agent prompt: exit 3, no agent prompt call" bash -c '[ "$1" = 3 ]' _ "$RC"
t "(a) the pane is closed and there is no record" chk 'n(r"^agent prompt") == 0 and n(r"^pane close") == 1'
t "(a) no record file" bash -c '! find "$1" -name "*.json" 2>/dev/null | grep -q .' _ "$TMP/home/.local/state/sdlc"
set -m
bgrun '{"worker-1":{"agents":0,"prompt_hang":20}}' '^agent prompt' 'INT'
t "(b) Ctrl-C during agent prompt --wait: exit 130" rc_is 130
t "(b) the pane is still there" chk 'json.load(open(d + "/state.json"))["worker-1"]["panes"] != [] and n(r"^pane close") == 0'
t "(b) left behind: pane, with the stop line" bash -c 'case "$1" in *"left behind: pane "*"stop:"*"pane close"*) ;; *) exit 1;; esac' _ "$ERR"
t "(b) the record file stays" test -f "$TMP/home/.local/state/sdlc/delegates/worker-1/reviewer-139.json"
set +m

echo "D62 an interrupt in the middle of a create call closes the pane the server made"
set -m
bgrun '{"worker-1":{"agents":0,"slow_create":4}}' '^workspace create' 'INT'
t "(a) Ctrl-C during workspace create: exit 130" rc_is 130
t "(a) no pane, agent or workspace is left" chk "$NOPANES"
t "(a) left behind: nothing (pane closed)" bash -c 'case "$1" in *"left behind: nothing (pane "*" closed)"*) ;; *) exit 1;; esac' _ "$ERR"
WSX='{"worker-1":{"agents":0,"slow_create":4,"workspaces":[{"label":"sdlc-delegate","tabs":[{"label":"sdlc:old","panes":[{"cwd":"/elsewhere","fg":"bash"}]}]}]}}'
bgrun "$WSX" '^tab create' 'INT'
t "(b) Ctrl-C during tab create: exit 130" rc_is 130
t "(b) only the pre-existing pane is left" chk '[p["pane_id"] for p in json.load(open(d + "/state.json"))["worker-1"]["panes"]] == ["w1:p11"]'
set +m

echo "D63 a background job's ignored SIGINT stays ignored"
newrow '{"worker-1":{"agents":0,"gates":["unknown"]}}'
cd "$TMP/cwd"      # a plain `cmd &` (not a subshell) is what leaves SIGINT ignored without job control
env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate reviewer --issue 139 \
    --registry "$REGF" --config "$CFG_W1" --start-timeout 20 >"$TMP/out" 2>"$TMP/err" &
BGP=$!
cd "$HERE"
for i in $(seq 1 100); do chk 'n(r"^agent start") >= 1' && break; sleep 0.2; done
sleep 1; kill -s INT $BGP; sleep 1
t "SIGINT sent to a background delegate is ignored (it is still running)" kill -0 $BGP
kill -s TERM $BGP; wait $BGP; RC=$?
t "it still stops on SIGTERM: exit 143" rc_is 143

echo "D64 the lock covers recheck, agent start and a provisional record, and falls back to another machine"
cat > "$TMP/fallback.py" <<'PYEOF'
import fcntl, os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import delegate
env = {"HERDR_ENV": "1", "HOME": sys.argv[2]}
d = delegate.decide("reviewer", issue=139, registry_file=sys.argv[3], config_file=sys.argv[4], env=env)
best = d.machine.name
alt = [a.machine.name for a in d.alternates]


def hold(name):
    path = delegate._state_dir(env) / name / ".lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(str(path), "a")
    fcntl.flock(handle, fcntl.LOCK_EX)
    return handle


h1 = hold(best)
s = delegate.start(d, lock_wait=0.5, env=env)
print("fell back:", best, "->", s.decision.machine.name, "|", ";".join(s.warnings))
h2 = [hold(n) for n in alt]
try:
    delegate.start(d, lock_wait=0.5, env=env)
    print("no refusal")
except delegate.Refused as exc:
    print("refused:", exc.reason)
PYEOF
newrow
OUT=$(cd "$TMP/cwd" && timeout 120 env PATH="$TMP/pybin" "$PY" -I "$TMP/fallback.py" "$LIB" "$TMP/home" "$REGF" "$CFG_ANY" 2>&1); RC=$?; ERR=""
t "a held lock on the best machine: the next fitting machine is used, and the skip is reported" has "fell back: worker-2 -> workstation | tried worker-2: worker-2 is busy"
t "every candidate locked: refused as no machine can take it" has "refused: no machine can take reviewer now: worker-2: worker-2 is busy"

echo "D65 browser jobs: provisional records count, stale ones don't"
BJREG="$TMP/reg-bj.yaml"; reg_file "$BJREG" '0,/browser_jobs: 2/s//browser_jobs: 1/'
newrow '{"worker-1":{"agents":0}}'
conc2() {   # conc2 N : a background browser-job delegate to worker-1 for issue N
  ( cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate validator --issue "$1" \
      --registry "$BJREG" --config "$BROWSER_CFG" --machine worker-1 >"$TMP/c$1.out" 2>"$TMP/c$1.err"; echo $? >"$TMP/c$1.rc" ) &
}
rm -f "$TMP"/c21.rc "$TMP"/c22.rc
conc2 21; conc2 22; wait
OUT="$(cat "$TMP/c21.rc" "$TMP/c22.rc" | sort | tr '\n' ' ')"; ERR="$(cat "$TMP/c21.err" "$TMP/c22.err")"
t "browser_jobs: 1 and two concurrent browser jobs: exactly one starts" has "0 1 "
t "the loser says the browser jobs are full" has "browser job"
t "two agents were not started" chk 'n(r"^agent start") == 1'
# a provisional record whose process is dead doesn't count; a live one does
DEADPID="$(sh -c 'echo $$')"
mkrec() {   # mkrec NAME PANE STATUS PID : a browser-job record for worker-1 (limit 2 below)
  mkdir -p "$STATE/worker-1"
  printf '{"name":"%s","pane_id":"%s","browser_job":true,"status":"%s","pid":%s,"started_at":"%s"}\n' "$1" "$2" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/worker-1/$1.json"
}
newrow '{"worker-1":{"agents":3}}'
mkrec busy1 w9:p1 working $$; mkrec busy2 w9:p2 starting "$DEADPID"
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1
t "a stale provisional record (dead process) isn't counted: 1 of 2 browser jobs, exit 0" first_is "validator-1: worker-1"
newrow '{"worker-1":{"agents":3}}'
mkrec busy1 w9:p1 working $$; mkrec busy2 w9:p2 starting $$
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1
t "a live provisional record counts: 2 of 2, exit 1" has "full: 2 browser jobs, limit 2"

echo "D66 an unwritable state directory only loses the record"
: > "$TMP/notadir"; mkdir -p "$TMP/run"
newrow; XENV=(XDG_STATE_HOME="$TMP/notadir" XDG_RUNTIME_DIR="$TMP/run"); D $B1 "$CFG_W1" reviewer --issue 139
t "exit 0: the start isn't refused" rc_is 0
t "it warns that no record will be written" has "no record will be written"
t "the lock lives under the runtime directory" test -f "$TMP/run/sdlc-delegate/worker-1.lock"

echo "D67 answer counts are kept across the brief retry"
newrow '{"worker-1":{"gates":["fullscreen-notice","fullscreen-notice"],"prompt_error_once":"agent_blocked","prompt_gate":"fullscreen-notice"}}'; D $B1 "$CFG_W1" reviewer --issue 139 --start-timeout 30
t "the dialog was answered twice, then shown a third time: still showing after 2 answers, exit 3" has "fullscreen-notice still showing after 2 answers"
t "exit 3" rc_is 3
t "only two Enters were sent" chk 'n(r"send-keys \S+ enter") == 2'

echo "D68 the fallback lock directory must be ours, a real directory, and private"
: > "$TMP/notadir"; rm -rf "$TMP/run" "$TMP/other"; mkdir -p "$TMP/run" "$TMP/other"
lockrow() {   # lockrow LABEL : a delegate whose records directory is unwritable, so the lock goes under $TMP/run
  newrow; XENV=(XDG_STATE_HOME="$TMP/notadir" XDG_RUNTIME_DIR="$TMP/run"); D $B1 "$CFG_W1" reviewer --issue 139
}
mkdir -p "$TMP/run/sdlc-delegate"; chmod 0777 "$TMP/run/sdlc-delegate"
lockrow
t "(a) a pre-created directory writable by others: exit 3, not safe" rc_is 3
t "(a) the refusal says why" has "is not safe to use"
t "(a) nothing was started" chk 'not mut()'
chmod 0750 "$TMP/run/sdlc-delegate"; lockrow
t "(b) a group-writable-or-not mode 0750 directory is fine" rc_is 0
chmod 0770 "$TMP/run/sdlc-delegate"; lockrow
t "(c) mode 0770 (group writable): exit 3" rc_is 3
rm -rf "$TMP/run/sdlc-delegate"; ln -s "$TMP/other" "$TMP/run/sdlc-delegate"; lockrow
t "(d) a symlink to a directory: exit 3, not safe" rc_is 3
t "(d) nothing was written through the link" bash -c '[ -z "$(ls -A "$1")" ]' _ "$TMP/other"
rm -f "$TMP/run/sdlc-delegate"
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$TMP/run/sdlc-delegate"; chmod 0700 "$TMP/run/sdlc-delegate"; chown 65534 "$TMP/run/sdlc-delegate"; lockrow
  t "(e) a directory owned by another user: exit 3" rc_is 3
  rm -rf "$TMP/run/sdlc-delegate"
fi
mkdir -p "$TMP/run/sdlc-delegate"; chmod 0700 "$TMP/run/sdlc-delegate"; lockrow
t "(f) our own 0700 directory is used: exit 0" rc_is 0
rm -rf "$TMP/run"

echo "D69 a failure in the locked phase is cleaned up before the lock is released"
stag() {   # stag SCENARIO GAP ARGS_A ARGS_B : A, then B GAP seconds later; rc and output in $TMP/s{a,b}.*
  local scen=$1 gap=$2 argsa=$3 argsb=$4
  newrow "$scen"; rm -f "$TMP"/sa.* "$TMP"/sb.*
  ( cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate ${ROLE_A:-reviewer} $argsa \
      --registry "${STAGREG:-$REGF}" --config "${STAGCFG:-$CFG_W1}" --start-timeout 60 >"$TMP/sa.out" 2>"$TMP/sa.err"; echo $? >"$TMP/sa.rc" ) &
  local pa=$!
  if [ -n "${WAITRX:-}" ]; then
    local i; for i in $(seq 1 100); do chk "n(r'$WAITRX') >= 1" && break; sleep 0.2; done
  fi
  sleep "$gap"
  ( cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate ${ROLE_B:-reviewer} $argsb \
      --registry "${STAGREG:-$REGF}" --config "${STAGCFG:-$CFG_W1}" --start-timeout 60 >"$TMP/sb.out" 2>"$TMP/sb.err"; echo $? >"$TMP/sb.rc" ) &
  wait
  RCA=$(cat "$TMP/sa.rc"); RCB=$(cat "$TMP/sb.rc")
  OUT="$(cat "$TMP/sb.out")"; ERR="$(cat "$TMP/sb.err")"
}
WAITRX='^agent start' stag '{"worker-1":{"agents":0,"start_error_once":"internal_error","slow_start":3,"slow_close":3}}' 1 "--issue 21" "--issue 22"
t "A's start fails (exit 3) and B, waiting on the lock, starts (exit 0)" bash -c '[ "$1" = 3 ] && [ "$2" = 0 ]' _ "$RCA" "$RCB"
t "B did not get A's pane: A's pane is the only one closed, and B's agent is alive" chk '(lambda starts, closes: len(closes) == 1 and closes[0] == starts[0]["argv"][starts[0]["argv"].index("--pane") + 1] and len(starts) == 2 and starts[1]["argv"][starts[1]["argv"].index("--pane") + 1] != closes[0] and len(json.load(open(d + "/state.json"))["worker-1"]["agents"]) == 1)([c for c in calls if c["j"].startswith("agent start")], [c["argv"][2] for c in calls if c["j"].startswith("pane close")])'

echo "D70 the provisional record reserves the slot and the name while the agent is still unnamed"
SLOWUN='{"worker-1":{"agents":0,"gates":["trust-prompt"],"unnamed_after_gate":true,"lag_enter_only":true,"redraw_lag":14}}'
BJREG2="$TMP/reg-bj2.yaml"; reg_file "$BJREG2" '0,/browser_jobs: 2/s//browser_jobs: 1/'
STAGREG="$BJREG2" STAGCFG="$BROWSER_CFG" ROLE_A=validator ROLE_B=validator WAITRX='^agent start' stag "$SLOWUN" 1 "--issue 31 --machine worker-1" "--issue 32 --machine worker-1"
t "(a) browser_jobs: 1, the first agent still unnamed: the first starts, the second is refused" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$RCA" "$RCB"
t "(a) the refusal is about browser jobs" has "browser job"
t "(a) only one agent was started" chk 'n(r"^agent start") == 1'
STAGREG="$REGF" STAGCFG="$CFG_W1" ROLE_A=reviewer ROLE_B=reviewer WAITRX='^agent start' stag "$SLOWUN" 1 "--issue 139" "--issue 139"
t "(b) two runs with the same default name: the second takes -2" bash -c 'printf "%s\n" "$1" | head -1 | grep -q "^reviewer-139-2: worker-1"' _ "$OUT"
t "(b) both started" bash -c '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$RCA" "$RCB"

echo "D71 the writer's deadline decides staleness, not the reader's --start-timeout"
mkrec2() {   # mkrec2 NAME PANE PID STARTED_AGO_S DEADLINE_IN_S : a live-looking provisional browser-job record
  mkdir -p "$STATE/worker-1"
  printf '{"name":"%s","pane_id":"%s","browser_job":true,"status":"starting","pid":%s,"started_at":"%s","deadline":%s}\n' \
    "$1" "$2" "$3" "$(date -u -d "-$4 seconds" +%Y-%m-%dT%H:%M:%SZ)" "$(( $(date +%s) + $5 ))" > "$STATE/worker-1/$1.json"
}
newrow '{"worker-1":{"agents":3}}'; mkrec busy1 w9:p1 working $$; mkrec2 busy2 w9:p2 $$ 100 300
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1 --start-timeout 10
t "a reader with a short --start-timeout still counts a writer whose deadline is ahead: 2 of 2, exit 1" has "full: 2 browser jobs, limit 2"
newrow '{"worker-1":{"agents":3}}'; mkrec busy1 w9:p1 working $$; mkrec2 busy2 w9:p2 $$ 100 -10
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1 --start-timeout 250
t "a writer past its own deadline isn't counted, whatever the reader's timeout: exit 0" first_is "validator-1: worker-1"

echo "D72 a failed run doesn't delete another job's record"
newrow '{"worker-1":{"missing_cwd":true}}'
mkdir -p "$STATE/worker-1"; printf '{"name":"reviewer-139","pane_id":"w9:p9","status":"working","briefed":true}\n' > "$STATE/worker-1/reviewer-139.json"
D $B1 "$CFG_W1" reviewer --issue 139
t "the run fails at the cwd check (exit 3)" rc_is 3
t "an earlier finished job's record with the same name survives" test -f "$STATE/worker-1/reviewer-139.json"

echo "D73 only the provisional record can make a slow first start count as load"
newrow '{"worker-1":{"agents":0,"gates":["trust-prompt"],"lag_enter_only":true,"redraw_lag":14}}'
( cd "$TMP/cwd" && timeout 120 env -u HERDR_ENV PATH="$TMP/pybin" HERDR_ENV=1 "$PY" "$SDLC" delegate validator --issue 41 \
    --registry "$BJREG2" --config "$BROWSER_CFG" --machine worker-1 --start-timeout 60 >"$TMP/p41.out" 2>"$TMP/p41.err"; echo $? >"$TMP/p41.rc" ) &
for i in $(seq 1 100); do chk 'n(r"^agent start") >= 1' && break; sleep 0.2; done
sleep 1.5
REGU="$BJREG2" D $B1 "$BROWSER_CFG" validator --issue 42 --machine worker-1
wait
t "the second browser job is refused while the first is still in its first start" has "browser job"
t "exit 1" rc_is 1

echo "D74 no records means no heavy work"
newrow; XENV=(XDG_STATE_HOME="$TMP/notadir" XDG_RUNTIME_DIR="$TMP/run"); mkdir -p "$TMP/run"
D $B1 "$BROWSER_CFG" validator --issue 1 --machine worker-1
t "a browser role is refused when only the fallback lock is available" has "no records can be kept"
t "exit 1 and nothing was started" bash -c '[ "$1" = 1 ]' _ "$RC"
t "no pane was made" chk 'not mut()'
rm -rf "$TMP/run"

echo "D75 an interrupted workspace create closes only the workspace with this run's label"
set -m
bgrun '{"worker-1":{"agents":0,"slow_create":4,"concurrent_workspace":true}}' '^workspace create' 'INT'
t "Ctrl-C during workspace create: exit 130" rc_is 130
t "the other coordinator's sdlc-delegate workspace and its pane survive" chk '[(w["label"], [p["pane_id"] for p in json.load(open(d + "/state.json"))["worker-1"]["panes"]]) for w in json.load(open(d + "/state.json"))["worker-1"]["workspaces"]] == [("sdlc-delegate", ["w%d:p%d" % (101, 101)])]'
t "only our own workspace was closed" chk 'n(r"^pane close") == 1'
set +m

echo "D46 plugin/bin/sdlc is executable; the fake herdr is executable"
t "sdlc is executable" test -x "$SDLC"
t "fake-herdr.py is executable" test -x "$FAKE"

echo
echo "delegate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
