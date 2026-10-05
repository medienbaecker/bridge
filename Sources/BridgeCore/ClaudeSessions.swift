import Foundation
import Darwin

/// Claude Code sessions as `bridge --hook session` records them: one file per live session,
/// removed at SessionEnd. Every flavour's hook writes to and every flavour's app reads
/// from the stable flavour's state dir, since one hook serves them all.
public enum ClaudeSessions {
    public enum Life: String, Sendable { case unknown, gone, working, idle }

    nonisolated(unsafe) static var dir = Paths.stateBase.appendingPathComponent("bridge/sessions")

    public static func record(_ event: String, session: String, pid: Int32) {
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
        guard let data = try? JSONSerialization.data(withJSONObject: ["pid": Int(pid), "state": state]) else { return }
        try? data.write(to: file, options: .atomic)
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
