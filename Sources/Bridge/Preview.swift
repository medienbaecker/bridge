import AppKit
import WebKit
import BridgeCore

// WebKit only lays out and paints a web view that sits in an ordered-in window,
// so the page gets a borderless one far off every screen.
@MainActor
enum Preview {
    static func render(_ location: String, model: Model, width: CGFloat, to path: String) async throws -> NSSize {
        let page = Page(location: location, model: model, preview: true)
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.effectiveAppearance
        window.contentView = page.webView
        window.orderFrontRegardless()
        defer { page.close(); window.orderOut(nil) }

        page.load()
        let deadline = Date().addingTimeInterval(15)
        while !page.ready, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard page.ready else { throw Shot.Failure("the page did not finish loading in 15 s") }
        _ = try? await page.run("await document.fonts.ready", [:], in: .page)
        try await Task.sleep(for: .milliseconds(100))
        var height: CGFloat = 900
        if case .number(let h) = try await page.run("return Math.ceil(document.documentElement.scrollHeight)", [:], in: .page) { height = min(max(CGFloat(h), 200), 8000) }
        window.setContentSize(NSSize(width: width, height: height))
        try await Task.sleep(for: .milliseconds(150))

        let shot = try await page.webView.takeSnapshot(configuration: nil)
        let scale: CGFloat = 2
        guard let rep = Snapshot.transparentRep(NSSize(width: width, height: height), scale: scale) else { throw Shot.Failure("could not allocate the image") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        shot.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Shot.Failure("could not encode png") }
        try png.write(to: URL(fileURLWithPath: path))
        return NSSize(width: width, height: height)
    }
}
