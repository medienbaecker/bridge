import WebKit
import UniformTypeIdentifiers

final class LocalFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "bridge-file"

    static func register(in config: WKWebViewConfiguration) {
        let secure = NSSelectorFromString("_registerURLSchemeAsSecure:")
        if config.processPool.responds(to: secure) { config.processPool.perform(secure, with: scheme) }
    }

    let folder: String
    private var allowed: Set<String> = []

    init(folder: String) { self.folder = folder }

    func serves(_ path: String) -> Bool { allowed.contains(path) || path.hasPrefix(folder + "/") }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, serves(url.path), let data = FileManager.default.contents(atPath: url.path) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type, "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func rewrite(_ html: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"(\b(?:src|href|poster)\s*=\s*)(["'])([^"']*)\2"#, options: .caseInsensitive)
        var out = html
        for m in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let lead = Range(m.range(at: 1), in: html), let quote = Range(m.range(at: 2), in: html),
                  let value = Range(m.range(at: 3), in: html), let local = local(String(html[value])) else { continue }
            out.replaceSubrange(Range(m.range, in: out)!, with: html[lead] + html[quote] + local + html[quote])
        }
        return out
    }

    private func local(_ value: String) -> String? {
        let cut = value.firstIndex { $0 == "?" || $0 == "#" } ?? value.endIndex
        let given = String(value[..<cut]), rest = String(value[cut...])
        let path: String
        if given.hasPrefix("file://") {
            path = String(given.dropFirst("file://".count)).removingPercentEncoding ?? ""
        } else if given.hasPrefix("/"), !given.hasPrefix("//") {
            path = given
        } else if !given.isEmpty, !given.contains(":"), !given.hasPrefix("//") {
            path = URL(fileURLWithPath: folder).appendingPathComponent(given).standardizedFileURL.path
        } else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        allowed.insert(path)
        var url = URLComponents()
        url.scheme = Self.scheme
        url.host = ""
        url.path = path
        return (url.string ?? Self.scheme + "://" + path) + rest
    }
}
