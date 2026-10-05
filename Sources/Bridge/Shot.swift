import AppKit
import ScreenCaptureKit

/// Captures the window as the window server has it: real materials, popover
/// chrome, the true key state. Needs the display awake; `--snap` covers runs
/// with it asleep. `screen` captures the screen region instead, other apps
/// included, which needs the screen-recording permission.
enum Shot {
    struct Result {
        let width: Int; let height: Int; let colours: Int; let windows: [String]; let missing: [String]; let clipped: Bool
        let frames: [String]; let display: String; let scale: Double
    }

    static func capture(screen: Bool, windows: [NSWindow], to path: String) async throws -> Result {
        // A window the window server has not listed yet (a popover still opening)
        // would be cropped out silently, so wait for it and report it if still missing.
        let ids = Set(windows.map { CGWindowID($0.windowNumber) })
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var ours = content.windows.filter { ids.contains($0.windowID) }
        var tries = 0
        while ours.count < windows.count, tries < 10 {
            try await Task.sleep(for: .milliseconds(100))
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            ours = content.windows.filter { ids.contains($0.windowID) }
            tries += 1
        }
        let listed = Set(ours.map { $0.windowID })
        let missing = windows.filter { !listed.contains(CGWindowID($0.windowNumber)) }.map { $0.title }
        guard !ours.isEmpty else { throw Failure("none of the app's windows is on screen") }
        let union = ours.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        // Use the display holding most of the union: a window straddling two displays
        // otherwise came back at the other one's scale.
        let area = { (d: SCDisplay) -> CGFloat in let r = d.frame.intersection(union); return r.isNull ? 0 : r.width * r.height }
        guard let display = content.displays.max(by: { area($0) < area($1) }), area(display) > 0 else { throw Failure("no display under the window") }
        // A window hanging off the display's edge comes back cut; the reply says so.
        let clipped = !display.frame.contains(union)
        let filter = screen ? SCContentFilter(display: display, excludingWindows: []) : SCContentFilter(display: display, including: ours)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = union.offsetBy(dx: -display.frame.origin.x, dy: -display.frame.origin.y)
        config.width = Int(union.width * scale)
        config.height = Int(union.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure("could not encode png") }
        try data.write(to: URL(fileURLWithPath: path))
        return Result(width: image.width, height: image.height, colours: colours(in: rep), windows: ours.map { $0.title ?? "" }, missing: missing, clipped: clipped,
                      frames: ours.map { "\($0.title ?? "") \($0.frame)" }, display: "\(display.frame)", scale: Double(scale))
    }

    /// Distinct colours on a coarse grid: a blank or black frame counts one or two, a real one hundreds.
    static func colours(in rep: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        let steps = 48
        for i in 0..<steps {
            for j in 0..<steps {
                let x = i * rep.pixelsWide / steps, y = j * rep.pixelsHigh / steps
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let key = UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
                seen.insert(key)
            }
        }
        return seen.count
    }

    struct Failure: Error, CustomStringConvertible { let description: String; init(_ d: String) { description = d } }
}
