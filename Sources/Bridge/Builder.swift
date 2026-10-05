import Foundation
import BridgeCore

enum Builder {
    struct Failure: Sendable { var text: String; var file: String?; var line: Int?; var lineText: String? }
    enum Result: Sendable { case built(URL, ms: Int), failed([Failure]) }

    nonisolated static let toolkit: URL? = {
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let t = env["BRIDGE_TOOLKIT"] { candidates.append(URL(fileURLWithPath: t)) }
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/bridge/toolkit"))
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/bridge-dev/toolkit"))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("toolkit"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("build.mjs").path) }
    }()

    nonisolated static let node: String? = {
        if let n = ProcessInfo.processInfo.environment["BRIDGE_NODE"] { return n }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v node"]
        let out = Pipe()
        probe.standardOutput = out
        probe.standardError = FileHandle.nullDevice
        try? probe.run()
        let found = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        probe.waitUntilExit()
        if !found.isEmpty { return found }
        return ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    @concurrent static func build(_ source: String) async -> Result {
        guard let toolkit else { return .failed([Failure(text: "The Mantine toolkit is not installed (no toolkit/build.mjs found; set BRIDGE_TOOLKIT).")]) }
        guard let node else { return .failed([Failure(text: "node was not found; set BRIDGE_NODE to its path.")]) }
        let out = Paths.builds.appendingPathComponent(Paths.id(for: source))
        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [toolkit.appendingPathComponent("build.mjs").path, "page", source, out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return .failed([Failure(text: "could not run node: \(error)")]) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if p.terminationStatus == 0, json?["ok"] as? Bool == true { return .built(out.appendingPathComponent("index.html"), ms: ms) }
        let errors = (json?["errors"] as? [[String: Any]])?.map {
            Failure(text: $0["text"] as? String ?? "build failed", file: $0["file"] as? String, line: $0["line"] as? Int, lineText: $0["lineText"] as? String)
        } ?? [Failure(text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))]
        return .failed(errors)
    }

    static func failurePage(_ source: String, _ failures: [Failure]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let items = failures.map { f in
            var where_ = ""
            if let line = f.line { where_ = "<div class=\"muted\">\(esc((source as NSString).lastPathComponent)):\(line)</div>" }
            let code = f.lineText.map { "<pre>\(esc($0))</pre>" } ?? ""
            return "<div class=\"evidence\"><strong>\(esc(f.text))</strong>\(where_)\(code)</div>"
        }.joined()
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Build failed</title></head>
        <body data-bridge-build-failed>
        <script>document.addEventListener('DOMContentLoaded', () => document.dispatchEvent(new Event('bridge:rendered')))</script>
        <h1>Build failed</h1>
        <p class="muted">\(esc(source)) did not compile. The page will build again as soon as the file is saved.</p>
        \(items)
        </body></html>
        """
    }
}
