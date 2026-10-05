import AppKit
import WebKit
import CryptoKit
import BridgeCore

final class Page: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    static let world = WKContentWorld.world(name: "bridge")
    static let runtime: String = {
        let web = Bundle.module.url(forResource: "web", withExtension: nil)!
        func read(_ name: String) -> String { (try? String(contentsOf: web.appendingPathComponent(name), encoding: .utf8)) ?? "" }
        let css = ["page": read("page.css"), "ui": read("ui.css")]
        return "const __BRIDGE_CSS = \(JSON.string(css, pretty: false));\n" + read("idiomorph.js") + "\n" + read("marked.js") + "\n" + read("prism.js") + "\n" + read("bridge.js")
    }()
    static let pageAPI: String = {
        let web = Bundle.module.url(forResource: "web", withExtension: nil)!
        return (try? String(contentsOf: web.appendingPathComponent("page-api.js"), encoding: .utf8)) ?? ""
    }()

    let location: String
    let kind: Kind
    unowned let model: Model
    let webView: WKWebView
    let sidecarURL: URL
    var sidecar: Sidecar
    var title: String
    var viewingVersion: Int?
    var pointing = false
    var ready = false
    /// The file behind a listed bridge is gone, e.g. a crossed one whose session deleted its folder.
    var missing = false
    var unknownClasses: [String] = []
    var collidingClasses: [String] = []
    var changeSummary: String?
    var note: String?
    var lastContent: Data?
    var versionContent: Data?
    var lastWritten: Data?
    var unreadable: String?
    var lastData: Data?
    var watcher: Watcher?
    var buildFailed = false
    var buildMs: Int?
    var frames: [WKFrameInfo] = []
    var frameLinks: [String: Links] = [:]
    var shape: String?
    var shapedContent: Data?
    var bump: (content: Data?, why: String)?
    var zoom: CGFloat = 1 { didSet { webView.pageZoom = zoom } }
    var drives: [String: [String: Any]] = [:]
    var errors: [String] = []

    init(location: String, model: Model) {
        self.location = location
        self.kind = Kind.of(location)
        self.model = model
        self.sidecarURL = Paths.sidecar(for: location)
        do { self.sidecar = try Sidecar.load(sidecarURL) } catch { self.sidecar = Sidecar(); self.unreadable = "\(error)" }
        self.title = model.listing.entry(location)?.title ?? BridgeEntry.defaultTitle(location)
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // For pages without a charset.
        config.preferences.setValue("utf-8", forKey: "defaultTextEncodingName")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        super.init()
        installScripts()
        config.userContentController.addScriptMessageHandler(self, contentWorld: Page.world, name: "bridge")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if kind != .url {
            let dir = URL(fileURLWithPath: location).deletingLastPathComponent()
            let files = [location, sidecarURL.path, Paths.dataFile(for: location).path]
            watcher = Watcher(directory: dir, files: files) { [weak self] in self?.fileChanged() }
        }
    }

    func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let options = JSON.string(["local": kind != .url, "built": kind == .jsx], pretty: false)
        controller.addUserScript(WKUserScript(source: Page.runtime + "\n__bridgeInit(\(options));", injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Page.world))
        if kind != .url {
            let answers = JSON.string(JSONValue.object(sidecar.answers), pretty: false)
            let api = JSON.string(JSONValue.array(sidecar.questions.map { .string($0) }), pretty: false)
            let defaults = JSON.string(JSONValue.array(sidecar.defaults.map { .string($0) }), pretty: false)
            controller.addUserScript(WKUserScript(source: "window.__bridgeAnswers = \(answers);\nwindow.__bridgeApi = \(api);\nwindow.__bridgeDefaults = \(defaults);\n" + Page.pageAPI, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
    }

    func close() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bridge", contentWorld: Page.world)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        watcher = nil
    }

    var bannerText: String? {
        if let unreadable { return "Nothing here will be saved: \(unreadable)" }
        if missing { return "This page's file is gone: \(location). What was answered is kept." }
        if let v = viewingVersion {
            let when = sidecar.history.first { $0.n == v }.map { Self.clock.string(from: $0.at) } ?? ""
            return "Version \(v) of \(sidecar.version), as it was at \(when). Read-only; ⌘] goes forward."
        }
        if let n = note ?? changeSummary { return [n, moved].compactMap { $0 }.joined(separator: " · ") }
        if let moved { return moved }
        // No echo of the answer here: the toolbar already shows the sent state, and an
        // answer can be far too long for chrome.
        return nil
    }

    var moved: String? {
        let n = sidecar.presented?.ground?.commitsSince() ?? 0
        return n > 0 ? "\(n) commit\(n == 1 ? "" : "s") since this was asked" : nil
    }

    static func short(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): return s.count > 40 ? String(s.prefix(40)) + "…" : s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "yes" : "no"
        case .null: return "–"
        case .array(let a): return a.map(short).joined(separator: ", ")
        case .object: return "{…}"
        }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    // MARK: Loading

    func load() {
        viewingVersion = nil
        ready = false
        frames = []
        frameLinks = [:]
        drives = [:]
        errors = []
        // The page reads the record through a document-start script, which is a
        // snapshot taken at injection: re-inject on every load, or a reload sees stale answers.
        installScripts()
        switch kind {
        case .url:
            if let url = URL(string: location) { webView.load(URLRequest(url: url)) }
        case .html:
            missing = !FileManager.default.fileExists(atPath: location)
            if missing {
                loadDocument("<!doctype html><html><head><title>\(title)</title></head><body><p class=\"muted\">This page's file is gone. What was answered is kept in the record.</p></body></html>")
                break
            }
            lastContent = try? Data(contentsOf: URL(fileURLWithPath: location))
            if versionContent == nil { versionContent = lastContent }
            loadDocument(String(decoding: lastContent ?? Data(), as: UTF8.self))
        case .md, .text, .svg, .image:
            lastContent = try? Data(contentsOf: URL(fileURLWithPath: location))
            if versionContent == nil { versionContent = lastContent }
            loadDocument(wrapped(lastContent))
        case .pdf:
            webView.loadFileURL(URL(fileURLWithPath: location), allowingReadAccessTo: URL(fileURLWithPath: "/"))
        case .jsx:
            lastContent = try? Data(contentsOf: URL(fileURLWithPath: location))
            lastData = try? Data(contentsOf: Paths.dataFile(for: location))
            Task { @MainActor in
                switch await Builder.build(location) {
                case .built(let index, let ms):
                    buildFailed = false
                    buildMs = ms
                    note = nil
                    webView.loadFileURL(index, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                case .failed(let failures):
                    buildFailed = true
                    note = "Build failed: " + (failures.first?.text ?? "")
                    webView.loadHTMLString(Builder.failurePage(location, failures), baseURL: URL(fileURLWithPath: location))
                }
                model.onChange()
            }
        }
    }

    func presented(_ p: Presentation) {
        sidecar.presented = p
        sidecar.page = location
        if sidecar.status == "closed" { sidecar.status = "open"; sidecar.closedAt = nil }
        save()
        if viewingVersion != nil { load() } else { fileChanged() }
    }

    func collected(by session: String) {
        guard sidecar.answered, sidecar.changedSinceCollected else { return }
        sidecar.collectedAt = Date()
        sidecar.collectedBy = session
        save()
    }

    func closed() {
        guard sidecar.status == "open", viewingVersion == nil else { return }
        sidecar.status = "closed"
        sidecar.closedAt = Date()
        save()
    }

    func fileChanged() {
        guard kind != .url else { return }
        if let data = try? Data(contentsOf: sidecarURL), data != lastWritten, data != sidecar.data() {
            lastWritten = data
            do { sidecar = try Sidecar.load(sidecarURL); unreadable = nil } catch { unreadable = "\(error)" }
            pushNotes()
            model.onChange()
        }
        if kind == .jsx {
            if let data = try? Data(contentsOf: Paths.dataFile(for: location)), data != lastData {
                lastData = data
                if !buildFailed { call("__bridge.setData(json)", ["json": String(decoding: data, as: UTF8.self)]) }
            }
            if let data = try? Data(contentsOf: URL(fileURLWithPath: location)), data != lastContent {
                lastContent = data
                load()
            }
            return
        }
        if kind == .pdf { load(); return }
        guard kind.isDocument, kind != .jsx, let data = try? Data(contentsOf: URL(fileURLWithPath: location)), data != lastContent else { return }
        let previous = lastContent
        lastContent = data
        guard viewingVersion == nil else { return }
        let html = kind == .html ? String(decoding: data, as: UTF8.self) : wrapped(data)
        let before = kind == .html ? String(decoding: previous ?? Data(), as: UTF8.self) : wrapped(previous)
        Task { @MainActor in
            let result = try? await run("return __bridge.patch(html, previous)", ["html": html, "previous": before], in: Page.world)
            if result?["reload"]?.boolValue == true {
                note = result?["reason"]?.stringValue == "script-built"
                    ? "This page builds itself with a script, so it was reloaded rather than patched."
                    : "The page's scripts changed, so it was reloaded."
                load()
            } else {
                note = nil
                versionContent = lastContent
            }
            model.onChange()
        }
    }

    // MARK: Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { replyHandler(nil, "bad message"); return }
        switch type {
        case "ready":
            ready = true
            let classes = body["classes"] as? [String: Any]
            unknownClasses = (classes?["unknown"] as? [String]) ?? []
            collidingClasses = (classes?["both"] as? [String]) ?? []
            if let t = body["title"] as? String, !t.isEmpty, viewingVersion == nil, !buildFailed { title = t; model.setTitle(t, for: location) }
            checkFrames()
            fallthrough
        case "shape":
            if viewingVersion == nil, !buildFailed, !missing, let shape = body["shape"] as? String {
                applyShape(shape, questions: body["questions"] as? [String] ?? [], api: body["api"] as? [String] ?? [])
            }
            replyHandler(readyPayload(), nil)
        case "frame-ready":
            if !message.frameInfo.isMainFrame {
                frames.removeAll { $0.request.url == message.frameInfo.request.url }
                frames.append(message.frameInfo)
                for d in drives.values { call("__bridge.drive(prop, value, target)", d, in: message.frameInfo) }
            }
            replyHandler(nil, nil)
        case "frame-links":
            if !message.frameInfo.isMainFrame, let url = Self.document(message.frameInfo.request.url) {
                frameLinks[url] = Links(rawValue: body["links"] as? String ?? "") ?? .external
            }
            replyHandler(nil, nil)
        case "drive":
            if let prop = body["prop"] as? String, let value = body["value"] as? String {
                let d: [String: Any] = ["prop": prop, "value": value, "target": body["target"] as? String ?? NSNull()]
                drives[prop] = d
                for frame in frames { call("__bridge.drive(prop, value, target)", d, in: frame) }
            }
            replyHandler(nil, nil)
        case "size":
            if kind == .image, let w = body["width"] as? Int, let h = body["height"] as? Int {
                title = "\((location as NSString).lastPathComponent) · \(w)×\(h)"
                model.setTitle(title, for: location)
            }
            replyHandler(nil, nil)
        case "record":
            if let key = body["key"] as? String {
                if body["default"] as? Bool == true { recordDefault(key, JSONValue(any: body["value"] ?? NSNull())) }
                else { record(key, JSONValue(any: body["value"] ?? NSNull())) }
            }
            replyHandler(nil, nil)
        case "send":
            send()
            replyHandler(nil, nil)
        case "pin":
            let c = addComment(anchor: JSONValue(any: body["anchor"] ?? NSNull()), target: body["target"] as? String ?? "", text: body["text"] as? String ?? "")
            replyHandler(["id": c.id, "notes": notesJSON()], nil)
        case "note":
            let id = body["id"] as? String ?? ""
            switch body["action"] as? String {
            case "edit": editComment(id, text: body["text"] as? String ?? "")
            case "delete": deleteComment(id)
            case "done": setNote(id, state: "done", by: "user")
            case "reopen": setNote(id, state: "reopen", by: "user")
            case "reply": reply(to: id, text: body["text"] as? String ?? "", by: "user")
            case "move": moveComment(id, anchor: JSONValue(any: body["anchor"] ?? NSNull()), target: body["target"] as? String ?? "")
            default: break
            }
            replyHandler(notesJSON(), nil)
        case "lost":
            if let map = body["lost"] as? [String: Bool] {
                for (id, lost) in map { if let i = sidecar.comments.firstIndex(where: { $0.id == id }), sidecar.comments[i].lost != lost { sidecar.comments[i].lost = lost } }
                save()
            }
            replyHandler(nil, nil)
        case "error":
            if let text = body["text"] as? String, !errors.contains(text), errors.count < 10 { errors.append(text) }
            replyHandler(nil, nil)
        case "pointing":
            pointing = body["on"] as? Bool ?? false
            model.onChange()
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown message \(type)")
        }
    }

    func readyPayload() -> [String: Any] {
        var answers = sidecar.answers
        if let v = viewingVersion, let h = sidecar.history.first(where: { $0.n == v }) { answers = h.answers }
        var previous: [String: JSONValue]? = nil
        if viewingVersion == nil, sidecar.version > 1, let last = sidecar.history.last { previous = last.answers.filter { !(last.defaults ?? []).contains($0.key) } }
        return [
            "answers": any(.object(answers)),
            "previous": previous.map { any(.object($0)) } ?? NSNull(),
            "status": sidecar.status,
            "readOnly": viewingVersion != nil || unreadable != nil || missing,
            "pointing": pointing,
            "notes": notesJSON(),
            "version": sidecar.version,
            "defaults": sidecar.defaults,
        ]
    }

    func any(_ v: JSONValue) -> Any {
        let data = (try? JSON.compact.encode(v)) ?? Data("null".utf8)
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
    }

    // MARK: Answers

    /// Defaults are kept apart from the user's own answers and never change the
    /// status, so opening a page alone records nothing.
    func recordDefault(_ key: String, _ value: JSONValue) {
        guard viewingVersion == nil, sidecar.answers[key] == nil else { return }
        sidecar.answers[key] = value
        if !sidecar.defaults.contains(key) { sidecar.defaults.append(key) }
        save()
        model.onChange()
    }

    func record(_ key: String, _ value: JSONValue) {
        guard viewingVersion == nil else { return }
        note = nil
        sidecar.answers[key] = value
        sidecar.defaults.removeAll { $0 == key }
        if sidecar.status != "open" { sidecar.status = "open"; sidecar.sentAt = nil; sidecar.collectedAt = nil; sidecar.collectedBy = nil }
        save()
        model.onChange()
    }

    var sendLabel: String {
        guard sidecar.status == "sent", let at = sidecar.sentAt else { return "Send" }
        let fresh = sidecar.comments.contains { c in c.at > at || c.said.contains { $0.by != "agent" && $0.at > at } }
        return fresh ? "Send again" : "Sent"
    }

    var sendToolTip: String {
        guard sidecar.status == "sent", let at = sidecar.sentAt else { return "Send your answer" }
        return sendLabel == "Sent" ? "Sent \(Self.clock.string(from: at))" : "Sent \(Self.clock.string(from: at)); send what you added since"
    }

    func send() {
        guard viewingVersion == nil else { return }
        sidecar.status = "sent"
        sidecar.sentAt = Date()
        sidecar.collectedAt = nil
        sidecar.collectedBy = nil
        changeSummary = nil
        save()
        model.onChange()
        call("__bridge.status(status)", ["status": "sent"])
    }

    // MARK: Versions

    func applyShape(_ shape: String, questions: [String], api: [String] = []) {
        let before = self.shape
        self.shape = shape
        shapedContent = lastContent
        let fp = SHA256.hash(data: Data(shape.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        if sidecar.fingerprint == nil {
            sidecar.fingerprint = fp
            sidecar.questions = questions
            save()
            return
        }
        guard sidecar.fingerprint != fp else { return }
        // A page declaring keys through its own script (bridge.get/set) grew its
        // questions itself, not through a rewrite, so adopt them silently.
        let grew = Set(questions).subtracting(sidecar.questions)
        if !grew.isEmpty, Set(sidecar.questions).isSubset(of: questions), grew.isSubset(of: api) {
            sidecar.fingerprint = fp
            sidecar.questions = questions
            save()
            return
        }
        let dir = Paths.versions.appendingPathComponent(Paths.id(for: location))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? versionContent?.write(to: dir.appendingPathComponent("\(sidecar.version).html"))
        versionContent = lastContent
        let old = Version(n: sidecar.version, fingerprint: sidecar.fingerprint ?? "", at: sidecar.history.last?.at ?? sidecar.presented?.at ?? Date(),
                          answers: sidecar.answers, sentAt: sidecar.sentAt, questions: sidecar.questions, defaults: sidecar.defaults)
        sidecar.history.append(old)
        let added = questions.filter { !old.questions.contains($0) }
        let removed = old.questions.filter { !questions.contains($0) }
        var parts: [String] = []
        if !added.isEmpty { parts.append("asks " + added.joined(separator: ", ")) }
        if !removed.isEmpty { parts.append("no longer asks " + removed.joined(separator: ", ")) }
        if parts.isEmpty { parts.append("the options changed") }
        changeSummary = "Changed since you answered: " + parts.joined(separator: "; ") + ". Version \(sidecar.version + 1)."
        bump = (lastContent, Self.changes(from: before, to: shape, added: added, removed: removed))
        sidecar.version += 1
        sidecar.fingerprint = fp
        sidecar.questions = questions
        sidecar.answers = [:]
        sidecar.defaults = []
        sidecar.sentAt = nil
        sidecar.collectedAt = nil
        sidecar.collectedBy = nil
        sidecar.status = "open"
        save()
        model.markUnread(location)
    }

    func checkFrames() {
        guard kind == .html, let html = lastContent.map({ String(decoding: $0, as: UTF8.self) }) else { return }
        Framing.refused(Framing.sources(in: html)) { found in
            Task { @MainActor in for (src, why) in found { self.call("__bridge.frameRefused(url, why)", ["url": src, "why": why]) } }
        }
    }

    static func changes(from old: String?, to new: String, added: [String], removed: [String]) -> String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("asks " + added.joined(separator: ", ")) }
        if !removed.isEmpty { parts.append("no longer asks " + removed.joined(separator: ", ")) }
        let decode = { (s: String?) -> [String: [String]] in
            guard let d = s?.data(using: .utf8), let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[Any]] else { return [:] }
            return Dictionary(rows.compactMap { r in (r.first as? String).map { ($0, (r.last as? [String]) ?? []) } }, uniquingKeysWith: { a, _ in a })
        }
        let a = decode(old), b = decode(new)
        for k in b.keys.sorted() { if let was = a[k], let now = b[k], was != now { parts.append("\(k) offered \(was.joined(separator: " ")), now \(now.joined(separator: " "))") } }
        return parts.isEmpty ? "the options changed" : parts.joined(separator: "; ")
    }

    func showVersion(_ n: Int) {
        guard kind.isDocument, kind != .jsx, n >= 1, n <= sidecar.version else { return }
        if n == sidecar.version { load(); return }
        let file = Paths.versions.appendingPathComponent(Paths.id(for: location)).appendingPathComponent("\(n).html")
        guard let data = try? Data(contentsOf: file) else { return }
        viewingVersion = n
        ready = false
        loadDocument(kind == .html ? String(decoding: data, as: UTF8.self) : wrapped(data))
    }

    // A wrapped document is based on its directory, not on itself: an image page
    // whose base URL is the image would fetch the document's own cache entry for its <img>.
    // Everything goes through loadFileURL because it is the only load that grants
    // the web content process read access to local files (images by absolute path).
    func loadDocument(_ html: String) {
        let file = URL(fileURLWithPath: location)
        if kind == .html && html == String(decoding: lastContent ?? Data(), as: UTF8.self) {
            webView.loadFileURL(file, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            return
        }
        let dir = Paths.builds.appendingPathComponent(Paths.id(for: location))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("document.html")
        let base = "<base href=\"\(file.deletingLastPathComponent().absoluteString)\">"
        let withBase = html.range(of: "<head>").map { html.replacingCharacters(in: $0, with: "<head>" + base) } ?? base + html
        try? Data(withBase.utf8).write(to: out, options: .atomic)
        webView.loadFileURL(out, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    // Markdown, text, SVG and images are wrapped in HTML so the same runtime
    // (pins, patching, versions) applies to them.
    func wrapped(_ data: Data?) -> String {
        let name = (location as NSString).lastPathComponent
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;") }
        func doc(_ title: String, _ body: String) -> String {
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>\(esc(title))</title></head><body>\(body)</body></html>"
        }
        let text = String(decoding: data ?? Data(), as: UTF8.self)
        func head(_ source: String) -> String {
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            return "<div class=\"doc-text-head\"><span class=\"muted\">\(words) words · \(text.count) characters</span><button data-copy=\"#\(source)\" class=\"primary\">Copy</button></div>"
        }
        switch kind {
        case .md:
            let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) } ?? name
            return doc(heading, "\(head("markdown-source"))<div class=\"bridge-md\"></div><template id=\"markdown-source\">\(esc(text))</template>")
        case .text:
            return doc(name, "\(head("text-source"))<pre class=\"draft doc-text\">\(esc(text))</pre><template id=\"text-source\">\(esc(text))</template>")
        case .svg:
            return doc(name, "<div class=\"doc-svg\">\(text)</div>")
        case .image:
            let stamp = (try? FileManager.default.attributesOfItem(atPath: location)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let src = URL(fileURLWithPath: location).absoluteString + "?v=\(Int(stamp))"
            return doc(name, "<figure class=\"doc-image\"><img src=\"\(esc(src))\" alt=\"\(esc(name))\"></figure>")
        default:
            return text
        }
    }

    // MARK: Notes

    func addComment(anchor: JSONValue, target: String, text: String) -> Comment {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let c = Comment(id: id, text: text, target: target, anchor: anchor, version: sidecar.version)
        sidecar.comments.append(c)
        save()
        model.onChange()
        return c
    }

    func editComment(_ id: String, text: String) {
        guard let i = sidecar.comments.firstIndex(where: { $0.id == id }) else { return }
        sidecar.comments[i].text = text
        save(); model.onChange()
    }

    func moveComment(_ id: String, anchor: JSONValue, target: String) {
        guard let i = sidecar.comments.firstIndex(where: { $0.id == id }) else { return }
        sidecar.comments[i].anchor = anchor
        sidecar.comments[i].target = target
        sidecar.comments[i].lost = false
        save(); model.onChange()
    }

    func deleteComment(_ id: String) {
        sidecar.comments.removeAll { $0.id == id }
        save(); model.onChange()
    }

    func reply(to id: String, text: String, by: String = "agent") {
        guard let i = sidecar.comments.firstIndex(where: { $0.id == id }) else { return }
        sidecar.comments[i].said.append(Say(by: by, text: text))
        save(); pushNotes(); model.onChange()
        if by == "agent" { model.markUnread(location) }
    }

    func setNote(_ id: String, state: String, by: String = "agent") {
        guard let i = sidecar.comments.firstIndex(where: { $0.id == id }) else { return }
        let (newState, event) = state == "done" ? ("done", "marked done") : state == "reopen" ? ("open", "reopened") : ("working", "working on it")
        sidecar.comments[i].state = newState
        sidecar.comments[i].said.append(Say(by: by, text: event, kind: "status"))
        save(); pushNotes(); model.onChange()
    }

    func notesJSON() -> [Any] {
        sidecar.comments.map { any(.object([
            "id": .string($0.id), "text": .string($0.text), "target": .string($0.target), "state": .string($0.state),
            "anchor": $0.anchor, "version": .number(Double($0.version)), "lost": .bool($0.lost ?? false),
            "said": .array($0.said.map { s in .object(["by": .string(s.by), "text": .string(s.text), "kind": .string(s.kind), "at": .string(ISO8601DateFormatter().string(from: s.at))]) }),
        ])) }
    }

    func pushNotes() { call("__bridge.notes(notes)", ["notes": notesJSON()]) }
    func reveal(_ id: String) { call("__bridge.reveal(id)", ["id": id]) }

    func setPointing(_ on: Bool) {
        pointing = on
        call("__bridge.point(on)", ["on": on])
    }

    // MARK: Plumbing

    func call(_ code: String, _ arguments: [String: Any] = [:], in frame: WKFrameInfo? = nil) {
        Task { @MainActor in _ = try? await run(code, arguments, in: Page.world, frame: frame) }
    }

    func run(_ code: String, _ arguments: [String: Any], in world: WKContentWorld, frame: WKFrameInfo? = nil) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(code, arguments: arguments, in: frame, in: world) { result in
                switch result {
                case .success(let value): continuation.resume(returning: JSONValue(any: value))
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func evaluate(_ code: String) async throws -> JSONValue {
        if code.hasPrefix("@frame ") {
            guard let frame = frames.last else { throw SocketError.io("no subframe has announced itself") }
            return try await run(String(code.dropFirst(7)), [:], in: .page, frame: frame)
        }
        let bridgeWorld = code.hasPrefix("@bridge ")
        let source = bridgeWorld ? String(code.dropFirst(8)) : code
        return try await run(source, [:], in: bridgeWorld ? Page.world : .page)
    }

    func save() {
        guard unreadable == nil else { return }
        let data = sidecar.data()
        lastWritten = data
        try? data.write(to: sidecarURL, options: .atomic)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if kind == .url { let t = webView.title ?? ""; if !t.isEmpty { title = t; model.setTitle(t, for: location) } }
        if kind == .pdf { ready = true; model.onChange() }
    }

    // Local development servers (Herd, for one) use a locally generated CA the
    // system does not trust. Accept it for local development hosts only.
    static func isLocalDevelopment(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".test") || h.hasSuffix(".localhost")
    }

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
              Self.isLocalDevelopment(space.host) else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    var links: Links {
        model.listing.entry(location)?.links.flatMap(Links.init) ?? (kind == .url ? .external : .browser)
    }

    static var openedExternally: [URL] = []

    static func openExternally(_ url: URL) {
        if Env.test { openedExternally.append(url) } else { NSWorkspace.shared.open(url) }
    }

    static func document(_ url: URL?) -> String? { url?.absoluteString.components(separatedBy: "#").first }

    static func origin(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }

    // A link that opens a new window has no target frame; createWebViewWith hands it to the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url, !url.isFileURL, let frame = action.targetFrame else {
            decisionHandler(.allow); return
        }
        // A main frame's info reads about:blank during a fragment navigation, so the main frame goes by the web view's URL.
        let current = frame.isMainFrame ? webView.url : frame.request.url
        let samePage = url.fragment != nil && Self.document(url) == Self.document(current)
        let mode = frame.isMainFrame ? links : Self.document(current).flatMap { frameLinks[$0] } ?? .external
        let sameHost = Self.origin(url) != nil && Self.origin(url) == Self.origin(current)
        if !samePage, mode == .browser || (mode == .external && !sameHost) {
            Self.openExternally(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme != "about" { Self.openExternally(url) }
        return nil
    }
}
