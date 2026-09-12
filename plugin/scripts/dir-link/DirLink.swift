// DirLink — handler for the statusline's working-directory link.
//
// Cmd+click copies the path; Cmd+Shift+click splits a herdr pane there.
//
// Terminals never report Cmd in a mouse click, so the modifier cannot travel in
// the URL: the helper reads the live keyboard state as the URL arrives, which is
// why it stays resident — a cold launch would let Shift go first. Ghostty opens
// an OSC 8 link only when the mouse modifiers equal Cmd (Surface.zig,
// mouse_mods.equal(input.ctrlOrSuper(.{}))), and strips Shift while a pane's app
// is capturing the mouse, which is what lets Cmd+Shift through as plain Cmd.
//
// The link therefore uses this app's own scheme, which can only ever launch its
// handler (a file: URL gets revealed instead of run):
//
//   ccp-dir://open?path=<dir>&pane=<herdr pane id>[&do=copy|split]
//
// That single gesture copies the path. Splitting needs no link at all: herdr's
// Cmd+D already opens a split in the pane's own directory (new_cwd = "follow").
// herdr's Ctrl+click lane runs this binary with --split-url, and a token file
// from an earlier design is still accepted, so old links keep working.
//
// Stays resident (accessory app, no windows) so a click is not a cold launch.
// Built and registered by install.sh; not meant to be run by hand.

import AppKit

enum Action { case copy, split }

struct Target {
    let path: String
    let pane: String
    var explicitAction: Action?

    // Either a token file (file:…/<hash>.ccpdir holding JSON) or the older
    // ccp-dir://open?path=…&pane=… form, which `open` still accepts.
    init?(url: URL) {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = json["path"] as? String, !path.isEmpty
            else { return nil }
            self.path = path
            self.pane = json["pane"] as? String ?? ""
            return
        }
        guard url.scheme == "ccp-dir",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value, !path.isEmpty
        else { return nil }
        self.path = path
        self.pane = items.first(where: { $0.name == "pane" })?.value ?? ""
        if items.first(where: { $0.name == "do" })?.value == "split" { self.explicitAction = .split }
    }
}

// One line per invocation, so a click that never arrives here can be told
// apart from one that arrives and does the wrong thing. Trimmed to 200 lines.
func log(_ line: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/ccp-dir-link")
    let file = dir.appendingPathComponent("dirlink.log")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter().string(from: Date())
    var lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    lines.append("\(stamp) \(line)")
    try? lines.suffix(200).joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
}

@discardableResult
func run(_ target: Target, _ action: Action) -> Bool {
    log("run action=\(action) path=\(target.path) pane=\(target.pane)")
    if action == .split, split(target) { return true }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(target.path, forType: .string)
    herdr(["notification", "show", "Copied path", "--body", target.path, "--sound", "none"])
    return true
}

// No pane id means the statusline is not running inside herdr — nothing to
// split. A pane that moved has a new id, so fall back to the focused pane,
// which is the one that was just clicked.
func split(_ target: Target) -> Bool {
    guard !target.pane.isEmpty else { return false }
    let tail = ["--direction", "right", "--cwd", target.path, "--focus"]
    return herdr(["pane", "split", target.pane] + tail) || herdr(["pane", "split"] + tail)
}

@discardableResult
func herdr(_ args: [String]) -> Bool {
    guard let bin = herdrPath() else { return false }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: bin)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// Apps launched by LaunchServices get a bare PATH, so install.sh bakes the
// resolved herdr path into Info.plist; the list covers a herdr installed later.
func herdrPath() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let baked = Bundle.main.object(forInfoDictionaryKey: "HerdrPath") as? String
    return [baked, "\(home)/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        .compactMap { $0 }
        .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
}

final class DirLink: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, open urls: [URL]) {
        // Read first: Shift is gone the moment the user lets go.
        let shift = CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        for url in urls {
            log("open url=\(url.absoluteString) shift=\(shift)")
            guard let target = Target(url: url) else { log("unreadable target"); continue }
            // An explicit `do=` in the URL wins; otherwise Shift picks the action.
            run(target, target.explicitAction ?? (shift ? .split : .copy))
        }
        app.hide(nil)  // hand focus back to the terminal
    }
}

// CLI lane for herdr's Ctrl+click plugin action: DirLink --split-url <url>
let args = CommandLine.arguments
if let flag = args.dropFirst().first, flag.hasPrefix("--"), args.count >= 3,
   let url = URL(string: args[2]), let target = Target(url: url) {
    run(target, flag == "--split-url" ? .split : .copy)
    exit(0)
}

let app = NSApplication.shared
let delegate = DirLink()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
