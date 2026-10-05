import Foundation

public enum Framing {
    public static func refusal(_ headers: [AnyHashable: Any]) -> String? {
        func value(_ name: String) -> String? { headers.first { ($0.key as? String)?.lowercased() == name }?.value as? String }
        if let xfo = value("x-frame-options")?.trimmingCharacters(in: .whitespaces), ["deny", "sameorigin"].contains(xfo.lowercased()) {
            return "X-Frame-Options: \(xfo)"
        }
        if let csp = value("content-security-policy"),
           let directive = csp.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.lowercased().hasPrefix("frame-ancestors") }),
           !directive.split(separator: " ").dropFirst().contains("*") {
            return "Content-Security-Policy: \(directive)"
        }
        return nil
    }

    public static func refused(_ sources: [String], done: @escaping @Sendable ([(String, String)]) -> Void) {
        let found = Found()
        let group = DispatchGroup()
        for src in Set(sources) {
            guard let url = URL(string: src) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpMethod = "HEAD"
            group.enter()
            URLSession.shared.dataTask(with: request) { _, response, _ in
                if let http = response as? HTTPURLResponse, let why = refusal(http.allHeaderFields) { found.add(src, why) }
                group.leave()
            }.resume()
        }
        group.notify(queue: .global()) { done(found.all.sorted { $0.0 < $1.0 }) }
    }

    final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var all: [(String, String)] = []
        func add(_ src: String, _ why: String) { lock.lock(); all.append((src, why)); lock.unlock() }
    }

    public static func sources(in html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"(?i)<iframe\b[^>]*\bsrc\s*=\s*["']?(https?://[^"'\s>]+)"#)
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range(at: 1), in: html).map { String(html[$0]) } }
    }
}
