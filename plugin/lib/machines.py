"""Machine registry: where agents can run.

The registry is a per-person YAML file kept on the box you coordinate from:
${XDG_CONFIG_HOME:-~/.config}/sdlc/machines.yaml, or $SDLC_MACHINES, or `--registry PATH`.
`transport: local` means *that* box, so do not copy the file to worker boxes.

Rules for importers (the `sdlc` CLI now, the phase-tuning hook in #138): this module prints
nothing, never calls sys.exit, does no I/O at import time, imports `yaml` lazily, and `load()`
never raises on bad input. Every problem becomes an `Issue`. Python >= 3.8, stdlib only.
Set `sys.dont_write_bytecode = True` before importing it, or a __pycache__ lands in the plugin
install directory (bin/sdlc does; the #138 hook must too).

YAML backends: PyYAML (a private strict loader) or yq, with the same booleans, plain decimal
integers, whole floats read as ints, and dates left as strings. Duplicate keys are reported under
both. Known gap: hex (0x10), octal (0o10) and 1_000 are numbers to yq but strings to PyYAML, so write
plain decimals. yq rejects the whole file for .inf, .nan, 0b11 and integers above 2^63.

Consumer contract for placement code (#137 resolve, #139 delegate):

1. The registry as a whole. `Registry.usable` is true only when the file exists, parsed into a
   `machines` map, exactly one machine has a valid `transport: local`, and that local machine is
   `ok`. When `usable` is false, behave as if there were no registry: the resolver keeps
   everything on this box, the hook adds no hint, and `delegate` refuses (its reason is the first
   registry error, or "no registry" when the registry is inert). A file that is broken as a whole
   is inert for placement; `check` still exits 1 on it.
2. Each machine. `Machine.invalid` holds the keys whose values were rejected. A machine with any
   invalid key (`Machine.ok` is false) is never a placement target. Name the keys in the refusal,
   e.g. "machine 'box' has registry errors in: assignable, limits.cores". Other machines are
   unaffected.
3. An invalid value loads as its restrictive fallback, never its default (invalid `assignable`
   loads as False, invalid `gaming_sensitive` as True). So code that forgets `ok` still cannot
   place on a box whose assignability was mistyped. A fallback is not a full guarantee for every
   field: an invalid `busy_flag` loads as unset with `gaming_sensitive: True`, and with no flag
   there is nothing to test, so rely on `ok` for that machine.
4. Warnings never change placement.
5. `Issue.where` tells registry-level problems from per-machine ones:
   "registry", "registry.<key>" or "probe" (file unreadable, unparseable, missing at an explicit path,
   unknown top-level key), "machines" (structure, local-machine count, bad machine name), and
   "machines.<name>[.<key>[.<sub>]]" (one machine's entry). Placement adds a third family
   for `.claude/sdlc.yml`: "sdlc.yml" (file-level) and "sdlc.yml.<key>[.<role>[.<sub>]]" (one entry).
6. Placement never raises and prints nothing. `resolve()` and `lookup()` return a `Placement` for
   any `str` role, even an empty one; `locate()` returns a tuple whose first element is that
   `Placement`. `status` is one of `off`, `placed`, `fallback` or `unplaceable`, and `off_cause`
   says why a placement is `off`. Only `placed` and `fallback` carry a `machine`.
7. `lookup()` time bound. Its file reads finish within `LOOKUP_BUDGET` (2.5 s). With no registry
   file it costs one `stat` and sdlc.yml is never opened. The registry parse is bounded by
   `YQ_TIMEOUT`. If that read took `SDLC_SKIP_AFTER` (1.0 s) or longer, sdlc.yml is not read and the
   result is `off` with `off_cause` "time-budget". Otherwise sdlc.yml is parsed with a timeout of
   min(YQ_TIMEOUT, LOOKUP_BUDGET - elapsed). Worst case with start-up is about 3 s inside the hook's
   5 s. PyYAML parses in-process and ignores the timeout, so the hook must still call `lookup()`
   inside its try/except. `locate(budget=None)` (used by `sdlc machines where`) has no budget.
8. The resolver judges trust and fit only. Load (`limits`, agent counts), busy flags and
   `gaming_sensitive` belong to `delegate` (#139). `Placement.candidates` is fit-ordered, never
   load-ordered.
9. Duplicate placement keys never silently win. A repeated top-level `phase_machines`,
   `agent_machines`, `default_machine`, `needs` or `phases` breaks the config (everything `off`); a
   repeated `needs` role or key makes that role unplaceable; a repeated target makes the role fall
   back. Repeats in keys placement doesn't own are ignored. `Needs.invalid` and
   `PlacementConfig.needs_broken` record needs problems whether or not the file opted in (only the
   `Issue`s are withheld then). A consumer that reads `config.needs` outside `resolve()` (#139's
   `--machine`) MUST refuse when `not config.usable`, when `config.needs_broken` is set, or when
   `not needs.ok` for the role.
"""
from __future__ import annotations

import difflib
import json
import math
import os
import re
import reprlib
import shutil
import subprocess
import time
from collections import Counter
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Callable, Dict, FrozenSet, List, Mapping, Optional, Tuple

REGISTRY_ENV = "SDLC_MACHINES"
DEFAULT_RELPATH = "sdlc/machines.yaml"                  # under ${XDG_CONFIG_HOME:-~/.config}
RESERVED_NAMES = frozenset({"any", "auto", "local"})     # placement keywords (#137, #139) + transport word
NAME_PATTERN = r"[A-Za-z0-9][A-Za-z0-9_-]*"              # fullmatch; no dots: keeps `where` paths unambiguous
SECRET_LEVELS = ("none", "dev", "prod")                  # ordered; #137 compares by index
FIRST_START_GATES = ("trust-prompt", "fullscreen-notice")
PERSISTENCE = ("durable", "disposable")
LIMIT_KEYS = ("cores", "mem_gb", "browser_jobs", "agents")
ALIASES = {"gaming_flag": "busy_flag"}                   # D5
YQ_MEMORY_LIMIT = 1 << 30                                # address-space cap for the yq child (Go needs ~768 MB to start)
YQ_MIN_TIMEOUT = 0.1                                     # a smaller remaining budget is raised to this
YQ_TIMEOUT = 2.0                                         # seconds; the #138 hook is killed at 5 s
NEAR_MISS_CUTOFF = 0.8                                   # difflib ratio at which a fail-closed key typo is an error


class RegistryError(Exception):
    """Raised by parse_yaml; load() converts it to an Issue."""


@dataclass(frozen=True)
class Issue:
    level: str      # "error" | "warning" | "info" (info: CLI passes only)
    where: str      # "registry" | "registry.<key>" | "probe" | "machines" | "machines.<name>[.<key>[.<sub>]]"
    message: str


@dataclass(frozen=True)
class Transport:
    kind: str                       # "local" | "herdr" | "none" (absent or invalid)
    herdr: Optional[str] = None     # label for `herdr --machine <label>`
    ssh: Optional[str] = None       # recorded only; GitHub is the return path

    def describe(self) -> str:
        if self.kind == "local":
            return "local"
        if self.kind == "herdr":
            return "herdr:%s" % self.herdr
        return "-"


@dataclass(frozen=True)
class Limits:
    cores: Optional[int] = None
    mem_gb: Optional[float] = None
    browser_jobs: Optional[int] = None
    agents: Optional[int] = None


@dataclass(frozen=True)
class Machine:
    name: str
    transport: Transport
    workdir: Optional[str] = None
    limits: Limits = field(default_factory=Limits)
    caps: Tuple[str, ...] = ()
    keeps: Tuple[str, ...] = ()
    secrets: str = "none"            # one of SECRET_LEVELS
    gaming_sensitive: bool = False   # True whenever busy_flag is set (D5)
    busy_flag: Optional[str] = None  # raw; #139 expands it and tests existence
    backup: bool = False
    persistence: Optional[str] = None
    role: Optional[str] = None
    assignable: bool = True
    first_start: Tuple[str, ...] = ()
    invalid: FrozenSet[str] = frozenset()   # keys whose value was rejected ("assignable", "limits.cores", ...)

    @property
    def ok(self) -> bool:
        """Not invalid: the only machines placement may target."""
        return not self.invalid

    @property
    def is_local(self) -> bool:
        return self.transport.kind == "local"


@dataclass
class Registry:
    path: Path
    source: str                      # "flag" | "env" | "default"
    exists: bool
    machines: Dict[str, Machine]     # file order; bad/reserved names excluded
    issues: List[Issue]

    @property
    def inert(self) -> bool:
        return self.source == "default" and not self.exists and not self.issues

    @property
    def usable(self) -> bool:
        """Exists, parsed to a machines map, one valid local machine, and that machine is ok."""
        local = self.local
        return self.exists and local is not None and local.ok

    @property
    def errors(self) -> List[Issue]:
        return [i for i in self.issues if i.level == "error"]

    @property
    def warnings(self) -> List[Issue]:
        return [i for i in self.issues if i.level == "warning"]

    @property
    def local(self) -> Optional[Machine]:
        found = [m for m in self.machines.values() if m.is_local]
        return found[0] if len(found) == 1 else None

    def get(self, name: str) -> Optional[Machine]:
        return self.machines.get(name)


# ── path resolution ──────────────────────────────────────────────────────────

def registry_path(explicit: Optional[str] = None,
                  env: Optional[Mapping[str, str]] = None) -> Tuple[Path, str]:
    """Resolve the registry file: --registry, then $SDLC_MACHINES, then the XDG default."""
    if env is None:
        env = os.environ
    home = env.get("HOME") or os.path.expanduser("~")

    def expand(text: str) -> Path:
        if text == "~" or text.startswith("~/"):
            text = home + text[1:]
        return Path(text)

    if explicit is not None:
        return expand(explicit), "flag"
    if env.get(REGISTRY_ENV):
        return expand(env[REGISTRY_ENV]), "env"
    base = env.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    return Path(base) / DEFAULT_RELPATH, "default"


# ── YAML backends ────────────────────────────────────────────────────────────

class _BoundedRepr(reprlib.Repr):
    """reprlib.Repr that also bounds _Map, so a value built from nested aliases prints in constant time."""

    def __init__(self) -> None:
        super().__init__()
        self.maxlevel = 3
        self.maxdict = 4
        self.maxlist = 4
        self.maxstring = 60
        self.maxother = 60

    def repr__Map(self, x: Any, level: int) -> str:
        return self.repr_dict(x, level)


_BOUNDED = _BoundedRepr()


def _r(value: Any) -> str:
    """A short repr of a user value for messages. Never walks more than a few entries."""
    return _BOUNDED.repr(value)


class _Map(dict):
    """A parsed mapping that remembers keys written more than once (`dups`) and the earlier values (`shadowed`)."""
    dups = ()
    shadowed = ()       # ((key, earlier value), ...) for repeated keys, in file order

    def __repr__(self) -> str:
        return _r(self)


def _pairs_to_map(pairs: Any) -> "_Map":
    out = _Map()
    seen = set()
    dups = []
    shadowed = []
    for key, value in pairs:
        if key in seen:
            if key not in dups:
                dups.append(key)
            shadowed.append((key, out[key]))
        seen.add(key)
        out[key] = value
    if dups:
        out.dups = tuple(dups)
        out.shadowed = tuple(shadowed)
    return out


def _normalise_numbers(doc: Any, seen: Optional[set] = None) -> Any:
    """Make both backends agree on numbers: a whole float (4.0, 1e3) becomes an int."""
    if seen is None:
        seen = set()
    if isinstance(doc, float):
        return int(doc) if math.isfinite(doc) and doc == int(doc) else doc
    if isinstance(doc, (dict, list)):
        if id(doc) in seen:
            return doc
        seen.add(id(doc))
        if isinstance(doc, dict):
            for k in list(doc):
                doc[k] = _normalise_numbers(doc[k], seen)
        else:
            for i, v in enumerate(doc):
                doc[i] = _normalise_numbers(v, seen)
    return doc


_BOOL_TAG = "tag:yaml.org,2002:bool"
_INT_TAG = "tag:yaml.org,2002:int"
_FLOAT_TAG = "tag:yaml.org,2002:float"
_TS_TAG = "tag:yaml.org,2002:timestamp"
_MAP_TAG = "tag:yaml.org,2002:map"
_MERGE_TAG = "tag:yaml.org,2002:merge"


def _strict_loader(yaml: Any) -> Any:
    """A SafeLoader that reads the YAML subset the registry uses the way yq does.

    - Booleans are only true/True/TRUE/false/False/FALSE (YAML 1.2 core). Stock PyYAML reads
      yes/no/on/off as booleans, and the key `on:` as True; yq does not.
    - Integers are plain decimal (010 is 10, not octal 8). Floats follow the 1.2 core pattern
      (1e3 is a number). Timestamps are not resolved (a date stays a string).
    - Scalar mapping keys are kept as their text, as in yq's JSON (a key `123:` is "123").
    - A mapping that repeats a key is returned as a _Map whose `dups` names the repeats.
    SafeLoader itself is not mutated.
    """
    drop = (_BOOL_TAG, _INT_TAG, _FLOAT_TAG, _TS_TAG)

    class StrictLoader(yaml.SafeLoader):
        def construct_mapping(self, node, deep=False):  # type: ignore
            if not all(isinstance(k, yaml.ScalarNode) for k, _ in node.value):
                return super().construct_mapping(node, deep=deep)
            written = [k.value for k, _ in node.value if k.tag != _MERGE_TAG]
            self.flatten_mapping(node)
            pairs = [(k.value, self.construct_object(v, deep=deep)) for k, v in node.value]
            out = _pairs_to_map(pairs)
            counts = Counter(written)
            repeated = tuple(dict.fromkeys(k for k in written if counts[k] > 1))
            out.dups = repeated
            # A merge key (`<<: *base`) followed by an explicit key is standard YAML override, not a repeat:
            # keep only what the file wrote twice, so PyYAML and yq agree.
            out.shadowed = tuple((k, v) for k, v in out.shadowed if k in repeated)
            return out

        def construct_yaml_map(self, node):  # type: ignore
            data = _Map()
            yield data
            value = self.construct_mapping(node)
            data.update(value)
            data.dups = value.dups
            data.shadowed = value.shadowed

    StrictLoader.yaml_implicit_resolvers = {
        ch: [(tag, rx) for (tag, rx) in resolvers if tag not in drop]
        for ch, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }
    StrictLoader.add_implicit_resolver(
        _BOOL_TAG, re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF"))
    StrictLoader.add_implicit_resolver(_INT_TAG, re.compile(r"^[-+]?[0-9]+$"), list("-+0123456789"))
    StrictLoader.add_implicit_resolver(
        _FLOAT_TAG,
        re.compile(r"^(?:[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?"
                   r"|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$"),
        list("-+0123456789."))
    StrictLoader.add_constructor(_INT_TAG, lambda loader, node: int(loader.construct_scalar(node)))
    StrictLoader.add_constructor(_MAP_TAG, StrictLoader.construct_yaml_map)
    return StrictLoader


def _first_line(text: str) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def parse_yaml(path: Path, timeout: Optional[float] = None) -> object:
    """Parse `path` with PyYAML (strict loader), else yq, else raise RegistryError.

    Duplicate keys: PyYAML reports them (mapping._Map.dups). yq 4 keeps every repeated key in its
    JSON output, so they are reported there too (checked with yq 4.44.3). A future yq that drops
    repeats would leave that check silent; the test suite notices.

    `timeout` bounds the yq run (None: YQ_TIMEOUT); PyYAML parses in-process and ignores it.
    """
    limit = YQ_TIMEOUT if timeout is None else max(float(timeout), YQ_MIN_TIMEOUT)
    try:
        import yaml  # type: ignore
    except ImportError:
        yaml = None
    if yaml is not None:
        try:
            with open(str(path), "r", encoding="utf-8") as fh:
                return _normalise_numbers(yaml.load(fh, Loader=_strict_loader(yaml)))
        except OSError as exc:
            raise RegistryError("could not read %s: %s" % (path, exc.strerror or exc))
        except UnicodeDecodeError as exc:
            raise RegistryError("could not read %s: %s" % (path, exc))
        except Exception as exc:  # YAMLError, or a constructor ValueError (e.g. an absurdly long integer)
            raise RegistryError("could not parse %s: %s" % (path, _first_line(str(exc)) or type(exc).__name__))
    if shutil.which("yq") is None:
        raise RegistryError(
            "reading %s needs PyYAML (pip install pyyaml) or yq (mikefarah v4) on PATH" % path)
    extra: Dict[str, Any] = {}
    try:
        import resource  # POSIX only; without it yq runs unlimited
        extra["preexec_fn"] = lambda: resource.setrlimit(resource.RLIMIT_AS, (YQ_MEMORY_LIMIT, YQ_MEMORY_LIMIT))
    except ImportError:
        pass
    try:
        proc = subprocess.run(["yq", "-o=json", ".", str(path)], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=limit, **extra)
    except subprocess.TimeoutExpired:
        raise RegistryError("yq timed out after %gs reading %s" % (limit, path))
    except (OSError, subprocess.SubprocessError) as exc:      # incl. a setrlimit failure in the child: fail closed
        raise RegistryError("could not run yq on %s: %s" % (path, exc))
    if proc.returncode != 0:
        raise RegistryError("could not parse %s: %s" % (path, _first_line(proc.stderr) or "yq failed"))
    try:
        return _normalise_numbers(json.loads(proc.stdout, object_pairs_hook=_pairs_to_map))
    except (ValueError, RecursionError):
        raise RegistryError("could not parse %s: yq printed output that is not JSON" % path)


# ── schema ───────────────────────────────────────────────────────────────────

class _Bad(Exception):
    """A checker rejects a value; the message says what was expected."""


def _check_bool(v: Any) -> bool:
    if isinstance(v, bool):
        return v
    raise _Bad("must be true or false (yes/no/on/off, 1 and quoted strings are not booleans), got %s" % (_r(v),))


def _check_str(v: Any) -> str:
    if isinstance(v, str):
        return v
    raise _Bad("must be a string, got %s" % (_r(v),))


def _check_path(v: Any) -> str:
    if isinstance(v, str) and v.strip():
        return v
    raise _Bad("must be a non-empty path string, got %s" % (_r(v),))


def _check_strlist(v: Any) -> Tuple[str, ...]:
    if not isinstance(v, list):
        raise _Bad("must be a list of non-empty strings, got %s" % (_r(v),))
    for item in v:
        if not (isinstance(item, str) and item.strip()):
            raise _Bad("must be a list of non-empty strings, got item %s" % (_r(item),))
    return tuple(v)


def _enum(values: Tuple[str, ...]) -> Callable[[Any], str]:
    def check(v: Any) -> str:
        if isinstance(v, str) and v in values:
            return v
        raise _Bad("must be one of %s, got %s" % (", ".join(values), _r(v)))
    return check


def _check_gates(v: Any) -> Tuple[str, ...]:
    if not isinstance(v, list):
        raise _Bad("must be a list of %s, got %s" % (" and/or ".join(FIRST_START_GATES), _r(v)))
    for item in v:
        if not (isinstance(item, str) and item in FIRST_START_GATES):
            raise _Bad("has unknown first-start gate %s; known: %s" % (_r(item), ", ".join(FIRST_START_GATES)))
    return tuple(v)


@dataclass(frozen=True)
class FieldSpec:
    default: Any                     # value when the key is absent or null
    fallback: Any                    # value when the key is rejected: always the restrictive choice
    check: Optional[Callable[[Any], Any]]   # None: handled by special code (transport, limits)
    fail_closed: bool = False        # a near-miss spelling of this key (ratio >= NEAR_MISS_CUTOFF) is an error


# The schema is one table: #137 reads it, and unknown-key detection and did-you-mean come from it.
SCHEMA: Dict[str, FieldSpec] = {
    "transport": FieldSpec(None, None, None),
    "workdir": FieldSpec(None, None, _check_path),
    "limits": FieldSpec(None, None, None),
    "caps": FieldSpec((), (), _check_strlist),
    "keeps": FieldSpec((), (), _check_strlist),
    "secrets": FieldSpec("none", "none", _enum(SECRET_LEVELS)),
    "gaming_sensitive": FieldSpec(False, True, _check_bool, fail_closed=True),
    "busy_flag": FieldSpec(None, None, _check_path, fail_closed=True),
    "backup": FieldSpec(False, False, _check_bool),
    "persistence": FieldSpec(None, "disposable", _enum(PERSISTENCE)),
    "role": FieldSpec(None, None, _check_str),
    "assignable": FieldSpec(True, False, _check_bool, fail_closed=True),
    "first_start": FieldSpec((), (), _check_gates),
}
KNOWN_KEYS = tuple(SCHEMA) + tuple(ALIASES)


def _is_int(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_num(v: Any) -> bool:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return False
    try:
        return math.isfinite(v)
    except OverflowError:  # an integer too large for a float
        return False


_LIMIT_RULES = {
    "cores": (lambda v: _is_int(v) and v > 0, "a whole number > 0"),
    "mem_gb": (lambda v: _is_num(v) and v > 0, "a number > 0"),
    "browser_jobs": (lambda v: _is_int(v) and v >= 0, "a whole number >= 0"),
    "agents": (lambda v: _is_int(v) and v >= 0, "a whole number >= 0"),
}


MESSAGE_CAP = 300       # characters in any message or output line
LIST_SHOWN = 10         # entries of a list shown before "(+k more)"


def cap_text(text: str, n: int = MESSAGE_CAP) -> str:
    """A pasted value must not become a wall of text."""
    return text if len(text) <= n else text[:n - 3] + "..."


def shown_list(items: Any, n: int = LIST_SHOWN) -> str:
    """The first `n` items joined with commas, then "(+k more)"."""
    items = list(items)
    more = " (+%d more)" % (len(items) - n) if len(items) > n else ""
    return ", ".join(str(i) for i in items[:n]) + more


def _issue(out: List[Issue], level: str, where: str, message: str) -> None:
    out.append(Issue(level, where, cap_text(message)))


def _transport(value: Any, base: str, out: List[Issue], invalid: set) -> Transport:
    """Validate `transport`. Any error gives kind `none`."""
    if isinstance(value, str) and value == "local":
        return Transport("local")
    if not isinstance(value, dict):
        _issue(out, "error", base, "transport must be 'local' or a map {herdr: <label>, ssh: <target>}, got %s" % (_r(value),))
        invalid.add("transport")
        return Transport("none")
    bad = False
    label = value.get("herdr")
    if not (isinstance(label, str) and label.strip()):
        _issue(out, "error", base, "transport map needs a non-empty string 'herdr' label (see `herdr machine list`)")
        invalid.add("transport")
        bad = True
    ssh = value.get("ssh")
    if ssh is not None and not isinstance(ssh, str):
        _issue(out, "error", base + ".ssh", "transport.ssh must be a string, got %s" % (_r(ssh),))
        invalid.add("transport.ssh")
        bad = True
    for key in value:
        if key not in ("herdr", "ssh"):
            _issue(out, "warning", "%s.%s" % (base, key), "unknown transport key %s" % (_r(key),))
    if bad:
        return Transport("none")
    return Transport("herdr", herdr=label, ssh=ssh)


def _limits(value: Any, base: str, out: List[Issue], invalid: set) -> Limits:
    if value is None:
        return Limits()
    if not isinstance(value, dict):
        _issue(out, "error", base, "limits must be a map of %s, got %s" % (", ".join(LIMIT_KEYS), _r(value)))
        invalid.add("limits")
        return Limits(0, 0, 0, 0)
    got: Dict[str, Any] = {}
    for key, v in value.items():
        if key not in _LIMIT_RULES:
            _issue(out, "warning", "%s.%s" % (base, key), "unknown limit %s; known: %s" % (_r(key), ", ".join(LIMIT_KEYS)))
            continue
        if v is None:
            continue
        test, what = _LIMIT_RULES[key]
        if test(v):
            got[key] = v
        else:
            _issue(out, "error", "%s.%s" % (base, key), "limits.%s must be %s, got %s" % (key, what, _r(v)))
            invalid.add("limits.%s" % key)
            got[key] = 0
    return Limits(**got)


# Keys whose absence means a safe default but whose blank value must not: a blank value is an
# error and takes the restrictive fallback (`assignable:` with nothing after it is not "true").
TRUST_KEYS = ("assignable", "gaming_sensitive", "busy_flag", "secrets")


def _norm_key(text: str) -> str:
    return text.lower().replace("-", "_")


def _has_dups(value: Any, seen: Optional[set] = None) -> bool:
    if seen is None:
        seen = set()
    if id(value) in seen:
        return False
    seen.add(id(value))
    if isinstance(value, _Map) and value.dups:
        return True
    items = value.values() if isinstance(value, dict) else value if isinstance(value, list) else ()
    return any(_has_dups(v, seen) for v in items)


def _machine(name: str, raw: Any, out: List[Issue]) -> Machine:
    base = "machines.%s" % name
    invalid: set = set()
    if raw is None:
        raw = {}
    if not isinstance(raw, dict):
        _issue(out, "error", base, "machine entry must be a map of keys, got %s" % (_r(raw),))
        return Machine(name, Transport("none"), secrets="none", gaming_sensitive=True, assignable=False,
                       persistence="disposable", limits=Limits(0, 0, 0, 0), invalid=frozenset({"entry"}))

    # Collect the keys as written, folding aliases. A null value means "unset", except for TRUST_KEYS.
    present: Dict[str, Any] = {}
    written: Dict[str, str] = {}       # canonical key -> the spelling in the file (for messages)
    unknown: List[str] = []
    flag_keys: List[str] = []
    forced: Dict[str, str] = {}        # canonical key -> why it is rejected without looking at its value
    for key, value in raw.items():
        canon = ALIASES.get(key, key)
        if canon in SCHEMA:
            written[canon] = key
            if canon == "busy_flag":
                flag_keys.append(key)
            if value is None:
                if canon in TRUST_KEYS:
                    forced[canon] = "must not be blank"
                    present[canon] = None
            else:
                present[canon] = value
        else:
            unknown.append(str(key))
    for key in getattr(raw, "dups", ()):
        canon = ALIASES.get(key, key)
        forced[canon] = "is written more than once"
        if canon in SCHEMA:
            written.setdefault(canon, key)
        else:
            _issue(out, "error", "%s.%s" % (base, key), "%s is written more than once" % key)
            invalid.add(key)
    for canon in SCHEMA:
        if canon in present and canon not in forced and _has_dups(present[canon]):
            forced[canon] = "contains a key written more than once"

    near_miss_flag = False
    for text in unknown:
        norm = _norm_key(text)
        matches = difflib.get_close_matches(norm, KNOWN_KEYS, n=3)
        first = matches[0] if matches else None
        canon = ALIASES.get(first, first) if first else None
        if (first is not None and SCHEMA[canon].fail_closed
                and difflib.SequenceMatcher(None, norm, first).ratio() >= NEAR_MISS_CUTOFF):
            _issue(out, "error", "%s.%s" % (base, text),
                   "unknown key %s looks like a misspelling of %s; fix it (the restrictive value is used meanwhile)"
                   % (_r(text), _r(first)))
            invalid.add(canon)
            if canon == "busy_flag":
                near_miss_flag = True
        else:
            hint = "; did you mean %s?" % _r(first) if first else ""
            _issue(out, "warning", "%s.%s" % (base, text), "unknown key %s%s" % (_r(text), hint))

    # Plain keys, through the table.
    values: Dict[str, Any] = {}
    for key, spec in SCHEMA.items():
        if spec.check is None:
            continue
        label = written.get(key, key)
        if key in forced:
            _issue(out, "error", "%s.%s" % (base, label), "%s %s" % (label, forced[key]))
            invalid.add(key)
            values[key] = spec.fallback
        elif key not in present:
            values[key] = spec.default
        else:
            try:
                values[key] = spec.check(present[key])
            except _Bad as exc:
                _issue(out, "error", "%s.%s" % (base, label), "%s %s" % (label, exc))
                invalid.add(key)
                values[key] = spec.fallback

    # Derived rules read the value as written, not the fallback: "assignable is false" means
    # it was written as a valid false.
    written_unassignable = present.get("assignable") is False and "assignable" not in forced

    # transport: an invalid value gives one error; "missing" applies only when the key is absent.
    if "transport" in forced:
        _issue(out, "error", base + ".transport", "transport %s" % forced["transport"])
        invalid.add("transport")
        transport = Transport("none")
    elif "transport" in present:
        transport = _transport(present["transport"], base + ".transport", out, invalid)
    else:
        transport = Transport("none")
        if not written_unassignable:
            _issue(out, "error", base + ".transport",
                   "transport is missing; an assignable machine needs 'local' or {herdr: <label>}, "
                   "or set assignable: false")
            invalid.add("transport")
    if "limits" in forced:
        _issue(out, "error", base + ".limits", "limits %s" % forced["limits"])
        invalid.add("limits")
        limits = Limits(0, 0, 0, 0)
    else:
        limits = _limits(present.get("limits"), base + ".limits", out, invalid)

    if transport.kind == "herdr" and not written_unassignable and "workdir" not in present:
        _issue(out, "warning", base + ".workdir",
               "workdir is not set; `sdlc delegate` will need it to start agents on this machine")

    # D5: busy_flag (alias gaming_flag) implies gaming_sensitive.
    if len(flag_keys) > 1:
        _issue(out, "error", base + ".busy_flag", "busy_flag and gaming_flag are the same setting; set only one")
        invalid.add("busy_flag")
        values["busy_flag"] = None
    flag_written = bool(flag_keys) or near_miss_flag
    flag_valid = values.get("busy_flag") is not None and "busy_flag" not in invalid
    gs_written = present.get("gaming_sensitive")
    if gs_written is True and not flag_written and "gaming_sensitive" not in forced:
        _issue(out, "warning", base + ".gaming_sensitive",
               "gaming_sensitive is true but there is no busy_flag, so there is nothing to check")
    if gs_written is False and flag_valid and "gaming_sensitive" not in forced:
        _issue(out, "warning", base + ".gaming_sensitive",
               "gaming_sensitive: false is ignored because busy_flag is set (it implies true)")
    gaming = bool(values["gaming_sensitive"]) or flag_written or bool(invalid & {"gaming_sensitive", "busy_flag"})
    assignable = bool(values["assignable"]) and "assignable" not in invalid

    return Machine(
        name=name, transport=transport, workdir=values["workdir"], limits=limits,
        caps=values["caps"], keeps=values["keeps"], secrets=values["secrets"],
        gaming_sensitive=gaming, busy_flag=values["busy_flag"], backup=values["backup"],
        persistence=values["persistence"], role=values["role"], assignable=assignable,
        first_start=values["first_start"], invalid=frozenset(invalid),
    )


def validate(doc: object) -> Tuple[Dict[str, Machine], List[Issue]]:
    """Validate a parsed registry document. Pure: no I/O."""
    issues: List[Issue] = []
    machines: Dict[str, Machine] = {}
    if not isinstance(doc, dict):
        _issue(issues, "error", "machines", "registry must be a map with a top-level 'machines' map, got %s" %
               ("an empty file" if doc is None else type(doc).__name__))
        return machines, issues
    for key in doc:
        if key != "machines":
            _issue(issues, "warning", "registry.%s" % (key,), "unknown top-level key %s" % (_r(key),))
    for key in getattr(doc, "dups", ()):
        _issue(issues, "error", "registry.%s" % (key,), "top-level key %s is written more than once" % (_r(key),))
    if "machines" in getattr(doc, "dups", ()):
        _issue(issues, "error", "machines", "the 'machines' key is written more than once; no machines are loaded")
        return machines, issues
    entries = doc.get("machines")
    if not isinstance(entries, dict) or not entries:
        _issue(issues, "error", "machines", "registry needs a non-empty 'machines' map")
        return machines, issues
    repeated = set(getattr(entries, "dups", ()))
    for name in sorted(repeated, key=str):
        _issue(issues, "error", "machines", "machine name %s is written more than once; it is left out" % (_r(name),))
    pattern = re.compile(NAME_PATTERN)
    for name, raw in entries.items():
        if name in repeated:
            continue
        if not isinstance(name, str) or not pattern.fullmatch(name) or name.isdigit():
            _issue(issues, "error", "machines",
                   "machine name %s is not allowed: use letters, digits, '-' and '_', starting with a letter or "
                   "digit, and not digits only (YAML would read it as a number)" % (_r(name),))
            continue
        if name in RESERVED_NAMES:
            _issue(issues, "error", "machines",
                   "machine name %s is reserved (%s)" % (_r(name), ", ".join(sorted(RESERVED_NAMES))))
            continue
        machines[name] = _machine(name, raw, issues)
    locals_ = [m.name for m in machines.values() if m.is_local]
    if not locals_:
        _issue(issues, "error", "machines", "no machine has `transport: local`; mark the box you run Claude Code on")
    elif len(locals_) > 1:
        _issue(issues, "error", "machines",
               "more than one machine has `transport: local` (%s); exactly one box is 'here'" % ", ".join(locals_))
    return machines, issues


def load(explicit: Optional[str] = None,
         env: Optional[Mapping[str, str]] = None) -> Registry:
    """Locate, parse and validate the registry. Never raises: any failure becomes an error Issue."""
    path, source, exists = Path(explicit or "."), "flag" if explicit is not None else "default", False
    try:
        if explicit == "":
            return Registry(Path(""), "flag", False, {},
                            [Issue("error", "registry", "--registry was given an empty path")])
        path, source = registry_path(explicit, env)
        try:
            exists = path.exists()
        except (OSError, ValueError) as exc:
            return Registry(path, source, False, {}, [Issue(
                "error", "registry", "cannot access %s: %s" % (path, getattr(exc, "strerror", None) or exc))])
        if not exists:
            issues: List[Issue] = []
            if source != "default":
                _issue(issues, "error", "registry", "registry file not found: %s (from %s)" %
                       (path, "--registry" if source == "flag" else "$" + REGISTRY_ENV))
            return Registry(path, source, False, {}, issues)
        try:
            doc = parse_yaml(path)
        except RegistryError as exc:
            return Registry(path, source, True, {}, [Issue("error", "registry", str(exc))])
        machines, issues = validate(doc)
        return Registry(path, source, True, machines, issues)
    except Exception as exc:  # last resort: importers rely on load() never raising
        return Registry(path, source, exists, {}, [Issue(
            "error", "registry", "internal error reading the registry: %s: %s" % (type(exc).__name__, exc))])


# ── placement (#137) ─────────────────────────────────────────────────────────

SDLC_RELPATH = ".claude/sdlc.yml"
PROJECT_ENV = "CLAUDE_PROJECT_DIR"
KINDS = ("phase", "agent")
PLACEMENT_KEYWORDS = ("any", "local")           # `auto` is #139's --machine auto; refused in sdlc.yml
PLACEMENT_KEYS = ("phase_machines", "agent_machines", "default_machine", "needs", "phases")   # a problem with one of these as a whole is block-level
NEEDS_KEYS = ("caps", "keeps", "secrets")
LOOKUP_BUDGET = 2.5                             # seconds for lookup()'s file reads (the hook is killed at 5 s)
SDLC_SKIP_AFTER = 1.0                           # a registry read this slow: lookup() doesn't read sdlc.yml


@dataclass(frozen=True)
class Needs:
    caps: Tuple[str, ...] = ()
    keeps: Tuple[str, ...] = ()
    secrets: str = "none"                       # a floor: the machine must hold at least this level
    invalid: FrozenSet[str] = frozenset()       # "entry" | "caps" | "keeps" | "secrets" | an unknown or repeated key as written

    @property
    def ok(self) -> bool:
        return not self.invalid


@dataclass(frozen=True)
class Requested:
    value: Optional[str]                        # the target as written; None when the value was rejected
    at: str                                     # "phases.<role>.machine" | "phase_machines.<role>" | "agent_machines.<role>" | "default_machine"
    error: Optional[str] = None                 # why it can't be used (not a string, `auto`, written more than once)


@dataclass
class PlacementConfig:
    path: Optional[Path]                        # the sdlc.yml read; None when none was found
    source: str                                 # "flag" | "project" | "env" | "search" | "none"
    exists: bool
    phases: Dict[str, Requested]                # grouped phases.<role>.machine over flat phase_machines.<role>
    agents: Dict[str, Requested]                # agent_machines.<role>
    default: Optional[Requested]                # default_machine; None when unset or blank
    needs: Dict[str, Needs]
    issues: List[Issue]                         # where: "sdlc.yml" | "sdlc.yml.<key>[.<role>[.<sub>]]"
    broken: bool = False                        # a file- or block-level error, incl. a repeated top-level placement key
    opted_in: bool = False                      # sets at least one target
    needs_broken: bool = False                  # top-level `needs` repeated or malformed, whether or not opted in

    @property
    def usable(self) -> bool:
        return not self.broken

    def roles(self) -> List[Tuple[str, Optional[str]]]:
        """(role, kind), each role once: phases, then agents, then roles named only in needs."""
        out: List[Tuple[str, Optional[str]]] = [(r, "phase") for r in self.phases]
        out += [(r, "agent") for r in self.agents if r not in self.phases]
        out += [(r, None) for r in self.needs if r not in self.phases and r not in self.agents]
        return out


@dataclass(frozen=True)
class Placement:
    role: str                                   # namespace stripped
    kind: Optional[str]                         # "phase" | "agent" | None
    status: str                                 # "off" | "placed" | "fallback" | "unplaceable"
    off_cause: Optional[str]                    # when status == "off": "no-registry" | "registry-errors" | "sdlc-errors" | "no-placement" | "time-budget"
    machine: Optional[str]                      # set only for "placed" and "fallback"
    candidates: Tuple[str, ...]                 # fitting machines of the winning target; `any`: local first, then file order
    local: bool                                 # runs on this box
    requested: Optional[Requested]              # the role's own placement; None when it has none
    rejected: Tuple[Tuple[str, str], ...]       # (machine name, or target as written when no machine was judged; why)
    reason: str                                 # one line, always set
    target: Optional[str] = None                # the winning target as written ("any", "local" or a name)


def _w(*parts: str) -> str:
    return ".".join(("sdlc.yml",) + tuple(parts))


def strip_role(text: str) -> str:
    """`sdlc:validator` -> `validator`: the role name without its plugin namespace."""
    return text.rsplit(":", 1)[-1].strip()


def _blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def _mk(level: str, where: str, message: str) -> Issue:
    """An Issue whose message is capped like the registry's."""
    out: List[Issue] = []
    _issue(out, level, where, message)
    return out[0]


def _new_config(path: Optional[Path], source: str, exists: bool) -> PlacementConfig:
    return PlacementConfig(path, source, exists, {}, {}, None, {}, [])


def _broken(path: Optional[Path], source: str, exists: bool, message: str) -> PlacementConfig:
    cfg = _new_config(path, source, exists)
    _issue(cfg.issues, "error", "sdlc.yml", message)
    cfg.broken = True
    return cfg


def sdlc_path(explicit: Optional[str] = None, *, project_dir: Optional[str] = None,
              env: Optional[Mapping[str, str]] = None,
              cwd: Optional[str] = None) -> Tuple[Optional[Path], str]:
    """Find sdlc.yml: --config, then project_dir, then $CLAUDE_PROJECT_DIR, then walk up from cwd.

    The first three return the path without checking it; the walk-up returns the first
    `.claude/sdlc.yml` that is a file, stopping after a directory that holds `.git`, or None.
    """
    if env is None:
        env = os.environ
    home = env.get("HOME") or os.path.expanduser("~")
    if explicit is not None:
        text = explicit
        if text == "~" or text.startswith("~/"):
            text = home + text[1:]
        return Path(text), "flag"
    if project_dir:
        return Path(project_dir) / SDLC_RELPATH, "project"
    if env.get(PROJECT_ENV):
        return Path(env[PROJECT_ENV]) / SDLC_RELPATH, "env"
    try:
        here = Path(cwd) if cwd else Path(os.getcwd())
        for directory in [here] + list(here.parents):
            candidate = directory / SDLC_RELPATH
            if candidate.is_file():
                return candidate, "search"
            if (directory / ".git").exists():
                break
    except (OSError, ValueError):
        pass
    return None, "none"


# ── reading sdlc.yml ─────────────────────────────────────────────────────────

def _target(value: Any, at: str, soft: List[Issue]) -> Requested:
    """Read one target (not blank). Problems become an error Issue and Requested.error."""
    if isinstance(value, str):
        text = value.strip()
        if text == "auto":
            msg = "'auto' is reserved for `sdlc delegate --machine auto`; write 'any' to let any fitting machine take it"
            soft.append(_mk("error", _w(at), msg))
            return Requested(None, at, msg)
        return Requested(text, at)
    msg = "must be a machine name, 'local' or 'any', got %s" % _r(value)
    soft.append(_mk("error", _w(at), msg))
    return Requested(None, at, msg)


def _entries(block: Any, name: str, soft: List[Issue]) -> Tuple[List[str], Dict[str, Any], set]:
    """Normalise a role-keyed block: (roles in file order, role -> last value, roles written more than once)."""
    order: List[str] = []
    values: Dict[str, Any] = {}
    repeated: set = set()
    for key, value in block.items():
        if not isinstance(key, str) or not strip_role(key):
            soft.append(_mk("error", _w(name), "a role key must be a non-empty string, got %s" % _r(key)))
            continue
        role = strip_role(key)
        if role != key:
            soft.append(_mk("warning", _w(name, key),
                              "role keys are written without the plugin prefix: %s is read as %s" % (_r(key), _r(role))))
        if role in values:
            repeated.add(role)
        else:
            order.append(role)
        values[role] = value
    for key in getattr(block, "dups", ()):
        if isinstance(key, str) and strip_role(key):
            repeated.add(strip_role(key))
    return order, values, repeated


def _needs_entry(role: str, value: Any, repeated: bool, soft: List[Issue]) -> Needs:
    base = _w("needs", role)
    invalid: set = set()
    caps: Tuple[str, ...] = ()
    keeps: Tuple[str, ...] = ()
    secrets = "none"

    def err(where: str, message: str, key: str) -> None:
        soft.append(_mk("error", where, message))
        invalid.add(key)

    if repeated:
        err(base, "needs for %s is written more than once; the role is unplaceable until it is written once" % _r(role), "entry")
    elif value is None:
        err(base, "needs.%s must not be blank (it is a requirement; write [] for none)" % role, "entry")
    elif isinstance(value, list):
        try:
            caps = _check_strlist(value)
        except _Bad as exc:
            err(base, "needs.%s %s" % (role, exc), "caps")
    elif isinstance(value, dict):
        dups = set(getattr(value, "dups", ()))
        for key, v in value.items():
            if key in NEEDS_KEYS:
                label = _w("needs", role, key)
                if key in dups:
                    err(label, "needs.%s.%s is written more than once" % (role, key), key)
                elif _has_dups(v):
                    err(label, "needs.%s.%s contains a key written more than once" % (role, key), key)
                elif v is None:
                    err(label, "needs.%s.%s must not be blank" % (role, key), key)
                else:
                    try:
                        if key == "secrets":
                            secrets = _enum(SECRET_LEVELS)(v)
                        elif key == "caps":
                            caps = _check_strlist(v)
                        else:
                            keeps = _check_strlist(v)
                    except _Bad as exc:
                        err(label, "needs.%s.%s %s" % (role, key, exc), key)
            else:
                text = str(key)
                near = difflib.get_close_matches(_norm_key(text), NEEDS_KEYS, n=1)
                hint = "; did you mean %s?" % _r(near[0]) if near else ""
                err(_w("needs", role, text), "unknown needs key %s%s (every needs key is a requirement, so it is an error)"
                    % (_r(text), hint), text)
    else:
        err(base, "needs.%s must be a list of caps or a map {caps, keeps, secrets}, got %s" % (role, _r(value)), "entry")
    return Needs(caps, keeps, secrets, frozenset(invalid))


def _copies(mapping: Any, key: Any) -> List[Any]:
    """Every value written for `key`, earlier copies first (the parser keeps only the last in the mapping)."""
    out = [v for k, v in getattr(mapping, "shadowed", ()) if k == key]
    if key in mapping:
        out.append(mapping[key])
    return out


def _sets_target(value: Any) -> bool:
    """A phase_machines / agent_machines copy that attempts to place, including a repeat inside it."""
    if isinstance(value, dict):
        if getattr(value, "dups", ()):
            return True
        roles = [strip_role(k) for k in value if isinstance(k, str)]
        return len(roles) != len(set(roles)) or any(not _blank(v) for v in value.values())
    return not _blank(value)


def _opts_in(doc: Any) -> bool:
    """True when the file, as written, sets at least one target, or repeats a key that could have set one.

    Decided from every copy of a repeated key, not only the last one the parser kept: a repeat is an
    attempt to place, and the last copy may be blank.
    """
    dups = set(getattr(doc, "dups", ()))
    for key in ("phase_machines", "agent_machines"):
        if key in dups or any(_sets_target(c) for c in _copies(doc, key)):
            return True
    if "default_machine" in dups or not _blank(doc.get("default_machine")):
        return True
    for phases in _copies(doc, "phases"):
        if not isinstance(phases, dict):
            continue
        for role in phases:
            for value in _copies(phases, role):
                if isinstance(value, dict) and ("machine" in getattr(value, "dups", ()) or not _blank(value.get("machine"))):
                    return True
    return False


def read_placement(doc: object, path: Optional[Path] = None, source: str = "flag") -> PlacementConfig:
    """Validate a parsed sdlc.yml. Pure. Issues are reported only once the file opts in.

    `Needs.invalid` and `needs_broken` are recorded either way: a consumer outside resolve() must
    not be able to miss a dropped requirement just because the file placed nothing.
    """
    cfg = _new_config(path, source if path is not None else "none", path is not None)
    if doc is None:
        doc = {}
    if not isinstance(doc, dict):
        cfg.issues.append(_mk("error", "sdlc.yml", "sdlc.yml must be a map at the top level, got %s" % type(doc).__name__))
        cfg.broken = True
        return cfg
    soft: List[Issue] = []
    soft_broken = False
    dups = set(getattr(doc, "dups", ()))
    cfg.opted_in = _opts_in(doc)

    def block(key: str) -> Optional[dict]:
        nonlocal soft_broken
        if key in dups:
            soft.append(_mk("error", _w(key), "%s is written more than once; no placement applies until it is written once" % key))
            soft_broken = True
        value = doc.get(key)
        if value is None:
            return {}
        if not isinstance(value, dict):
            soft.append(_mk("error", _w(key), "%s must be a map, got %s" % (key, _r(value))))
            soft_broken = True
            return None
        return value

    def flat(key: str) -> Dict[str, Requested]:
        out: Dict[str, Requested] = {}
        raw = block(key)
        if not raw:
            return out
        order, values, repeated = _entries(raw, key, soft)
        for role in order:
            at = "%s.%s" % (key, role)
            if role in repeated:
                soft.append(_mk("error", _w(at), "%s is written more than once" % role))
                out[role] = Requested(None, at, "written more than once")
            elif not _blank(values[role]):
                out[role] = _target(values[role], at, soft)
        return out

    flat_phases = flat("phase_machines")

    grouped: Dict[str, Requested] = {}
    raw_phases = block("phases")
    if raw_phases:
        order, values, repeated = _entries(raw_phases, "phases", soft)
        for role in order:
            at = "phases.%s.machine" % role
            value = values[role]
            if role in repeated:
                # Fails closed: the dropped copy may have set `machine`, even if neither visibly did.
                soft.append(_mk("error", _w("phases", role), "phases.%s is written more than once" % role))
                grouped[role] = Requested(None, at, "written more than once")
            elif isinstance(value, dict):
                if "machine" in getattr(value, "dups", ()):
                    soft.append(_mk("error", _w(at), "machine is written more than once"))
                    grouped[role] = Requested(None, at, "written more than once")
                elif not _blank(value.get("machine")):
                    grouped[role] = _target(value["machine"], at, soft)

    for role in list(flat_phases) + [r for r in grouped if r not in flat_phases]:
        g, f = grouped.get(role), flat_phases.get(role)
        if g is not None:
            cfg.phases[role] = g
            if f is not None and f.error is None and g.error is None and f.value != g.value:
                soft.append(_mk("warning", _w(f.at), "overridden by phases.%s.machine (%s)" % (role, _r(g.value))))
        elif f is not None:
            cfg.phases[role] = f

    cfg.agents = flat("agent_machines")
    for role, req in cfg.agents.items():
        other = cfg.phases.get(role)
        if other is not None and other.error is None and req.error is None and other.value != req.value:
            soft.append(_mk("error", _w(req.at), "%s is placed by %s (%s) and by agent_machines (%s); with no kind the "
                              "phase entry is used" % (role, other.at, _r(other.value), _r(req.value))))

    if "default_machine" in dups:
        soft.append(_mk("error", _w("default_machine"), "default_machine is written more than once"))
        soft_broken = True
    default = doc.get("default_machine")
    if not _blank(default):
        cfg.default = _target(default, "default_machine", soft)

    raw_needs = doc.get("needs")
    if "needs" in dups or (raw_needs is not None and not isinstance(raw_needs, dict)):
        cfg.needs_broken = True
    needs_block = block("needs")
    if needs_block:
        order, values, repeated = _entries(needs_block, "needs", soft)
        for role in order:
            cfg.needs[role] = _needs_entry(role, values[role], role in repeated, soft)

    if cfg.opted_in:
        cfg.issues.extend(soft)
        cfg.broken = soft_broken
    elif doc.get("needs") not in (None, {}):
        cfg.issues.append(_mk("warning", _w("needs"),
                                "needs has no effect until something is placed (set phase_machines, agent_machines, "
                                "default_machine or phases.<role>.machine)"))
    return cfg


def load_placement(explicit: Optional[str] = None, *, project_dir: Optional[str] = None,
                   env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None,
                   timeout: Optional[float] = None) -> PlacementConfig:
    """Find, parse and read sdlc.yml. Never raises: any failure is a broken config."""
    path: Optional[Path] = None
    source = "none"
    try:
        if explicit is not None and not explicit.strip():
            return _broken(None, "flag", False, "--config was given an empty path")
        path, source = sdlc_path(explicit, project_dir=project_dir, env=env, cwd=cwd)
        if path is None:
            return _new_config(None, "none", False)
        try:
            exists = path.is_file()
        except (OSError, ValueError) as exc:
            return _broken(path, source, False, "cannot access %s: %s" % (path, getattr(exc, "strerror", None) or exc))
        if not exists:
            if source == "flag":
                return _broken(path, source, False, "sdlc.yml not found: %s (from --config)" % path)
            return _new_config(path, source, False)
        try:
            doc = parse_yaml(path, timeout)
        except RegistryError as exc:
            return _broken(path, source, True, str(exc))
        return read_placement(doc, path, source)
    except Exception as exc:  # last resort: importers rely on this never raising
        return _broken(path, source, False,
                       "internal error reading sdlc.yml: %s: %s" % (type(exc).__name__, exc))


# ── resolution ───────────────────────────────────────────────────────────────

def unfit_reason(machine: Machine, needs: Needs) -> Optional[str]:
    """None when `machine` fits `needs`; else the first failing filter."""
    if not machine.ok:
        return "machine '%s' has registry errors in: %s" % (machine.name, shown_list(sorted(machine.invalid)))
    if not machine.assignable:
        return "machine '%s' is not assignable" % machine.name
    missing = [c for c in needs.caps if c not in machine.caps]
    if missing:
        return "machine '%s' lacks caps: %s" % (machine.name, shown_list(missing))
    missing = [k for k in needs.keeps if k not in machine.keeps]
    if missing:
        return "machine '%s' lacks keeps: %s" % (machine.name, shown_list(missing))
    have = SECRET_LEVELS.index(machine.secrets) if machine.secrets in SECRET_LEVELS else -1
    need = SECRET_LEVELS.index(needs.secrets) if needs.secrets in SECRET_LEVELS else len(SECRET_LEVELS)
    if have < need:
        return "machine '%s' holds secrets '%s', needs '%s'" % (machine.name, machine.secrets, needs.secrets)
    return None


def _first_error(issues: List[Issue], fallback: str) -> str:
    for issue in issues:
        if issue.level == "error":
            return issue.message
    return fallback


def _off(role: str, kind: Optional[str], cause: str, reason: str) -> Placement:
    return Placement(role, kind, "off", cause, None, (), True, None, (), reason)


def _unknown_name(name: str, registry: Registry) -> str:
    text = "%s is not in the registry" % _r(name)
    near = difflib.get_close_matches(name, list(registry.machines), n=1)
    return text + ("; did you mean %s?" % _r(near[0]) if near else "")


def _own_request(config: PlacementConfig, role: str, kind: Optional[str]) -> Optional[Requested]:
    if kind in (None, "phase") and role in config.phases:
        return config.phases[role]
    if kind in (None, "agent") and role in config.agents:
        return config.agents[role]
    return None


def _default_target(registry: Registry, config: PlacementConfig) -> Tuple[str, Optional[str], Optional[str]]:
    """(target, replaced, why): the default target; when default_machine was replaced by this box,
    how to name it ("default_machine 'x'", or just "default_machine" when it has no usable text); and why."""
    d = config.default
    if d is None:
        return "local", None, None
    if d.error is not None:
        return "local", "default_machine", d.error
    if d.value in PLACEMENT_KEYWORDS:
        return d.value or "local", None, None
    m = registry.get(d.value or "")
    if m is None:
        why = _unknown_name(d.value or "", registry)
    elif m.ok and m.assignable:
        return d.value or "local", None, None
    else:
        why = unfit_reason(m, Needs()) or "not usable"
    return "local", "default_machine %s" % _r(d.value), why


def _evaluate(target: str, registry: Registry, needs: Needs, skip: FrozenSet[str] = frozenset()
              ) -> Tuple[List[str], List[Tuple[str, str]], str]:
    """(fitting machines, [(key, why)] refusals, refusal text when none fit).

    Machines in `skip` were already judged and refused with these same needs, so they are not judged again.
    """
    local = registry.local
    if target == "any":
        order = ([local] if local is not None else []) + [m for m in registry.machines.values() if m is not local]
        fits: List[str] = []
        refused: List[Tuple[str, str]] = []
        for m in order:
            if m.name in skip:
                continue
            why = unfit_reason(m, needs)
            if why is None:
                fits.append(m.name)
            else:
                refused.append((m.name, why))
        text = "no machine fits: " + "; ".join("%s: %s" % (k, w) for k, w in refused[:LIST_SHOWN]) + (
            " (+%d more)" % (len(refused) - LIST_SHOWN) if len(refused) > LIST_SHOWN else "") if refused and not fits else ""
        return fits, refused, text
    if target == "local":
        machine = local
        key = machine.name if machine is not None else "local"
    else:
        machine = registry.get(target)
        key = target
    if key in skip:
        return [], [], ""
    if machine is None:
        why = _unknown_name(target, registry) if target != "local" else "there is no local machine"
        return [], [(key, why)], why
    why = unfit_reason(machine, needs)
    if why is None:
        return [machine.name], [], ""
    return [], [(machine.name, why)], why


def resolve(role: str, kind: Optional[str] = None, *,
            registry: Registry, config: PlacementConfig) -> Placement:
    """Where does `role` run? Pure: no I/O. See the module docstring, rules 6-9.

    `reason` and every `rejected` explanation are capped at MESSAGE_CAP characters.
    """
    p = _resolve(role, kind, registry, config)
    return replace(p, reason=cap_text(p.reason), rejected=tuple((k, cap_text(w)) for k, w in p.rejected))


def _resolve(role: str, kind: Optional[str], registry: Registry, config: PlacementConfig) -> Placement:
    role = strip_role(role)
    kind_in = kind if kind in KINDS else None
    if not registry.usable:
        if registry.inert:
            return _off(role, kind_in, "no-registry", "machines are off: no machine registry at %s" % registry.path)
        return _off(role, kind_in, "registry-errors", "machines are off: the registry has errors (%s)" %
                    _first_error(registry.issues, "it is not usable"))
    if not config.usable:
        return _off(role, kind_in, "sdlc-errors", "machines are off: sdlc.yml has errors (%s)" %
                    _first_error(config.issues, "it is not usable"))
    if not config.opted_in:
        return _off(role, kind_in, "no-placement", "machines are off: sdlc.yml places nothing")

    local = registry.local
    local_name = local.name if local is not None else "local"
    req = _own_request(config, role, kind_in)
    shown_kind = kind_in
    if shown_kind is None and req is not None:
        shown_kind = "phase" if req.at.startswith(("phases.", "phase_machines.")) else "agent"
    needs = config.needs.get(role, Needs())
    if not needs.ok:
        return Placement(role, shown_kind, "unplaceable", None, None, (), False, req, (),
                         "needs.%s has errors in: %s" % (role, shown_list(sorted(needs.invalid))))

    dtarget, replaced, replaced_why = _default_target(registry, config)
    d = config.default
    rejected: List[Tuple[str, str]] = []
    texts: List[str] = []
    refused_own = False
    own_label = ""

    if req is not None:
        own_label = ("%s %s" % (req.at, _r(req.value))) if req.value else req.at
        refused_own = True
        if req.error is not None:
            rejected.append((req.at, req.error))
            texts.append("%s: %s" % (own_label, req.error))
        else:
            fits, refusals, text = _evaluate(req.value or "", registry, needs)
            rejected.extend(refusals)
            if fits:
                how = "%s places %s on %s" % (req.at, role, _r(fits[0]))
                if req.value == "any":
                    how = "%s places %s on any: %d %s" % (
                        req.at, role, len(fits), "machine fits" if len(fits) == 1 else "machines fit")
                return Placement(role, shown_kind, "placed", None, fits[0], tuple(fits), fits[0] == local_name, req,
                                 tuple(rejected), how, req.value)
            if text:
                texts.append(text)

    # A machine the own target already refused is not judged again: same needs, same answer.
    fits, refusals, text = _evaluate(dtarget, registry, needs, frozenset(k for k, _w2 in rejected))
    rejected.extend(refusals)
    if not fits:
        if text:
            texts.append(text)
        return Placement(role, shown_kind, "unplaceable", None, None, (), False, req, tuple(rejected),
                         "%s has nowhere to run: %s" % (role, "; ".join(texts)))

    if dtarget == "any":
        tail = "default_machine 'any' (%d machine%s fit)" % (len(fits), "" if len(fits) == 1 else "s")
    elif d is None:
        tail = "this box (%s)" % _r(local_name)
    else:
        tail = "default_machine %s" % _r(d.value)
    if not refused_own:
        if replaced is not None:
            reason = "%s has no placement; %s is not usable (%s); runs on this box (%s)" % (
                role, replaced, replaced_why, _r(local_name))
        elif d is None:
            reason = "%s has no placement; runs on this box (%s)" % (role, _r(local_name))
        else:
            reason = "%s has no placement; %s" % (role, tail)
        status = "placed"
    else:
        if replaced is not None:
            reason = "%s was refused (%s); %s is not usable; using this box (%s)" % (
                own_label, texts[0] if texts else "refused", replaced, _r(local_name))
        else:
            reason = "%s was refused (%s); using %s" % (own_label, texts[0] if texts else "refused", tail)
        status = "fallback"
    return Placement(role, shown_kind, status, None, fits[0], tuple(fits), fits[0] == local_name, req,
                     tuple(rejected), reason, dtarget)


# ── the check pass ───────────────────────────────────────────────────────────

def _default_issue(registry: Registry, config: PlacementConfig) -> Optional[str]:
    """One error for the default target: an unusable default_machine, or nowhere for unplaced roles to run."""
    d = config.default
    local = registry.local
    if local is None:
        return None
    _t, replaced, why = _default_target(registry, config)
    reported = d is not None and d.error is not None       # already an error at sdlc.yml.default_machine
    explicit_local = d is not None and not reported and d.value == "local"
    effective_local = d is None or reported or explicit_local or replaced is not None
    parts: List[str] = []
    if replaced is not None and not reported:
        parts.append("%s is not usable (%s)" % (replaced, why))
    if effective_local and not local.assignable:
        if explicit_local:
            parts.append("default_machine 'local' is the local machine %s, which is not assignable, so unplaced roles "
                         "have nowhere to run" % _r(local.name))
        else:
            parts.append("no usable default_machine and the local machine %s is not assignable, so unplaced roles "
                         "have nowhere to run" % _r(local.name))
    elif parts:
        parts[-1] += "; unplaced roles run on this box (%s) instead" % _r(local.name)
    return "; ".join(parts) if parts else None


def placement_issues(registry: Registry, config: PlacementConfig) -> List[Issue]:
    """The repo pass of `check`. Call only when registry.usable."""
    if not config.usable:
        # A broken config shows only its file- or block-level errors, and no role lines.
        levels = {"sdlc.yml"} | {_w(k) for k in PLACEMENT_KEYS}
        return [i for i in config.issues if i.level == "error" and i.where in levels]
    out = list(config.issues)
    if not config.opted_in:
        return out
    message = _default_issue(registry, config)
    if message:
        out.append(_mk("error", _w("default_machine"), message))
    for role, kind in config.roles():
        p = resolve(role, kind, registry=registry, config=config)
        req = _own_request(config, role, kind)
        where = _w(req.at) if req is not None else _w("needs", role)
        if p.status == "placed":
            if req is not None and req.value == "any":
                text = "%s -> any: %s" % (role, ", ".join(p.candidates))
            elif req is None:
                text = "%s -> %s (default)" % (role, p.machine)
            else:
                text = "%s -> %s" % (role, p.machine)
            out.append(_mk("info", where, text))
            continue
        value_error = (req is not None and req.error is not None) or not config.needs.get(role, Needs()).ok
        out.append(_mk("info" if value_error else "error", where, p.reason))
    return out


# ── the two entry points ─────────────────────────────────────────────────────

def locate(role: str, kind: Optional[str] = None, *, project_dir: Optional[str] = None,
           registry_file: Optional[str] = None, config_file: Optional[str] = None,
           env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None,
           budget: Optional[float] = None) -> Tuple[Placement, Registry, Optional[PlacementConfig]]:
    """load(); when the registry is usable (and within `budget`), load_placement(); resolve().

    The config is None when sdlc.yml was not read. Never raises.
    """
    reg: Optional[Registry] = None
    try:
        started = time.monotonic()
        reg = load(registry_file, env)
        if not reg.usable:
            return resolve(role, kind, registry=reg, config=_new_config(None, "none", False)), reg, None
        elapsed = time.monotonic() - started
        if budget is not None and elapsed >= SDLC_SKIP_AFTER:
            return _off(strip_role(role), kind if kind in KINDS else None, "time-budget",
                        "machines are off: time budget spent reading the registry (%.1fs); sdlc.yml not read"
                        % elapsed), reg, None
        timeout = None if budget is None else min(YQ_TIMEOUT, budget - elapsed)
        cfg = load_placement(config_file, project_dir=project_dir, env=env, cwd=cwd, timeout=timeout)
        return resolve(role, kind, registry=reg, config=cfg), reg, cfg
    except Exception as exc:  # last resort
        cfg = _broken(None, "none", False, "internal error: %s: %s" % (type(exc).__name__, exc))
        fallback_reg = reg if reg is not None else Registry(Path("."), "default", False, {}, [])
        return (_off(strip_role(str(role)), None, "sdlc-errors", "machines are off: %s" % cfg.issues[0].message),
                fallback_reg, cfg)


def lookup(role: str, kind: Optional[str] = None, *, project_dir: Optional[str] = None,
           registry_file: Optional[str] = None, config_file: Optional[str] = None,
           env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None) -> Placement:
    """The hook's entry point (#138): locate() with a time budget. #138 passes kind=None."""
    return locate(role, kind, project_dir=project_dir, registry_file=registry_file, config_file=config_file,
                  env=env, cwd=cwd, budget=LOOKUP_BUDGET)[0]
