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
