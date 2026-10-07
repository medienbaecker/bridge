import Foundation

public enum Kind: String, Codable, Sendable {
    case html, jsx, md, text, image, svg, pdf, url

    public static func of(_ location: String) -> Kind {
        if location.hasPrefix("http://") || location.hasPrefix("https://") { return .url }
        switch (location as NSString).pathExtension.lowercased() {
        case "html", "htm": return .html
        case "jsx", "tsx": return .jsx
        case "md", "markdown": return .md
        case "svg": return .svg
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "avif": return .image
        default: return .text
        }
    }

    public var isDocument: Bool { self != .url && self != .pdf }
}

public enum Links: String, Codable, Sendable {
    case window, browser, external
}

public struct BridgeEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var location: String
    public var kind: Kind
    public var project: String
    public var title: String
    public var presentedAt: Date
    public var unread: Bool
    public var crossed: Bool
    public var session: String
    public var links: String?
    public var site: String?

    public init(location: String, project: String, session: String, at: Date = Date()) {
        self.id = Paths.id(for: location)
        self.location = location
        self.kind = Kind.of(location)
        self.project = project
        self.title = BridgeEntry.defaultTitle(location)
        self.presentedAt = at
        self.unread = true
        self.crossed = false
        self.session = session
    }

    public var projectName: String { (project as NSString).lastPathComponent }

    public static func defaultTitle(_ location: String) -> String {
        let kind = Kind.of(location)
        if kind == .url { return location.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") }
        let name = (location as NSString).lastPathComponent
        return kind == .html || kind == .jsx || kind == .md ? (name as NSString).deletingPathExtension : name
    }
}

public struct Listing: Codable, Equatable, Sendable {
    public var bridges: [BridgeEntry] = []

    public init() {}

    public static func load() -> Listing {
        guard let data = try? Data(contentsOf: Paths.list),
              let l = try? JSON.decoder.decode(Listing.self, from: data) else { return Listing() }
        return l
    }

    public func save() throws {
        try JSON.encoder.encode(self).write(to: Paths.list, options: .atomic)
    }

    public func entry(_ location: String) -> BridgeEntry? {
        bridges.first { $0.location == location }
    }

    public mutating func update(_ location: String, _ change: (inout BridgeEntry) -> Void) {
        guard let i = bridges.firstIndex(where: { $0.location == location }) else { return }
        change(&bridges[i])
    }

    public var projects: [String] {
        var seen: [String: Date] = [:]
        for b in bridges { seen[b.project] = max(seen[b.project] ?? .distantPast, b.presentedAt) }
        return seen.sorted { $0.value > $1.value }.map(\.key)
    }

    public func bridges(in project: String, crossed: Bool) -> [BridgeEntry] {
        bridges.filter { $0.project == project && $0.crossed == crossed }.sorted { $0.presentedAt > $1.presentedAt }
    }
}
