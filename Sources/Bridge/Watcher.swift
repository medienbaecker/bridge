import Foundation
import CoreServices

final class Watcher {
    static var calls = 0
    let files: [String]
    let folders: [String]
    private var directories: [WatchedDirectory] = []

    init(files: [String], folders: [String] = [], onChange: @escaping () -> Void) {
        self.files = files
        self.folders = folders
        var interests: [String: WatchedDirectory.Interest] = [:]
        for file in files {
            let folder = (file as NSString).deletingLastPathComponent
            interests[folder, default: .init(onChange: onChange)].names.insert((file as NSString).lastPathComponent.lowercased())
        }
        for folder in folders { interests[folder, default: .init(onChange: onChange)].everything = true }
        directories = interests.map { WatchedDirectory.join($0.key, as: ObjectIdentifier(self), $0.value) }
    }

    isolated deinit {
        for directory in directories { directory.leave(ObjectIdentifier(self)) }
    }
}

final class WatchedDirectory {
    struct Interest {
        var names: Set<String> = []
        var everything = false
        let onChange: () -> Void
    }

    static var open: [String: WatchedDirectory] = [:]
    let path: String
    var stream: FSEventStreamRef?
    var interests: [ObjectIdentifier: Interest] = [:]

    static func join(_ path: String, as watcher: ObjectIdentifier, _ interest: Interest) -> WatchedDirectory {
        let directory = open[path] ?? WatchedDirectory(path: path)
        open[path] = directory
        directory.interests[watcher] = interest
        return directory
    }

    init(path: String) {
        self.path = path
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                if let info { _ = Unmanaged<WatchedDirectory>.fromOpaque(info).retain() }
                return info
            },
            release: { info in
                if let info { Unmanaged<WatchedDirectory>.fromOpaque(info).release() }
            },
            copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let directory = Unmanaged<WatchedDirectory>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let lost = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
            let everything = UnsafeBufferPointer(start: flags, count: count).contains { $0 & lost != 0 }
            MainActor.assumeIsolated { directory.changed(paths, everything: everything) }
        }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.04,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else {
            NSLog("Bridge cannot watch %@", path)
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func leave(_ watcher: ObjectIdentifier) {
        interests[watcher] = nil
        guard interests.isEmpty else { return }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        Self.open[path] = nil
    }

    func changed(_ paths: [String], everything: Bool) {
        let folder = Self.real(path).lowercased()
        var names: Set<String> = []
        var everything = everything
        for changed in paths.map({ $0.lowercased() }) {
            if changed == folder || folder.hasPrefix(changed + "/") { everything = true }
            else if (changed as NSString).deletingLastPathComponent == folder { names.insert((changed as NSString).lastPathComponent) }
        }
        for interest in Array(interests.values) where everything || interest.everything && !names.isEmpty || !interest.names.isDisjoint(with: names) {
            Watcher.calls += 1
            interest.onChange()
        }
    }

    static func real(_ path: String) -> String {
        var folder = path
        var rest: [String] = []
        while folder != "/" {
            if let resolved = realpath(folder, nil) {
                defer { free(resolved) }
                return rest.reduce(String(cString: resolved)) { ($0 as NSString).appendingPathComponent($1) }
            }
            rest.insert((folder as NSString).lastPathComponent, at: 0)
            folder = (folder as NSString).deletingLastPathComponent
        }
        return path
    }
}
