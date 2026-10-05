import Foundation
import Darwin

public struct Waiter: Codable, Equatable, Sendable {
    public var pid: Int32
    public var kind: String
    public var session: String
    public var locations: [String]
    public var flavor: String
    // A pid the system reused must not pass for this process.
    public var startSec: Int
    public var started: Date
    public var bytes: UInt64?

    public var megabytes: Int { Int((bytes ?? 0) / 1_000_000) }
}

public enum Waiters {
    static func dir(_ flavor: String) -> URL {
        Paths.stateDir(for: flavor).appendingPathComponent("waiters")
    }

    nonisolated(unsafe) static var registered: String?
    nonisolated(unsafe) static var mine: Waiter?

    public static func superseded() -> Bool {
        guard let mine else { return false }
        return autoreleasepool {
            all().contains { $0.pid != mine.pid && $0.kind == mine.kind && $0.session == mine.session && $0.started > mine.started }
        }
    }

    // A killed process cannot take its file back, so readers drop files whose process is gone.
    public static func register(kind: String, session: String, locations: [String]) {
        let pid = getpid()
        guard registered == nil, let start = startSec(of: pid) else { return }
        let folder = dir(Flavor.name)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(pid).json")
        let me = Waiter(pid: pid, kind: kind, session: session, locations: locations, flavor: Flavor.name, startSec: start, started: Date())
        guard (try? JSON.encoder.encode(me).write(to: url, options: .atomic)) != nil else { return }
        registered = url.path
        mine = me
        atexit { if let path = Waiters.registered { unlink(path) } }
    }

    public static func all() -> [Waiter] {
        var out: [Waiter] = []
        for flavor in Flavor.all {
            for file in (try? FileManager.default.contentsOfDirectory(at: dir(flavor), includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
                guard var w = (try? Data(contentsOf: file)).flatMap({ try? JSON.decoder.decode(Waiter.self, from: $0) }),
                      startSec(of: w.pid) == w.startSec
                else { try? FileManager.default.removeItem(at: file); continue }
                w.bytes = footprint(of: w.pid)
                out.append(w)
            }
        }
        return out.sorted { $0.started < $1.started }
    }

    static func startSec(of pid: Int32) -> Int? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int(info.pbi_start_tvsec)
    }

    static func footprint(of pid: Int32) -> UInt64? {
        var usage = rusage_info_v2()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0 }
        }
        return ok ? usage.ri_phys_footprint : nil
    }
}
