import AppKit
import BridgeCore

enum Env {
    static let test = ProcessInfo.processInfo.environment["BRIDGE_TEST"] == "1"
}

var handles = rlimit()
getrlimit(RLIMIT_NOFILE, &handles)
handles.rlim_cur = min(handles.rlim_max, rlim_t(OPEN_MAX))
setrlimit(RLIMIT_NOFILE, &handles)

Flavor.name = Flavor.fromBundle(Bundle.main.bundleIdentifier)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(Env.test ? .accessory : .regular)
// The harness measures pixels against light chrome, so a system switch to dark mode must not reach it.
Settings.applyAppearance()
app.run()
