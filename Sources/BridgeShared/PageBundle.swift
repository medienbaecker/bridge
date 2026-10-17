import Foundation
import CryptoKit
import BridgeCore

public struct PageBundle: Codable, Equatable, Sendable {
    public var html: String
    public var files: [String: Data]

    public static let limit = 50 * 1024 * 1024

    public init(html: String, files: [String: Data]) {
        self.html = html; self.files = files
    }

    static let reference = try! NSRegularExpression(pattern: #"(\b(?:src|href|poster)\s*=\s*)(["'])([^"']*)\2"#, options: .caseInsensitive)

    public static func make(page: URL) throws -> PageBundle {
        var html = String(decoding: try Data(contentsOf: page), as: UTF8.self)
        let folder = page.deletingLastPathComponent()
        var files: [String: Data] = [:]
        var total = 0
        let source = html
        for m in reference.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(m.range(at: 3), in: source), let path = local(String(source[range]), in: folder) else { continue }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let name = "files/" + digest(path) + "-" + (path as NSString).lastPathComponent
            if files[name] == nil { total += data.count; files[name] = data }
            guard total <= limit else { throw TooLarge(bytes: total) }
            html.replaceSubrange(Range(m.range(at: 3), in: html)!, with: name)
        }
        return PageBundle(html: html, files: files)
    }

    public func install(into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("files"), withIntermediateDirectories: true)
        for (name, data) in files {
            guard name.hasPrefix("files/"), !name.contains(".."), !name.dropFirst(6).contains("/") else { throw Unsafe(name: name) }
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        let page = dir.appendingPathComponent("page.html")
        try Data(html.utf8).write(to: page, options: .atomic)
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
        public var description: String { "refused a shared file named \(name)" }
    }
}

public struct Share: Codable, Equatable, Sendable {
    public var id: String
    public var location: String
    public var from: String
    public var title: String

    public init(id: String, location: String, from: String, title: String) {
        self.id = id; self.location = location; self.from = from; self.title = title
    }
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
