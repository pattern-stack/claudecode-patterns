#!/usr/bin/env bash
# install.sh — make the statusline's working-directory segment clickable (macOS).
#
#   click        copy the directory path
#   Cmd+click    split the herdr pane the statusline is in, rooted at that directory
#   Ctrl+click   same split, through herdr's native link handler (the reliable path)
#
# Builds "CCP Dir Link.app" into ~/Applications from DirLink.swift, registers
# the ccp-dir:// URL scheme with LaunchServices, and — when herdr is installed —
# links herdr-plugin/ from a stable copy (the plugin cache path changes with
# every version). statusline.sh only emits the link once the app exists, so
# nothing changes for anyone who never runs this.
#
#   bash install.sh              install or rebuild
#   bash install.sh --uninstall  remove the app, the scheme and the herdr plugin

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$HOME/Applications/CCP Dir Link.app"   # statusline.sh checks this path
share="${XDG_DATA_HOME:-$HOME/.local/share}/ccp-dir-link"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
herdr_bin="$(command -v herdr || true)"

[[ "$(uname)" == Darwin ]] || { echo "dir-link: macOS only" >&2; exit 1; }

pkill -x DirLink 2>/dev/null || true  # the helper stays resident; drop the old build

if [[ "${1:-}" == --uninstall ]]; then
  [[ -d "$app" ]] && "$lsregister" -u "$app" 2>/dev/null || true
  rm -rf "$app" "$share"
  [[ -n "$herdr_bin" ]] && herdr plugin unlink ccp.dir-link >/dev/null 2>&1 || true
  echo "dir-link: removed"
  exit 0
fi

command -v swiftc >/dev/null || { echo "dir-link: needs swiftc (xcode-select --install)" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -o "$app/Contents/MacOS/DirLink" "$here/DirLink.swift"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.claudecode-patterns.dir-link</string>
  <key>CFBundleName</key><string>CCP Dir Link</string>
  <key>CFBundleExecutable</key><string>DirLink</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>HerdrPath</key><string>${herdr_bin}</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>dev.claudecode-patterns.dir-link.token</string>
      <key>UTTypeDescription</key><string>Directory link token</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>ccpdir</string></array>
      </dict>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Directory link token</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>dev.claudecode-patterns.dir-link.token</string></array>
      <key>CFBundleTypeExtensions</key><array><string>ccpdir</string></array>
    </dict>
  </array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>ccp-dir</string>
      <key>CFBundleURLSchemes</key><array><string>ccp-dir</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null 2>&1
"$lsregister" -f "$app"
open -g -a "$app"  # start resident now, so the first Cmd+click is not a cold launch
echo "dir-link: installed $app"

if [[ -n "$herdr_bin" ]]; then
  rm -rf "$share"
  mkdir -p "$share"
  cp -R "$here/herdr-plugin" "$share/herdr-plugin"
  herdr plugin unlink ccp.dir-link >/dev/null 2>&1 || true
  herdr plugin link "$share/herdr-plugin"
fi
