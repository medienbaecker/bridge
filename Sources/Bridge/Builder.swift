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
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("dist/vendor.js").path) }
    }()

    nonisolated static let modules = ["react", "react-dom", "react-dom/client", "react/jsx-runtime", "@mantine/core", "@mantine/hooks"]

    @concurrent static func build(_ source: String) async -> Result {
        guard let toolkit else { return .failed([Failure(text: "The Mantine toolkit is not installed (no toolkit/dist/vendor.js found; set BRIDGE_TOOLKIT).")]) }
        let esbuild = ProcessInfo.processInfo.environment["BRIDGE_ESBUILD"] ?? toolkit.appendingPathComponent("bin/esbuild").path
        guard FileManager.default.isExecutableFile(atPath: esbuild) else { return .failed([Failure(text: "esbuild was not found at \(esbuild); set BRIDGE_ESBUILD to its path.")]) }
        let out = Paths.builds.appendingPathComponent(Paths.id(for: source))
        let dist = toolkit.appendingPathComponent("dist")
        let dir = URL(fileURLWithPath: source).deletingLastPathComponent()
        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: esbuild)
        p.currentDirectoryURL = dir
        p.arguments = [
            toolkit.appendingPathComponent("scaffold.jsx").path,
            "--bundle", "--format=iife", "--platform=browser", "--target=safari26", "--jsx=automatic",
            "--define:process.env.NODE_ENV=\"production\"",
            "--alias:@bridge=" + toolkit.appendingPathComponent("bridge.js").path,
            "--alias:@page=" + source,
            "--outfile=" + out.appendingPathComponent("page.js").path,
            "--log-level=error", "--color=false",
        ] + modules.map { "--alias:\($0)=" + dist.appendingPathComponent("shims/" + $0.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: "/", with: "_") + ".js").path }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return .failed([Failure(text: "could not run esbuild: \(error)")]) }
        let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return .failed(failures(log, in: dir)) }

        let dataFile = Paths.dataFile(for: source)
        var data = "null"
        var title = (source as NSString).lastPathComponent.replacingOccurrences(of: #"\.[jt]sx$"#, with: "", options: .regularExpression)
        if let raw = try? Data(contentsOf: dataFile) {
            do {
                let parsed = try JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed)
                if let t = (parsed as? [String: Any])?["title"] as? String { title = t }
                data = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
                return .failed([Failure(text: "page.data.json is not valid JSON: \(reason)", file: dataFile.path)])
            }
        }
        func stamped(_ file: URL) -> String {
            let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date()
            return file.absoluteString + "?v=\(Int((modified.timeIntervalSince1970 * 1000).rounded(.down)))"
        }
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(title.replacingOccurrences(of: "<", with: "&lt;"))</title>
        <link rel="stylesheet" href="\(stamped(dist.appendingPathComponent("mantine.css")))">
        <link rel="stylesheet" href="\(stamped(toolkit.appendingPathComponent("theme.css")))">
        <script>window.__bridgeData = \(data.replacingOccurrences(of: "<", with: "\\u003c"));</script>
        </head>
        <body>
        <div id="root"></div>
        <script src="\(stamped(dist.appendingPathComponent("vendor.js")))"></script>
        <script src="page.js?v=\(Int(Date().timeIntervalSince1970 * 1000))"></script>
        </body>
        </html>

        """
        do { try html.write(to: out.appendingPathComponent("index.html"), atomically: true, encoding: .utf8) }
        catch { return .failed([Failure(text: "could not write index.html: \(error)")]) }
        return .built(out.appendingPathComponent("index.html"), ms: Int(Date().timeIntervalSince(started) * 1000))
    }

    nonisolated static func failures(_ log: String, in dir: URL) -> [Failure] {
        var failures: [Failure] = []
        for line in log.components(separatedBy: "\n") {
            if line.hasPrefix("✘ [ERROR] ") {
                failures.append(Failure(text: String(line.dropFirst("✘ [ERROR] ".count))))
            } else if var last = failures.last, last.file == nil,
                      let m = line.wholeMatch(of: /\ {4}(.+):(\d+):(\d+):/), let n = Int(m.2) {
                last.file = String(m.1)
                last.line = n
                let path = dir.appendingPathComponent(last.file!).path
                let lines = (try? String(contentsOfFile: path, encoding: .utf8))?.components(separatedBy: "\n")
                if let lines, n >= 1, n <= lines.count { last.lineText = lines[n - 1] }
                failures[failures.count - 1] = last
            }
        }
        let text = log.trimmingCharacters(in: .whitespacesAndNewlines)
        return failures.isEmpty ? [Failure(text: text.isEmpty ? "build failed" : text)] : failures
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
