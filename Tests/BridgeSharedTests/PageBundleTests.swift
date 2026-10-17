import Foundation
import Testing
@testable import BridgeShared

func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func aPageTravelsWithItsLocalFilesAndPointsAtTheCopies() throws {
    let here = try scratch(), elsewhere = try scratch(), there = try scratch()
    try Data("near".utf8).write(to: here.appendingPathComponent("near.png"))
    try Data("far".utf8).write(to: elsewhere.appendingPathComponent("far.png"))
    let page = here.appendingPathComponent("page.html")
    try Data("""
    <img src="near.png"><img src="\(elsewhere.path)/far.png?v=2"><img src="\(elsewhere.path)/far.png">
    <a href="https://example.com">x</a><img src="missing.png">
    """.utf8).write(to: page)

    let bundle = try PageBundle.make(page: page)
    #expect(bundle.files.count == 2)
    #expect(!bundle.html.contains(elsewhere.path))
    #expect(bundle.html.contains("https://example.com"))
    #expect(bundle.html.contains("missing.png"))

    let installed = try bundle.install(into: there)
    let html = try String(contentsOf: installed, encoding: .utf8)
    let srcs = try NSRegularExpression(pattern: #"src="(files/[^"]+)""#).matches(in: html, range: NSRange(html.startIndex..., in: html)).map { String(html[Range($0.range(at: 1), in: html)!]) }
    #expect(srcs.count == 3)
    #expect(try Set(srcs.map { try String(contentsOf: there.appendingPathComponent($0), encoding: .utf8) }) == ["near", "far"])
}

@Test func aBundleCannotWriteOutsideItsFolder() throws {
    let bundle = PageBundle(html: "", files: ["files/../../evil": Data()])
    #expect(throws: PageBundle.Unsafe.self) { try bundle.install(into: try scratch()) }
}

@Test func aRewriteFromTheOtherMacPointsBackAtTheOriginalFiles() throws {
    let here = try scratch(), elsewhere = try scratch(), there = try scratch(), mine = try scratch()
    try Data("far".utf8).write(to: elsewhere.appendingPathComponent("far.png"))
    let page = here.appendingPathComponent("page.html")
    try Data(#"<h1>One</h1><img src="\#(elsewhere.path)/far.png">"#.utf8).write(to: page)
    let sent = try PageBundle.make(page: page)

    let copy = try sent.install(into: there)
    let html = try String(contentsOf: copy, encoding: .utf8).replacingOccurrences(of: "One", with: "Two")
    try Data((html + #"<img src="files/new.png">"#).utf8).write(to: copy)
    try Data("new".utf8).write(to: there.appendingPathComponent("files/new.png"))
    let back = try PageBundle.make(page: copy)
    #expect(Set(back.files.keys) == Set(sent.files.keys).union(["files/new.png"]))

    let restored = PageBundle.restore(back.html, origins: sent.origins, folder: mine)
    #expect(restored.contains("<h1>Two</h1>"))
    #expect(restored.contains("\(elsewhere.path)/far.png"))
    #expect(restored.contains("\(mine.path)/files/new.png"))
    try Data(restored.utf8).write(to: page)
    var origins = sent.origins
    origins["files/new.png"] = mine.appendingPathComponent("files/new.png").path
    try FileManager.default.createDirectory(at: mine.appendingPathComponent("files"), withIntermediateDirectories: true)
    try Data("new".utf8).write(to: mine.appendingPathComponent("files/new.png"))
    let again = try PageBundle.make(page: page, known: Dictionary(uniqueKeysWithValues: origins.map { ($0.value, $0.key) }))
    #expect(again.html == back.html)
}

@Test func ofTwoRewritesTheLaterOrTheHigherWriterWinsOnBothMacs() {
    var share = Share(id: "s", location: "/x", from: "thomas", title: "x")
    #expect(share.older(than: 1, by: "a"))
    share.clock = 3; share.writer = "b"
    #expect(share.older(than: 4, by: "a"))
    #expect(!share.older(than: 2, by: "z"))
    #expect(share.older(than: 3, by: "c"))
    #expect(!share.older(than: 3, by: "a"))
    #expect(!share.older(than: 3, by: "b"))
}
