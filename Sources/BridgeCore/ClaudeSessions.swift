import Foundation
import Darwin

/// Claude Code sessions as `bridge --hook session` records them: one file per live session,
/// removed at SessionEnd. Every flavour's hook writes to and every flavour's app reads
/// from the stable flavour's state dir, since one hook serves them all.
public enum ClaudeSessions {
    public enum Life: String, Sendable { case unknown, gone, working, idle }

    nonisolated(unsafe) static var dir = Paths.stateBase.appendingPathComponent("bridge/sessions")

    public static func record(_ event: String, session: String, pid: Int32, cwd: String = "") {
        guard !session.isEmpty, !session.contains("/") else { return }
        let file = dir.appendingPathComponent("\(session).json")
        let state: String
        switch event {
        case "SessionEnd": try? FileManager.default.removeItem(at: file); return
        case "UserPromptSubmit": state = "working"
        case "SessionStart", "Stop": state = "idle"
        default: return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let kept = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["cwd"] as? String ?? ""
        guard let data = try? JSONSerialization.data(withJSONObject: ["pid": Int(pid), "state": state, "cwd": cwd.isEmpty ? kept : cwd]) else { return }
        try? data.write(to: file, options: .atomic)
    }

    public struct Live: Sendable {
        public let session: String
        public let cwd: String
        public let life: Life
    }

    public static func live() -> [Live] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            let session = file.deletingPathExtension().lastPathComponent
            let life = life(of: session)
            guard life != .gone, let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            return Live(session: session, cwd: obj["cwd"] as? String ?? "", life: life)
        }
    }

    nonisolated(unsafe) static var transcripts = ProcessInfo.processInfo.environment["BRIDGE_TRANSCRIPTS"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    public struct About: Sendable {
        public let topic: String?
        public let cwd: String?
    }

    public static func about(_ session: String) -> About {
        guard !session.isEmpty, !session.contains("/"),
              let folders = try? FileManager.default.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil),
              let file = folders.map({ $0.appendingPathComponent("\(session).jsonl") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let handle = try? FileHandle(forReadingFrom: file) else { return About(topic: nil, cwd: nil) }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 256 * 1024)) ?? Data(), as: UTF8.self)
        var cwd: String?
        for line in head.split(separator: "\n") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if cwd == nil { cwd = obj["cwd"] as? String }
            guard obj["type"] as? String == "user", (obj["isSidechain"] as? Bool) != true,
                  let text = (obj["message"] as? [String: Any])?["content"] as? String else { continue }
            let first = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
            guard !first.isEmpty, !first.hasPrefix("<") else { continue }
            return About(topic: first.count > 48 ? String(first.prefix(47)) + "…" : first, cwd: cwd ?? obj["cwd"] as? String)
        }
        return About(topic: nil, cwd: cwd)
    }

    public static func life(of session: String) -> Life {
        autoreleasepool {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return .unknown }
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(session).json")),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return .gone }
            if let pid = (obj["pid"] as? NSNumber)?.int32Value, pid > 0, kill(pid, 0) != 0, errno == ESRCH { return .gone }
            return obj["state"] as? String == "working" ? .working : .idle
        }
    }

    /// Hooks run through a shell, so the Claude Code process is an ancestor rather than
    /// the parent. Without one, 0: the shell itself exits as soon as the hook does.
    public static func claudePID() -> Int32 {
        var pid = getppid()
        for _ in 0..<12 {
            var buf = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).lowercased().contains("claude") { return pid }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else { break }
            pid = Int32(info.pbi_ppid)
        }
        return 0
    }
}
