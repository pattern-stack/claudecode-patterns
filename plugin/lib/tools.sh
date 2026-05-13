#!/usr/bin/env bash
#
# plugin/lib/tools.sh — runtime install primitive for binaries shipped by
# the sdlc plugin. Read `plugin/lib/tools.json` once at source-time; expose
# `ensure_tool <name>` and `tool_binary_path <name>` so hook scripts and
# /sdlc:setup share a single install code path.
#
# Source from a caller that has $PLUGIN_ROOT set (the absolute path to
# the installed `plugin/` directory). Hook scripts invoked by Claude Code
# get this via $CLAUDE_PLUGIN_ROOT. /sdlc:setup resolves it from
# ~/.claude/plugins/installed_plugins.json (per the prerequisites block).
#
# Contract:
#   ensure_tool <name>
#     - Returns 0 on success with the binary path printed to stdout.
#     - Returns 0 with empty stdout when the tool is unavailable
#       (no curl, no tarball for this platform, network failure, etc.).
#       Hooks treat empty as "skip telemetry" — never block the user.
#     - Returns non-zero only on caller error (missing args, malformed
#       tools.json).
#
#   tool_binary_path <name>
#     - Pure path computation. Does not check existence; does not download.
#     - Useful for /sdlc:setup to detect "already installed" without
#       triggering a network call.
#
# Caching:
#   ~/.local/state/<tool>/bin/<tool>-v<plugin-version>-<platform>
#   (or $XDG_STATE_HOME/<tool>/... when XDG_STATE_HOME is set)
#
# Versioning:
#   Plugin version (from plugin/.claude-plugin/plugin.json) IS the tool
#   version. Each git tag of the plugin attaches per-platform tarballs to
#   the GH release for that tag. Bumping plugin.json + tagging is the
#   entire update flow.

set -uo pipefail

# ---- Resolve plugin metadata ------------------------------------------------

if [[ -z "${PLUGIN_ROOT:-}" ]]; then
  echo "[tools.sh] PLUGIN_ROOT not set — caller must export it before sourcing" >&2
  return 1 2>/dev/null || exit 1
fi

_TOOLS_JSON="${PLUGIN_ROOT}/lib/tools.json"
_PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

if [[ ! -f "$_TOOLS_JSON" ]]; then
  echo "[tools.sh] missing $_TOOLS_JSON" >&2
  return 1 2>/dev/null || exit 1
fi
if [[ ! -f "$_PLUGIN_JSON" ]]; then
  echo "[tools.sh] missing $_PLUGIN_JSON" >&2
  return 1 2>/dev/null || exit 1
fi

# ---- Helpers ---------------------------------------------------------------

# Pure-bash JSON field read with jq fallback removed — jq is in our install
# baseline (Claude Code's runtime ships it). If jq is somehow absent we
# return empty and let the caller no-op cleanly.
_json_field() {
  local file="$1" path="$2"
  command -v jq >/dev/null 2>&1 || { echo ""; return 0; }
  jq -r "${path} // empty" "$file" 2>/dev/null
}

_plugin_version() {
  _json_field "$_PLUGIN_JSON" ".version"
}

# pattern-stack/claudecode-patterns
_gh_repo() {
  local homepage
  homepage="$(_json_field "$_PLUGIN_JSON" ".homepage")"
  # Strip https://github.com/ prefix, drop trailing slash/.git.
  echo "${homepage#https://github.com/}" | sed 's#/$##; s#\.git$##'
}

# darwin-arm64 / linux-x64 / etc.
_detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
  esac
  echo "${os}-${arch}"
}

_state_dir() {
  local tool="$1"
  local stateRoot="${XDG_STATE_HOME:-${HOME}/.local/state}"
  echo "${stateRoot}/${tool}"
}

# ---- Public API ------------------------------------------------------------

# tool_binary_path <name> — print the expected cache path for the tool's
# binary at the current plugin version. Does not check existence.
tool_binary_path() {
  local tool="$1"
  local version platform
  version="$(_plugin_version)"
  platform="$(_detect_platform)"
  [[ -z "$version" || -z "$platform" ]] && { echo ""; return 0; }
  echo "$(_state_dir "$tool")/bin/${tool}-v${version}-${platform}"
}

# ensure_tool <name> — make sure the binary exists, downloading if needed.
# Prints the binary path to stdout on success, empty on silent skip.
ensure_tool() {
  local tool="$1"
  if [[ -z "$tool" ]]; then
    echo "[tools.sh] usage: ensure_tool <name>" >&2
    return 1
  fi

  local version platform bin tools_entry
  version="$(_plugin_version)"
  platform="$(_detect_platform)"

  if [[ -z "$version" || -z "$platform" ]]; then
    # jq missing or platform undetectable — skip silently.
    return 0
  fi

  # Confirm the tool is declared and supports this platform.
  tools_entry="$(_json_field "$_TOOLS_JSON" ".tools[\"${tool}\"]")"
  if [[ -z "$tools_entry" ]]; then
    echo "[tools.sh] tool '${tool}' not declared in tools.json" >&2
    return 1
  fi

  local supported
  supported="$(_json_field "$_TOOLS_JSON" ".tools[\"${tool}\"].platforms | index(\"${platform}\")")"
  if [[ -z "$supported" || "$supported" == "null" ]]; then
    # No binary for this platform — silent skip.
    return 0
  fi

  bin="$(tool_binary_path "$tool")"
  if [[ -x "$bin" ]]; then
    echo "$bin"
    return 0
  fi

  # ---- Download path -----------------------------------------------------
  command -v curl >/dev/null 2>&1 || return 0
  command -v tar  >/dev/null 2>&1 || return 0

  local repo state_dir bindir tmp tarball binary_name url
  repo="$(_gh_repo)"
  state_dir="$(_state_dir "$tool")"
  bindir="${state_dir}/bin"
  binary_name="$(_json_field "$_TOOLS_JSON" ".tools[\"${tool}\"].binary_name")"
  [[ -z "$binary_name" ]] && binary_name="$tool"

  mkdir -p "$bindir"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/tools-${tool}.XXXXXX")"
  tarball="${tool}-${platform}.tar.gz"
  url="https://github.com/${repo}/releases/download/v${version}/${tarball}"

  if ! curl -fsSL --max-time 30 -o "${tmp}/${tarball}" "$url" 2>>"${state_dir}/install.log"; then
    rm -rf "$tmp"
    echo "[tools.sh] download failed: $url (see ${state_dir}/install.log)" >>"${state_dir}/install.log"
    return 0
  fi

  # Optional checksum verification — best-effort; missing SHA256SUMS won't
  # block install (we'd rather have telemetry than nothing).
  if curl -fsSL --max-time 10 -o "${tmp}/SHA256SUMS" \
      "https://github.com/${repo}/releases/download/v${version}/SHA256SUMS" 2>/dev/null; then
    local expected actual
    expected="$(grep -E " ${tarball}$" "${tmp}/SHA256SUMS" | awk '{print $1}' | head -1)"
    if [[ -n "$expected" ]]; then
      actual="$(shasum -a 256 "${tmp}/${tarball}" 2>/dev/null | awk '{print $1}')"
      if [[ "$actual" != "$expected" ]]; then
        echo "[tools.sh] checksum mismatch for ${tarball} (expected ${expected:0:12}…, got ${actual:0:12}…)" >>"${state_dir}/install.log"
        rm -rf "$tmp"
        return 0
      fi
    fi
  fi

  if ! tar -xzC "$tmp" -f "${tmp}/${tarball}" 2>>"${state_dir}/install.log"; then
    rm -rf "$tmp"
    return 0
  fi

  if [[ ! -f "${tmp}/${binary_name}" ]]; then
    echo "[tools.sh] tarball missing binary '${binary_name}'" >>"${state_dir}/install.log"
    rm -rf "$tmp"
    return 0
  fi

  mv "${tmp}/${binary_name}" "$bin"
  chmod +x "$bin"
  rm -rf "$tmp"

  echo "$bin"
}
