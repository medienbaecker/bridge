import Foundation

// Watches a directory (renames, atomic replaces, new files) and the named files
// themselves (in-place writes and appends, which never touch the directory).
// File sources go stale when a file is replaced, so they are reopened after
// every event.
final class Watcher {
    let directory: URL
    let files: [String]
    let onChange: () -> Void
    var sources: [DispatchSourceFileSystemObject] = []
    var pending: DispatchWorkItem?

    init(directory: URL, files: [String], onChange: @escaping () -> Void) {
        self.directory = directory
        self.files = files
        self.onChange = onChange
        open()
    }

    func open() {
        for s in sources { s.cancel() }
        sources = ([directory.path] + files).compactMap { path in
            let fd = Darwin.open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: .global())
            source.setCancelHandler { @Sendable in close(fd) }
            source.setEventHandler { @Sendable [self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.fire() } }
            }
            source.resume()
            return source
        }
    }

    func fire() {
        pending?.cancel()
        let item = DispatchWorkItem { [self] in
            open()
            onChange()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    deinit { for s in sources { s.cancel() } }
}
