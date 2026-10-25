#!/usr/bin/env bash
# Tests for the machine registry: plugin/lib/machines.py, plugin/lib/herdr.py, plugin/bin/sdlc.
# Plain bash + python3 (PyYAML and/or yq for the YAML cases). No network, no real herdr.
# Run: bash plugin/lib/machines.test.sh   (exits 0 only when every case that ran passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE"
SDLC="$(cd "$HERE/../bin" && pwd)/sdlc"
EXAMPLE="$(cd "$HERE/.." && pwd)/machines.example.yaml"
PY="$(command -v python3)"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Never read the real user's registry.
export HOME="$TMP/home"
mkdir -p "$HOME"
unset SDLC_MACHINES XDG_CONFIG_HOME
# Keep the placement pass deterministic: no sdlc.yml here, rather than walking up into the repo the suite runs in.
export CLAUDE_PROJECT_DIR="$TMP/proj"
mkdir -p "$TMP/proj"
export PYTHONDONTWRITEBYTECODE=1
FX="$TMP/fx"; mkdir -p "$FX"

# ── backends ────────────────────────────────────────────────────────────────
HAVE_PYYAML=0; HAVE_YQ=0
"$PY" -c 'import yaml' 2>/dev/null && HAVE_PYYAML=1
command -v yq >/dev/null 2>&1 && HAVE_YQ=1
# Shadow package that hides PyYAML, so the yq path runs.
mkdir -p "$TMP/noyaml/yaml"; echo 'raise ImportError("hidden for the test")' > "$TMP/noyaml/yaml/__init__.py"
# PATH directories, each built fresh.
mkdir -p "$TMP/pybin" "$TMP/pyyq" "$TMP/slowyq" "$TMP/badyq" "$TMP/fakebin"
ln -s "$PY" "$TMP/pybin/python3"
ln -s "$PY" "$TMP/pyyq/python3"
[ "$HAVE_YQ" = 1 ] && ln -s "$(command -v yq)" "$TMP/pyyq/yq"
SLEEP="$(command -v sleep)"
ln -s "$PY" "$TMP/slowyq/python3"
printf '#!/bin/sh\nexec %s 5\n' "$SLEEP" > "$TMP/slowyq/yq"; chmod +x "$TMP/slowyq/yq"
ln -s "$PY" "$TMP/badyq/python3"
printf '#!/bin/sh\necho "this is not json"\n' > "$TMP/badyq/yq"; chmod +x "$TMP/badyq/yq"
# Fake herdr: worker-1 answers, "slow" hangs, any other label is unknown (herdr 0.9.5's text).
cat > "$TMP/fakebin/herdr" <<EOF
#!/bin/sh
[ "\$1" = "--machine" ] || exit 3
case "\$2" in
  worker-1) echo '{"id":"cli:agent:list","result":{"agents":[{},{}],"type":"agent_list"}}'; exit 0 ;;
  slow) exec $SLEEP 5 ;;
  *) echo "error: unknown machine '\$2'; use \`herdr machine list\`" >&2; exit 2 ;;
esac
EOF
chmod +x "$TMP/fakebin/herdr"

if [ "${SDLC_REQUIRE_BOTH_BACKENDS:-0}" = 1 ]; then
  [ "$HAVE_PYYAML" = 1 ] && ok "required backend present: PyYAML" || bad "required backend missing: PyYAML"
  [ "$HAVE_YQ" = 1 ] && ok "required backend present: yq" || bad "required backend missing: yq"
fi
BACKENDS=()
[ "$HAVE_PYYAML" = 1 ] && BACKENDS+=(py)
[ "$HAVE_YQ" = 1 ] && BACKENDS+=(yq)

# sdlc_run BACKEND args...   (BACKEND yq hides PyYAML; extra env via ENVX)
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
# run_path PATHDIRS args...   (no YAML shadowing; explicit PATH)
run_path() { local p=$1; shift; OUT=$(env PATH="$p" "$PY" "$SDLC" "$@" 2>&1); RC=$?; }
# pyl BACKEND FILE 'python expr over r (Registry), b (box), h (here)'  -> status 0 when true
pyl() {
  local be=$1 f=$2 expr=$3 pp="$LIB"
  [ "$be" = yq ] && pp="$LIB:$TMP/noyaml"
  PYTHONPATH="$pp" PATH="$([ "$be" = yq ] && echo "$TMP/pyyq" || echo "$PATH")" "$PY" -c '
import sys, machines
r = machines.load(sys.argv[1]); b = r.machines.get("box"); h = r.machines.get("here")
sys.exit(0 if eval(sys.argv[2]) else 1)' "$f" "$expr"
}

has()  { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
t()    { local label=$1; shift; if "$@"; then ok "$label"; else bad "$label"; printf '      output: %s\n' "$OUT" | head -8; fi; }
rc_is(){ [ "$RC" = "$1" ]; }
# fixture NAME <<EOF  -> $FX/NAME.yaml
fixture() { cat > "$FX/$1.yaml"; echo "$FX/$1.yaml"; }
# box_fixture NAME 'yaml line(s) for box'  : valid local `here` + `box` with a herdr transport and workdir
box_fixture() {
  local name=$1; shift
  local own_transport=0 a
  for a in "$@"; do case "$a" in transport:*) own_transport=1 ;; esac; done
  {
    echo "machines:"
    echo "  here: {transport: local}"
    echo "  box:"
    [ "$own_transport" = 1 ] || echo "    transport: {herdr: box}"
    echo "    workdir: /w"
    printf '    %s\n' "$@"
  } > "$FX/$name.yaml"
}

if [ "$HAVE_PYYAML" = 0 ] && [ "$HAVE_YQ" = 0 ]; then
  echo "skip: neither PyYAML nor yq is available; running only the cases that need no YAML backend (7, 8, 19, 20, 21, 23, 25, 26)"
fi

# ── 1  valid example [both] ─────────────────────────────────────────────────
echo "1  the example file"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$EXAMPLE"
  t "[$be] example: check ok, 0 warnings" bash -c '[ "$1" = 0 ]' _ "$RC"
  t "[$be] example: exact result line" has "check: ok (errors=0, warnings=0)"
  run $be machines list --registry "$EXAMPLE"
  t "[$be] example list: rc 0, three machines, no !" bash -c '[ "$1" = 0 ] && case "$2" in *"!"*) exit 1;; *workstation*local*) ;; *) exit 1;; esac; case "$2" in *herdr:worker-1*) ;; *) exit 1;; esac' _ "$RC" "$OUT"
  t "[$be] example list: control has no transport and is not assignable" bash -c 'echo "$1" | grep -qE "^control +- +control-plane +no "' _ "$OUT"
  t "[$be] example: usable, local is workstation" pyl $be "$EXAMPLE" 'r.usable and r.local.name == "workstation" and all(m.ok for m in r.machines.values())'
done

# ── 2  one rejected value per key ───────────────────────────────────────────
echo "2  one rejected value per key"
# line @@ where @@ python expression about the loaded machine
CASES=(
  'transport: 42@@machines.box.transport@@b.transport.kind == "none"'
  'transport: ssh@@machines.box.transport@@b.transport.kind == "none"'
  'transport: {herdr: box, ssh: 5}@@machines.box.transport@@b.transport.kind == "none"'
  'workdir: [a]@@machines.box.workdir@@b.workdir is None'
  'limits: 3@@machines.box.limits@@b.limits.cores == 0 and b.limits.agents == 0'
  'limits: {cores: twelve}@@machines.box.limits.cores@@b.limits.cores == 0'
  'limits: {cores: 0}@@machines.box.limits.cores@@b.limits.cores == 0'
  'limits: {mem_gb: -1}@@machines.box.limits.mem_gb@@b.limits.mem_gb == 0'
  'limits: {browser_jobs: 1.5}@@machines.box.limits.browser_jobs@@b.limits.browser_jobs == 0'
  'limits: {agents: true}@@machines.box.limits.agents@@b.limits.agents == 0'
  'caps: edit@@machines.box.caps@@b.caps == ()'
  'caps: [1]@@machines.box.caps@@b.caps == ()'
  'keeps: {a: b}@@machines.box.keeps@@b.keeps == ()'
  'secrets: 3@@machines.box.secrets@@b.secrets == "none"'
  'secrets: staging@@machines.box.secrets@@b.secrets == "none"'
  'gaming_sensitive: 1@@machines.box.gaming_sensitive@@b.gaming_sensitive is True'
  'gaming_sensitive: "false"@@machines.box.gaming_sensitive@@b.gaming_sensitive is True'
  'busy_flag: 7@@machines.box.busy_flag@@b.busy_flag is None and b.gaming_sensitive is True'
  'backup: "true"@@machines.box.backup@@b.backup is False'
  'persistence: ephemeral@@machines.box.persistence@@b.persistence == "disposable"'
  'role: [x]@@machines.box.role@@b.role is None'
  'assignable: "no"@@machines.box.assignable@@b.assignable is False'
  'assignable: 0@@machines.box.assignable@@b.assignable is False'
  'first_start: trust-prompt@@machines.box.first_start@@b.first_start == ()'
  'first_start: [trust-prompt, reboot]@@machines.box.first_start@@b.first_start == ()'
)
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  n=0
  for c in "${CASES[@]}"; do
    n=$((n+1)); line="${c%%@@*}"; rest="${c#*@@}"; where="${rest%%@@*}"; expr="${rest#*@@}"
    box_fixture "c2_$n" "$line"
    run $be machines check --registry "$FX/c2_$n.yaml"
    t "[$be] $line: one error at $where, no warning" bash -c '[ "$1" = 1 ] && case "$2" in *"check: failed (errors=1, warnings=0)"*) ;; *) exit 1;; esac; echo "$2" | grep -q "^error .*$3"' _ "$RC" "$OUT" "$where"
    ik="${where#machines.box.}"
    t "[$be] $line: restrictive value, key in invalid, here ok, usable" pyl $be "$FX/c2_$n.yaml" "not b.ok and ($expr) and h.ok and r.usable and any(k == '$ik' or k.startswith('$ik.') or '$ik'.startswith(k + '.') for k in b.invalid)"
  done
done

# ── 3  the blocker: unquoted YAML 1.1 booleans [both] ───────────────────────
echo "3  unquoted yes/no/on/off fail closed under every backend"
box_fixture c3a 'assignable: no'
box_fixture c3b 'backup: yes'
box_fixture c3c 'gaming_sensitive: off'
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$FX/c3a.yaml"; t "[$be] assignable: no -> exit 1" rc_is 1
  t "[$be] assignable: no -> loads False" pyl $be "$FX/c3a.yaml" 'b.assignable is False and not b.ok'
  run $be machines list --registry "$FX/c3a.yaml"
  t "[$be] assignable: no -> list shows box! and no!" bash -c 'echo "$1" | grep -qE "^box! .* no! "' _ "$OUT"
  OUT=$(sdlc_run $be machines list --registry "$FX/c3a.yaml" 2>&1 >/dev/null)
  t "[$be] assignable: no -> the ! legend goes to stderr" has "! = invalid value"
  OUT=$(sdlc_run $be machines list --registry "$FX/c3a.yaml" 2>/dev/null)
  t "[$be] assignable: no -> and not to stdout" bash -c '! echo "$1" | grep -q "invalid value"' _ "$OUT"
  run $be machines check --registry "$FX/c3b.yaml"; t "[$be] backup: yes -> exit 1" rc_is 1
  t "[$be] backup: yes -> loads False" pyl $be "$FX/c3b.yaml" 'b.backup is False and not b.ok'
  run $be machines check --registry "$FX/c3c.yaml"; t "[$be] gaming_sensitive: off -> exit 1" rc_is 1
  t "[$be] gaming_sensitive: off -> loads True" pyl $be "$FX/c3c.yaml" 'b.gaming_sensitive is True and not b.ok'
done

# ── 4  backend parity ───────────────────────────────────────────────────────
echo "4  backend parity: a machine named on, True and TRUE"
F4="$(fixture c4 <<'YML'
machines:
  here: {transport: local}
  on: {transport: {herdr: on}, workdir: /w, assignable: True}
  box: {transport: {herdr: box}, workdir: /w, assignable: TRUE}
YML
)"
for be in ${BACKENDS[@]+"${BACKENDS[@]}"}; do
  run $be machines check --registry "$F4"
  t "[$be] parity: exit 0, no warnings" has "check: ok (errors=0, warnings=0)"
  t "[$be] parity: key 'on' is a string; True/TRUE load True" pyl $be "$F4" '"on" in r.machines and r.machines["on"].assignable is True and b.assignable is True'
done

# ── 5, 6, 6b, 6c  transport label, unknown keys, near-misses ────────────────
echo "5  missing herdr label"
B1="${BACKENDS[0]:-py}"
if [ ${#BACKENDS[@]} -gt 0 ]; then
  box_fixture c5a 'transport: {ssh: agent@192.0.2.10}'
  box_fixture c5b 'transport: {herdr: ""}'
  for f in c5a c5b; do
    run $B1 machines check --registry "$FX/$f.yaml"
    t "$f: exit 1 at machines.box.transport" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "^error .*machines.box.transport"' _ "$RC" "$OUT"
    t "$f: kind none" pyl $B1 "$FX/$f.yaml" 'b.transport.kind == "none"'
  done

  echo "6  unknown keys are warnings"
  F6="$(fixture c6 <<'YML'
version: 1
machines:
  here: {transport: local}
  box:
    transport: {herdr: box, port: 22}
    workdir: /w
    gpus: 2
    limits: {gpu: 1}
YML
)"
  run $B1 machines check --registry "$F6"
  t "unknown keys: exit 0 with 4 warnings" has "check: ok (errors=0, warnings=4)"
  for w in registry.version machines.box.gpus machines.box.limits.gpu machines.box.transport.port; do
    t "unknown keys: warning at $w" bash -c 'echo "$1" | grep -q "^warning .*$2"' _ "$OUT" "$w"
  done

  echo "6b  near-miss keys: error only at ratio >= 0.8 on the first suggestion"
  box_fixture c6b 'asignable: false'
  run $B1 machines check --registry "$FX/c6b.yaml"
  t "asignable: exit 1, suggests assignable" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "^error .*asignable.*assignable"' _ "$RC" "$OUT"
  t "asignable: loads assignable False" pyl $B1 "$FX/c6b.yaml" 'b.assignable is False and not b.ok'
  for k in 'available: true' 'assign: 1'; do
    box_fixture c6w "$k"
    run $B1 machines check --registry "$FX/c6w.yaml"
    t "$k: stays a warning (exit 0, did you mean)" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^warning .*did you mean"' _ "$RC" "$OUT"
    t "$k: box still assignable and ok" pyl $B1 "$FX/c6w.yaml" 'b.assignable is True and b.ok'
  done
  for k in 'gaming_sensitve: true' 'busyflag: /x' 'gaming-flag: /x'; do
    box_fixture c6e "$k"
    run $B1 machines check --registry "$FX/c6e.yaml"
    t "$k: error (exit 1, exactly one)" bash -c '[ "$1" = 1 ] && case "$2" in *"errors=1,"*) ;; *) exit 1;; esac' _ "$RC" "$OUT"
    t "$k: gaming_sensitive loads True, box not ok" pyl $B1 "$FX/c6e.yaml" 'b.gaming_sensitive is True and not b.ok'
  done
  box_fixture c6f 'Assignable: true'
  run $B1 machines check --registry "$FX/c6f.yaml"
  t "Assignable: true (wrong case) is an error, box not assignable" bash -c '[ "$1" = 1 ]' _ "$RC"
  t "Assignable: true -> loads False" pyl $B1 "$FX/c6f.yaml" 'b.assignable is False'
fi

# ── 7, 8, 9  location (7 and 8 need no backend) ─────────────────────────────
echo "7  inert: no file at the default path"
run py machines list;  t "list: exit 0, inert message with cp hint" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^No machine registry at " && echo "$2" | grep -q "cp .*machines.example.yaml"' _ "$RC" "$OUT"
run py machines check; t "check: exit 0, inert message" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^No machine registry at "' _ "$RC" "$OUT"
t "inert true, usable false" "$PY" -c "
import sys; sys.path.insert(0, '$LIB'); import machines
r = machines.load(); sys.exit(0 if r.inert and not r.usable and not r.issues else 1)"

echo "8  explicit path missing"
ENVX=(SDLC_MACHINES="$TMP/nope.yaml")
run py machines check; t "SDLC_MACHINES missing: check exit 1" rc_is 1
run py machines list;  t "SDLC_MACHINES missing: list exit 1" rc_is 1
ENVX=()
run py machines check --registry "$TMP/nope.yaml"; t "--registry missing: check exit 1" rc_is 1
run py machines list --registry "$TMP/nope.yaml";  t "--registry missing: list exit 1" rc_is 1

if [ ${#BACKENDS[@]} -gt 0 ]; then
  echo "9  XDG_CONFIG_HOME and SDLC_MACHINES"
  mkdir -p "$TMP/xdg/sdlc"; cp "$EXAMPLE" "$TMP/xdg/sdlc/machines.yaml"
  ENVX=(XDG_CONFIG_HOME="$TMP/xdg")
  run $B1 machines list; t "XDG_CONFIG_HOME file is used" has "Registry: $TMP/xdg/sdlc/machines.yaml"
  ENVX=(SDLC_MACHINES="$EXAMPLE" XDG_CONFIG_HOME="$TMP/xdg")
  run $B1 machines check; t "SDLC_MACHINES wins over XDG_CONFIG_HOME" has "Registry: $EXAMPLE"
  ENVX=()

  # ── 10-16 field rules ─────────────────────────────────────────────────────
  echo "10  assignable default"
  box_fixture c10 'role: x'
  run $B1 machines list --registry "$FX/c10.yaml"
  t "no assignable key -> True and shown as yes" bash -c 'echo "$1" | grep -qE "^box +herdr:box +x +yes "' _ "$OUT"
  t "no assignable key -> loader True" pyl $B1 "$FX/c10.yaml" 'b.assignable is True'

  echo "11  12  transport-less machines"
  F11="$(fixture c11 <<'YML'
machines:
  here: {transport: local}
  box: {assignable: false}
YML
)"
  run $B1 machines check --registry "$F11"
  t "transport-less + assignable: false: no error, ok" bash -c '[ "$1" = 0 ]' _ "$RC"
  t "transport-less + assignable: false: box.ok" pyl $B1 "$F11" 'b.ok and not b.assignable'
  F12="$(fixture c12 <<'YML'
machines:
  here: {transport: local}
  box: {role: x}
YML
)"
  run $B1 machines check --registry "$F12"
  t "transport-less + assignable: exit 1 at machines.box.transport" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "^error .*machines.box.transport"' _ "$RC" "$OUT"
  t "transport-less + assignable: box not ok" pyl $B1 "$F12" 'not b.ok'

  echo "13  local machine count"
  F13a="$(fixture c13a <<'YML'
machines:
  box: {transport: {herdr: box}, workdir: /w}
YML
)"
  run $B1 machines check --registry "$F13a"
  t "no local: exit 1 at machines" bash -c '[ "$1" = 1 ] && echo "$2" | grep -qE "^error +machines: no machine has .transport: local"' _ "$RC" "$OUT"
  t "no local: local None, not usable" pyl $B1 "$F13a" 'r.local is None and not r.usable'
  F13b="$(fixture c13b <<'YML'
machines:
  here: {transport: local}
  box: {transport: local}
YML
)"
  run $B1 machines check --registry "$F13b"
  t "two local: exit 1, error names both" bash -c '[ "$1" = 1 ] && echo "$2" | grep -E "^error +machines: " | grep -q "here" && echo "$2" | grep -E "^error +machines: " | grep -q "box"' _ "$RC" "$OUT"
  t "two local: local None, not usable" pyl $B1 "$F13b" 'r.local is None and not r.usable'

  echo "14  machine names"
  for nm in any auto local "bad name" a.b; do
    printf 'machines:\n  here: {transport: local}\n  "%s": {transport: {herdr: x}, workdir: /w}\n' "$nm" > "$FX/c14.yaml"
    run $B1 machines check --registry "$FX/c14.yaml"
    t "name '$nm': exit 1 at machines" bash -c '[ "$1" = 1 ] && echo "$2" | grep -qE "^error +machines: "' _ "$RC" "$OUT"
    t "name '$nm': left out of Registry.machines" "$PY" -c "
import sys; sys.path.insert(0, '$LIB'); import machines
r = machines.load('$FX/c14.yaml'); sys.exit(0 if list(r.machines) == ['here'] else 1)"
  done

  echo "15  D5: busy_flag implies gaming_sensitive"
  for k in 'busy_flag: /x' 'gaming_flag: /x'; do
    box_fixture c15 "$k"
    run $B1 machines check --registry "$FX/c15.yaml"
    t "$k alone: exit 0, no warnings" has "check: ok (errors=0, warnings=0)"
    t "$k alone: flag kept, gaming_sensitive True" pyl $B1 "$FX/c15.yaml" 'b.busy_flag == "/x" and b.gaming_sensitive is True and b.ok'
  done
  box_fixture c15b 'busy_flag: /x' 'gaming_sensitive: false'
  run $B1 machines check --registry "$FX/c15b.yaml"
  t "flag + gaming_sensitive: false: exit 0 with one warning" has "check: ok (errors=0, warnings=1)"
  t "flag + gaming_sensitive: false: loads True" pyl $B1 "$FX/c15b.yaml" 'b.gaming_sensitive is True'
  box_fixture c15c 'gaming_sensitive: true'
  run $B1 machines check --registry "$FX/c15c.yaml"
  t "gaming_sensitive: true, no flag: exit 0 with one warning" has "check: ok (errors=0, warnings=1)"
  box_fixture c15d 'busy_flag: /x' 'gaming_flag: /y'
  run $B1 machines check --registry "$FX/c15d.yaml"
  t "busy_flag and gaming_flag together: exit 1" rc_is 1

  echo "16  workdir warning"
  F16a="$(fixture c16a <<'YML'
machines:
  here: {transport: local}
  box: {transport: {herdr: box}}
YML
)"
  run $B1 machines check --registry "$F16a"
  t "assignable herdr machine without workdir: one warning" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^warning .*machines.box.workdir"' _ "$RC" "$OUT"
  F16b="$(fixture c16b <<'YML'
machines:
  here: {transport: local}
  box: {transport: {herdr: box}, assignable: false}
YML
)"
  run $B1 machines check --registry "$F16b"
  t "unassignable herdr machine without workdir: no warning" has "check: ok (errors=0, warnings=0)"

  # ── 17, 18  broken files [both] ───────────────────────────────────────────
  echo "17  18  broken files"
  printf 'machines: [\n' > "$FX/c17.yaml"
  printf -- '- a\n- b\n' > "$FX/c18a.yaml"
  printf 'machines: {}\n' > "$FX/c18b.yaml"
  : > "$FX/c18c.yaml"
  for be in "${BACKENDS[@]}"; do
    run $be machines check --registry "$FX/c17.yaml"
    t "[$be] unparseable: exit 1, could not parse" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "could not parse"' _ "$RC" "$OUT"
    t "[$be] unparseable: not usable, no machines" pyl $be "$FX/c17.yaml" '(not r.usable) and r.machines == {}'
    for f in c18a c18b c18c; do
      run $be machines check --registry "$FX/$f.yaml"
      t "[$be] $f: exit 1, not usable" bash -c '[ "$1" = 1 ]' _ "$RC"
      t "[$be] $f: loader not usable" pyl $be "$FX/$f.yaml" 'not r.usable'
    done
  done
fi

# ── 19, 20, 21  no backend, slow yq ─────────────────────────────────────────
echo "19  no YAML backend, file present"
OUT=$(env PYTHONPATH="$TMP/noyaml" PATH="$TMP/pybin" "$PY" "$SDLC" machines check --registry "$EXAMPLE" 2>&1); RC=$?
t "no backend: exit 1, names PyYAML and yq" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q PyYAML && echo "$2" | grep -q yq' _ "$RC" "$OUT"
echo "20  no YAML backend, file absent"
OUT=$(env PYTHONPATH="$TMP/noyaml" PATH="$TMP/pybin" "$PY" "$SDLC" machines check 2>&1); RC=$?
t "no backend + no file: inert, exit 0" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^No machine registry at "' _ "$RC" "$OUT"
echo "21  yq trouble"
OUT=$(env PYTHONPATH="$TMP/noyaml" PATH="$TMP/slowyq" "$PY" "$SDLC" machines check --registry "$EXAMPLE" 2>&1); RC=$?
t "slow yq: exit 1 with 'yq timed out'" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "yq timed out"' _ "$RC" "$OUT"
OUT=$(env PYTHONPATH="$TMP/noyaml" PATH="$TMP/badyq" "$PY" "$SDLC" machines check --registry "$EXAMPLE" 2>&1); RC=$?
t "yq prints non-JSON: exit 1 with 'could not parse', no traceback" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "could not parse" && ! echo "$2" | grep -q Traceback' _ "$RC" "$OUT"
t "yq prints non-JSON: load() does not raise" env PYTHONPATH="$LIB:$TMP/noyaml" PATH="$TMP/badyq" "$PY" -c "
import sys, machines
r = machines.load('$EXAMPLE'); sys.exit(0 if (not r.usable and r.errors) else 1)"

# ── 22, 22b  probe ──────────────────────────────────────────────────────────
if [ "$HAVE_YQ" = 1 ] || [ "$HAVE_PYYAML" = 1 ]; then
  echo "22  probe"
  PP="$TMP/fakebin:$TMP/pyyq"
  # PyYAML may be absent from the PATH python only under the yq backend; here it is whatever is installed.
  run_path "$PP" machines check --registry "$EXAMPLE" --probe
  t "probe: example exits 0 with the reachable line" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q "^info .*reachable via herdr:worker-1, 2 agents (limit 4)"' _ "$RC" "$OUT"
  F22a="$(fixture c22a <<'YML'
machines:
  here: {transport: local}
  box: {transport: {herdr: ghost}, workdir: /w}
YML
)"
  run_path "$PP" machines check --registry "$F22a" --probe
  t "probe: unknown label exits 1 with herdr's message" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "herdr probe failed: error: unknown machine"' _ "$RC" "$OUT"
  F22b="$(fixture c22b <<'YML'
machines:
  here: {transport: local}
  box: {transport: {herdr: slow}, workdir: /w}
YML
)"
  run_path "$PP" machines check --registry "$F22b" --probe --timeout 1
  t "probe: hanging herdr exits 1 with 'timed out'" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "timed out"' _ "$RC" "$OUT"

  echo "22b  probe without herdr (only herdr is removed)"
  run_path "$TMP/pyyq" machines check --registry "$EXAMPLE" --probe
  t "no herdr, herdr machine present: exit 1 'herdr not found'" bash -c '[ "$1" = 1 ] && echo "$2" | grep -q "herdr not found"' _ "$RC" "$OUT"
  F22c="$(fixture c22c <<'YML'
machines:
  here: {transport: local}
YML
)"
  run_path "$TMP/pyyq" machines check --registry "$F22c" --probe
  t "no herdr, no herdr machine: exit 0, no herdr error" bash -c '[ "$1" = 0 ] && ! echo "$2" | grep -q herdr' _ "$RC" "$OUT"
fi

# ── 23, 24, 24b, 25 ─────────────────────────────────────────────────────────
echo "23  SECRET_LEVELS"
t "SECRET_LEVELS is (none, dev, prod)" "$PY" -c "
import sys; sys.path.insert(0, '$LIB'); import machines
sys.exit(0 if machines.SECRET_LEVELS == ('none', 'dev', 'prod') else 1)"
if [ ${#BACKENDS[@]} -gt 0 ]; then
  box_fixture c23 'secrets: prod'
  run $B1 machines check --registry "$FX/c23.yaml"
  t "secrets: prod passes" has "check: ok (errors=0, warnings=0)"

  echo "24  --registry on the group parser, and on the leaf"
  run $B1 machines --registry "$EXAMPLE"
  t "machines --registry X lists the example" bash -c '[ "$1" = 0 ] && echo "$2" | grep -q workstation' _ "$RC" "$OUT"
  F24="$(fixture c24 <<'YML'
machines:
  box: {transport: {herdr: box}, workdir: /w}
YML
)"
  run $B1 machines --registry "$F24" check
  t "24b machines --registry <broken> check: exit 1 (group flag survives the leaf)" rc_is 1
  t "24b it checked the broken file" has "Registry: $F24"
  run $B1 machines --registry "$F24" check --registry "$EXAMPLE"
  t "a --registry on the leaf wins" bash -c '[ "$1" = 0 ]' _ "$RC"
fi

# ── 26  the importer contract: load() never raises, never prints; usable needs a good local ──
echo "26  load() contract"
LONG="$(printf 'a%.0s' $(seq 1 5000))"
t "overlong path: load() returns an error Issue, prints nothing" env PYTHONPATH="$LIB" "$PY" -c "
import sys, io, machines
out, err = io.StringIO(), io.StringIO()
sys.stdout, sys.stderr = out, err
r = machines.load('$LONG')
sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
sys.exit(0 if (not r.usable and r.errors and r.errors[0].where == 'registry' and not out.getvalue() and not err.getvalue()) else 1)"
t "unsearchable directory (PermissionError from exists): error Issue, no raise" env PYTHONPATH="$LIB" "$PY" -c "
import sys, pathlib, machines
def boom(self): raise PermissionError(13, 'Permission denied')
pathlib.Path.exists = boom
r = machines.load()
sys.exit(0 if (not r.usable and r.errors and 'Permission denied' in r.errors[0].message) else 1)"
t "catch-all: a bug inside validate becomes an error Issue" env PYTHONPATH="$LIB" "$PY" -c "
import sys, machines
def boom(doc): raise RuntimeError('boom')
machines.validate = boom
r = machines.load('$EXAMPLE')
sys.exit(0 if (not r.usable and r.errors and 'RuntimeError' in r.errors[0].message) else 1)"
t "empty explicit path is an error, not the default" env PYTHONPATH="$LIB" "$PY" -c "
import sys, machines
r = machines.load('')
sys.exit(0 if (r.errors and not r.inert) else 1)"
run py machines check --registry ""
t "--registry '' is refused (never a fallback to the default)" bash -c '[ "$1" != 0 ]' _ "$RC"
for tm in nan inf 0 -1 abc; do
  run py machines check --registry "$EXAMPLE" --probe --timeout "$tm"
  t "--timeout $tm: usage error (exit 2)" rc_is 2
done
if [ ${#BACKENDS[@]} -gt 0 ]; then
  HUGE="$(printf '9%.0s' $(seq 1 400))"
  box_fixture c26h "limits: {mem_gb: $HUGE}"
  for be in "${BACKENDS[@]}"; do
    PYP="$LIB"; PPATH="$PATH"
    [ "$be" = yq ] && { PYP="$LIB:$TMP/noyaml"; PPATH="$TMP/pyyq"; }
    t "[$be] a 400-digit limit: load() returns, not usable-breaking" env PYTHONPATH="$PYP" PATH="$PPATH" "$PY" -c "
import sys, machines
r = machines.load('$FX/c26h.yaml')
sys.exit(0 if (r.errors and not r.machines['box'].ok) else 1)"
    run $be machines check --registry "$FX/c26h.yaml"
    t "[$be] a 400-digit limit: check exits 1 without a traceback" bash -c '[ "$1" = 1 ] && ! echo "$2" | grep -q Traceback' _ "$RC" "$OUT"
    OUT=$(env PYTHONPATH="$PYP" PATH="$PPATH" "$PY" -c "
import machines
for f in ['$EXAMPLE', '$FX/c26h.yaml', '$FX/c17.yaml', '$TMP/nope.yaml']:
    machines.load(f)" 2>&1)
    t "[$be] load() writes nothing to stdout or stderr" bash -c '[ -z "$1" ]' _ "$OUT"
  done

  echo "27  a broken local machine makes the registry unusable"
  F27a="$(fixture c27a <<'YML'
machines:
  here: {transport: local, secrets: staging}
  box: {transport: {herdr: box}, workdir: /w}
YML
)"
  F27b="$(fixture c27b <<'YML'
machines:
  here: {transport: local, asignable: false}
  box: {transport: {herdr: box}, workdir: /w}
YML
)"
  for be in "${BACKENDS[@]}"; do
    for f in "$F27a" "$F27b"; do
      run $be machines check --registry "$f"
      t "[$be] $(basename $f): check exits 1" rc_is 1
      t "[$be] $(basename $f): local is here, not ok, registry not usable" pyl $be "$f" 'r.local is not None and r.local.name == "here" and not r.local.ok and not r.usable and b.ok'
    done
  done

  echo "28  near-miss: case and separators"
  for k in 'ASSIGNABLE: false' 'Assignable: false' 'assign-able: false' 'BusyFlag: /x' 'GAMING_SENSITIVE: true' 'Busy-Flag: /x'; do
    box_fixture c28 "$k"
    for be in "${BACKENDS[@]}"; do
      run $be machines check --registry "$FX/c28.yaml"
      t "[$be] $k: error, exit 1" rc_is 1
    done
    case "$k" in
      *ssignable*|*ASSIGNABLE*|*assign-able*) t "$k: loads not assignable" pyl $B1 "$FX/c28.yaml" 'b.assignable is False and not b.ok' ;;
      *) t "$k: gaming_sensitive loads True" pyl $B1 "$FX/c28.yaml" 'b.gaming_sensitive is True and not b.ok' ;;
    esac
  done

  echo "31  a repeated top-level machines: key"
  F31="$(fixture c31 <<'YML'
machines:
  here: {transport: local}
  ctl: {assignable: false}
machines:
  here: {transport: local}
  ctl: {transport: {herdr: ctl}, workdir: /w}
YML
)"
  for be in "${BACKENDS[@]}"; do
    run $be machines check --registry "$F31"; t "[$be] repeated machines: exit 1" rc_is 1
    t "[$be] repeated machines: no machines, not usable" pyl $be "$F31" 'r.machines == {} and not r.usable'
  done

  echo "32  alias-nested values are bounded in time and message length"
  "$PY" - "$FX/c32.yaml" <<'PYG'
import sys
lines = ["l0: &l0 {a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9}"]
for n in range(1, 8):
    lines.append("l%d: &l%d {%s}" % (n, n, ", ".join("k%d: *l%d" % (i, n - 1) for i in range(9))))
lines += ["machines:", "  here: {transport: local}",
          "  w: {transport: {herdr: w}, workdir: /w, caps: *l7, limits: *l7, keeps: *l7}"]
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PYG
  for be in "${BACKENDS[@]}"; do
    PYP="$LIB"; PPATH="$PATH"; BOUND=2
    # yq expands aliases itself and gives up after YQ_TIMEOUT (2 s), so its bound is that plus slack.
    [ "$be" = yq ] && { PYP="$LIB:$TMP/noyaml"; PPATH="$TMP/pyyq"; BOUND=4; }
    t "[$be] alias bomb: load() returns in under ${BOUND}s, every message <= 300 chars" env PYTHONPATH="$PYP" PATH="$PPATH" "$PY" -c "
import sys, time, machines
t0 = time.time()
r = machines.load('$FX/c32.yaml')
dt = time.time() - t0
longest = max([len(i.message) for i in r.issues] or [0])
sys.exit(0 if (dt < $BOUND and longest <= 300) else 1)"
    t0=$(date +%s%N)
    run $be machines check --registry "$FX/c32.yaml"
    t1=$(date +%s%N)
    t "[$be] alias bomb: check returns in under ${BOUND}s with no traceback" bash -c '[ $(( ($1 - $2) / 1000000 )) -lt $(( $3 * 1000 )) ] && ! echo "$4" | grep -q Traceback' _ "$t1" "$t0" "$BOUND" "$OUT"
    t "[$be] alias bomb: no printed line over 400 chars" bash -c '! echo "$1" | awk "length > 400 {f=1} END {exit !f}"' _ "$OUT"
  done

  echo "29  blank trust keys and duplicate keys"
  for k in 'assignable:' 'gaming_sensitive:' 'busy_flag:' 'gaming_flag:' 'secrets:'; do
    box_fixture c29 "$k"
    for be in "${BACKENDS[@]}"; do
      run $be machines check --registry "$FX/c29.yaml"
      t "[$be] blank $k : error, exit 1" rc_is 1
    done
  done
  box_fixture c29a 'assignable:'
  t "blank assignable loads False" pyl $B1 "$FX/c29a.yaml" 'b.assignable is False and not b.ok'
  box_fixture c29b 'secrets:'
  t "blank secrets loads none, not ok" pyl $B1 "$FX/c29b.yaml" 'b.secrets == "none" and not b.ok'
  box_fixture c29c 'busy_flag:'
  t "blank busy_flag loads gaming_sensitive True, not ok" pyl $B1 "$FX/c29c.yaml" 'b.busy_flag is None and b.gaming_sensitive is True and not b.ok'
  box_fixture c29d 'role:'
  run $B1 machines check --registry "$FX/c29d.yaml"; t "blank role (not a trust key) is just unset" has "check: ok (errors=0, warnings=0)"
  F29e="$(fixture c29e <<'YML'
machines:
  here: {transport: local}
  box:
    transport: {herdr: box}
    workdir: /w
    assignable: false
    assignable: true
YML
)"
  F29f="$(fixture c29f <<'YML'
machines:
  here: {transport: local}
  box:
    transport: {herdr: box}
    workdir: /w
    role: a
    role: b
    limits: {cores: 2, cores: 3}
YML
)"
  F29g="$(fixture c29g <<'YML'
machines:
  here: {transport: local}
  box: {transport: {herdr: box}, workdir: /w}
  box: {transport: {herdr: box}, workdir: /w}
YML
)"
  for be in "${BACKENDS[@]}"; do
    run $be machines check --registry "$F29e"; t "[$be] duplicate assignable: exit 1" rc_is 1
    t "[$be] duplicate assignable: loads False, not ok" pyl $be "$F29e" 'b.assignable is False and not b.ok'
    run $be machines check --registry "$F29f"; t "[$be] duplicate role and limits.cores: exit 1" rc_is 1
    t "[$be] duplicate role/limits: not ok, limits fail closed" pyl $be "$F29f" 'not b.ok and b.limits.cores == 0'
    run $be machines check --registry "$F29g"; t "[$be] duplicate machine name: exit 1, left out" bash -c '[ "$1" = 1 ]' _ "$RC"
    t "[$be] duplicate machine name: box not in registry" pyl $be "$F29g" '"box" not in r.machines'
  done

  echo "30  backend agreement on numbers, names and dates"
  box_fixture c30 'limits: {cores: 010, mem_gb: 1e3, agents: 4.0}' 'role: 2026-01-01'
  for be in "${BACKENDS[@]}"; do
    run $be machines check --registry "$FX/c30.yaml"; t "[$be] 010 / 1e3 / 4.0 / a date: exit 0" has "check: ok (errors=0, warnings=0)"
    t "[$be] 010 is 10, 1e3 is 1000, 4.0 is 4, the date stays a string" pyl $be "$FX/c30.yaml" 'b.limits.cores == 10 and b.limits.mem_gb == 1000 and b.limits.agents == 4 and b.role == "2026-01-01"'
  done
  F30b="$(fixture c30b <<'YML'
machines:
  here: {transport: local}
  123: {transport: {herdr: x}, workdir: /w}
YML
)"
  F30c="$(printf 'machines:\n  here: {transport: local}\n  "box\\n": {transport: {herdr: x}, workdir: /w}\n' > "$FX/c30c.yaml"; echo "$FX/c30c.yaml")"
  for be in "${BACKENDS[@]}"; do
    run $be machines check --registry "$F30b"; t "[$be] digit-only name 123: exit 1, left out" bash -c '[ "$1" = 1 ]' _ "$RC"
    t "[$be] digit-only name left out" pyl $be "$F30b" 'list(r.machines) == ["here"]'
    run $be machines check --registry "$F30c"; t "[$be] name with a trailing newline: exit 1, left out" bash -c '[ "$1" = 1 ]' _ "$RC"
    t "[$be] name with a trailing newline left out" pyl $be "$F30c" 'list(r.machines) == ["here"]'
  done
  box_fixture c30d 'workdir: ""'
  sed -i '0,/    workdir: \/w/{//d}' "$FX/c30d.yaml"
  run $B1 machines check --registry "$FX/c30d.yaml"; t "workdir: '' is an error at machines.box.workdir" bash -c 'echo "$1" | grep -q "^error .*machines.box.workdir"' _ "$OUT"
fi

echo "25  executable"
t "plugin/bin/sdlc is executable" test -x "$SDLC"

echo
echo "machines: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
