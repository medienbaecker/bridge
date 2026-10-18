import Foundation
import CryptoKit
import BridgeCore

public struct PageBundle: Codable, Equatable, Sendable {
    public var html: String
    public var files: [String: Data]
    public var main = "page.html"
    public var binary: Data?
    public var pageData: Data?
    public var origins: [String: String] = [:]

    enum CodingKeys: String, CodingKey { case html, files, main, binary, pageData }

    public var content: Data { binary ?? Data(html.utf8) }

    public static let limit = 50 * 1024 * 1024

    public init(html: String, files: [String: Data]) {
        self.html = html; self.files = files
    }

    static let reference = try! NSRegularExpression(pattern: #"(\b(?:src|href|poster)\s*=\s*)(["'])([^"']*)\2"#, options: .caseInsensitive)

    public static func make(page: URL, known: [String: String] = [:]) throws -> PageBundle {
        let kind = Kind.of(page.path)
        let ext = page.pathExtension.lowercased()
        let main = "page." + (ext.isEmpty ? "txt" : ext)
        let raw = try Data(contentsOf: page)
        guard raw.count <= limit else { throw TooLarge(bytes: raw.count) }
        if kind == .image || kind == .pdf {
            var bundle = PageBundle(html: "", files: [:])
            bundle.main = main
            bundle.binary = raw
            return bundle
        }
        var pageData: Data?
        if kind == .jsx { pageData = try? Data(contentsOf: Paths.dataFile(for: page.path)) }
        var html = String(decoding: raw, as: UTF8.self)
        guard kind == .html || kind == .svg || kind == .md else {
            var bundle = PageBundle(html: html, files: [:])
            bundle.main = main
            bundle.pageData = pageData
            return bundle
        }
        let folder = page.deletingLastPathComponent()
        html = Quote.inline(html, in: folder)
        var files: [String: Data] = [:]
        var origins: [String: String] = [:]
        var total = 0
        let source = html
        for m in reference.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(m.range(at: 3), in: source), let path = local(String(source[range]), in: folder) else { continue }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let given = String(source[range])
            let name = given.hasPrefix("files/") && path == folder.appendingPathComponent(given).standardizedFileURL.path
                ? given : known[path] ?? "files/" + digest(path) + "-" + (path as NSString).lastPathComponent
            origins[name] = path
            if files[name] == nil { total += data.count; files[name] = data }
            guard total <= limit else { throw TooLarge(bytes: total) }
            html.replaceSubrange(Range(m.range(at: 3), in: html)!, with: name)
        }
        var bundle = PageBundle(html: html, files: files)
        bundle.main = main
        bundle.origins = origins
        return bundle
    }

    public static func restore(_ html: String, origins: [String: String], folder: URL) -> String {
        var out = html
        for m in reference.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(m.range(at: 3), in: html) else { continue }
            let value = String(html[range])
            guard value.hasPrefix("files/") else { continue }
            let name = String(value[..<(value.firstIndex { $0 == "?" || $0 == "#" } ?? value.endIndex)])
            out.replaceSubrange(Range(m.range(at: 3), in: out)!, with: origins[name] ?? folder.appendingPathComponent(name).path)
        }
        return out
    }

    public func install(into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("files"), withIntermediateDirectories: true)
        for (name, data) in files {
            guard name.hasPrefix("files/"), !name.contains(".."), !name.dropFirst(6).contains("/") else { throw Unsafe(name: name) }
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        guard main.hasPrefix("page."), !main.contains("/") else { throw Unsafe(name: main) }
        let page = dir.appendingPathComponent(main)
        if let pageData { try pageData.write(to: Paths.dataFile(for: page.path), options: .atomic) }
        try content.write(to: page, options: .atomic)
        return page
    }

    static func local(_ value: String, in folder: URL) -> String? {
        let given = String(value[..<(value.firstIndex { $0 == "?" || $0 == "#" } ?? value.endIndex)])
        let path: String
        if given.hasPrefix("file://") {
            path = String(given.dropFirst("file://".count)).removingPercentEncoding ?? ""
        } else if given.hasPrefix("/"), !given.hasPrefix("//") {
            path = given
        } else if !given.isEmpty, !given.contains(":"), !given.hasPrefix("//") {
            path = folder.appendingPathComponent(given).standardizedFileURL.path
        } else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return path
    }

    static func digest(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    public struct TooLarge: Error, CustomStringConvertible {
        public let bytes: Int
        public var description: String { "the page and its files come to \(bytes / 1_048_576) MB; sharing stops at \(PageBundle.limit / 1_048_576) MB" }
    }

    public struct Unsafe: Error, CustomStringConvertible {
        public let name: String
        public init(name: String) { self.name = name }
        public var description: String { "refused a shared file named \(name)" }
    }
}

public struct Share: Codable, Equatable, Sendable {
    public var id: String
    public var location: String
    public var from: String
    public var title: String
    public var origins: [String: String]?
    public var synced: String?
    public var clock: Int?
    public var writer: String?

    public func older(than clock: Int, by writer: String) -> Bool {
        (self.clock ?? 0, self.writer ?? "") < (clock, writer)
    }

    public init(id: String, location: String, from: String, title: String) {
        self.id = id; self.location = location; self.from = from; self.title = title
    }

    public var received: Bool { location.hasPrefix(Paths.shared.path + "/") }
}

public enum Shares {
    public static var file: URL { Paths.stateDir.appendingPathComponent("shares.json") }
    public static var folder: URL { Paths.shared }

    public static func load() -> [Share] {
        (try? Data(contentsOf: file)).flatMap { try? JSON.decoder.decode([Share].self, from: $0) } ?? []
    }

    public static func save(_ shares: [Share]) throws {
        try JSON.encoder.encode(shares).write(to: file, options: .atomic)
    }
}
