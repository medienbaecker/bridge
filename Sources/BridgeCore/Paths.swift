import Foundation
import CryptoKit
import Synchronization

// Stable, beta and dev share one code base; each flavour has its own app, CLI
// name and state dir. The CLI learns its flavour from its basename, the app
// from its bundle identifier.
public enum Flavor {
    public static let all = ["bridge", "bridge-beta", "bridge-dev"]
    nonisolated(unsafe) public static var name: String = ProcessInfo.processInfo.environment["BRIDGE_NAME"] ?? "bridge-dev"

    public static var appName: String {
        switch name { case "bridge": return "Bridge"; case "bridge-beta": return "Bridge Beta"; default: return "Bridge Dev" }
    }
    public static var executable: String { appName.replacingOccurrences(of: " ", with: "") }
    public static var bundleID: String {
        switch name { case "bridge": return "com.medienbaecker.bridge.app"; case "bridge-beta": return "com.medienbaecker.bridge.beta"; default: return "com.medienbaecker.bridge-dev" }
    }

    public static func fromCLI(_ argv0: String) -> String {
        let base = (argv0 as NSString).lastPathComponent
        if let env = ProcessInfo.processInfo.environment["BRIDGE_NAME"], !env.isEmpty { return env }
        return all.contains(base) ? base : "bridge-dev"
    }

    public static func fromBundle(_ identifier: String?) -> String {
        if let env = ProcessInfo.processInfo.environment["BRIDGE_NAME"], !env.isEmpty { return env }
        switch identifier { case "com.medienbaecker.bridge.app": return "bridge"; case "com.medienbaecker.bridge.beta": return "bridge-beta"; default: return "bridge-dev" }
    }
}

public enum Paths {
    public static var stateDir: URL { stateDir(for: Flavor.name) }

    // Resolved once per process: looking up the home directory on every call
    // grew each long-running waiter by about 30 MB a minute.
    static let stateBase: URL = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
    static let made = Mutex<Set<String>>([])

    public static func stateDir(for flavor: String) -> URL {
        let dir = stateBase.appendingPathComponent(flavor)
        made.withLock { made in
            if made.insert(flavor).inserted {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        return dir
    }

    // Unix socket paths are limited to 104 bytes and a state directory is a
    // user-chosen path of any length, so the socket lives under the temp
    // directory, named after the state directory it belongs to.
    public static var socket: URL {
        if let s = ProcessInfo.processInfo.environment["BRIDGE_SOCKET"], !s.isEmpty { return URL(fileURLWithPath: s) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Flavor.name)-\(id(for: stateDir.path)).sock")
    }
    public static var launchError: URL { stateDir.appendingPathComponent("launch-error.txt") }
    public static var list: URL { stateDir.appendingPathComponent("list.json") }
    public static var versions: URL { stateDir.appendingPathComponent("versions") }
    public static var builds: URL { stateDir.appendingPathComponent("builds") }

    public static func id(for location: String) -> String {
        let digest = SHA256.hash(data: Data(location.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Records live in the app's store, not beside pages: beside them they
    /// cluttered the user's folders and died with deleted scratch folders. A
    /// record from before the store is copied in the first time its page is
    /// touched, and the old file is renamed `.bridge.json.migrated` so nothing
    /// mistakes a left-behind copy for the live one.
    /// Off, records beside pages are left alone: for seeding another flavour
    /// or working on a copy of the list.
    nonisolated(unsafe) public static var migrates = ProcessInfo.processInfo.environment["BRIDGE_NO_MIGRATE"] != "1"

    public static func sidecar(for location: String) -> URL {
        let dir = stateDir.appendingPathComponent("answers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let isURL = location.hasPrefix("http://") || location.hasPrefix("https://")
        // Keyed by the file itself, not the spelling of its path: `/tmp/x` and
        // `/private/tmp/x` are one page and must be one record.
        let key = isURL ? location : canonical(location)
        let name = isURL ? id(for: key) : (key as NSString).lastPathComponent + "-" + id(for: key)
        let url = dir.appendingPathComponent(name + ".bridge.json")
        if migrates, !FileManager.default.fileExists(atPath: url.path) {
            let legacy = legacySidecar(for: location)
            if FileManager.default.fileExists(atPath: legacy.path), (try? FileManager.default.copyItem(at: legacy, to: url)) != nil {
                try? FileManager.default.moveItem(at: legacy, to: legacy.appendingPathExtension("migrated"))
            }
        }
        return url
    }

    /// Where a record lived before the store: beside the page, or under `urls/` for a site.
    public static func legacySidecar(for location: String) -> URL {
        if location.hasPrefix("http://") || location.hasPrefix("https://") {
            return stateDir.appendingPathComponent("urls").appendingPathComponent(id(for: location) + ".bridge.json")
        }
        return URL(fileURLWithPath: location + ".bridge.json")
    }

    public static func dataFile(for location: String) -> URL {
        URL(fileURLWithPath: location).deletingPathExtension().appendingPathExtension("data.json")
    }

    public static func resolve(_ path: String, relativeTo cwd: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: cwd).appendingPathComponent(path)
        return canonical(url.path)
    }

    static func canonical(_ path: String) -> String {
        var dir = URL(fileURLWithPath: path).standardizedFileURL, rest: [String] = []
        while dir.path != "/", !FileManager.default.fileExists(atPath: dir.path) {
            rest.insert(dir.lastPathComponent, at: 0)
            dir.deleteLastPathComponent()
        }
        return rest.reduce(dir.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.path
    }
}

public enum Session {
    public static var current: String {
        let env = ProcessInfo.processInfo.environment
        if let s = env["BRIDGE_SESSION"], !s.isEmpty { return s }
        if let s = env["CLAUDE_CODE_SESSION_ID"], !s.isEmpty { return s }
        if let tty = ttyname(0) { return String(cString: tty) }
        return "anonymous"
    }
}

public struct Ground: Codable, Equatable, Sendable {
    public var repo: String
    public var branch: String
    public var commit: String

    public init(repo: String, branch: String, commit: String) {
        self.repo = repo; self.branch = branch; self.commit = commit
    }

    public static func current(in cwd: String) -> Ground? {
        guard let repo = git(["rev-parse", "--show-toplevel"], in: cwd) else { return nil }
        let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], in: cwd) ?? "HEAD"
        let commit = git(["rev-parse", "--short", "HEAD"], in: cwd) ?? ""
        return Ground(repo: repo, branch: branch, commit: commit)
    }

    public func commitsSince() -> Int? {
        guard let n = Self.git(["rev-list", "--count", "\(commit)..HEAD"], in: repo) else { return nil }
        return Int(n)
    }

    public static func projectRoot(for cwd: String) -> String {
        if let repo = git(["rev-parse", "--show-toplevel"], in: cwd) { return repo }
        return claudeScratchpadProject(cwd) ?? cwd
    }

    /// A session whose cwd is its own scratchpad is in no repo, and naming the project
    /// after the last path component would file every such session under `scratchpad`.
    /// The real project is in the path: `/tmp/claude-<uid>/<encoded>/<uuid>/scratchpad`,
    /// where `<encoded>` is the cwd with every separator turned into a dash.
    ///
    /// That encoding is lossy: a dash in a directory name looks like a separator, and a
    /// naive decode reads `-Users-…-Projects-test-alter` as `Projects/test/alter` when a
    /// `test` directory exists. So walk only as deep as the filesystem confirms, longest
    /// component first, then take everything left as one name. That keeps `Project-A`
    /// and `test-alter` whole and still names a project whose folder is gone.
    static func claudeScratchpadProject(_ cwd: String) -> String? {
        let parts = (cwd as NSString).pathComponents
        // Positional, not "ends in scratchpad": an agent that cd'd into a folder of
        // its own scratchpad is still in that session's project.
        guard let tmp = parts.firstIndex(where: { $0.hasPrefix("claude-") }),
              parts.count > tmp + 3, parts[tmp + 3] == "scratchpad",
              case let encoded = parts[tmp + 1], encoded.hasPrefix("-")
        else { return nil }
        var parent = "/"
        var rest = encoded.dropFirst().components(separatedBy: "-")
        while !rest.isEmpty {
            var took = false
            for n in stride(from: rest.count, through: 1, by: -1) {
                let candidate = (parent as NSString).appendingPathComponent(rest.prefix(n).joined(separator: "-"))
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue else { continue }
                parent = candidate
                rest = Array(rest.dropFirst(n))
                took = true
                break
            }
            if !took { break }
        }
        guard parent != "/" || !rest.isEmpty else { return nil }
        return rest.isEmpty ? parent : (parent as NSString).appendingPathComponent(rest.joined(separator: "-"))
    }

    static func git(_ args: [String], in dir: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
