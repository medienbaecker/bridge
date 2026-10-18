import Foundation

public enum Quote {
    public struct Failure: Error { public let message: String }

    public static func read(_ spec: String, in folder: URL) -> Result<String, Failure> {
        var path = spec, from = 1, to = Int.max
        if let colon = spec.lastIndex(of: ":") {
            let range = spec[spec.index(after: colon)...].split(separator: "-", omittingEmptySubsequences: false)
            if (1...2).contains(range.count), let a = Int(range[0]), let b = range.count == 2 ? Int(range[1]) : a {
                path = String(spec[..<colon]); from = a; to = b
            }
        }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent((path as NSString).expandingTildeInPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .failure(Failure(message: "\(path) is not a readable text file")) }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard from >= 1, from <= to, from <= lines.count else {
            return .failure(Failure(message: "\(spec) is past the end of \(path), which has \(lines.count) lines"))
        }
        let picked = Array(lines[(from - 1)..<min(to, lines.count)])
        let indent = picked.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        return .success(picked.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " || $0 == "\t" }.count))) }.joined(separator: "\n"))
    }

    static let html = try! NSRegularExpression(pattern: #"<code\b([^>]*?)\bdata-quote\s*=\s*"([^"]*)"([^>]*)>[\s\S]*?</code>"#, options: .caseInsensitive)
    static let fence = try! NSRegularExpression(pattern: #"^([ \t]*)(`{3,}|~{3,})([^\n]*?)\bquote=(\S+)([^\n]*)\n[\s\S]*?^\1\2[ \t]*$"#, options: .anchorsMatchLines)

    /// The page with every quote replaced by the lines it names, for a copy that
    /// leaves this Mac: the other side gets those lines, never the file.
    public static func inline(_ page: String, in folder: URL) -> String {
        var out = page
        for m in html.matches(in: page, range: NSRange(page.startIndex..., in: page)).reversed() {
            let ns = page as NSString
            let spec = ns.substring(with: m.range(at: 2))
            let text = (try? read(spec, in: folder).get()) ?? ""
            let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let tag = "<code\(ns.substring(with: m.range(at: 1)))data-quoted=\"\(spec)\"\(ns.substring(with: m.range(at: 3)))>\(escaped)</code>"
            out.replaceSubrange(Range(m.range, in: out)!, with: tag)
        }
        let source = out
        for m in fence.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            let ns = source as NSString
            let indent = ns.substring(with: m.range(at: 1)), mark = ns.substring(with: m.range(at: 2)), spec = ns.substring(with: m.range(at: 4))
            let text = (try? read(spec, in: folder).get()) ?? ""
            let block = "\(indent)\(mark)\(ns.substring(with: m.range(at: 3)))quoted=\(spec)\(ns.substring(with: m.range(at: 5)))\n\(text)\n\(indent)\(mark)"
            out.replaceSubrange(Range(m.range, in: out)!, with: block)
        }
        return out
    }
}
