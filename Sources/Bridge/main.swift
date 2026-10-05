import AppKit
import BridgeCore

enum Env {
    static let test = ProcessInfo.processInfo.environment["BRIDGE_TEST"] == "1"
    static let logPath = ProcessInfo.processInfo.environment["BRIDGE_LOG"]

    static func log(_ text: @autoclosure () -> String) {
        guard let logPath else { return }
        let line = "\(Date().timeIntervalSince1970) \(text())\n"
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { try? line.write(toFile: logPath, atomically: false, encoding: .utf8) }
    }
}

Flavor.name = Flavor.fromBundle(Bundle.main.bundleIdentifier)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(Env.test ? .accessory : .regular)
// The harness measures pixels against light chrome, so a system switch to dark mode must not reach it.
if Env.test { app.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["BRIDGE_APPEARANCE"] == "dark" ? .darkAqua : .aqua) }
app.run()
