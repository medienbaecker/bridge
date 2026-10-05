import Testing
import Foundation
@testable import BridgeCore

@Test func jsonValueRoundTrip() throws {
    let v: JSONValue = .object(["a": .number(1), "b": .array([.string("x"), .bool(true), .null])])
    let data = try JSON.compact.encode(v)
    #expect(try JSON.decoder.decode(JSONValue.self, from: data) == v)
    #expect(JSONValue(any: NSNumber(value: true)) == .bool(true))
    #expect(JSONValue(any: NSNumber(value: 1)) == .number(1))
}

@Test func nonFiniteNumbersAreScrubbed() throws {
    let data = try JSON.compact.encode(JSONValue.number(.nan))
    #expect(String(decoding: data, as: UTF8.self) == "0")
}

@Test func sidecarPaths() {
    // A record lives in the store, named after its page and keyed by the page's resolved path; a site's by its URL.
    let page = Paths.sidecar(for: "/tmp/x/page.jsx").path
    #expect(page.contains("/answers/page.jsx-") && page.hasSuffix(".bridge.json") && page.split(separator: "-").last!.count == 12 + ".bridge.json".count)
    #expect(Paths.sidecar(for: "https://example.test/a").path.hasSuffix("/answers/" + Paths.id(for: "https://example.test/a") + ".bridge.json"))
    #expect(Paths.legacySidecar(for: "/tmp/x/page.jsx").path == "/tmp/x/page.jsx.bridge.json")
    #expect(Paths.dataFile(for: "/tmp/x/page.jsx").path == "/tmp/x/page.data.json")
}

@Test func listingOrdersProjectsByActivity() {
    var l = Listing()
    l.bridges.append(BridgeEntry(location: "/a/one.html", project: "/a", session: "s", at: Date(timeIntervalSince1970: 100)))
    l.bridges.append(BridgeEntry(location: "/b/two.html", project: "/b", session: "s", at: Date(timeIntervalSince1970: 200)))
    l.bridges.append(BridgeEntry(location: "/a/three.html", project: "/a", session: "s", at: Date(timeIntervalSince1970: 300)))
    #expect(l.projects == ["/a", "/b"])
    #expect(l.bridges(in: "/a", crossed: false).map(\.title) == ["three", "one"])
}

@Test func requestRoundTrip() throws {
    let r = Request.present(locations: ["/x.html"], cwd: "/x", session: "tty", ground: Ground(repo: "/x", branch: "main", commit: "abc"))
    let data = try JSON.compact.encode(r)
    let back = try JSON.decoder.decode(Request.self, from: data)
    if case .present(let l, _, _, let g) = back { #expect(l == ["/x.html"]); #expect(g?.commit == "abc") } else { Issue.record("wrong case") }
}

@Test func responseRoundTrip() throws {
    let r = Response.ok(.number(2))
    let data = try JSON.compact.encode(r)
    let s = String(decoding: data, as: UTF8.self)
    let back = try JSON.decoder.decode(Response.self, from: data)
    #expect(back.value == .number(2), "wire: \(s)")
    #expect(JSONValue(any: 2 as Any) == .number(2))
    #expect(JSONValue(any: "x" as Any) == .string("x"))
    #expect(JSONValue(any: true as Any) == .bool(true))
    let opt: Any? = 3
    #expect(JSONValue(any: opt ?? NSNull()) == .number(3))
}

@Test func sidecarFromAnEarlierBuildDecodesWithDefaults() throws {
    let old = #"{"answers":{"script":"Der alte Text"},"status":"sent"}"#
    let s = try JSON.decoder.decode(Sidecar.self, from: Data(old.utf8))
    #expect(s.answers["script"] == .string("Der alte Text"))
    #expect(s.status == "sent")
    #expect(s.version == 1)
    #expect(s.comments.isEmpty && s.history.isEmpty && s.fingerprint == nil)
}

@Test func sidecarKeepsFieldsItDoesNotKnow() throws {
    let json = #"{"status":"open","version":2,"future":{"kept":true},"mood":"blue"}"#
    var s = try JSON.decoder.decode(Sidecar.self, from: Data(json.utf8))
    #expect(s.extra["future"] == .object(["kept": .bool(true)]))
    s.answers["a"] = .string("b")
    let again = try JSON.decoder.decode(Sidecar.self, from: s.data())
    #expect(again.extra["mood"] == .string("blue"))
    #expect(again.version == 2 && again.answers["a"] == .string("b"))
}

@Test func unreadableSidecarIsRefusedNotReplaced() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).bridge.json")
    let bytes = Data(#"{"status":"open","version":1,"answers":{"a":"Lost"#.utf8)
    try bytes.write(to: url)
    #expect(throws: Sidecar.Unreadable.self) { try Sidecar.load(url) }
    #expect(throws: Sidecar.Unreadable.self) { try Sidecar.modify(url) { $0.status = "sent" } }
    #expect(try Data(contentsOf: url) == bytes)
    let wrongShape = Data(#"{"version":"one"}"#.utf8)
    try wrongShape.write(to: url)
    #expect(throws: Sidecar.Unreadable.self) { try Sidecar.load(url) }
    #expect(try Sidecar.load(url.appendingPathExtension("missing")).version == 1)
}

@Test func datesKeepFractionsAndStillReadWholeSeconds() throws {
    let stamp = Date(timeIntervalSince1970: 1_790_000_000.25)
    let written = String(decoding: try JSON.compact.encode(["at": stamp]), as: UTF8.self)
    #expect(written.contains(".250Z"))
    let back = try JSON.decoder.decode([String: Date].self, from: Data(written.utf8))
    #expect(abs(back["at"]!.timeIntervalSince(stamp)) < 0.001)
    let old = try JSON.decoder.decode([String: Date].self, from: Data(#"{"at":"2026-09-20T20:00:00Z"}"#.utf8))
    #expect(old["at"] == Date(timeIntervalSince1970: 1_789_934_400))
    let same = String(decoding: try JSON.compact.encode(old), as: UTF8.self)
    #expect(same == #"{"at":"2026-09-20T20:00:00Z"}"#)
}

@Test func oneRecordForEverySpellingOfAPath() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spell-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let real = dir.appendingPathComponent("page.html"); try Data("x".utf8).write(to: real)
    let link = dir.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
    let a = Paths.sidecar(for: real.path)
    let b = Paths.sidecar(for: link.appendingPathComponent("page.html").path)
    let c = Paths.sidecar(for: dir.appendingPathComponent("sub/../page.html").path)
    #expect(a == b && b == c)
}

@Test func lintNamesTheFourFaults() {
    let kit = ".muted { color: red } .card { border: 0 } .row { display: flex } .row.between { } .num { } .draft { padding: 14px } .bar::after { } .token.comment { } .bridge-pin { }"
    let page = """
    <title>Editor notes</title>
    <style>.th { border-radius: 3px; color: #333 } .th.draft { border: 1px dashed red }</style>
    <div class="card faint">x</div>
    <figure class="th draft"></figure>
    <pre><code class="language-html">#item-a     "Lorem ipsum"       fallback A
    #item-b     "Dolor sit"         B</code></pre>
    <pre><code class="language-php">&lt;?php return $page->children();</code></pre>
    """
    let findings = Lint(kitCSS: kit).run(html: page)
    let texts = findings.map(\.text)
    #expect(texts.contains { $0.hasPrefix("`.faint` styles nothing: did you mean `.muted`?") })
    #expect(texts.contains { $0.hasPrefix("`.draft` is styled by this page and by the kit") && $0.contains("`.editor-draft`") })
    #expect(texts.contains { $0.contains("a colour written out (#333)") })
    #expect(texts.contains { $0.contains("a radius written out (3px)") })
    #expect(texts.filter { $0.contains("columns spaced by hand") }.count == 1)
    #expect(!texts.contains { $0.contains("`.card`") })
    #expect(findings.filter { $0.level == .error }.count == 2)
    #expect(Lint(kitCSS: kit).vocabulary == ["muted", "card", "row", "between", "num", "draft", "bar"])
}

@Test func defaultsIsAbsentOnEveryEarlierRecordAndSurvivesARoundTrip() throws {
    // A record as every build before this one wrote it: no defaults key.
    let earlier = #"{"answers":{"layout":"grid","radius":8},"comments":[],"history":[],"questions":["layout","radius"],"status":"open","version":1}"#
    let s = try JSON.decoder.decode(Sidecar.self, from: Data(earlier.utf8))
    #expect(s.defaults.isEmpty)
    #expect(s.answers["layout"] == .string("grid"))
    let again = String(decoding: try JSON.compact.encode(s), as: UTF8.self)
    #expect(again == earlier)
    // Written by this build, the key is there; an older build files it under extra and carries it.
    var d = s; d.defaults = ["radius"]
    let written = String(decoding: try JSON.compact.encode(d), as: UTF8.self)
    #expect(written.contains(#""defaults":["radius"]"#))
    #expect(try JSON.decoder.decode(Sidecar.self, from: Data(written.utf8)).defaults == ["radius"])
}

@Test func scratchpadNamesTheProjectItCameFrom() throws {
    // The project is encoded in the scratchpad path with every separator turned into
    // a dash, which a dash in a directory name looks exactly like, so the decode is
    // checked against real directories.
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bridge-scratchpad-\(UUID().uuidString)")
    let projects = root.appendingPathComponent("Work/Projects")
    for name in ["Project-A", "test-alter", "test", "site"] {
        try fm.createDirectory(at: projects.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    // The real path of the temp root, because the decode walks the filesystem.
    let base = projects.resolvingSymlinksInPath().path
    func cwd(_ dir: String) -> String {
        "/tmp/claude-501/" + dir.replacingOccurrences(of: "/", with: "-") + "/" + UUID().uuidString + "/scratchpad"
    }

    // A plain name, a name with a dash in it, and one whose sibling is a prefix of it.
    #expect(Ground.claudeScratchpadProject(cwd(base + "/site")) == base + "/site")
    #expect(Ground.claudeScratchpadProject(cwd(base + "/Project-A")) == base + "/Project-A")
    #expect(Ground.claudeScratchpadProject(cwd(base + "/test-alter")) == base + "/test-alter")
    // A project whose folder is gone is still named correctly.
    #expect(Ground.claudeScratchpadProject(cwd(base + "/old-project")) == base + "/old-project")
    // A folder inside the scratchpad is still that session's project.
    #expect(Ground.claudeScratchpadProject(cwd(base + "/site") + "/notes") == base + "/site")
    // Not a scratchpad at all, and a scratchpad whose segment encodes no path.
    #expect(Ground.claudeScratchpadProject("/Users/x/Work/thing") == nil)
    #expect(Ground.claudeScratchpadProject("/tmp/claude-501/bash-edit-diff/x/scratchpad") == nil)
    // The whole point: a session in its own scratchpad never reports `scratchpad`.
    #expect(Ground.projectRoot(for: cwd(base + "/site")) == base + "/site")
    try? fm.removeItem(at: root)
}

@Test func lintLeavesAPillAlone() {
    let page = #"<style>.chip { border-radius: 999px } .tag { border-radius: 99px } .box { border-radius: 12px }</style>"#
    let texts = Lint(kitCSS: "").run(html: page).map(\.text)
    #expect(texts.filter { $0.contains("a radius written out") } == ["a radius written out (12px): use var(--bridge-radius), the kit's one"])
}

@Test func lintNamesABlobWorklet() {
    let blob = "<script>const u = URL.createObjectURL(new Blob([src])); await ctx.audioWorklet.addModule(u);</script>"
    let file = "<script>await ctx.audioWorklet.addModule('synth.js');</script>"
    #expect(Lint(kitCSS: "").run(html: blob).contains { $0.text.hasPrefix("an AudioWorklet module from a blob URL") })
    #expect(!Lint(kitCSS: "").run(html: file).contains { $0.text.hasPrefix("an AudioWorklet module from a blob URL") })
}

@Test func sessionLifeFollowsTheHook() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-sessions-\(UUID().uuidString)")
    let own = ClaudeSessions.dir
    ClaudeSessions.dir = dir
    defer { ClaudeSessions.dir = own; try? FileManager.default.removeItem(at: dir) }
    #expect(ClaudeSessions.life(of: "s") == .unknown)
    ClaudeSessions.record("SessionStart", session: "s", pid: getpid())
    #expect(ClaudeSessions.life(of: "s") == .idle)
    #expect(ClaudeSessions.life(of: "other") == .gone)
    ClaudeSessions.record("UserPromptSubmit", session: "s", pid: getpid())
    #expect(ClaudeSessions.life(of: "s") == .working)
    ClaudeSessions.record("Stop", session: "s", pid: 0)
    #expect(ClaudeSessions.life(of: "s") == .idle)
    ClaudeSessions.record("SessionEnd", session: "s", pid: 0)
    #expect(ClaudeSessions.life(of: "s") == .gone)
    ClaudeSessions.record("UserPromptSubmit", session: "s", pid: 999_999)
    #expect(ClaudeSessions.life(of: "s") == .gone)
}
