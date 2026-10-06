import Foundation

public enum Request: Codable, Sendable {
    case present(locations: [String], cwd: String, session: String, ground: Ground?, links: String?)
    case state
    case audit(location: String)
    case cross(location: String)
    case uncross(location: String)
    case remove(location: String)
    case reset(location: String)
    case reply(location: String, id: String, text: String)
    case note(location: String, id: String, state: String)
    case collect(location: String, session: String)
    case js(location: String?, code: String)
    case command(name: String, argument: String?)
    case snapshot(path: String)
    case shot(path: String, screen: Bool)
    case render(location: String, path: String, width: Double?)
    case quit
}

public enum Response: Codable, Sendable {
    case ok(JSONValue)
    case error(String)

    public var value: JSONValue? { if case .ok(let v) = self { return v }; return nil }
}

public enum SocketError: Error { case unavailable, io(String) }

public enum Client {
    public static func send(_ request: Request) throws -> Response {
        let fd = try connect()
        defer { close(fd) }
        var line = try JSON.compact.encode(request)
        line.append(0x0A)
        try writeAll(fd, line)
        let data = try readLine(fd)
        return try JSON.decoder.decode(Response.self, from: data)
    }

    public static var appIsRunning: Bool {
        guard let fd = try? connect() else { return false }
        close(fd)
        return true
    }

    static func connect() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.unavailable }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Paths.socket.path
        guard path.utf8.count < 104 else { close(fd); throw SocketError.io("socket path too long") }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                _ = strlcpy(dst, path, 104)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        guard rc == 0 else { close(fd); throw SocketError.unavailable }
        // An app that accepts the connection while quitting may never answer;
        // no reply in a minute is an error, not a wait.
        var patience = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &patience, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                guard n > 0 else { throw SocketError.io("write failed") }
                offset += n
            }
        }
    }

    static func readLine(_ fd: Int32) throws -> Data {
        var out = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            out.append(contentsOf: chunk[0..<n])
            if chunk[n - 1] == 0x0A { break }
        }
        guard !out.isEmpty else { throw SocketError.io("empty reply") }
        return out
    }
}

public final class Server: @unchecked Sendable {
    public typealias Handler = @Sendable (Request, @escaping @Sendable (Response) -> Void) -> Void
    let handler: Handler
    var listenFD: Int32 = -1

    public init(handler: @escaping Handler) { self.handler = handler }

    public func start() -> String? {
        let path = Paths.socket.path
        guard path.utf8.count < 104 else { return "socket path is \(path.utf8.count) bytes, the limit is 104: \(path)" }
        if Client.appIsRunning { return "another \(Flavor.appName) is already answering on \(path)" }
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return "cannot create socket: \(String(cString: strerror(errno)))" }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { return "cannot bind \(path): \(String(cString: strerror(errno)))" }
        guard listen(listenFD, 16) == 0 else { return "cannot listen on \(path): \(String(cString: strerror(errno)))" }
        let fd = listenFD
        Thread.detachNewThread { [self] in
            while true {
                let conn = accept(fd, nil, nil)
                if conn < 0 { break }
                Thread.detachNewThread { self.serve(conn) }
            }
        }
        try? FileManager.default.removeItem(at: Paths.launchError)
        return nil
    }

    func serve(_ conn: Int32) {
        guard let data = try? Client.readLine(conn),
              let request = try? JSON.decoder.decode(Request.self, from: data) else {
            close(conn); return
        }
        handler(request) { response in
            var line = (try? JSON.compact.encode(response)) ?? Data()
            line.append(0x0A)
            try? Client.writeAll(conn, line)
            close(conn)
        }
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(Paths.socket.path)
    }
}
