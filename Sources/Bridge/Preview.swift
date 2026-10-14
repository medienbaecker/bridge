import AppKit
import WebKit
import BridgeCore

// WebKit only lays out and paints a web view that sits in an ordered-in window,
// so the page gets a borderless one far off every screen.
@MainActor
enum Preview {
    static let framesLoaded = """
        const loaded = (f) => new Promise((done) => {
          let doc = null
          try { doc = f.contentDocument } catch {}
          if (!f.getAttribute('src') && !f.srcdoc) return done()
          if (doc && doc.URL !== 'about:blank' && doc.readyState === 'complete') return done()
          f.addEventListener('load', done, { once: true })
        })
        await Promise.race([Promise.all([...document.querySelectorAll('iframe')].map(loaded)), new Promise((r) => setTimeout(r, 10000))])
        await new Promise((r) => setTimeout(r, 200))
        """

    struct Rendered { let size: NSSize; let origin: CGPoint; let pixels: NSSize }

    static func render(_ location: String, model: Model, width: CGFloat, site: URL?, crop: [Double]? = nil, scale: CGFloat? = nil, zoom: CGFloat? = nil, to path: String) async throws -> Rendered {
        let page = Page(location: location, model: model, preview: true)
        page.siteOverride = site
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
        _ = try? await page.run(Self.framesLoaded, [:], in: .page)
        try await Task.sleep(for: .milliseconds(100))
        var height: CGFloat = 900
        if case .number(let h) = try await page.run("return Math.ceil(document.documentElement.scrollHeight)", [:], in: .page) { height = min(max(CGFloat(h), 200), 8000) }
        window.setContentSize(NSSize(width: width, height: height))
        try await Task.sleep(for: .milliseconds(150))

        let full = NSRect(x: 0, y: 0, width: width, height: height)
        var rect = full
        if let crop {
            rect = NSRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3]).intersection(full)
            guard !rect.isEmpty else { throw Shot.Failure("--crop lies outside the page, which is \(Int(width))×\(Int(height))") }
        }
        let density = scale ?? 2
        let enlarge = zoom ?? 1
        let pixels = NSSize(width: (rect.width * density * enlarge).rounded(), height: (rect.height * density * enlarge).rounded())
        guard max(pixels.width, pixels.height) <= 16384 else { throw Shot.Failure("the image would be \(Int(pixels.width))×\(Int(pixels.height)) pixels; pass a smaller --crop") }

        let config = WKSnapshotConfiguration()
        config.rect = rect
        if scale != nil { config.snapshotWidth = NSNumber(value: Double(rect.width * density / window.backingScaleFactor)) }
        let shot = try await page.webView.takeSnapshot(configuration: config)
        guard let rep = Snapshot.transparentRep(rect.size, scale: density) else { throw Shot.Failure("could not allocate the image") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: rect.size).fill()
        }
        shot.draw(in: NSRect(origin: .zero, size: rect.size))
        NSGraphicsContext.restoreGraphicsState()

        var out = rep
        if enlarge > 1 {
            guard let big = Snapshot.transparentRep(rect.size, scale: density * enlarge), let image = rep.cgImage else { throw Shot.Failure("could not allocate the image") }
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: big)
            context?.imageInterpolation = .none
            NSGraphicsContext.current = context
            NSImage(cgImage: image, size: rect.size).draw(in: NSRect(origin: .zero, size: rect.size))
            NSGraphicsContext.restoreGraphicsState()
            out = big
        }
        guard let png = out.representation(using: .png, properties: [:]) else { throw Shot.Failure("could not encode png") }
        try png.write(to: URL(fileURLWithPath: path))
        return Rendered(size: rect.size, origin: rect.origin, pixels: NSSize(width: out.pixelsWide, height: out.pixelsHigh))
    }
}
