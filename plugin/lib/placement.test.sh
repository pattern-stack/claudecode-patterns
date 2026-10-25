#!/usr/bin/env bash
# Tests for placement: the sdlc.yml keys and resolver in plugin/lib/machines.py, plus
# `sdlc machines where` and the repo pass of `sdlc machines check` in plugin/bin/sdlc.
# Plain bash + python3. Part A needs no YAML backend; Part B uses PyYAML and/or yq.
# Run: bash plugin/lib/placement.test.sh   (exits 0 only when every case that ran passed;
#      SDLC_REQUIRE_BOTH_BACKENDS=1 makes a missing backend a failure, as CI does)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE"
ROOT="$(cd "$HERE/.." && pwd)"
SDLC="$ROOT/bin/sdlc"
EXAMPLE="$ROOT/machines.example.yaml"
SDLC_EXAMPLE="$ROOT/sdlc.example.yml"
HOOK="$ROOT/hooks/phase-tuning.sh"
PY="$(command -v python3)"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Never read the real user's registry or the repo this suite runs in.
export HOME="$TMP/home"
mkdir -p "$HOME"
unset SDLC_MACHINES XDG_CONFIG_HOME CLAUDE_PROJECT_DIR
export PYTHONDONTWRITEBYTECODE=1
FX="$TMP/fx"; mkdir -p "$FX"
mkdir -p "$TMP/cwd"; cd "$TMP/cwd" || exit 1     # no .claude/sdlc.yml above here

# ── backends ────────────────────────────────────────────────────────────────
HAVE_PYYAML=0; HAVE_YQ=0
"$PY" -c 'import yaml' 2>/dev/null && HAVE_PYYAML=1
command -v yq >/dev/null 2>&1 && HAVE_YQ=1
REAL_YQ="$(command -v yq || true)"
SLEEP="$(command -v sleep)"
mkdir -p "$TMP/noyaml/yaml"; echo 'raise ImportError("hidden for the test")' > "$TMP/noyaml/yaml/__init__.py"
mkdir -p "$TMP/pyyq"
ln -s "$PY" "$TMP/pyyq/python3"
[ "$HAVE_YQ" = 1 ] && ln -s "$REAL_YQ" "$TMP/pyyq/yq"

if [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ]; then
  [ "$HAVE_PYYAML" = 1 ] && ok "required backend present: PyYAML" || bad "required backend missing: PyYAML"
  [ "$HAVE_YQ" = 1 ] && ok "required backend present: yq" || bad "required backend missing: yq"
fi
BACKENDS=()
[ "$HAVE_PYYAML" = 1 ] && BACKENDS+=(py)
[ "$HAVE_YQ" = 1 ] && BACKENDS+=(yq)

# ── Part A: the table (no YAML backend) ─────────────────────────────────────
echo "A  the resolver table"
cat > "$TMP/parta.py" <<'PY'
import sys
sys.dont_write_bytecode = True
import machines as M
from pathlib import Path

WS = {"transport": "local", "caps": ["edit", "test", "browser"], "keeps": ["checkouts", "services"], "secrets": "dev"}
W1 = {"transport": {"herdr": "worker-1"}, "workdir": "/w", "caps": ["edit", "test", "browser", "docker", "full-suite"], "secrets": "none"}
VAULT = {"transport": {"herdr": "vault"}, "workdir": "/w", "caps": ["edit"], "secrets": "prod"}
CONTROL = {"assignable": False}
BROKEN = {"transport": {"herdr": "broken"}, "workdir": "/w", "limits": {"cores": 0}}


def registry(doc):
    machines, issues = M.validate(doc)
    return M.Registry(Path("/fx/machines.yaml"), "flag", True, machines, issues)


REGS = {
    "REG": registry({"machines": {"workstation": WS, "worker-1": W1, "vault": VAULT, "control": CONTROL, "broken": BROKEN}}),
    "REG_WF": registry({"machines": {"worker-1": W1, "workstation": WS, "vault": VAULT, "control": CONTROL, "broken": BROKEN}}),
    "REG_LOCKED": registry({"machines": {"workstation": dict(WS, assignable=False), "worker-1": W1, "vault": VAULT,
                                         "control": CONTROL, "broken": BROKEN}}),
    "INERT": M.Registry(Path("/nope/machines.yaml"), "default", False, {}, []),
    "TWO_LOCAL": registry({"machines": {"a": {"transport": "local"}, "b": {"transport": "local"}}}),
}


def with_opt(cfg):
    cfg = dict(cfg)
    pm = cfg.get("phase_machines")
    pm = dict(pm) if isinstance(pm, dict) else {}
    pm.setdefault("implementer", "local")
    cfg["phase_machines"] = pm
    return cfg


def repeated(*pairs):
    return M._pairs_to_map(list(pairs))


ROWS = []


def row(name, cfg, role, kind=None, reg="REG", opt=False, **expect):
    ROWS.append((name, with_opt(cfg) if opt else cfg, role, kind, reg, expect))


def errors_of(cfg):
    return [i for i in cfg.issues if i.level == "error"]


def warnings_of(cfg):
    return [i for i in cfg.issues if i.level == "warning"]


# A1-A45 ---------------------------------------------------------------------
row("A1 unassignable refused", {"phase_machines": {"validator": "control"}}, "validator",
    status="fallback", machine="workstation", local=True, has=["is not assignable", "using"])
row("A2 not-ok refused", {"phase_machines": {"validator": "broken"}}, "validator", status="fallback",
    fn=lambda p, c, r: "has registry errors in: " + ", ".join(sorted(r.machines["broken"].invalid)) in p.reason)
row("A3 caps mismatch", {"phase_machines": {"validator": "workstation"}, "needs": {"validator": ["full-suite"]},
                         "default_machine": "worker-1"}, "validator",
    status="fallback", machine="worker-1", has=["lacks caps: full-suite"])
row("A4 keeps mismatch", {"phase_machines": {"implementer": "worker-1"}, "needs": {"implementer": {"keeps": ["checkouts"]}}},
    "implementer", status="fallback", machine="workstation", has=["lacks keeps: checkouts"])
row("A5 secrets mismatch", {"phase_machines": {"implementer": "worker-1"}, "needs": {"implementer": {"secrets": "dev"}}},
    "implementer", status="fallback", machine="workstation", has=["holds secrets 'none', needs 'dev'"])
row("A6 secrets is a floor", {"phase_machines": {"implementer": "vault"}, "needs": {"implementer": {"secrets": "dev"}}},
    "implementer", status="placed", machine="vault")
row("A7 any, no needs", {"phase_machines": {"reviewer": "any"}}, "reviewer", status="placed", machine="workstation",
    local=True, cands=("workstation", "worker-1", "vault"), rej=["control", "broken"])
row("A8 any with needs", {"phase_machines": {"reviewer": "any"}, "needs": {"reviewer": ["full-suite"]}}, "reviewer",
    status="placed", machine="worker-1", local=False, cands=("worker-1",))
row("A9 any with secrets prod", {"phase_machines": {"reviewer": "any"}, "needs": {"reviewer": {"secrets": "prod"}}},
    "reviewer", status="placed", cands=("vault",))
row("A10 any, nothing fits", {"phase_machines": {"reviewer": "any"}, "needs": {"reviewer": ["gpu"]}}, "reviewer",
    status="unplaceable", machine=None, has=["no machine fits", "has nowhere to run"])
row("A11 any is local first", {"phase_machines": {"reviewer": "any"}}, "reviewer", reg="REG_WF",
    fn=lambda p, c, r: p.candidates[0] == "workstation")
row("A12 unknown machine", {"phase_machines": {"validator": "worker-9"}}, "validator", status="fallback",
    machine="workstation", has=["'worker-9' is not in the registry", "did you mean 'worker-1'"], rej_has=["worker-9"])
row("A13 no registry", {"phase_machines": {"validator": "control"}}, "validator", reg="INERT", status="off",
    cause="no-registry", machine=None, local=True, has=["no machine registry"])
row("A14 broken registry", {"phase_machines": {"validator": "control"}}, "validator", reg="TWO_LOCAL", status="off",
    cause="registry-errors", has=["the registry has errors"])
row("A15 broken config", {"phase_machines": ["validator"]}, "validator", status="off", cause="sdlc-errors",
    has=["sdlc.yml has errors"])
row("A16 grouped beats flat",
    {"phases": {"validator": {"model": "fable", "machine": "worker-1"}}, "phase_machines": {"validator": "workstation"}},
    "validator", status="placed", machine="worker-1", at="phases.validator.machine", nwarn=1)
row("A17 grouped null -> flat", {"phases": {"validator": {"machine": None}}, "phase_machines": {"validator": "worker-1"}},
    "validator", machine="worker-1", at="phase_machines.validator")
row("A17b grouped blank -> flat", {"phases": {"validator": {"machine": "  "}}, "phase_machines": {"validator": "worker-1"}},
    "validator", machine="worker-1", at="phase_machines.validator", nissues=0)
row("A18 invalid grouped still wins", {"phases": {"validator": {"machine": 3}}, "phase_machines": {"validator": "worker-1"}},
    "validator", status="fallback", machine="workstation")
row("A19 default used", {"default_machine": "worker-1"}, "tour", status="placed", machine="worker-1", local=False,
    req_none=True, kind_is=None)
row("A20 no default", {}, "tour", opt=True, status="placed", machine="workstation", local=True)
row("A21 unknown default -> local", {"default_machine": "worker-9"}, "tour", status="placed", machine="workstation",
    has=["default_machine 'worker-9' is not usable"])
row("A22 unassignable default -> local", {"default_machine": "control"}, "tour", status="placed", machine="workstation",
    has=["default_machine 'control' is not usable"])
row("A23 needs invalid", {"needs": {"validator": {"secrets": "staging"}}}, "validator", opt=True, status="unplaceable",
    has=["needs.validator has errors in: secrets"])
row("A24 needs unknown key", {"needs": {"validator": {"cap": ["browser"]}}}, "validator", opt=True, status="unplaceable",
    fn=lambda p, c, r: "cap" in c.needs["validator"].invalid)
row("A25 bare list = caps", {"needs": {"validator": ["full-suite", "browser"]}}, "validator", opt=True,
    fn=lambda p, c, r: c.needs["validator"].caps == ("full-suite", "browser"))
row("A26 kind auto -> agent", {"agent_machines": {"browser-pilot": "worker-1"}}, "browser-pilot", kind_is="agent",
    machine="worker-1")
row("A27 explicit kind", {"phase_machines": {"validator": "worker-1"}}, "validator", kind="agent", status="placed",
    machine="workstation", req_none=True)
row("A28 namespace stripped", {"phase_machines": {"validator": "worker-1"}}, "sdlc:validator",
    fn=lambda p, c, r: (p.role, p.status, p.machine) == ("validator", "placed", "worker-1")
    and M.resolve("validator", registry=r, config=c) == p)
row("A29 local keyword", {"phase_machines": {"implementer": "local"}}, "implementer", status="placed",
    machine="workstation", local=True)
row("A30 auto refused", {"phase_machines": {"validator": "auto"}}, "validator", status="fallback", has=["any"])
row("A31 both targets unfit", {"phase_machines": {"validator": "worker-1"}, "needs": {"validator": {"keeps": ["datasets"]}}},
    "validator", status="unplaceable", has=["worker-1", "workstation"])
row("A32 role in both maps", {"phase_machines": {"x": "worker-1"}, "agent_machines": {"x": "workstation"}}, "x",
    kind_is="phase", machine="worker-1",
    fn=lambda p, c, r: [role for role, _k in c.roles()] == ["x"])
row("A33 local unassignable", {}, "tour", reg="REG_LOCKED", opt=True, status="unplaceable")
row("A34 never raises", {}, "x", opt=True,
    fn=lambda p, c, r: all(isinstance(M.resolve(t, registry=r, config=c), M.Placement) for t in ("", "a:b:c", "sdlc:", " ")))
row("A36a blank needs role", {"needs": {"validator": None}}, "validator", opt=True, status="unplaceable",
    fn=lambda p, c, r: "entry" in c.needs["validator"].invalid)
row("A36b blank needs key", {"needs": {"validator": {"secrets": None}}}, "validator", opt=True, status="unplaceable",
    fn=lambda p, c, r: "secrets" in c.needs["validator"].invalid)
row("A37 case-folded did-you-mean", {"needs": {"validator": {"Caps": ["browser"]}}}, "validator", opt=True,
    fn=lambda p, c, r: any(i.where == "sdlc.yml.needs.validator.Caps" and "'caps'" in i.message for i in c.issues))
row("A38 blank target is not a bypass",
    {"phase_machines": {"validator": None}, "default_machine": "local", "needs": {"validator": ["full-suite"]}},
    "validator", status="unplaceable", has=["lacks caps: full-suite"])
row("A39 bad default -> local still filtered",
    {"default_machine": "worker-9", "phase_machines": {"validator": "worker-1"},
     "needs": {"validator": {"keeps": ["datasets"]}}},
    "validator", status="unplaceable", rej=["worker-1", "workstation"],
    fn=lambda p, c, r: "worker-9" not in p.reason)      # the unplaceable reason names refusals only; `check` reports the default
row("A40 unassignable default never tried", {"default_machine": "control", "needs": {"tour": ["full-suite"]}}, "tour",
    status="unplaceable", rej=["workstation"], rej_not=["control"])
row("A41 local tried once", {"phase_machines": {"validator": "local"}, "needs": {"validator": ["full-suite"]}}, "validator",
    status="unplaceable", rej=["workstation"])
row("A42 default any, nothing fits", {"default_machine": "any", "needs": {"validator": {"keeps": ["datasets"]}}}, "validator",
    status="unplaceable", has=["no machine fits"])
row("A43 prefixed role key", {"phase_machines": {"validator": "worker-1"},
                              "needs": {"sdlc:validator": {"keeps": ["datasets"]}}}, "validator",
    status="unplaceable",
    fn=lambda p, c, r: any(i.level == "warning" and i.where == "sdlc.yml.needs.sdlc:validator" for i in c.issues))
row("A44 not opted in", {}, "tour", reg="REG_LOCKED", status="off", cause="no-placement", local=True)
row("A45 needs alone does not opt in", {"needs": {"validator": ["gpu"]}}, "validator", status="off", cause="no-placement")

# unfit_reason order (A35) and the reader's repeat handling ---------------------
m35, _ = M.validate({"machines": {"here": {"transport": "local"},
                                  "b": {"transport": {"herdr": "b"}, "workdir": "/w", "assignable": "no"}}})
row("A35 unfit_reason: errors before assignable", {}, "x", opt=True,
    fn=lambda p, c, r: ("has registry errors in:" in M.unfit_reason(m35["b"], M.Needs())
                        and "assignable" in M.unfit_reason(m35["b"], M.Needs())
                        and "is not assignable" not in M.unfit_reason(m35["b"], M.Needs())))

row("R1 repeated top-level needs: recorded though nothing is placed",
    repeated(("needs", {"validator": ["a"]}), ("needs", {"validator": ["b"]})), "validator",
    status="off", cause="no-placement",
    fn=lambda p, c, r: c.needs_broken and c.usable and not c.opted_in and not errors_of(c))
row("R2 malformed top-level needs: recorded though nothing is placed", {"needs": "browser"}, "validator",
    status="off", cause="no-placement", fn=lambda p, c, r: c.needs_broken and c.usable and not errors_of(c))
row("R3 a bad needs role is recorded though nothing is placed", {"needs": {"validator": {"cap": ["x"]}}}, "validator",
    status="off", cause="no-placement",
    fn=lambda p, c, r: c.needs["validator"].invalid == frozenset({"cap"}) and not c.needs_broken and not errors_of(c))
row("R4 a repeated needs role is recorded though nothing is placed",
    {"needs": repeated(("validator", ["a"]), ("validator", ["b"]))}, "validator", status="off", cause="no-placement",
    fn=lambda p, c, r: "entry" in c.needs["validator"].invalid and not errors_of(c))
row("R5 repeated top-level needs when opted in: broken and flagged",
    repeated(("needs", {"validator": ["a"]}), ("needs", {"validator": ["b"]}), ("phase_machines", {"validator": "worker-1"})),
    "validator", status="off", cause="sdlc-errors",
    fn=lambda p, c, r: c.needs_broken and c.broken and any(i.where == "sdlc.yml.needs" for i in errors_of(c)))
row("R6 well-formed needs: not flagged", {"needs": {"validator": ["gpu"]}}, "validator", fn=lambda p, c, r: not c.needs_broken)
row("R7 repeated tuning-only phases.<role> overrides a flat target and falls back",
    {"phase_machines": {"validator": "worker-1"},
     "phases": repeated(("validator", {"model": "opus"}), ("validator", {"effort": "high"}))},
    "validator", status="fallback", machine="workstation",
    fn=lambda p, c, r: p.requested.error is not None
    and any(i.where == "sdlc.yml.phases.validator" for i in errors_of(c)))
row("R8 a repeated top-level phases hides a machine: nothing else is placed, so it is off",
    repeated(("phases", {"validator": {"machine": "worker-1"}}), ("phases", {"validator": {"model": "opus"}})),
    "validator", status="off", cause="no-placement")

# placement_issues rows ---------------------------------------------------------
IROWS = []


def irow(name, cfg, errors=(), warnings=(), reg="REG", opt=True, check=None):
    IROWS.append((name, with_opt(cfg) if opt else cfg, reg, sorted(errors), sorted(warnings), check))


def sw(*parts):
    return ".".join(("sdlc.yml",) + parts)


for target in ("worker-9", "control", "broken"):
    irow("I1 %s refused: one error" % target, {"phase_machines": {"validator": target}}, [sw("phase_machines", "validator")])
irow("I2 auto: one error", {"phase_machines": {"validator": "auto"}}, [sw("phase_machines", "validator")])
irow("I3 grouped machine [a]: one error, outcome is info", {"phases": {"validator": {"machine": ["a"]}}},
     [sw("phases", "validator", "machine")])
irow("I4 needs secrets staging: one error", {"phase_machines": {"validator": "worker-1"},
                                            "needs": {"validator": {"secrets": "staging"}}},
     [sw("needs", "validator", "secrets")])
irow("I5 needs cap: one error", {"needs": {"validator": {"cap": ["x"]}}}, [sw("needs", "validator", "cap")])
irow("I6 needs a string: one error", {"needs": {"validator": "browser"}}, [sw("needs", "validator")])
irow("I7 needs null: one error", {"needs": {"validator": None}}, [sw("needs", "validator")])
for default in ("worker-9", "control", 3):
    irow("I8 default_machine %r: one error" % (default,), {"default_machine": default}, [sw("default_machine")])
irow("I9 role in both maps: one error", {"phase_machines": {"x": "worker-1"}, "agent_machines": {"x": "workstation"}},
     [sw("agent_machines", "x")])
irow("I10 grouped over flat: one warning", {"phases": {"validator": {"machine": "worker-1"}},
                                           "phase_machines": {"validator": "workstation"}},
     [], [sw("phase_machines", "validator")])
irow("I11 prefixed needs key: a warning, and the needs bind", {"phase_machines": {"validator": "worker-1"},
                                                              "needs": {"sdlc:validator": {"keeps": ["datasets"]}}},
     [sw("phase_machines", "validator")], [sw("needs", "sdlc:validator")])
irow("I12 local unassignable: default and implementer", {}, [sw("default_machine"), sw("phase_machines", "implementer")],
     reg="REG_LOCKED")
irow("I13 local unassignable, not opted in: nothing", {}, [], reg="REG_LOCKED", opt=False,
     check=lambda iss: iss == [])
irow("I14 needs alone: one warning", {"needs": {"validator": ["gpu"]}}, [], [sw("needs")], opt=False)
irow("I15 needs malformed alone: one warning, no errors",
     {"needs": {"validator": {"cap": ["x"]}, "sdlc:tour": None}}, [], [sw("needs")], opt=False)
irow("I16 default_machine: local on an unassignable local box", {"default_machine": "local"}, [sw("default_machine")],
     reg="REG_LOCKED", opt=False,
     check=lambda iss: any("default_machine 'local'" in i.message and "not assignable" in i.message for i in iss))
irow("I17 unknown default on an unassignable local box: one combined error", {"default_machine": "worker-9"},
     [sw("default_machine")], reg="REG_LOCKED", opt=False,
     check=lambda iss: any("worker-9" in i.message and "nowhere to run" in i.message for i in iss))
irow("I18 placed roles are info lines", {"phase_machines": {"reviewer": "any", "validator": "worker-1"}}, [],
     check=lambda iss: any(i.level == "info" and i.message == "reviewer -> any: workstation, worker-1, vault" for i in iss)
     and any(i.level == "info" and i.message == "validator -> worker-1" for i in iss))

total = len(ROWS) + len(IROWS)
print("rows: %d" % total)
sys.stdout.flush()


def getters(p, c, r):
    return {
        "status": p.status, "machine": p.machine, "local": p.local, "kind": p.kind, "cause": p.off_cause,
        "cands": p.candidates, "at": p.requested.at if p.requested else None,
    }


for name, cfgdoc, role, kind, regname, expect in ROWS:
    try:
        reg = REGS[regname]
        cfg = M.read_placement(cfgdoc)
        p = M.resolve(role, kind, registry=reg, config=cfg)
        got = getters(p, cfg, reg)
        problems = []
        for key, want in expect.items():
            if key == "kind_is":
                if p.kind != want:
                    problems.append("kind expected %r got %r" % (want, p.kind))
            elif key in got:
                if got[key] != want:
                    problems.append("%s expected %r got %r" % (key, want, got[key]))
            elif key == "has":
                for s in want:
                    if s not in p.reason:
                        problems.append("reason lacks %r: %s" % (s, p.reason))
            elif key == "rej":
                if [k for k, _ in p.rejected] != want:
                    problems.append("rejected keys expected %r got %r" % (want, [k for k, _ in p.rejected]))
            elif key == "rej_has":
                for k in want:
                    if k not in [x for x, _ in p.rejected]:
                        problems.append("rejected lacks %r" % k)
            elif key == "rej_not":
                for k in want:
                    if k in [x for x, _ in p.rejected]:
                        problems.append("rejected has %r" % k)
            elif key == "req_none":
                if (p.requested is None) != want:
                    problems.append("requested is None expected %r" % want)
            elif key == "nwarn":
                if len(warnings_of(cfg)) != want:
                    problems.append("warnings expected %d got %d" % (want, len(warnings_of(cfg))))
            elif key == "nissues":
                if len(cfg.issues) != want:
                    problems.append("issues expected %d got %d: %r" % (want, len(cfg.issues), cfg.issues))
            elif key == "fn":
                if not want(p, cfg, reg):
                    problems.append("check failed (reason: %s)" % p.reason)
            else:
                problems.append("unknown expectation %r" % key)
        if problems:
            print("FAIL: %s: %s" % (name, "; ".join(problems)))
        else:
            print("ok: %s" % name)
    except Exception as exc:
        print("FAIL: %s: raised %s: %s" % (name, type(exc).__name__, exc))

for name, cfgdoc, regname, errors, warnings, check in IROWS:
    try:
        reg = REGS[regname]
        cfg = M.read_placement(cfgdoc)
        iss = M.placement_issues(reg, cfg)
        got_e = sorted(i.where for i in iss if i.level == "error")
        got_w = sorted(i.where for i in iss if i.level == "warning")
        problems = []
        if got_e != errors:
            problems.append("errors expected %r got %r" % (errors, got_e))
        if got_w != warnings:
            problems.append("warnings expected %r got %r" % (warnings, got_w))
        if check is not None and not check(iss):
            problems.append("check failed: %r" % (iss,))
        print(("FAIL: %s: %s" % (name, "; ".join(problems))) if problems else ("ok: %s" % name))
    except Exception as exc:
        print("FAIL: %s: raised %s: %s" % (name, type(exc).__name__, exc))
PY
OUTA="$(PYTHONPATH="$LIB" "$PY" "$TMP/parta.py" 2>&1)"
RCA=$?
NROWS="$(printf '%s\n' "$OUTA" | sed -n 's/^rows: //p' | head -1)"
NOK="$(printf '%s\n' "$OUTA" | grep -c '^ok: ' || true)"
printf '%s\n' "$OUTA" | grep '^ok: ' | sed 's/^ok: /  ✓ /'
while IFS= read -r line; do bad "${line#FAIL: }"; done < <(printf '%s\n' "$OUTA" | grep '^FAIL: ' || true)
pass=$((pass+NOK))
if [ "$RCA" = 0 ] && [ -n "$NROWS" ] && [ "$NOK" = "$NROWS" ]; then
  ok "A: all $NROWS table rows ran"
else
  bad "A: the table did not finish (rows=$NROWS, ok=$NOK, exit=$RCA)"
  printf '%s\n' "$OUTA" | grep -v -e '^ok: ' -e '^FAIL: ' | head -20
fi

# ── Part B: YAML and the CLI ────────────────────────────────────────────────
if [ "$HAVE_PYYAML" = 0 ] && [ "$HAVE_YQ" = 0 ]; then
  echo "skip: neither PyYAML nor yq is available; Part B needs one of them"
  [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ] && bad "Part B skipped under SDLC_REQUIRE_BOTH_BACKENDS"
  echo "placement: $pass passed, $fail failed"
  [ "$fail" = 0 ]; exit $?
fi

ENVX=()
sdlc_run() {
  local be=$1; shift
  if [ "$be" = yq ]; then
    env PYTHONPATH="$TMP/noyaml" PATH="$TMP/pyyq" ${ENVX[@]+"${ENVX[@]}"} "$PY" "$SDLC" "$@"
  else
    env ${ENVX[@]+"${ENVX[@]}"} "$PY" "$SDLC" "$@"
  fi
}
run() { local be=$1; shift; OUT=$(sdlc_run "$be" "$@" 2>&1); RC=$?; }
# pyrun BACKEND 'python code' args...   (sys.argv[1:] = args; machines importable)
pyrun() {
  local be=$1 code=$2; shift 2
  if [ "$be" = yq ]; then
    OUT=$(PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/pyyq" ${ENVX[@]+"${ENVX[@]}"} "$PY" -c "$code" "$@" 2>&1); RC=$?
  else
    OUT=$(PYTHONPATH="$LIB" ${ENVX[@]+"${ENVX[@]}"} "$PY" -c "$code" "$@" 2>&1); RC=$?
  fi
}
has()  { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
lacks(){ case "$OUT" in *"$1"*) return 1 ;; *) return 0 ;; esac; }
t()    { local label=$1; shift; if "$@"; then ok "$label"; else bad "$label"; printf '      output: %s\n' "$OUT" | head -12; fi; }
rc_is(){ [ "$RC" = "$1" ]; }
first_is() { [ "$(printf '%s\n' "$OUT" | head -1)" = "$1" ]; }
cfgfile() { cat > "$FX/$1.yml"; echo "$FX/$1.yml"; }

BLOCK_FILE="$FX/b1.yml"
sed -n '/^# phase_machines:/,/^#$/p' "$SDLC_EXAMPLE" | sed -e 's/^# //' -e 's/^#$//' > "$BLOCK_FILE"
PLACE_VALIDATOR="$(cfgfile place-validator <<'EOF'
phase_machines: {validator: worker-1}
EOF
)"

echo "B1  the commented example block"
t "B1 the block was extracted" test -s "$BLOCK_FILE"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$BLOCK_FILE"
  t "[$be] B1 check: ok, 0 errors, 0 warnings" bash -c '[ "$1" = 0 ]' _ "$RC"
  t "[$be] B1 check: exact result line" has "check: ok (errors=0, warnings=0)"
  for role in validator implementer reviewer browser-pilot; do
    t "[$be] B1 check: info line for $role" has "info     sdlc.yml."
    t "[$be] B1 check: $role is reported" has "$role ->"
  done
  run $be machines where validator --registry "$EXAMPLE" --config "$BLOCK_FILE"
  t "[$be] B1 where validator: first line" first_is "validator: worker-1"
  t "[$be] B1 where validator: rc 0" rc_is 0
  run $be machines where reviewer --registry "$EXAMPLE" --config "$BLOCK_FILE"
  t "[$be] B1 where reviewer: local first" first_is "reviewer: workstation (local)"
  t "[$be] B1 where reviewer: candidates line" has "candidates:  workstation, worker-1"
  t "[$be] B1 where reviewer: rc 0" rc_is 0
  run $be machines where browser-pilot --registry "$EXAMPLE" --config "$BLOCK_FILE"
  t "[$be] B1 where browser-pilot: kind agent" has "kind:        agent"
  t "[$be] B1 where browser-pilot: rc 0" rc_is 0
done

echo "B2  the example as shipped places nothing"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$SDLC_EXAMPLE"
  t "[$be] B2 check: rc 0" rc_is 0
  t "[$be] B2 check: places nothing" has "places nothing"
  t "[$be] B2 check: no role lines" lacks " -> "
  pyrun $be 'import sys, machines
c = machines.load_placement(sys.argv[1])
sys.exit(0 if (c.phases == {} and c.agents == {} and c.default is None and not c.opted_in and c.usable and not c.issues) else 1)' "$SDLC_EXAMPLE"
  t "[$be] B2 read_placement: empty maps, not opted in" rc_is 0
  run $be machines where validator --registry "$EXAMPLE" --config "$SDLC_EXAMPLE"
  t "[$be] B2 where: rc 0 and machines are off" bash -c '[ "$1" = 0 ]' _ "$RC"
  t "[$be] B2 where: says off" has "machines are off"
done

echo "B3  grouped beats flat"
G_BLOCK="$(cfgfile g-block <<'EOF'
phase_machines: {validator: workstation}
phases:
  validator:
    model: fable
    machine: worker-1
EOF
)"
G_FLOW="$(cfgfile g-flow <<'EOF'
phase_machines: {validator: workstation}
phases:
  validator: { model: fable, machine: worker-1 }
EOF
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  for f in "$G_BLOCK" "$G_FLOW"; do
    run $be machines where validator --registry "$EXAMPLE" --config "$f"
    t "[$be] B3 $(basename "$f"): validator -> worker-1" first_is "validator: worker-1"
    run $be machines check --registry "$EXAMPLE" --config "$f"
    t "[$be] B3 $(basename "$f"): one warning" has "warnings=1)"
  done
done

echo "B4-B5  fallback and nowhere to run"
UNKNOWN="$(cfgfile unknown <<'EOF'
phase_machines: {validator: worker-9}
EOF
)"
NOWHERE="$(cfgfile nowhere <<'EOF'
phase_machines: {validator: worker-1}
needs: {validator: {keeps: [datasets]}}
EOF
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$UNKNOWN"
  t "[$be] B4 check: rc 1" rc_is 1
  t "[$be] B4 check: one error" has "check: failed (errors=1, warnings=0)"
  t "[$be] B4 check: error at the key" has "error    sdlc.yml.phase_machines.validator:"
  run $be machines where validator --registry "$EXAMPLE" --config "$UNKNOWN"
  t "[$be] B4 where: rc 1" rc_is 1
  t "[$be] B4 where: fallback to this box" first_is "validator: workstation (local), fallback"
  t "[$be] B4 where: refused line" has "refused:     worker-9:"
  run $be machines where validator --registry "$EXAMPLE" --config "$NOWHERE"
  t "[$be] B5 where: rc 1" rc_is 1
  t "[$be] B5 where: nowhere" first_is "validator: nowhere"
done

echo "B6  no registry"
run py machines where validator --config "$BLOCK_FILE"
[ "$HAVE_PYYAML" = 0 ] && run yq machines where validator --config "$BLOCK_FILE"
t "B6 where: rc 0" rc_is 0
t "B6 where: this box" first_is "validator: this box (machines are off)"
t "B6 where: sdlc.yml was not read" has "not read (the registry is not usable)"
run py machines check --config "$BLOCK_FILE"
[ "$HAVE_PYYAML" = 0 ] && run yq machines check --config "$BLOCK_FILE"
EXPECT_INERT="No machine registry at $HOME/.config/sdlc/machines.yaml. Machines are off, so everything runs on this box.
To set one up: cp $ROOT/machines.example.yaml $HOME/.config/sdlc/machines.yaml   (or set \$SDLC_MACHINES)"
t "B6 check: rc 0" rc_is 0
t "B6 check: byte-identical to the 0.2.40 inert message" bash -c '[ "$1" = "$2" ]' _ "$OUT" "$EXPECT_INERT"
run py machines where validator --config "$TMP/nope.yml"
[ "$HAVE_PYYAML" = 0 ] && run yq machines where validator --config "$TMP/nope.yml"
t "B6 where: a missing --config is not read without a registry, so it exits 0 (documented)" rc_is 0

echo "B7  broken registry"
cat > "$FX/two-local.yaml" <<'EOF'
machines:
  a: {transport: local}
  b: {transport: local}
EOF
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$FX/two-local.yaml" --config "$BLOCK_FILE"
  t "[$be] B7 check: rc 1" rc_is 1
  t "[$be] B7 check: placement not checked" has "Placement: not checked (the registry is not usable)"
  t "[$be] B7 check: no sdlc.yml lines" lacks "sdlc.yml."
  t "[$be] B7 check: registry errors print above the Placement line" bash -c '
    e=$(printf "%s\n" "$1" | grep -n "^error " | head -1 | cut -d: -f1)
    p=$(printf "%s\n" "$1" | grep -n "^Placement:" | head -1 | cut -d: -f1)
    [ -n "$e" ] && [ -n "$p" ] && [ "$e" -lt "$p" ]' _ "$OUT"
  run $be machines where validator --registry "$FX/two-local.yaml" --config "$BLOCK_FILE"
  t "[$be] B7 where: rc 1" rc_is 1
  t "[$be] B7 where: off, registry has errors" has "the registry has errors"
  t "[$be] B7 where: first line says off" first_is "validator: this box (machines are off)"
  t "[$be] B7 where: sdlc.yml not read" has "sdlc.yml:    not read (the registry is not usable)"
  run $be machines where validator --registry "$TMP/nope.yaml" --config "$BLOCK_FILE"
  t "[$be] B7 where: a missing --registry exits 1" rc_is 1
done

echo "B8-B9  an unreadable sdlc.yml"
BADYAML="$(cfgfile badyaml <<'EOF'
phase_machines: [
EOF
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$BADYAML"
  t "[$be] B8 check: rc 1" rc_is 1
  t "[$be] B8 check: could not parse" has "error    sdlc.yml: could not parse"
  run $be machines where validator --registry "$EXAMPLE" --config "$BADYAML"
  t "[$be] B8 where: rc 1" rc_is 1
  t "[$be] B8 where: sdlc.yml has errors" has "sdlc.yml has errors"
  run $be machines check --registry "$EXAMPLE" --config "$TMP/nope.yml"
  t "[$be] B9 check: rc 1" rc_is 1
  t "[$be] B9 check: not found" has "sdlc.yml not found"
  run $be machines where validator --registry "$EXAMPLE" --config "$TMP/nope.yml"
  t "[$be] B9 where: rc 1" rc_is 1
done

echo "B10  discovery"
mkdir -p "$TMP/p1/.claude" "$TMP/p2/.claude" "$TMP/p2/a/b" "$TMP/p3/.claude" "$TMP/p3/repo/.git" "$TMP/p3/repo/x" "$TMP/empty"
echo 'phase_machines: {validator: worker-1}' > "$TMP/p1/.claude/sdlc.yml"
echo 'phase_machines: {validator: workstation}' > "$TMP/p2/.claude/sdlc.yml"
echo 'phase_machines: {validator: workstation}' > "$TMP/p3/.claude/sdlc.yml"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  cd "$TMP/p2/a/b" || exit 1
  ENVX=(CLAUDE_PROJECT_DIR="$TMP/p1")
  run $be machines where validator --registry "$EXAMPLE"
  t "[$be] B10 CLAUDE_PROJECT_DIR beats the cwd" has "sdlc.yml:    $TMP/p1/.claude/sdlc.yml"
  ENVX=()
  run $be machines where validator --registry "$EXAMPLE"
  t "[$be] B10 walk-up finds the project above the cwd" has "sdlc.yml:    $TMP/p2/.claude/sdlc.yml"
  ENVX=(CLAUDE_PROJECT_DIR="$TMP/empty")
  run $be machines check --registry "$EXAMPLE"
  t "[$be] B10 a project dir without sdlc.yml does not walk up" has "Placement: none (no .claude/sdlc.yml found)"
  ENVX=()
  cd "$TMP/p3/repo/x" || exit 1
  run $be machines check --registry "$EXAMPLE"
  t "[$be] B10 the walk stops at a directory with .git" has "Placement: none (no .claude/sdlc.yml found)"
  run $be machines where validator --registry "$EXAMPLE"
  t "[$be] B10 where: none found, machines off for lack of placement, rc 0" bash -c '[ "$1" = 0 ]' _ "$RC"
  t "[$be] B10 where: sdlc.yml none found" has "sdlc.yml:    none found"
  cd "$TMP/cwd" || exit 1
done

echo "B11  --config on the group and on the leaf"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines --registry "$EXAMPLE" --config "$G_BLOCK" where validator
  t "[$be] B11 group --config" has "sdlc.yml:    $G_BLOCK"
  run $be machines --registry "$EXAMPLE" --config "$G_BLOCK" where validator --config "$G_FLOW"
  t "[$be] B11 leaf --config wins" has "sdlc.yml:    $G_FLOW"
  run $be machines --config "$G_BLOCK" --registry "$EXAMPLE" check
  t "[$be] B11 group --config reaches check" has "Placement: $G_BLOCK"
done

echo "B12-B13b  lookup() and the time budget (yq only; PyYAML is hidden)"
if [ "$HAVE_YQ" = 1 ]; then
  mkdir -p "$TMP/b12" "$TMP/b13" "$TMP/b13b" "$TMP/proj/.claude"
  cp "$BLOCK_FILE" "$TMP/proj/.claude/sdlc.yml"
  for d in b12 b13 b13b; do ln -s "$PY" "$TMP/$d/python3"; done
  TOUCH="$(command -v touch)"
  cat > "$TMP/b12/yq" <<EOF
#!/bin/sh
$TOUCH "$TMP/yq-called"
exec $REAL_YQ "\$@"
EOF
  cat > "$TMP/b13/yq" <<EOF
#!/bin/sh
for last; do :; done
case "\$last" in
  *sdlc.yml) exec $SLEEP 5 ;;
esac
exec $REAL_YQ "\$@"
EOF
  cat > "$TMP/b13b/yq" <<EOF
#!/bin/sh
for last; do :; done
case "\$last" in
  *sdlc.yml) $TOUCH "$TMP/sdlc-read"; exec $REAL_YQ "\$@" ;;
esac
$SLEEP 0.5
exec $REAL_YQ "\$@"
EOF
  chmod +x "$TMP/b12/yq" "$TMP/b13/yq" "$TMP/b13b/yq"
  LOOKUP='import sys, machines
p = machines.lookup("validator", project_dir=sys.argv[1], registry_file=(sys.argv[2] if len(sys.argv) > 2 else None))
print(p.status, p.off_cause, "|", p.reason)'
  OUT=$(env PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/b12" "$PY" -c "$LOOKUP" "$TMP/proj" 2>&1); RC=$?
  t "B12 lookup with no registry: off, no-registry" has "off no-registry"
  t "B12 lookup with no registry: yq was never called" test ! -e "$TMP/yq-called"
  OUT=$(env PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/b12" "$PY" -c "$LOOKUP" "$TMP/proj" "$EXAMPLE" 2>&1); RC=$?
  t "B12 lookup with the example registry: placed" has "placed None"
  t "B12 lookup with the example registry: the wrapper ran" test -e "$TMP/yq-called"

  OUT=$(env PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/b13" "$PY" -c "$LOOKUP" "$TMP/proj" "$EXAMPLE" 2>&1); RC=$?
  t "B13 a hung yq on sdlc.yml: off, sdlc-errors" has "off sdlc-errors"
  t "B13 the reason starts with the sdlc.yml error" has "| machines are off: sdlc.yml has errors"
  t "B13 the reason says it timed out" has "timed out"

  rm -f "$TMP/sdlc-read"
  # The wrapper sleeps 0.5 s on the registry. Lowering the threshold to 0.2 s here leaves 0.3 s of margin on
  # the skip side and 1.5 s before YQ_TIMEOUT on the other, so the row cannot flip on a slow box.
  OUT=$(env PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/b13b" "$PY" -c "
import sys, machines
machines.SDLC_SKIP_AFTER = 0.2
p = machines.lookup('validator', project_dir=sys.argv[1], registry_file=sys.argv[2])
print(p.status, p.off_cause, '|', p.reason)" "$TMP/proj" "$EXAMPLE" 2>&1); RC=$?
  t "B13b a slow registry read: off, time-budget" has "off time-budget"
  t "B13b sdlc.yml was not read" test ! -e "$TMP/sdlc-read"
  OUT=$(env PYTHONPATH="$TMP/noyaml" PATH="$TMP/b13b" "$PY" "$SDLC" machines where validator --registry "$EXAMPLE" --config "$TMP/proj/.claude/sdlc.yml" 2>&1); RC=$?
  t "B13b where has no budget: resolves normally" first_is "validator: worker-1"
  t "B13b where read sdlc.yml" test -e "$TMP/sdlc-read"
else
  [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ] || echo "skip: B12-B13b need yq"
fi

echo "B14  lookup() is quiet and never raises"
mkdir -p "$FX/bad"
mkbad() { local d; d="$(mktemp -d "$FX/bad/XXXXXX")"; mkdir -p "$d/.claude"; cat > "$d/.claude/sdlc.yml"; echo "$d"; }
BAD_DIRS=()
BAD_DIRS+=("$(printf 'phase_machines: [\n' | mkbad)")
BAD_DIRS+=("$(printf -- '- a\n- b\n' | mkbad)")
BAD_DIRS+=("$(printf 'phase_machines: [validator]\n' | mkbad)")
BAD_DIRS+=("$(printf 'needs: browser\nphase_machines: {validator: worker-1}\n' | mkbad)")
BAD_DIRS+=("$(printf '' | mkbad)")
BAD_DIRS+=("$(printf '\000\377\376binary\000' | mkbad)")
QUIET='import sys, machines
p = machines.lookup("validator", project_dir=sys.argv[1], registry_file=sys.argv[2])
print(p.status)'
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  n=0
  for d in "${BAD_DIRS[@]}"; do
    n=$((n+1))
    if [ "$be" = yq ]; then
      STDOUT=$(PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/pyyq" "$PY" -c "$QUIET" "$d" "$EXAMPLE" 2>"$TMP/err"); RC=$?
    else
      STDOUT=$(PYTHONPATH="$LIB" "$PY" -c "$QUIET" "$d" "$EXAMPLE" 2>"$TMP/err"); RC=$?
    fi
    OUT="$STDOUT $(cat "$TMP/err")"
    t "[$be] B14 file $n: exit 0, empty stderr, a status on stdout" bash -c '[ "$1" = 0 ] && [ ! -s "$2" ] && case "$3" in off|placed|fallback|unplaceable) true ;; *) false ;; esac' _ "$RC" "$TMP/err" "$STDOUT"
  done
done

echo "B14b  empty and overlong paths"
LONG="$("$PY" -c 'print("a" * 5000)')"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config ""
  t "[$be] B14b check --config \"\": usage error 2" rc_is 2
  t "[$be] B14b check --config \"\": message" has "--config needs a path"
  run $be machines where validator --registry "$EXAMPLE" --config ""
  t "[$be] B14b where --config \"\": usage error 2" rc_is 2
  run $be machines --config "" where validator
  t "[$be] B14b group --config \"\": usage error 2" rc_is 2
  run $be machines check --registry "$EXAMPLE" --config "$LONG"
  t "[$be] B14b a 5000-character --config: rc 1" rc_is 1
  t "[$be] B14b a 5000-character --config: an error at sdlc.yml" has "error    sdlc.yml:"
  t "[$be] B14b a 5000-character --config: no traceback" lacks "Traceback"
  ENVX=(CLAUDE_PROJECT_DIR="$LONG")
  run $be machines where validator --registry "$EXAMPLE"
  t "[$be] B14b a 5000-character CLAUDE_PROJECT_DIR: rc 1" rc_is 1
  t "[$be] B14b a 5000-character CLAUDE_PROJECT_DIR: sdlc.yml has errors" has "sdlc.yml has errors"
  ENVX=()
  pyrun $be 'import sys, machines
p = machines.lookup("validator", project_dir=sys.argv[1], registry_file=sys.argv[2])
c = machines.load_placement("")
sys.exit(0 if (p.status == "off" and c.broken and c.issues[0].where == "sdlc.yml") else 1)' "$LONG" "$EXAMPLE"
  t "[$be] B14b lookup(project_dir=long) is off, load_placement(\"\") is broken" rc_is 0
done

echo "B15  the tuning hook ignores machine"
HOOKDIR="$TMP/hook"; mkdir -p "$HOOKDIR/.claude"
payload='{"tool_name":"Agent","tool_input":{"subagent_type":"sdlc:validator","prompt":"x"},"cwd":"IGNORED"}'
hook_model() { printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$HOOKDIR" bash "$HOOK" 2>/dev/null | "$PY" -c '
import json, sys
try:
    ui = json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]
except Exception:
    print("none"); sys.exit(0)
print(ui.get("model", "-"), "machine" in ui)'; }
cat > "$HOOKDIR/.claude/sdlc.yml" <<'EOF'
phases:
  validator:
    model: fable
    machine: worker-1
EOF
OUT="$(hook_model)"
t "B15 model injected, no machine key in updatedInput" bash -c '[ "$1" = "fable False" ]' _ "$OUT"
cat > "$HOOKDIR/.claude/sdlc.yml" <<'EOF'
phases:
  validator:
    machine: null
    model: fable
EOF
OUT="$(hook_model)"
t "B15 machine: null before model: model is still injected" bash -c '[ "$1" = "fable False" ]' _ "$OUT"

echo "B16  repeated placement keys"
R_A1="$(cfgfile r-a1 <<'EOF'
phase_machines: {validator: worker-1}
needs: {validator: [browser]}
needs: {validator: {keeps: [datasets]}}
EOF
)"
R_A2="$(cfgfile r-a2 <<'EOF'
needs: {validator: [browser]}
needs: {validator: [gpu]}
EOF
)"
R_B1="$(cfgfile r-b1 <<'EOF'
phase_machines: {validator: worker-1}
needs:
  validator: {keeps: [datasets]}
  validator: [browser]
EOF
)"
R_B2="$(cfgfile r-b2 <<'EOF'
phase_machines: {implementer: workstation}
needs:
  implementer:
    keeps: [checkouts]
    keeps: []
EOF
)"
R_C1="$(cfgfile r-c1 <<'EOF'
phase_machines:
  validator: worker-1
  validator: workstation
EOF
)"
R_C2="$(cfgfile r-c2 <<'EOF'
phases:
  validator:
    machine: worker-1
    machine: workstation
EOF
)"
R_C3="$(cfgfile r-c3 <<'EOF'
phase_machines: {validator: worker-1}
phases:
  validator: {model: opus}
  validator: {effort: high}
EOF
)"
R_D="$(cfgfile r-d <<'EOF'
phase_machines: {validator: worker-1}
phase_models: {a: x, a: y}
develop_team: [a]
develop_team: [b]
EOF
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$R_A1"
  t "[$be] B16a check: rc 1" rc_is 1
  t "[$be] B16a check: error at sdlc.yml.needs, written more than once" has "error    sdlc.yml.needs: needs is written more than once"
  run $be machines where validator --registry "$EXAMPLE" --config "$R_A1"
  t "[$be] B16a where: rc 1, sdlc.yml has errors" bash -c '[ "$1" = 1 ]' _ "$RC"
  t "[$be] B16a where: reason" has "sdlc.yml has errors"
  # No target: not opted in, so the repeat is not an error, but it is recorded.
  run $be machines check --registry "$EXAMPLE" --config "$R_A2"
  t "[$be] B16a2 no target, check: rc 0, one warning, no error" has "check: ok (errors=0, warnings=1)"
  run $be machines where validator --registry "$EXAMPLE" --config "$R_A2"
  t "[$be] B16a2 no target, where: rc 0" rc_is 0
  t "[$be] B16a2 no target, where: off, places nothing" has "sdlc.yml places nothing"
  pyrun $be 'import sys, machines
c = machines.load_placement(sys.argv[1])
sys.exit(0 if (c.needs_broken and c.usable and not c.opted_in) else 1)' "$R_A2"
  t "[$be] B16a2 no target: needs_broken is set, the config is usable and not opted in" rc_is 0
  run $be machines where validator --registry "$EXAMPLE" --config "$R_B1"
  t "[$be] B16b where: nowhere, rc 1" first_is "validator: nowhere"
  run $be machines check --registry "$EXAMPLE" --config "$R_B1"
  t "[$be] B16b check: error at sdlc.yml.needs.validator" has "error    sdlc.yml.needs.validator:"
  run $be machines check --registry "$EXAMPLE" --config "$R_B2"
  t "[$be] B16b keeps twice: error at sdlc.yml.needs.implementer.keeps" has "error    sdlc.yml.needs.implementer.keeps:"
  run $be machines where implementer --registry "$EXAMPLE" --config "$R_B2"
  t "[$be] B16b keeps twice: the role is unplaceable" first_is "implementer: nowhere"
  for f in "$R_C1" "$R_C2" "$R_C3"; do
    run $be machines where validator --registry "$EXAMPLE" --config "$f"
    t "[$be] B16c $(basename "$f") where: fallback, rc 1" first_is "validator: workstation (local), fallback"
    t "[$be] B16c $(basename "$f") where: rc 1" rc_is 1
  done
  run $be machines check --registry "$EXAMPLE" --config "$R_C1"
  t "[$be] B16c error at sdlc.yml.phase_machines.validator" has "error    sdlc.yml.phase_machines.validator:"
  run $be machines check --registry "$EXAMPLE" --config "$R_C2"
  t "[$be] B16c error at sdlc.yml.phases.validator.machine" has "error    sdlc.yml.phases.validator.machine:"
  run $be machines check --registry "$EXAMPLE" --config "$R_C3"
  t "[$be] B16c a repeated tuning-only phases.validator: error at sdlc.yml.phases.validator" has "error    sdlc.yml.phases.validator:"
  run $be machines check --registry "$EXAMPLE" --config "$R_D"
  t "[$be] B16d unrelated repeats: check ok, no placement issues" has "check: ok (errors=0, warnings=0)"
  run $be machines where validator --registry "$EXAMPLE" --config "$R_D"
  t "[$be] B16d unrelated repeats: validator -> worker-1" first_is "validator: worker-1"
  t "[$be] B16d unrelated repeats: rc 0" rc_is 0
done

echo "B17  a prefixed-key collision"
R_E="$(cfgfile r-e <<'EOF'
phase_machines: {validator: worker-1}
needs: {validator: [browser], sdlc:validator: {keeps: [datasets]}}
EOF
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE" --config "$R_E"
  t "[$be] B17 check: error at sdlc.yml.needs.validator" has "error    sdlc.yml.needs.validator:"
  run $be machines where validator --registry "$EXAMPLE" --config "$R_E"
  t "[$be] B17 where: nowhere" first_is "validator: nowhere"
done

echo "placement: $pass passed, $fail failed"
[ "$fail" = 0 ]
