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
        for m in uses where !Self.escaped(html, at: m.whole.lowerBound) {
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

        let colour = #"(?i)(?:^|[\s;{])(?:color|background(?:-color)?|border(?:-color)?|border-top|border-bottom|border-left|border-right|outline|box-shadow|fill|stroke|stop-color)\s*:\s*([^;}]*(?:#[0-9a-f]{3,8}\b|\b(?:rgba?|hsla?|oklch|oklab)\()[^;}]*)"#
        let dark = html.range(of: #"(?i)prefers-color-scheme\s*:\s*dark|light-dark\("#, options: .regularExpression) != nil
        if !dark, let (css, base) = styles.map({ (String(html[$0.inner]), html.distance(from: html.startIndex, to: $0.inner.lowerBound)) }).first(where: { !Self.ranges(colour, in: $0.0).isEmpty }),
           let m = Self.ranges(colour, in: css).first {
            let line = lineOf(base + css.distance(from: css.startIndex, to: m.whole.lowerBound))
            out.append(Finding(line: line, level: .warning, text: "colours of your own and no dark variant: add them again under @media (prefers-color-scheme: dark), or the page breaks when the system is dark"))
        }
        for attr in Self.ranges(#"(?i)\sstyle\s*=\s*"([^"]*)""#, in: html) where !Self.escaped(html, at: attr.whole.lowerBound) {
            let css = String(html[attr.inner])
            guard let m = Self.ranges(colour, in: css).first else { continue }
            let line = lineOf(html.distance(from: html.startIndex, to: attr.inner.lowerBound))
            out.append(Finding(line: line, level: .warning, text: "a colour in a style attribute (\(String(css[m.inner]).trimmingCharacters(in: .whitespaces))): no dark variant can reach it; set a custom property from your <style> instead"))
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
        // A page is a file:// document and its blobs have another origin, so some WebKit
        // versions refuse an AudioWorklet module from a blob; a file beside the page always loads.
        for m in Self.ranges(#"(?is)<script[^>]*>(.*?)</script>"#, in: html) {
            let js = String(html[m.inner])
            guard let at = js.range(of: "addModule("), js.range(of: #"createObjectURL|blob:"#, options: .regularExpression) != nil else { continue }
            let line = lineOf(html.distance(from: html.startIndex, to: m.inner.lowerBound) + js.distance(from: js.startIndex, to: at.lowerBound))
            out.append(Finding(line: line, level: .warning, text: "an AudioWorklet module from a blob URL is refused by some WebKit versions (the page is a file:// document): write the processor to a .js file beside the page and addModule('that.js') (pages.md, Sound)"))
        }
        out += textWalls(html: html, lineOf: lineOf)
        return out.sorted { $0.line < $1.line }
    }

    static let blockWords = 40
    static let pageWords = 250
    static let cardWords = 15

    func textWalls(html: String, lineOf: (Int) -> Int) -> [Finding] {
        guard html.range(of: #"(?i)<!doctype html|<html\b|<body\b|<p\b|<div\b"#, options: .regularExpression) != nil else { return [] }
        let masked = Self.masked(html)
        let css = Self.ranges(#"(?is)<style[^>]*>(.*?)</style>"#, in: html).map { String(html[$0.inner]) }.joined(separator: "\n")
        let drawn = Self.drawn(in: masked, css: css)
        let text = Self.blanked(masked, drawn.pictures)
        let offset = { (i: String.Index) in text.distance(from: text.startIndex, to: i) }
        var out: [Finding] = []

        let valued = Self.ranges(#"(?i)<(?!input\b|option\b)(\w+)\b[^>]*\sdata-value\b[^>]*>"#, in: text).compactMap { m -> (whole: Range<String.Index>, open: String, words: Int, recorded: Bool)? in
            guard let whole = Self.element(in: text, at: m.whole, tag: String(text[m.inner])) else { return nil }
            let open = String(text[m.whole])
            return (whole, open, Self.words(String(text[whole])), open.range(of: #"(?i)\sdata-record\b"#, options: .regularExpression) != nil)
        }
        let choices = Self.ranges(#"(?i)<input\b[^>]*\stype\s*=\s*["']?(?:checkbox|radio)\b[^>]*>"#, in: text).map(\.whole.lowerBound)
        let holders = Self.ranges(#"(?i)<(label|div)\b[^>]*>"#, in: text).compactMap { m -> (whole: Range<String.Index>, open: String, words: Int, recorded: Bool)? in
            guard let whole = Self.element(in: text, at: m.whole, tag: String(text[m.inner])),
                  choices.filter(whole.contains).count == 1,
                  !valued.contains(where: { $0.whole.contains(whole.lowerBound) }) else { return nil }
            return (whole, String(text[m.whole]), Self.words(String(text[whole])), true)
        }
        let held = holders.filter { outer in !holders.contains { $0.whole != outer.whole && outer.whole.contains($0.whole.lowerBound) } }
        let cards = (valued + held).sorted { $0.whole.lowerBound < $1.whole.lowerBound }
        var walls = cards.filter { $0.words > Self.blockWords }.map(\.whole)
        for m in Self.ranges(#"(?is)<(p|li)\b[^>]*>.*?</\1>"#, in: text) where !walls.contains(where: { $0.contains(m.whole.lowerBound) }) {
            if Self.words(String(text[m.whole])) > Self.blockWords { walls.append(m.whole) }
        }
        for wall in walls {
            out.append(Finding(line: lineOf(offset(wall.lowerBound)), level: .warning, text: "\(Self.words(String(text[wall]))) words in one block: show it instead (pages.md, Screenshots, Swatches, Evidence: code, diffs, bars) or cut it to one line"))
        }

        let code = Self.ranges(#"(?i)<pre\b"#, in: html).map { html.distance(from: html.startIndex, to: $0.whole.lowerBound) }
        let plain = cards.filter { card in
            let inside = (offset(card.whole.lowerBound) + card.open.count)..<offset(card.whole.upperBound)
            return card.recorded && !(drawn.marks + code).contains { inside.contains($0) }
        }
        if let first = plain.first, let most = plain.map(\.words).max(), most > Self.cardWords {
            out.append(Finding(line: lineOf(offset(first.whole.lowerBound)), level: .warning, text: "option cards that are only text (up to \(most) words): put the evidence in the card, a rendered preview, the real screenshot, a swatch or the diff, and keep the words to one line (pages.md, Decision)"))
        }

        let total = Self.words(text)
        let visual = html.range(of: #"(?i)<(img|svg|canvas|video|iframe|table)\b|class\s*=\s*["'][^"']*\b(swatches|bars|bar|shots|wipe|color|dials)\b"#, options: .regularExpression) != nil
        if total > Self.pageWords, !visual, drawn.pictures.isEmpty {
            let body = html.range(of: #"(?i)<body\b"#, options: .regularExpression).map { html.distance(from: html.startIndex, to: $0.lowerBound) } ?? 0
            out.append(Finding(line: lineOf(body), level: .warning, text: "\(total) words and nothing to look at: show the thing (pages.md, Screenshots, Swatches, Evidence: code, diffs, bars), or put prose in your reply or a .md, not a page"))
        }
        return out
    }

    /// Where the page draws something: media, the kit's visual shapes, and elements its own CSS
    /// or a style attribute paints (background, border, shadow) or gives a shape (aspect-ratio,
    /// width and height, a background image). `marks` are their offsets; `pictures` are the ones whose
    /// text belongs to the picture: a shape, or a painted box with more drawing inside (a mockup).
    /// A painted box holding only prose is a callout, and its words still count.
    static func drawn(in text: String, css: String) -> (marks: [Int], pictures: [Range<Int>]) {
        var painted: Set<String> = [], shaped: Set<String> = []
        let bare = css.replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
        for rule in ranges(#"([^{}]+)\{([^{}]*)\}"#, in: bare) {
            let decls = String(bare[rule.inner])
            let (paints, shapes) = (Self.paints(decls), Self.shapes(decls))
            guard paints || shapes else { continue }
            let selectors = String(bare[rule.whole].prefix { $0 != "{" })
            for selector in selectors.split(separator: ",") {
                let last = selector.split(whereSeparator: { $0.isWhitespace || ">+~".contains($0) }).last.map(String.init) ?? ""
                for c in matches(#"\.(-?[_a-zA-Z][\w-]*)"#, in: last) {
                    if paints { painted.insert(c) }
                    if shapes { shaped.insert(c) }
                }
            }
        }
        let offset = { (i: String.Index) in text.distance(from: text.startIndex, to: i) }
        var found: [(at: Int, range: Range<Int>?, picture: Bool, card: Bool)] = []
        for m in ranges(#"(?i)<(\w+)\b[^>]*>"#, in: text) {
            let open = String(text[m.whole]), tag = String(text[m.inner]).lowercased()
            let classes = Set((matches(#"(?i)\sclass\s*=\s*["']([^"']*)"#, in: open).first ?? "").split(separator: " ").map(String.init))
            let style = matches(#"(?i)\sstyle\s*=\s*["']([^"']*)"#, in: open).first ?? ""
            let picture = ["img", "svg", "canvas", "video", "iframe", "picture"].contains(tag)
                || !classes.isDisjoint(with: ["swatches", "bars", "bar", "shots", "wipe", "color", "dials"])
                || !classes.isDisjoint(with: shaped) || shapes(style)
            guard picture || !classes.isDisjoint(with: painted) || paints(style) else { continue }
            let range = element(in: text, at: m.whole, tag: tag).map { offset($0.lowerBound)..<offset($0.upperBound) }
            found.append((offset(m.whole.lowerBound), range, picture, open.range(of: #"(?i)\sdata-value\b"#, options: .regularExpression) != nil))
        }
        let pictures = found.compactMap { d -> Range<Int>? in
            guard let r = d.range, !d.card else { return nil }
            return d.picture || found.contains { $0.at > r.lowerBound && r.contains($0.at) } ? r : nil
        }
        return (found.map(\.at), pictures)
    }

    static func paints(_ decls: String) -> Bool {
        decls.range(of: #"(?i)(?:^|[\s;])(?:background(?:-color)?|border|box-shadow)\s*:\s*(?!(?:none|0|transparent)\s*(?:;|$))"#, options: .regularExpression) != nil
    }

    static func shapes(_ decls: String) -> Bool {
        decls.range(of: #"(?i)(?:^|[\s;])aspect-ratio\s*:|(?:^|[\s;])background(?:-image)?\s*:[^;]*(?:url|gradient)\("#, options: .regularExpression) != nil
            || (decls.range(of: #"(?i)(?:^|[\s;])width\s*:"#, options: .regularExpression) != nil && decls.range(of: #"(?i)(?:^|[\s;])height\s*:"#, options: .regularExpression) != nil)
    }

    static func blanked(_ text: String, _ ranges: [Range<Int>]) -> String {
        var chars = Array(text)
        for r in ranges { for i in r where chars[i] != "\n" { chars[i] = " " } }
        return String(chars)
    }

    static func masked(_ html: String) -> String {
        var chars = Array(html)
        let blank = { (r: Range<String.Index>) in
            let a = html.distance(from: html.startIndex, to: r.lowerBound), b = html.distance(from: html.startIndex, to: r.upperBound)
            for i in a..<b where chars[i] != "\n" { chars[i] = " " }
        }
        for tag in ["head", "script", "style", "pre", "textarea", "details", "template"] {
            for m in ranges(#"(?is)<\#(tag)\b[^>]*>.*?</\#(tag)>"#, in: html) { blank(m.whole) }
        }
        let copied = Set(matches(#"(?i)data-copy\s*=\s*["']#([\w-]+)"#, in: html))
        for m in ranges(#"(?i)<(\w+)\b[^>]*>"#, in: html) {
            let open = String(html[m.whole])
            let id = matches(#"(?i)\sid\s*=\s*["']([\w-]+)"#, in: open).first
            let draft = open.range(of: #"(?i)\sclass\s*=\s*["'][^"']*\bdraft\b"#, options: .regularExpression) != nil
            guard draft || id.map(copied.contains) == true, let whole = element(in: html, at: m.whole, tag: String(html[m.inner])) else { continue }
            blank(whole)
        }
        return String(chars)
    }

    /// `&lt;div class="x"&gt;` shown as code is text, not markup.
    static func escaped(_ html: String, at i: String.Index) -> Bool {
        let before = html[..<i]
        guard let esc = before.range(of: "&lt;", options: .backwards) else { return false }
        return before.range(of: "<", options: .backwards).map { $0.lowerBound < esc.lowerBound } ?? true
    }

    static func element(in html: String, at open: Range<String.Index>, tag: String) -> Range<String.Index>? {
        let rest = String(html[open.upperBound...])
        var depth = 1
        for m in ranges(#"(?i)<(/?)\#(tag)\b[^>]*>"#, in: rest) {
            depth += rest[m.whole].hasPrefix("</") ? -1 : 1
            if depth == 0 {
                return open.lowerBound..<html.index(open.upperBound, offsetBy: rest.distance(from: rest.startIndex, to: m.whole.upperBound))
            }
        }
        return nil
    }

    static func words(_ html: String) -> Int {
        html.replacingOccurrences(of: #"<[^>]+>|&#?\w+;"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }.count
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
