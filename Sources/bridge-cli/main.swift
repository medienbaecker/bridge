import Foundation
import BridgeCore

// Name the CLI as invoked, so usage and hints show a command this flavour has.
let me = (CommandLine.arguments[0] as NSString).lastPathComponent
let usage = """
bridge-dev <file|url> [more files]      present; a URL opens the live site
bridge-dev --links <mode> <file|url>    where its links open: window (in Bridge), browser, or external (other hosts in the browser; a URL's default)
bridge-dev --read   <file>              what they have answered so far, JSON, no blocking
bridge-dev --sidecar <file>             where their record for that page lives (in the app's store)
bridge-dev --seed-from <flavour>        once, into an empty flavour: copy that flavour's list and records here
bridge-dev --wait   <file> [--timeout 900]   block until they click Send, then print
bridge-dev --cross  <file>              done with it: take it off their list
bridge-dev --uncross <file>             bring it back
bridge-dev --remove <file>              remove from the list entirely
bridge-dev --reset  <file>              remove it and forget their record (answers, history, notes): the next present is version 1
bridge-dev --lint   <file> [more files]   check a page before presenting it: unknown or colliding classes, colours with no dark variant, a pre that is really a table
bridge-dev --state                      what the running app is showing right now, JSON
bridge-dev --shot <out.png>             a picture of the app's window
bridge-dev --shot <file> <out.png> [--width N]   the page rendered off-screen as the window would show it, without presenting it
bridge-dev --waiters                    the agent processes waiting for an answer, with their age and memory, JSON
bridge-dev --pins   <file>              open notes with their threads
bridge-dev --reply  <file> <id> <text>
bridge-dev --done / --reopen / --working <file> <id>
bridge-dev --hook stop [--timeout N]     Claude Code Stop hook: deliver or wait for this session's answer
bridge-dev --hook post-write             Claude Code PostToolUse hook: tell the agent when its write made a new version or the page threw
bridge-dev --hook session                Claude Code SessionStart, UserPromptSubmit and SessionEnd hook: whether the session lives and works
""".replacingOccurrences(of: "bridge-dev", with: me)

Flavor.name = Flavor.fromCLI(CommandLine.arguments[0])
let cwd = FileManager.default.currentDirectoryPath
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func print(json value: some Encodable) {
    print(JSON.string(value))
}

func location(_ arg: String?) -> String {
    guard let arg else { fail(usage) }
    return Paths.resolve(arg, relativeTo: cwd)
}

func appExecutable() -> String? {
    let env = ProcessInfo.processInfo.environment
    var candidates: [String] = []
    let inside = "\(Flavor.appName).app/Contents/MacOS/\(Flavor.executable)"
    if let p = env["BRIDGE_DEV_APP"] { candidates.append(p.hasSuffix(".app") ? p + "/Contents/MacOS/" + Flavor.executable : p) }
    let here = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    candidates.append(here.appendingPathComponent(inside).path)
    candidates.append(NSHomeDirectory() + "/Applications/" + inside)
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func launchApp(hidden: Bool = false) -> pid_t {
    guard let exe = appExecutable() else { fail("\(Flavor.appName).app not found; set BRIDGE_DEV_APP") }
    try? FileManager.default.removeItem(at: Paths.launchError)
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    // The app outlives this command; if it inherited our streams,
    // `out=$(bridge page.html)` would never return.
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe), nil]
    var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
    envp.append(strdup("BRIDGE_LAUNCHED_BY_CLI=1"))
    if hidden { envp.append(strdup("BRIDGE_LAUNCH_HIDDEN=1")) }
    envp.append(nil)
    let rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp)
    posix_spawn_file_actions_destroy(&actions)
    posix_spawnattr_destroy(&attr)
    guard rc == 0 else { fail("could not launch \(exe): \(String(cString: strerror(rc)))") }
    return pid
}

func send(_ request: Request, launching: Bool = false, hidden: Bool = false) -> Response {
    if let r = try? Client.send(request) { return r }
    guard launching else { return .error("app not running") }
    let pid = launchApp(hidden: hidden)
    for _ in 0..<100 {
        usleep(50_000)
        if let r = try? Client.send(request) { return r }
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid { break }
    }
    let reason = (try? String(contentsOf: Paths.launchError, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    fail(reason ?? "Bridge app did not come up (no reason was recorded in \(Paths.launchError.path); socket: \(Paths.socket.path))")
}

func check(_ response: Response) -> JSONValue {
    switch response {
    case .ok(let v): return v
    case .error(let e): fail(e)
    }
}

// Collecting exactly once is what stops a wake loop, so a collect must not
// silently do nothing. The app may quit between the first check and the send,
// so whether it runs is asked again: the app is the sidecar's only writer while
// it runs, and the file may be written directly only once it is gone.
func collect(_ loc: String, as session: String = Session.current) {
    if Client.appIsRunning, (try? Client.send(.collect(location: loc, session: session))) != nil { return }
    guard !Client.appIsRunning else { return }
    do {
        try Sidecar.modify(Paths.sidecar(for: loc)) { s in
            guard s.answered, s.changedSinceCollected else { return }
            s.collectedAt = Date(); s.collectedBy = session
        }
    } catch {}
}

func readOut(_ loc: String) -> JSONValue {
    let s: Sidecar
    do { s = try Sidecar.load(Paths.sidecar(for: loc)) } catch { fail("\(error)") }
    var out: [String: JSONValue] = ["status": .string(s.status), "version": .number(Double(s.version))]
    let mine = s.presented.map { $0.session == Session.current } ?? true
    if !mine && !s.stale, let p = s.presented {
        out["heldBy"] = .string(p.session)
        out["note"] = .string("presented by another session; present the file again to take it over")
        // Null, not missing: a reader that does `.answers` on this must not see an empty record.
        out["answers"] = .null
        return .object(out)
    }
    if s.answered { collect(loc) }
    out["answers"] = .object(s.answers)
    // The answers the page proposed and the user left, so a reader can tell them apart.
    out["defaults"] = .array(s.defaults.map { .string($0) })
    if let t = s.sentAt { out["sent"] = .string(ISO8601DateFormatter().string(from: t)) }
    out["comments"] = .array(s.comments.map { c in
        .object([
            "id": .string(c.id), "text": .string(c.text), "target": .string(c.target),
            "state": .string(c.state), "version": .number(Double(c.version)), "lost": .bool(c.lost ?? false),
            "said": .array(c.said.map { .object(["by": .string($0.by), "at": .string(ISO8601DateFormatter().string(from: $0.at)), "text": .string($0.text), "kind": .string($0.kind)]) }),
        ])
    })
    if let g = s.presented?.ground {
        var ground: [String: JSONValue] = ["repo": .string(g.repo), "branch": .string(g.branch), "commit": .string(g.commit)]
        if let moved = g.commitsSince() { ground["headMoved"] = .number(Double(moved)) }
        out["ground"] = .object(ground)
    }
    if !s.history.isEmpty {
        out["history"] = .array(s.history.map { .object(["version": .number(Double($0.n)), "answers": .object($0.answers)]) })
    }
    return .object(out)
}

func modifyOffline(_ loc: String, _ change: (inout Sidecar) -> Void) {
    do { try Sidecar.modify(Paths.sidecar(for: loc), change) } catch { fail("\(error)") }
}

// Registered with asyncRewake, so the wait happens after the session has gone
// idle. Anything unexpected exits 0 so a broken hook never holds a session.
func hook(_ event: String) -> Never {
    if event == "post-write" { postWrite() }
    guard event == "stop" || event == "session" else { exit(0) }
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let fields = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
    let session = fields?["session_id"] as? String ?? Session.current
    ClaudeSessions.record(event == "stop" ? "Stop" : fields?["hook_event_name"] as? String ?? "", session: session, pid: ClaudeSessions.claudePID())
    guard event == "stop" else { exit(0) }
    var timeout: TimeInterval = 570
    if let i = args.firstIndex(of: "--timeout"), let t = args.dropFirst(i + 1).first.flatMap(Double.init) { timeout = t }
    let deadline = Date().addingTimeInterval(timeout)
    // One hook serves every flavour, so it looks in every flavour's state dir.
    func eachFlavor<T>(_ body: () -> T?) -> T? {
        let own = Flavor.name
        defer { Flavor.name = own }
        for name in Flavor.all { Flavor.name = name; if let r = body() { return r } }
        return nil
    }
    func deliverable() -> (String, BridgeEntry, Sidecar)? {
        eachFlavor {
            for entry in Listing.load().bridges {
                guard let s = try? Sidecar.load(Paths.sidecar(for: entry.location)) else { continue }
                if s.collectable(by: session) { return (Flavor.name, entry, s) }
            }
            return nil
        }
    }
    // Crossed never gates delivery; it only stops an open bridge from holding the turn.
    func waiting() -> Bool {
        eachFlavor {
            Listing.load().bridges.contains { entry in
                guard entry.session == session, !entry.crossed else { return false }
                return (try? Sidecar.load(Paths.sidecar(for: entry.location)))?.status == "open"
            } ? true : nil
        } ?? false
    }
    var found = autoreleasepool { deliverable() }
    if found == nil, waiting() { Waiters.register(kind: "hook", session: session, locations: []) }
    // Every turn that ends starts another hook for the session; only the newest keeps waiting.
    while found == nil, autoreleasepool(invoking: { waiting() }), Date() < deadline {
        if Waiters.superseded() { exit(0) }
        usleep(500_000)
        found = autoreleasepool { deliverable() }
    }
    // A Send landing between deliverable() and waiting() is seen by neither,
    // so look for an answer once more before giving up.
    if found == nil { found = deliverable() }
    guard let (flavor, entry, s) = found else { exit(0) }
    let again = s.collectedAt != nil
    Flavor.name = flavor
    collect(entry.location, as: session)
    let file = entry.location
    var reason: String
    if s.status == "closed" {
        reason = "Bridge: The user closed \(file) without answering. That means no, or not now; do not present it again unchanged."
    } else {
        let answers = JSON.string(JSONValue.object(s.answers), pretty: false)
        reason = again ? "Bridge: The user wrote more on \(file) since you read it (version \(s.version)): \(answers)."
                       : "Bridge: The user answered \(file) (version \(s.version)): \(answers)."
        let open = s.openComments.count
        // Name the CLI serving the hook: another flavour's command may not be installed.
        if open > 0 { reason += " They also left \(open) note\(open == 1 ? "" : "s"); read them with `\(me) --pins \(file)`." }
        reason += " Full answer: `\(me) --read \(file)`. Act on it, then `\(me) --cross \(file)`."
    }
    if s.presented?.session != session { reason += " (Presented by another session; uncollected for over two hours, so it is yours now.)" }
    // Both forms at once: stderr plus exit 2 wakes an idle session under
    // asyncRewake; the JSON on stdout serves a host that can only block the stop.
    let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "Stop", "decision": "block", "reason": reason]]
    if let data = try? JSONSerialization.data(withJSONObject: out) { print(String(decoding: data, as: UTF8.self)) }
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(2)
}

guard let first = args.first else { fail(usage) }

switch first {
case "--help", "-h":
    print(usage)

case "--read":
    print(json: readOut(location(args.dropFirst().first)))

case "--sidecar":
    print(Paths.sidecar(for: location(args.dropFirst().first)).path)

// Copies only, never renames: a record still beside its page is copied in, not
// migrated, because the source flavour still reads it there. Nothing this
// flavour does afterwards can reach the source flavour's records.
case "--seed-from":
    guard let other = args.dropFirst().first else { fail("--seed-from <flavour> [--force]") }
    let own = Flavor.name
    Flavor.name = other
    let source = Paths.stateDir, sourceList = Listing.load()
    Flavor.name = own
    guard source != Paths.stateDir else { fail("that is this flavour") }
    guard Listing.load().bridges.isEmpty || args.contains("--force") else { fail("\(own) already has a list; --force replaces it") }
    Paths.migrates = false
    let fm = FileManager.default
    try? fm.removeItem(at: Paths.list)
    do { try fm.copyItem(at: source.appendingPathComponent("list.json"), to: Paths.list) } catch { fail("no list at \(source.path)") }
    let answers = Paths.stateDir.appendingPathComponent("answers")
    try? fm.createDirectory(at: answers, withIntermediateDirectories: true)
    var records = 0
    for file in (try? fm.contentsOfDirectory(at: source.appendingPathComponent("answers"), includingPropertiesForKeys: nil)) ?? [] {
        let to = answers.appendingPathComponent(file.lastPathComponent)
        try? fm.removeItem(at: to)
        if (try? fm.copyItem(at: file, to: to)) != nil { records += 1 }
    }
    var beside = 0
    for entry in sourceList.bridges {
        let store = Paths.sidecar(for: entry.location)
        guard !fm.fileExists(atPath: store.path) else { continue }
        let legacy = Paths.legacySidecar(for: entry.location)
        if fm.fileExists(atPath: legacy.path), (try? fm.copyItem(at: legacy, to: store)) != nil { beside += 1 }
    }
    print("seeded \(own) from \(other): \(sourceList.bridges.count) bridges, \(records) records from its store, \(beside) copied from beside their pages")

case "--wait":
    let loc = location(args.dropFirst().first)
    var timeout: TimeInterval = 900
    if let i = args.firstIndex(of: "--timeout"), let t = args.dropFirst(i + 1).first.flatMap(Double.init) { timeout = t }
    let deadline = Date().addingTimeInterval(timeout)
    Waiters.register(kind: "wait", session: Session.current, locations: [loc])
    while Date() < deadline {
        guard autoreleasepool(invoking: { (try? Sidecar.load(Paths.sidecar(for: loc)))?.status == "open" }) else { break }
        usleep(250_000)
    }
    print(json: readOut(loc))

case "--cross", "--uncross", "--remove", "--reset":
    let loc = location(args.dropFirst().first)
    let request: Request = switch first {
    case "--cross": .cross(location: loc)
    case "--uncross": .uncross(location: loc)
    case "--remove": .remove(location: loc)
    default: .reset(location: loc)
    }
    if Client.appIsRunning { _ = check(send(request)) }
    else {
        var l = Listing.load()
        if first == "--remove" || first == "--reset" { l.bridges.removeAll { $0.location == loc } }
        else { l.update(loc) { $0.crossed = first == "--cross" } }
        try? l.save()
        if first == "--reset" { try? FileManager.default.removeItem(at: Paths.sidecar(for: loc)) }
    }

case "--waiters":
    let now = Date()
    print(json: JSONValue.array(Waiters.all().map { w in
        .object(["pid": .number(Double(w.pid)), "kind": .string(w.kind), "session": .string(w.session), "flavor": .string(w.flavor),
                 "ageSeconds": .number(now.timeIntervalSince(w.started).rounded()), "megabytes": .number(Double(w.megabytes)),
                 "locations": .array(w.locations.map { .string($0) })])
    }))

case "--state":
    if Client.appIsRunning { print(json: check(send(.state))) }
    else { print(json: JSONValue.object(["running": .bool(false)])) }

case "--pins":
    let s: Sidecar
    do { s = try Sidecar.load(Paths.sidecar(for: location(args.dropFirst().first))) } catch { fail("\(error)") }
    print(json: JSONValue.array(s.openComments.map { c in
        .object([
            "id": .string(c.id), "text": .string(c.text), "target": .string(c.target), "state": .string(c.state), "lost": .bool(c.lost ?? false),
            "said": .array(c.said.map { .object(["by": .string($0.by), "text": .string($0.text), "kind": .string($0.kind)]) }),
        ])
    }))

case "--reply":
    let loc = location(args.dropFirst().first)
    guard args.count >= 4 else { fail(usage) }
    let id = args[2], text = args[3...].joined(separator: " ")
    if Client.appIsRunning { _ = check(send(.reply(location: loc, id: id, text: text))) }
    else {
        modifyOffline(loc) { s in
            guard let i = s.comments.firstIndex(where: { $0.id == id }) else { return }
            s.comments[i].said.append(Say(by: "agent", text: text))
        }
    }

case "--done", "--reopen", "--working":
    let loc = location(args.dropFirst().first)
    guard args.count >= 3 else { fail(usage) }
    let state = String(first.dropFirst(2))
    if Client.appIsRunning { _ = check(send(.note(location: loc, id: args[2], state: state))) }
    else {
        modifyOffline(loc) { s in
            guard let i = s.comments.firstIndex(where: { $0.id == args[2] }) else { return }
            s.comments[i].state = state == "done" ? "done" : state == "reopen" ? "open" : "working"
            s.comments[i].said.append(Say(by: "agent", text: state == "done" ? "marked done" : state == "reopen" ? "reopened" : "working on it", kind: "status"))
        }
    }

case "--hook":
    hook(args.dropFirst().first ?? "stop")

// Harness-only verbs, kept out of usage on purpose.
case "--js":
    guard args.count >= 3 else { fail("--js <file|-> <code>") }
    let loc: String? = args[1] == "-" ? nil : location(args[1])
    print(json: check(send(.js(location: loc, code: args[2...].joined(separator: " ")))))

case "--do":
    guard args.count >= 2 else { fail("--do <command> [argument]") }
    // Everything after the verb is its argument: "resize 1242 1052" is one argument of two numbers.
    print(json: check(send(.command(name: args[1], argument: args.count > 2 ? args[2...].joined(separator: " ") : nil))))

case "--snap":
    guard args.count >= 2 else { fail("--snap <out.png>") }
    print(json: check(send(.snapshot(path: Paths.resolve(args[1], relativeTo: cwd)))))

case "--lint":
    // Read the stylesheet from the app rather than ship a copy that could drift.
    let files = args.dropFirst().map { location($0) }
    guard !files.isEmpty else { fail("--lint <file> [more files]") }
    guard let exe = appExecutable(),
          let css = try? String(contentsOfFile: URL(fileURLWithPath: exe).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/bridge_Bridge.bundle/Contents/Resources/web/page.css").path, encoding: .utf8)
    else { fail("\(Flavor.appName).app not found, so the kit's stylesheet is not either; set BRIDGE_DEV_APP") }
    let lint = Lint(kitCSS: css)
    var errors = 0
    for file in files {
        guard let html = try? String(contentsOfFile: file, encoding: .utf8) else { fail("cannot read \(file)") }
        let findings = lint.run(html: html)
        for f in findings { print("\((file as NSString).lastPathComponent):\(f.description)") }
        errors += findings.filter { $0.level == .error }.count
    }
    exit(errors > 0 ? 1 : 0)

case "--shot":
    guard args.count >= 2 else { fail("--shot <out.png> [--screen] | --shot <file> <out.png> [--width N]") }
    if args.count >= 3, !args[2].hasPrefix("--") {
        let width = args.firstIndex(of: "--width").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
        print(json: check(send(.render(location: location(args[1]), path: Paths.resolve(args[2], relativeTo: cwd), width: width), launching: true, hidden: true)))
        exit(0)
    }
    print(json: check(send(.shot(path: Paths.resolve(args[1], relativeTo: cwd), screen: args.contains("--screen")))))

case "--quit":
    _ = send(.quit)

default:
    var links: String?
    if let i = args.firstIndex(of: "--links") {
        guard i + 1 < args.count, Links(rawValue: args[i + 1]) != nil else { fail("--links window|browser|external <file|url>") }
        links = args[i + 1]
        args.removeSubrange(i...(i + 1))
    }
    if args.first?.hasPrefix("--") ?? true { fail(usage) }
    let locations = args.map { location($0) }
    for loc in locations where Kind.of(loc) != .url && !FileManager.default.fileExists(atPath: loc) {
        fail("no such file: \(loc)")
    }
    _ = check(send(.present(locations: locations, cwd: cwd, session: Session.current, ground: Ground.current(in: cwd), links: links), launching: true))
    // The agent that wrote the page sees this in its tool result; nothing else
    // would tell it that classes it made up style nothing.
    for loc in locations where Kind.of(loc) != .url {
        for _ in 0..<40 {
            // An older app does not know this request and answers with an error: nothing to wait for.
            guard case .ok(let v) = send(.audit(location: loc)) else { break }
            guard v["ready"]?.boolValue == true else { usleep(100_000); continue }
            let unknown = v["unknownClasses"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let both = v["collidingClasses"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let file = (loc as NSString).lastPathComponent
            if !unknown.isEmpty {
                FileHandle.standardError.write(Data("\(me): unknown classes on \(file): \(unknown.joined(separator: ", ")): see pages.md, What the base stylesheet gives you\n".utf8))
            }
            for e in v["errors"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                FileHandle.standardError.write(Data("\(me): \(file) threw: \(e)\n".utf8))
            }
            if !both.isEmpty {
                FileHandle.standardError.write(Data("\(me): classes on \(file) that the page and the kit both style, so the page gets both: \(both.joined(separator: ", ")): rename yours or reset what the kit sets\n".utf8))
            }
            break
        }
        guard let html = try? String(contentsOfFile: loc, encoding: .utf8) else { continue }
        for (src, why) in refusedFrames(Framing.sources(in: html)) {
            FileHandle.standardError.write(Data("\(me): \(src) in \((loc as NSString).lastPathComponent) refuses to be shown in a frame (\(why)), so it stays blank: present the URL on its own, or serve it through a proxy that drops that header\n".utf8))
        }
    }
}

func refusedFrames(_ sources: [String]) -> [(String, String)] {
    nonisolated(unsafe) var result: [(String, String)] = []
    let done = DispatchSemaphore(value: 0)
    Framing.refused(sources) { result = $0; done.signal() }
    _ = done.wait(timeout: .now() + 4)
    return result
}

func postWrite() -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let fields = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
    guard let path = (fields?["tool_input"] as? [String: Any])?["file_path"] as? String else { exit(0) }
    let loc = Paths.resolve(path, relativeTo: fields?["cwd"] as? String ?? cwd)
    for name in Flavor.all {
        Flavor.name = name
        guard Listing.load().bridges.contains(where: { $0.location == loc }), Client.appIsRunning else { continue }
        for _ in 0..<30 {
            guard case .ok(let v) = (try? Client.send(.audit(location: loc))) ?? .error("") else { break }
            guard v["current"]?.boolValue == true else { usleep(100_000); continue }
            let file = (loc as NSString).lastPathComponent
            var text = ""
            if v["bumpedByThis"]?.boolValue == true {
                let version = v["version"]?.intValue ?? 0
                let why = v["why"]?.stringValue ?? "the options changed"
                text = "Bridge: this write made \(file) version \(version) (\(why)). The user's answers moved to history, their Send was taken back, and they now see \"changed since you answered\". "
                    + "A new version comes from changing a data-record key, the offered data-values, or what a control accepts (an input's type, a range's min or max, a select's options); wording, layout and a range's value or step are free. "
                    + "Every further change like this costs them another version. To start the page over instead, `\(me) --reset \(path)` and present it again."
            }
            let errors = v["errors"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if !errors.isEmpty {
                text += (text.isEmpty ? "Bridge: " : " ") + "\(file) threw in their window: " + errors.joined(separator: "; ") + "."
            }
            guard !text.isEmpty else { exit(0) }
            let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PostToolUse", "additionalContext": text]]
            if let data = try? JSONSerialization.data(withJSONObject: out) { print(String(decoding: data, as: UTF8.self)) }
            exit(0)
        }
    }
    exit(0)
}
