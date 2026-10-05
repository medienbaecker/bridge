import Foundation

/// Checks a page against the kit's stylesheet while the writing agent still
/// holds the file. Findings are one line each and say what to do, not what is wrong.
public struct Lint {
    public struct Finding: Sendable {
        public enum Level: String, Sendable { case error, warning }
        public let line: Int
        public let level: Level
        public let text: String
        public var description: String { "\(line): \(level.rawValue): \(text)" }
    }

    public let kitCSS: String
    public init(kitCSS: String) { self.kitCSS = kitCSS }

    /// Classes page.css offers pages; the runtime's own and the highlighter's are internal.
    public var vocabulary: Set<String> {
        let tokens = Set(Self.matches(#"\.token\.([\w-]+)"#, in: kitCSS))
        return Set(Self.classes(in: kitCSS)).filter { !$0.hasPrefix("bridge-") && !$0.hasPrefix("doc-") && !$0.hasPrefix("language-") && !tokens.contains($0) && $0 != "token" }
    }

    public func run(html: String) -> [Finding] {
        var out: [Finding] = []
        let lines = Self.lineStarts(html)
        let lineOf = { (offset: Int) -> Int in (lines.lastIndex { $0 <= offset } ?? 0) + 1 }
        let styles = Self.ranges(#"(?is)<style[^>]*>(.*?)</style>"#, in: html)
        let own = Set(styles.flatMap { Self.classes(in: String(html[$0.inner])) })
        let external = html.range(of: #"(?i)<link[^>]+rel=["']?stylesheet"#, options: .regularExpression) != nil
        let kit = Set(Self.classes(in: kitCSS))
        let vocab = vocabulary

        // Classes set from script count too: pages that build elements in JS collide on those.
        var seen: Set<String> = []
        let uses = Self.ranges(#"(?i)\sclass\s*=\s*"([^"]*)""#, in: html)
            + Self.ranges(#"className\s*=\s*['"]([^'"]*)['"]"#, in: html)
            + Self.ranges(#"classList\.(?:add|toggle)\(\s*['"]([^'"]*)['"]"#, in: html)
        for m in uses {
            for c in String(html[m.inner]).split(separator: " ").map(String.init) where !seen.contains(c) {
                seen.insert(c)
                // A script's template pieces (`th${used[n] ? ' used' : ''}`) are not class names.
                guard c.range(of: #"^-?[_a-zA-Z][\w-]*$"#, options: .regularExpression) != nil else { continue }
                if c.hasPrefix("language-") || c.hasPrefix("bridge-") { continue }
                let line = lineOf(html.distance(from: html.startIndex, to: m.whole.lowerBound))
                if kit.contains(c) && own.contains(c) {
                    out.append(Finding(line: line, level: .error, text: "`.\(c)` is styled by this page and by the kit, so the element gets both: rename yours (`.\(Self.prefix(html))-\(c)`) or reset what the kit sets"))
                } else if !kit.contains(c) && !own.contains(c) && !external {
                    out.append(Finding(line: line, level: .error, text: "`.\(c)` styles nothing: \(Self.suggest(c, vocab)) (pages.md, What the base stylesheet gives you)"))
                }
            }
        }

        let cssBits = styles.map { (String(html[$0.inner]), html.distance(from: html.startIndex, to: $0.inner.lowerBound)) }
            + Self.ranges(#"(?i)\sstyle\s*=\s*"([^"]*)""#, in: html).map { (String(html[$0.inner]), html.distance(from: html.startIndex, to: $0.inner.lowerBound)) }
        for (css, base) in cssBits {
            for m in Self.ranges(#"(?i)(?:^|[\s;{])(color|background(?:-color)?|border(?:-color)?|border-top|border-bottom|border-left|border-right|outline|box-shadow|fill|stroke)\s*:\s*([^;}]*)"#, in: css) {
                let value = String(css[m.inner])
                guard value.range(of: #"(?i)#[0-9a-f]{3,8}\b|\b(rgba?|hsla?|oklch|oklab)\("#, options: .regularExpression) != nil else { continue }
                let line = lineOf(base + css.distance(from: css.startIndex, to: m.whole.lowerBound))
                out.append(Finding(line: line, level: .warning, text: "a colour written out (\(value.trimmingCharacters(in: .whitespaces))): use var(--bridge-accent), var(--bridge-muted), var(--bridge-line), var(--bridge-panel), or a system colour (Canvas, CanvasText), so it holds in dark mode"))
            }
            for m in Self.ranges(#"(?i)border-radius\s*:\s*([^;}]*)"#, in: css) {
                let value = String(css[m.inner]).trimmingCharacters(in: .whitespaces)
                guard value.range(of: #"^\d*\.?\d+(px|rem|em)$"#, options: .regularExpression) != nil, !value.hasPrefix("0") else { continue }
                // 999px is a pill, fully round whatever the height: a shape, not a choice of radius.
                if value.hasSuffix("px"), let px = Double(value.dropLast(2)), px >= 99 { continue }
                let line = lineOf(base + css.distance(from: css.startIndex, to: m.whole.lowerBound))
                out.append(Finding(line: line, level: .warning, text: "a radius written out (\(value)): use var(--bridge-radius), the kit's one"))
            }
        }

        for m in Self.ranges(#"(?is)<pre[^>]*>(.*?)</pre>"#, in: html) {
            let body = String(html[m.inner]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let rows = body.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let gutters = rows.filter { $0.trimmingCharacters(in: .whitespaces).range(of: #"\S {2,}\S"#, options: .regularExpression) != nil }
            // Braces, operators and a shell prompt say code; a leading # does not, ids in a table start with one.
            let codeish = body.range(of: #"[{};=<>()\[\]]|(?m)^\s*[$>] "#, options: .regularExpression) != nil
            let line = lineOf(html.distance(from: html.startIndex, to: m.whole.lowerBound))
            if rows.count >= 2, gutters.count * 2 >= rows.count, !codeish {
                out.append(Finding(line: line, level: .warning, text: "this pre looks like columns spaced by hand, not code: aligned data is a table.data with a .remark cell per row and a tbody per group (pages.md, Aligned data)"))
            }
        }
        // A page is a file:// document and its blobs have another origin, so WebKit
        // refuses an AudioWorklet module from a blob; a file beside the page loads.
        for m in Self.ranges(#"(?is)<script[^>]*>(.*?)</script>"#, in: html) {
            let js = String(html[m.inner])
            guard let at = js.range(of: "addModule("), js.range(of: #"createObjectURL|blob:"#, options: .regularExpression) != nil else { continue }
            let line = lineOf(html.distance(from: html.startIndex, to: m.inner.lowerBound) + js.distance(from: js.startIndex, to: at.lowerBound))
            out.append(Finding(line: line, level: .warning, text: "an AudioWorklet module from a blob URL is refused here (the page is a file:// document): write the processor to a .js file beside the page and addModule('that.js') (pages.md, Sound)"))
        }
        return out.sorted { $0.line < $1.line }
    }

    static func suggest(_ c: String, _ vocab: Set<String>) -> String {
        let meant: [String: String] = [
            "num": "`.row.between` with a `.num` value", "number": "`.row.between` with a `.num` value", "value": "`.row.between` with a `.num` value",
            "between": "`.row.between`", "spread": "`.row.between`", "card": "`.card`", "box": "`.card`", "panel": "`.evidence`",
            "faint": "`.muted`", "dim": "`.muted`", "quiet": "`.muted`", "secondary": "`.muted`", "subtle": "`.muted`", "hint": "`.muted`",
            "note": "`.remark` in a `table.data`, or `.muted`", "remark": "`.remark` in a `table.data`", "mono": "`<code>`",
            "grid": "`.compare` for two columns, `.options` for cards", "two": "`.compare`", "columns": "`.compare`", "cols": "`.compare`",
            "warn": "`data-tone=\"warn\"` on a `.bar`", "bad": "`data-tone=\"bad\"` on a `.bar`", "good": "plain text: there is no good tone",
            "metric": "`.metrics` (a dl of dt and dd)", "stat": "`.metrics`", "kv": "`.metrics`",
            "option": "`.options` with `[data-record][data-value]` cards", "option-title": "a `<strong>` inside the option", "option-desc": "plain text inside the option",
            "control": "a `<label>` around the control", "page": "no wrapper: the body is the page", "page-head": "an `<h1>` and a `<p>`", "section": "an `<h2>`",
            "button": "`.button` on a link, or a `<button>`", "btn": "`.button` on a link, or a `<button>`", "primary": "`.primary`",
            "table": "`table.data`", "data": "`table.data`", "code": "`<pre><code class=\"language-…\">`",
        ]
        if let m = meant[c] { return m.hasPrefix("`.") ? "did you mean \(m)?" : "use \(m)" }
        let near = vocab.map { ($0, Self.distance(c, $0)) }.filter { $0.1 <= max(2, c.count / 3) }.sorted { $0.1 < $1.1 }
        if let (name, _) = near.first { return "did you mean `.\(name)`?" }
        return "write a rule for it in the page's own <style>, or use a shape from the vocabulary"
    }

    static func prefix(_ html: String) -> String {
        let title = Self.matches(#"(?is)<title>([^<]*)</title>"#, in: html).first ?? "page"
        let word = title.split(whereSeparator: { !$0.isLetter }).first.map(String.init)?.lowercased() ?? "page"
        return word.isEmpty ? "page" : word
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for i in 1...max(1, a.count) where i <= a.count {
            var cur = [i]
            for j in 1...max(1, b.count) where j <= b.count {
                cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)))
            }
            if cur.count == b.count + 1 { prev = cur }
        }
        return prev[b.count]
    }

    static func classes(in css: String) -> [String] {
        let bare = css.replacingOccurrences(of: #"/\*.*?\*/"#, with: "", options: .regularExpression)
        return matches(#"\.(-?[_a-zA-Z][\w-]*)"#, in: bare)
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        ranges(pattern, in: text).map { String(text[$0.inner]) }
    }

    struct Match { let whole: Range<String.Index>; let inner: Range<String.Index> }

    static func ranges(_ pattern: String, in text: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let whole = Range(m.range, in: text) else { return nil }
            let group = m.numberOfRanges > 1 ? m.range(at: m.numberOfRanges - 1) : m.range
            guard group.location != NSNotFound, let inner = Range(group, in: text) else { return nil }
            return Match(whole: whole, inner: inner)
        }
    }

    static func lineStarts(_ text: String) -> [Int] {
        var starts = [0]
        for (i, ch) in text.enumerated() where ch == "\n" { starts.append(i + 1) }
        return starts
    }
}
