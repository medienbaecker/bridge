import Foundation

public enum Person {
    public static var file: URL { Paths.stateDir.appendingPathComponent("person") }

    public static var current: String {
        if let saved = try? String(contentsOf: file, encoding: .utf8), let name = clean(saved) { return name }
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return clean(first) ?? clean(NSUserName()) ?? "me"
    }

    public static var device: String {
        let file = Paths.stateDir.appendingPathComponent("device-id")
        if let saved = try? String(contentsOf: file, encoding: .utf8), let id = UUID(uuidString: saved.trimmingCharacters(in: .whitespacesAndNewlines)) { return id.uuidString }
        let id = UUID().uuidString
        try? Data((id + "\n").utf8).write(to: file, options: .atomic)
        return id
    }

    public static func set(_ name: String) throws -> String {
        guard let name = clean(name) else { throw Invalid() }
        try Data((name + "\n").utf8).write(to: file, options: .atomic)
        return name
    }

    public static func clean(_ raw: String) -> String? {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let kept = String(folded.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }.map(Character.init))
        return kept.isEmpty ? nil : String(kept.prefix(32))
    }

    public static var colourFile: URL { Paths.stateDir.appendingPathComponent("colour") }

    public static var colour: String? {
        (try? String(contentsOf: colourFile, encoding: .utf8)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap(cleanColour)
    }

    public static func setColour(_ raw: String) throws -> String? {
        if raw == "none" { try? FileManager.default.removeItem(at: colourFile); return nil }
        guard let colour = cleanColour(raw) else { throw InvalidColour() }
        try Data((colour + "\n").utf8).write(to: colourFile, options: .atomic)
        return colour
    }

    public static func cleanColour(_ raw: String) -> String? {
        let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex.lowercased()
    }

    public struct InvalidColour: Error, CustomStringConvertible {
        public var description: String { "a colour is a hex value like #e8590c, or none" }
    }

    public struct Invalid: Error, CustomStringConvertible {
        public var description: String { "a name needs at least one letter or digit" }
    }
}
