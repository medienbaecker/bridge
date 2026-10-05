import AppKit
import WebKit

// cacheDisplay on the theme frame skips layer-backed table rows, so those are
// re-rendered through PDF, and the out-of-process web view is only reachable
// through takeSnapshot. The three are composited into one picture.
enum Snapshot {
    static func write(window: NSWindow, webView: WKWebView?, to path: String) async {
        guard let content = window.contentView, let frame = content.superview else { return }
        let bounds = frame.bounds
        let scale = window.backingScaleFactor
        guard let chrome = frame.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        frame.cacheDisplay(in: bounds, to: chrome)
        let lists = views(in: content, of: NSScrollView.self).compactMap { scroll -> (NSBitmapImageRep, NSRect)? in
            guard let rep = transparentRep(scroll.bounds.size, scale: scale) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSImage(data: scroll.dataWithPDF(inside: scroll.bounds))?.draw(in: NSRect(origin: .zero, size: scroll.bounds.size))
            NSGraphicsContext.restoreGraphicsState()
            return (rep, scroll.convert(scroll.bounds, to: frame))
        }
        var shot: NSImage?
        if let webView, webView.window === window, webView.bounds.width > 0 {
            shot = try? await webView.takeSnapshot(configuration: nil)
        }
        guard let out = transparentRep(bounds.size, scale: scale) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let chromeImage = NSImage(size: chrome.size)
        chromeImage.addRepresentation(chrome)
        chromeImage.draw(in: bounds)
        for effect in views(in: content, of: NSVisualEffectView.self) {
            let dark = effect.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSColor(white: dark ? 0.2 : 0.94, alpha: 1).setFill()
            effect.convert(effect.bounds, to: frame).fill()
        }
        for (rep, rect) in lists {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            image.draw(in: rect)
        }
        if let shot, let webView { shot.draw(in: webView.convert(webView.bounds, to: frame)) }
        for other in NSApp.windows where other !== window && other.isVisible && other.parent === window {
            guard let view = other.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            let onScreen = other.convertToScreen(view.convert(view.bounds, to: nil))
            let origin = NSPoint(x: onScreen.origin.x - window.frame.origin.x, y: onScreen.origin.y - window.frame.origin.y)
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: origin, size: onScreen.size).fill()
            image.draw(in: NSRect(origin: origin, size: onScreen.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static func transparentRep(_ size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    static func dump(_ view: NSView, depth: Int = 0) -> [String] {
        [String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame) hidden=\(view.isHidden)"] + view.subviews.flatMap { dump($0, depth: depth + 1) }
    }

    static func views<T: NSView>(in view: NSView, of type: T.Type) -> [T] {
        if let v = view as? T { return [v] }
        return view.subviews.flatMap { views(in: $0, of: type) }
    }
}
