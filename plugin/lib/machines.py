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
   "machines.<name>[.<key>[.<sub>]]" (one machine's entry).
"""
from __future__ import annotations

import difflib
import json
import math
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
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

class _Map(dict):
    """A parsed mapping that remembers keys written more than once (`dups`)."""
    dups = ()


def _pairs_to_map(pairs: Any) -> "_Map":
    out = _Map()
    seen = set()
    dups = []
    for key, value in pairs:
        if key in seen and key not in dups:
            dups.append(key)
        seen.add(key)
        out[key] = value
    if dups:
        out.dups = tuple(dups)
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
            repeated = tuple(dict.fromkeys(k for k in written if written.count(k) > 1))
            out.dups = repeated
            return out

        def construct_yaml_map(self, node):  # type: ignore
            data = _Map()
            yield data
            value = self.construct_mapping(node)
            data.update(value)
            data.dups = value.dups

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


def parse_yaml(path: Path) -> object:
    """Parse `path` with PyYAML (strict loader), else yq, else raise RegistryError.

    Duplicate keys: PyYAML reports them (mapping._Map.dups). yq 4 keeps every repeated key in its
    JSON output, so they are reported there too (checked with yq 4.44.3). A future yq that drops
    repeats would leave that check silent; the test suite notices.
    """
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
    try:
        proc = subprocess.run(["yq", "-o=json", ".", str(path)], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=YQ_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise RegistryError("yq timed out after %gs reading %s" % (YQ_TIMEOUT, path))
    except OSError as exc:
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
    raise _Bad("must be true or false (yes/no/on/off, 1 and quoted strings are not booleans), got %r" % (v,))


def _check_str(v: Any) -> str:
    if isinstance(v, str):
        return v
    raise _Bad("must be a string, got %r" % (v,))


def _check_path(v: Any) -> str:
    if isinstance(v, str) and v.strip():
        return v
    raise _Bad("must be a non-empty path string, got %r" % (v,))


def _check_strlist(v: Any) -> Tuple[str, ...]:
    if not isinstance(v, list):
        raise _Bad("must be a list of non-empty strings, got %r" % (v,))
    for item in v:
        if not (isinstance(item, str) and item.strip()):
            raise _Bad("must be a list of non-empty strings, got item %r" % (item,))
    return tuple(v)


def _enum(values: Tuple[str, ...]) -> Callable[[Any], str]:
    def check(v: Any) -> str:
        if isinstance(v, str) and v in values:
            return v
        raise _Bad("must be one of %s, got %r" % (", ".join(values), v))
    return check


def _check_gates(v: Any) -> Tuple[str, ...]:
    if not isinstance(v, list):
        raise _Bad("must be a list of %s, got %r" % (" and/or ".join(FIRST_START_GATES), v))
    for item in v:
        if not (isinstance(item, str) and item in FIRST_START_GATES):
            raise _Bad("has unknown first-start gate %r; known: %s" % (item, ", ".join(FIRST_START_GATES)))
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


def _issue(out: List[Issue], level: str, where: str, message: str) -> None:
    if len(message) > 300:  # a pasted value must not become a wall of text
        message = message[:297] + "..."
    out.append(Issue(level, where, message))


def _transport(value: Any, base: str, out: List[Issue], invalid: set) -> Transport:
    """Validate `transport`. Any error gives kind `none`."""
    if isinstance(value, str) and value == "local":
        return Transport("local")
    if not isinstance(value, dict):
        _issue(out, "error", base, "transport must be 'local' or a map {herdr: <label>, ssh: <target>}, got %r" % (value,))
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
        _issue(out, "error", base + ".ssh", "transport.ssh must be a string, got %r" % (ssh,))
        invalid.add("transport.ssh")
        bad = True
    for key in value:
        if key not in ("herdr", "ssh"):
            _issue(out, "warning", "%s.%s" % (base, key), "unknown transport key %r" % (key,))
    if bad:
        return Transport("none")
    return Transport("herdr", herdr=label, ssh=ssh)


def _limits(value: Any, base: str, out: List[Issue], invalid: set) -> Limits:
    if value is None:
        return Limits()
    if not isinstance(value, dict):
        _issue(out, "error", base, "limits must be a map of %s, got %r" % (", ".join(LIMIT_KEYS), value))
        invalid.add("limits")
        return Limits(0, 0, 0, 0)
    got: Dict[str, Any] = {}
    for key, v in value.items():
        if key not in _LIMIT_RULES:
            _issue(out, "warning", "%s.%s" % (base, key), "unknown limit %r; known: %s" % (key, ", ".join(LIMIT_KEYS)))
            continue
        if v is None:
            continue
        test, what = _LIMIT_RULES[key]
        if test(v):
            got[key] = v
        else:
            _issue(out, "error", "%s.%s" % (base, key), "limits.%s must be %s, got %r" % (key, what, v))
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
        _issue(out, "error", base, "machine entry must be a map of keys, got %r" % (raw,))
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
                   "unknown key %r looks like a misspelling of %r; fix it (the restrictive value is used meanwhile)"
                   % (text, first))
            invalid.add(canon)
            if canon == "busy_flag":
                near_miss_flag = True
        else:
            hint = "; did you mean %r?" % first if first else ""
            _issue(out, "warning", "%s.%s" % (base, text), "unknown key %r%s" % (text, hint))

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
            _issue(issues, "warning", "registry.%s" % (key,), "unknown top-level key %r" % (key,))
    for key in getattr(doc, "dups", ()):
        _issue(issues, "error", "registry.%s" % (key,), "top-level key %r is written more than once" % (key,))
    if "machines" in getattr(doc, "dups", ()):
        _issue(issues, "error", "machines", "the 'machines' key is written more than once; no machines are loaded")
        return machines, issues
    entries = doc.get("machines")
    if not isinstance(entries, dict) or not entries:
        _issue(issues, "error", "machines", "registry needs a non-empty 'machines' map")
        return machines, issues
    repeated = set(getattr(entries, "dups", ()))
    for name in sorted(repeated, key=str):
        _issue(issues, "error", "machines", "machine name %r is written more than once; it is left out" % (name,))
    pattern = re.compile(NAME_PATTERN)
    for name, raw in entries.items():
        if name in repeated:
            continue
        if not isinstance(name, str) or not pattern.fullmatch(name) or name.isdigit():
            _issue(issues, "error", "machines",
                   "machine name %r is not allowed: use letters, digits, '-' and '_', starting with a letter or "
                   "digit, and not digits only (YAML would read it as a number)" % (name,))
            continue
        if name in RESERVED_NAMES:
            _issue(issues, "error", "machines",
                   "machine name %r is reserved (%s)" % (name, ", ".join(sorted(RESERVED_NAMES))))
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
