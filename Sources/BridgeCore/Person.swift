import Foundation

public enum Person {
    public static var file: URL { Paths.stateDir.appendingPathComponent("person") }

    public static var current: String {
        if let saved = try? String(contentsOf: file, encoding: .utf8), let name = clean(saved) { return name }
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return clean(first) ?? clean(NSUserName()) ?? "me"
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

    public struct Invalid: Error, CustomStringConvertible {
        public var description: String { "a name needs at least one letter or digit" }
    }
}
