import Foundation
import Darwin

public enum ClaudeSessions {
    public enum Life: String, Sendable { case unknown, gone, working, idle }

    public struct Live: Sendable, Equatable {
        public let pid: Int32
        public let session: String
        public let cwd: String
        public let name: String
        public let life: Life
        public let socket: String
    }

    nonisolated(unsafe) static var dir: URL = {
        let env = ProcessInfo.processInfo.environment
        if let d = env["BRIDGE_CLAUDE_SESSIONS"], !d.isEmpty { return URL(fileURLWithPath: d) }
        let config = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return config.appendingPathComponent("sessions")
    }()

    public static func live() -> [String: Live] {
        autoreleasepool {
            var out: [String: Live] = [:]
            for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let pid = (obj["pid"] as? NSNumber)?.int32Value, pid > 0,
                      let session = obj["sessionId"] as? String, !session.isEmpty,
                      kill(pid, 0) == 0 || errno == EPERM
                else { continue }
                out[session] = Live(pid: pid, session: session, cwd: obj["cwd"] as? String ?? "", name: obj["name"] as? String ?? "",
                                    life: obj["status"] as? String == "busy" ? .working : .idle,
                                    socket: obj["messagingSocketPath"] as? String ?? "")
            }
            return out
        }
    }

    public static func life(of session: String, in live: [String: Live]? = nil) -> Life {
        if let found = (live ?? Self.live())[session] { return found.life }
        return FileManager.default.fileExists(atPath: dir.path) ? .gone : .unknown
    }

    public static func post(_ text: String, to live: Live) -> Bool {
        let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        guard !live.socket.isEmpty, var data = try? JSONSerialization.data(withJSONObject: line) else { return false }
        data.append(0x0A)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(live.socket.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in path.withUnsafeBytes { raw.copyMemory(from: $0) } }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return false }
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + sent, data.count - sent) }
            guard n > 0 else { return false }
            sent += n
        }
        return true
    }
}
