import AppKit
import ApplicationServices
import BridgeCore
@preconcurrency import ScreenCaptureKit
import Vision
import WebKit

final class FreezePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, let freeze = Freeze.current, freeze.panel === self else { return super.sendEvent(event) }
        freeze.scroll(event)
    }

    override func resignKey() {
        super.resignKey()
        guard !Env.test, let freeze = Freeze.current, freeze.panel === self else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard Freeze.current === freeze, !isKeyWindow, NSWorkspace.shared.frontmostApplication == freeze.previous ?? .current else { return }
            makeKey()
        }
    }
}

final class Freeze: NSObject {
    enum Outcome: Equatable { case cancel, draft, send(String) }

    struct Picture: Sendable {
        let image: CGImage
        let frame: CGRect
    }

    nonisolated(unsafe) static var current: Freeze?
    nonisolated(unsafe) static var starting = false
    static var colour: NSColor { .controlAccentColor }
    static var pin: String {
        let accent = colour.usingColorSpace(.sRGB) ?? colour
        let fill = String(format: "#%02X%02X%02X", Int(accent.redComponent * 255), Int(accent.greenComponent * 255), Int(accent.blueComponent * 255))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"28\" height=\"32\" viewBox=\"0 0 28 32\"><path d=\"M14 29.6 L6.2 21.8 A11 11 0 1 1 21.8 21.8 Z\" fill=\"\(fill)\" stroke=\"white\" stroke-width=\"2\" stroke-linejoin=\"round\"/><path d=\"M14 9.5v8M10 13.5h8\" stroke=\"white\" stroke-width=\"2\" stroke-linecap=\"round\"/></svg>"
    }
    static var cursor: NSCursor {
        guard let image = NSImage(data: Data(pin.utf8)) else { return .crosshair }
        return NSCursor(image: image, hotSpot: CGPoint(x: 14, y: 29))
    }

    let screen: NSScreen
    let windows: [[String: Any]]
    let page: Page
    let panel: FreezePanel
    let backdrop = NSView()
    let overlay = FreezeView()
    let glass = NSGlassEffectView()
    let recipients: [Model.Recipient]
    var previous: NSRunningApplication?
    var highlight: CGRect?
    var pointer: CGPoint?
    var looking = false
    var awake: Set<pid_t> = []
    var describing: [Task<Void, Never>] = []
    var veiled: [NSWindow] = []
    var still: Task<Picture?, Never>?
    var taking: [String: Task<Picture?, Never>] = [:]
    var pictures: [String: Picture] = [:]
    var placed: [String: (page: String, anchor: JSONValue)] = [:]
    var captures = 0
    var glassLeftOut = false
    var content: Task<Result<SCShareableContent, Error>, Never>?
    var onFinish: (Freeze, Outcome) -> Void = { _, _ in }

    var picked: String?
    var places: [String: String] = [:]
    var settled = false

    init(screen: NSScreen, windows: [[String: Any]], recipients: [Model.Recipient], picked: String?, page: Page) {
        self.screen = screen
        self.windows = windows
        self.page = page
        self.recipients = recipients
        self.picked = recipients.contains { $0.session == picked } ? picked : nil
        panel = FreezePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.setFrame(screen.frame, display: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        backdrop.frame = content.bounds
        backdrop.wantsLayer = true
        backdrop.layer?.contentsGravity = .resize
        content.addSubview(backdrop)
        overlay.freeze = self
        overlay.frame = content.bounds
        content.addSubview(overlay)
        glass.cornerRadius = 12
        glass.isHidden = true
        content.addSubview(glass)
        page.webView.removeFromSuperview()
        page.webView.frame = content.bounds
        content.addSubview(page.webView)
        panel.contentView = content
    }

    static func screenUnderPointer() -> NSScreen? {
        if Env.test, let named = NSScreen.screens.first(where: { $0.localizedName == ProcessInfo.processInfo.environment["BRIDGE_SCREEN"] }) { return named }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func start(recipients: [Model.Recipient], picked: String?, page: Page, onFinish: @escaping (Freeze, Outcome) -> Void) async {
        guard current == nil, !starting, let screen = screenUnderPointer() else { return }
        starting = true
        defer { starting = false }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": !Env.test] as CFDictionary)
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        let previous = Env.test ? nil : NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        let windows = onScreen()
        page.startFreeze()
        let freeze = Freeze(screen: screen, windows: windows, recipients: recipients, picked: picked, page: page)
        freeze.onFinish = onFinish
        for pid in Set(windows.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 }) where pid != getpid() && freeze.awake.insert(pid).inserted {
            Task { await wake(pid) }
        }
        current = freeze
        freeze.previous = previous
        if NSApp.isHidden {
            freeze.veiled = NSApp.windows.filter { !($0 is FreezePanel) && $0.alphaValue > 0 }
            for window in freeze.veiled { window.alphaValue = 0 }
        }
        freeze.panel.orderFrontRegardless()
        freeze.content = Task { await Result { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) } }
        freeze.captures += 1
        freeze.still = Task { await freeze.shoot(CGRect(origin: .zero, size: screen.frame.size)) }
        Task {
            guard let picture = await freeze.still?.value, current === freeze else { return }
            freeze.backdrop.layer?.contents = picture.image
        }
        if !Env.test { freeze.panel.makeKeyAndOrderFront(nil) }
        freeze.panel.makeFirstResponder(page.webView)
        let list = freeze.recipients.map { ["session": $0.session, "name": $0.name.isEmpty ? $0.page : $0.name, "project": $0.project.isEmpty ? "No project" : $0.project, "busy": $0.busy, "picked": $0.session == freeze.picked, "colour": Self.css(Model.colour(of: $0.session))] as [String: Any] }
        _ = try? await page.run("__bridge.agents(list); __bridge.cursor(pin)", ["list": list, "pin": pin], in: Page.world)
        await freeze.setCursor()
        await freeze.opened(from: previous)
    }

    static func onScreen() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    func setCursor() async {
        let mouse = NSEvent.mouseLocation
        let at = ["x": mouse.x - screen.frame.minX, "y": screen.frame.maxY - mouse.y]
        let pin = try? await page.run("return __bridge.pinsAt(x, y)", at, in: Page.world)
        (pin == .bool(false) ? NSCursor.arrow : Self.cursor).set()
    }

    // MARK: Elements

    func global(_ point: CGPoint) -> CGPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: screen.frame.minX + point.x, y: top - screen.frame.maxY + point.y)
    }

    func local(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return rect.offsetBy(dx: -screen.frame.minX, dy: -(top - screen.frame.maxY))
    }

    func window(at point: CGPoint) -> [String: Any]? {
        let tops = Self.displayTops()
        return windows.first { info in
            (info[kCGWindowLayer as String] as? Int ?? 0) < 1000 && (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 && Self.frame(of: info).contains(point)
                && !WindowRules.menuBarStrip(title: info[kCGWindowName as String] as? String, frame: Self.frame(of: info), displayTops: tops)
        }
    }

    static func main(_ info: [String: Any], displayTops tops: [CGFloat]) -> Bool {
        WindowRules.main(layer: info[kCGWindowLayer as String] as? Int ?? 0, alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                         sharing: info[kCGWindowSharingState as String] as? Int ?? 1, title: info[kCGWindowName as String] as? String,
                         frame: frame(of: info), displayTops: tops)
    }

    static func displayTops() -> [CGFloat] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0).minY }
    }

    static func frame(of window: [String: Any]) -> CGRect {
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
    }

    nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    func element(at point: CGPoint, picture: Picture?) async -> [String: JSONValue] {
        let spot = global(point)
        guard let info = window(at: spot), let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return [:] }
        var out: [String: JSONValue] = ["app": .string(info[kCGWindowOwnerName as String] as? String ?? "")]
        if let title = info[kCGWindowName as String] as? String, !title.isEmpty { out["window"] = .string(title) }
        let offset = CGPoint(x: spot.x - point.x, y: spot.y - point.y)
        return await Self.label(out, at: point, offset: offset, in: pid == getpid() ? nil : pid, picture: picture)
    }

    @concurrent nonisolated static func label(_ known: [String: JSONValue], at point: CGPoint, offset: CGPoint, in pid: pid_t?, picture: Picture?) async -> [String: JSONValue] {
        var out = known
        let frame = pid.flatMap { accessible(at: CGPoint(x: point.x + offset.x, y: point.y + offset.y), in: $0, into: &out) }?.offsetBy(dx: -offset.x, dy: -offset.y)
        guard out["label"] == nil, let picture else { return out }
        let small = frame.map { $0.width < 800 && $0.height < 240 } ?? false
        let area = small ? frame! : CGRect(x: point.x - 160, y: point.y - 16, width: 320, height: 32)
        let scale = CGFloat(picture.image.width) / picture.frame.width
        if let text = read(area.offsetBy(dx: -picture.frame.minX, dy: -picture.frame.minY), in: picture.image, scale: scale) { out["label"] = .string(text) }
        return out
    }

    nonisolated static func accessible(at spot: CGPoint, in pid: pid_t, into out: inout [String: JSONValue]) -> CGRect? {
        var hit: AXUIElement?
        guard AXIsProcessTrusted(), AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(spot.x), Float(spot.y), &hit) == .success, let hit else { return nil }
        if let role = attribute(hit, "AXRole") as? String { out["role"] = .string(role.replacingOccurrences(of: "AX", with: "").lowercased()) }
        if let label = name(of: hit) { out["label"] = .string(label) }
        var node = attribute(hit, "AXParent") as! AXUIElement?
        for _ in 0..<40 {
            guard let current = node else { break }
            if attribute(current, "AXRole") as? String == "AXWebArea" {
                if let url = attribute(current, "AXURL") as? URL { out["url"] = .string(url.absoluteString) }
                break
            }
            node = attribute(current, "AXParent") as! AXUIElement?
        }
        return bounds(of: hit)
    }

    nonisolated static func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, "AXPosition"), let size = attribute(element, "AXSize") else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    @concurrent nonisolated static func wake(_ pid: pid_t) async {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    @concurrent nonisolated static func bounds(at spot: CGPoint, in pid: pid_t) async -> CGRect? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(spot.x), Float(spot.y), &hit) == .success, let hit else { return nil }
        return bounds(of: hit)
    }

    nonisolated static func text(_ element: AXUIElement) -> String? {
        for name in ["AXTitle", "AXDescription", "AXValue", "AXPlaceholderValue", "AXHelp"] {
            if let text = attribute(element, name) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
            }
        }
        return nil
    }

    nonisolated static func name(of element: AXUIElement) -> String? {
        if let own = text(element) { return own }
        if let label = attribute(element, "AXTitleUIElement"), CFGetTypeID(label) == AXUIElementGetTypeID(), let text = text(label as! AXUIElement) { return text }
        guard let size = attribute(element, "AXSize") else { return nil }
        var extent = CGSize.zero
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        guard extent.width <= 400, extent.height <= 80 else { return nil }
        var queue = (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
        var looked = 0
        while !queue.isEmpty, looked < 30 {
            let child = queue.removeFirst()
            looked += 1
            if let text = text(child) { return text }
            queue += (attribute(child, "AXChildren") as? [AXUIElement]) ?? []
        }
        return nil
    }

    nonisolated static func read(_ frame: CGRect, in image: CGImage, scale: CGFloat) -> String? {
        guard frame.width > 4, frame.height > 4 else { return nil }
        let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = image.cropping(to: pixels) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: crop).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(80))
    }

    // MARK: Notes

    var notes: [Comment] { page.sidecar.comments }

    func scroll(_ event: NSEvent) {
        let at = local(CGRect(origin: event.cgEvent?.location ?? .zero, size: .zero)).origin
        page.call("__bridge.wheel(x, y, dx, dy)", ["x": at.x, "y": at.y, "dx": -event.scrollingDeltaX, "dy": -event.scrollingDeltaY])
    }

    static func css(_ colour: NSColor) -> String {
        guard let rgb = colour.usingColorSpace(.sRGB) else { return "gray" }
        return "rgb(\(Int(rgb.redComponent * 255)) \(Int(rgb.greenComponent * 255)) \(Int(rgb.blueComponent * 255)))"
    }

    func showGlass(_ rect: CGRect?) {
        guard let rect else { glass.isHidden = true; return }
        glass.frame = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        glass.isHidden = false
    }

    func hover(_ point: CGPoint) {
        pointer = point
        if !looking { lookUp() }
    }

    func lookUp() {
        guard let point = pointer else { return }
        let spot = global(point)
        guard let info = window(at: spot), let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == getpid() || AXIsProcessTrusted() else { return show(nil, for: point) }
        let whole = Self.frame(of: info)
        let number = info[kCGWindowNumber as String] as? Int ?? 0
        looking = true
        let asleep = awake.insert(pid).inserted
        Task {
            if asleep, pid != getpid() { await Self.wake(pid) }
            let found = pid == getpid() ? await own(at: spot, in: number) : await Self.bounds(at: spot, in: pid)
            let frame = found.flatMap { $0.width * $0.height < whole.width * whole.height * 0.8 ? $0 : nil }
            looking = false
            show(frame.map(local), for: point)
            if pointer != point { lookUp() }
        }
    }

    static func view(at spot: CGPoint, in number: Int) -> (window: NSWindow, view: NSView, inWindow: CGPoint)? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        guard let window = NSApp.windows.first(where: { $0.windowNumber == number }), let frame = window.contentView?.superview else { return nil }
        let inWindow = window.convertPoint(fromScreen: CGPoint(x: spot.x, y: top - spot.y))
        guard let view = frame.hitTest(frame.superview?.convert(inWindow, from: nil) ?? inWindow) else { return nil }
        return (window, view, inWindow)
    }

    static func css(_ inWindow: CGPoint, in web: WKWebView) -> CGPoint {
        let at = web.convert(inWindow, from: nil)
        let inset = web.obscuredContentInsets
        return CGPoint(x: (at.x - inset.left) / web.pageZoom, y: (at.y - inset.top) / web.pageZoom)
    }

    func own(at spot: CGPoint, in number: Int) async -> CGRect? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        guard let (window, view, inWindow) = Self.view(at: spot, in: number) else { return nil }
        var rect = view.convert(view.bounds, to: nil)
        if let web = sequence(first: view, next: \.superview).first(where: { $0 is WKWebView }) as? WKWebView {
            let zoom = web.pageZoom
            let at = Self.css(inWindow, in: web)
            let found = try? await web.evaluateJavaScript("(() => { const e = document.elementFromPoint(\(at.x), \(at.y)); if (!e || e === document.body || e === document.documentElement) return null; const r = e.getBoundingClientRect(); return [r.left, r.top, r.width, r.height] })()") as? [Double]
            guard let found, found.count == 4 else { return nil }
            let inset = web.obscuredContentInsets
            rect = web.convert(CGRect(x: found[0] * zoom + inset.left, y: found[1] * zoom + inset.top, width: found[2] * zoom, height: found[3] * zoom), to: nil)
        }
        let screen = window.convertToScreen(rect)
        return CGRect(x: screen.minX, y: top - screen.maxY, width: screen.width, height: screen.height)
    }

    func show(_ frame: CGRect?, for point: CGPoint) {
        guard pointer == point, frame != highlight else { return }
        highlight = frame
        overlay.needsDisplay = true
    }

    func unhover() {
        pointer = nil
        guard highlight != nil else { return }
        highlight = nil
        overlay.needsDisplay = true
    }

    static func number(_ anchor: JSONValue, _ key: String, _ fallback: Double) -> Double {
        if case .object(let o) = anchor, case .number(let n)? = o[key] { return n }
        return fallback
    }

    func area(of anchor: JSONValue) -> (spot: CGPoint, box: CGRect?) {
        let size = screen.frame.size
        let spot = CGPoint(x: Self.number(anchor, "x", 0.5) * size.width, y: Self.number(anchor, "y", 0.5) * size.height)
        let w = Self.number(anchor, "w", 0), h = Self.number(anchor, "h", 0)
        return (spot, w > 0 && h > 0 ? CGRect(x: spot.x, y: spot.y, width: w * size.width, height: h * size.height) : nil)
    }

    func describe(_ anchor: JSONValue, picture: Picture?) async -> (target: String, found: [String: JSONValue]) {
        let (spot, box) = area(of: anchor)
        let found = await element(at: box.map { CGPoint(x: $0.midX, y: $0.midY) } ?? spot, picture: picture)
        func string(_ key: String) -> String? { found[key]?.stringValue }
        let what = [string("role"), string("label").map { "\"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
        let place = string("url") ?? string("window")
        return ([what.isEmpty ? nil : what, string("app"), place].compactMap { $0 }.joined(separator: " · "), found)
    }

    // MARK: Guessing the agent

    func opened(from app: NSRunningApplication?) async {
        guard let pid = app?.processIdentifier,
              case let tops = Self.displayTops(),
              let info = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid && Self.main($0, displayTops: tops) }) else { return }
        let frame = local(Self.frame(of: info))
        await suggest(await element(at: CGPoint(x: frame.midX, y: frame.midY), picture: nil), page: nil)
    }

    func clicked(_ anchor: JSONValue) async {
        guard !settled else { return }
        settled = true
        let (spot, box) = area(of: anchor)
        let found = await element(at: box.map { CGPoint(x: $0.midX, y: $0.midY) } ?? spot, picture: nil)
        await suggest(found, page: await place(anchor)?.page)
    }

    func suggest(_ found: [String: JSONValue], page location: String?) async {
        guard let session = guess(found, page: location), session != picked else { return }
        picked = session
        _ = try? await page.run("__bridge.pick(session)", ["session": session], in: Page.world)
    }

    func guess(_ found: [String: JSONValue], page location: String?) -> String? {
        if let location {
            let session = page.model.listing.entry(location)?.session
            return recipients.contains { $0.session == session } ? session : nil
        }
        let url = found["url"]?.stringValue
        let remembered = (Model.remembered("places") as? [String: String])?[Place.key(url: url, app: found["app"]?.stringValue ?? "")]
        guard let project = Place.project(url: url, window: found["window"]?.stringValue, among: recipients.map(\.project).filter { !$0.isEmpty }) ?? remembered else { return nil }
        return recipients.last { $0.project == project }?.session
    }

    func landed(_ id: String, found: [String: JSONValue]) {
        let key = Place.key(url: found["url"]?.stringValue, app: found["app"]?.stringValue ?? "")
        places[id] = placed[id] == nil && !key.isEmpty ? key : nil
    }

    func remember(_ notes: [Comment], sentTo session: String) {
        guard let project = recipients.first(where: { $0.session == session })?.project, !project.isEmpty else { return }
        var remembered = Model.remembered("places") as? [String: String] ?? [:]
        for note in notes { if let key = places[note.id] { remembered[key] = project } }
        Model.remember(remembered, "places")
    }

    // MARK: Pins on Bridge's own pages

    static func onElement(_ anchor: JSONValue) -> Bool {
        if case .object(let o) = anchor { return o["tag"] != nil }
        return false
    }

    func place(_ anchor: JSONValue) async -> (page: String, anchor: JSONValue)? {
        let (spot, box) = area(of: anchor)
        let at = global(box.map { CGPoint(x: $0.midX, y: $0.midY) } ?? spot)
        guard let info = window(at: at), info[kCGWindowOwnerPID as String] as? Int32 == getpid(),
              let (_, view, inWindow) = Self.view(at: at, in: info[kCGWindowNumber as String] as? Int ?? 0),
              let web = sequence(first: view, next: \.superview).first(where: { $0 is WKWebView }),
              let target = page.model.pages.values.first(where: { $0.webView === web && !$0.preview && !Paths.inDrafts($0.location) }) else { return nil }
        let css = Self.css(inWindow, in: target.webView)
        guard let found = try? await target.run("return __bridge.anchor(x, y)", ["x": css.x, "y": css.y], in: Page.world), Self.onElement(found) else { return nil }
        return (target.location, found)
    }

    // MARK: Pictures

    func take(_ id: String, anchor: JSONValue) {
        let frame = region(for: anchor)
        taking[id] = Task { await still?.value.flatMap { Self.crop($0, to: frame) } }
    }

    static func crop(_ picture: Picture, to frame: CGRect) -> Picture? {
        let scale = CGFloat(picture.image.width) / picture.frame.width
        let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).integral
        return picture.image.cropping(to: pixels).map { Picture(image: $0, frame: frame) }
    }

    func region(for anchor: JSONValue) -> CGRect {
        let (spot, box) = area(of: anchor)
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        if let box { return box.insetBy(dx: -40, dy: -40).intersection(bounds) }
        let room = window(at: global(spot)).map { local(Self.frame(of: $0)).intersection(bounds) } ?? bounds
        let width = min(room.width, 1000), height = min(room.height, 600)
        let x = min(max(spot.x - width / 2, room.minX), room.maxX - width)
        let y = min(max(spot.y - height / 2, room.minY), room.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func shoot(_ frame: CGRect) async -> Picture? {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let fetched = await Self.within(5, { await self.content?.value }) else { return nil }
        guard case .success(let content) = fetched else {
            if Self.current === self { cancel() }
            let alert = NSAlert()
            alert.messageText = "Bridge can't see the screen"
            alert.informativeText = "Allow Bridge in System Settings, Privacy & Security, Screen & System Audio Recording, then try again."
            if !Env.test { alert.runModal() }
            return nil
        }
        guard let display = content.displays.first(where: { $0.displayID == number }) else { return nil }
        let glass = content.windows.filter { $0.windowID == CGWindowID(panel.windowNumber) }
        glassLeftOut = !glass.isEmpty
        let filter = SCContentFilter(display: display, excludingWindows: glass)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = frame
        config.width = Int(frame.width * scale)
        config.height = Int(frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        guard let image = await Self.within(5, { try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }) else { return nil }
        return Picture(image: image, frame: frame)
    }

    final class Once<T: Sendable> {
        var continuation: CheckedContinuation<T?, Never>?
        func finish(_ value: T?) { continuation?.resume(returning: value); continuation = nil }
    }

    static func within<T: Sendable>(_ seconds: Double, _ work: @escaping () async -> T?) async -> T? {
        let once = Once<T>()
        return await withCheckedContinuation { continuation in
            once.continuation = continuation
            Task { once.finish(await work()) }
            Task { try? await Task.sleep(for: .seconds(seconds)); once.finish(nil) }
        }
    }

    // MARK: Sending

    func send(to session: String?) {
        guard !notes.isEmpty else { return }
        end(session.map { .send($0) } ?? .draft)
    }

    func cancel() { end(.cancel) }

    func end(_ outcome: Outcome) {
        Self.current = nil
        let panel = panel
        page.call("__bridge.leave()")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            Task { @MainActor in
                if outcome != .draft, !self.veiled.isEmpty { NSApp.hide(nil) }
                for window in self.veiled { window.alphaValue = 1 }
                for task in self.describing { await task.value }
                self.onFinish(self, outcome)
            }
        })
        if outcome != .draft { previous?.activate() }
    }

    // MARK: Output

    func picture(of index: Int) -> (data: Data, width: CGFloat)? {
        let note = notes[index]
        guard let picture = pictures[note.id] else { return nil }
        let image = picture.image, frame = picture.frame
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: CGFloat(image.width) / frame.width, y: -CGFloat(image.height) / frame.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: image, size: frame.size).draw(in: CGRect(origin: .zero, size: frame.size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let (spot, box) = area(of: note.anchor)
        FreezeView.draw(number: index + 1, at: CGPoint(x: spot.x - frame.minX, y: spot.y - frame.minY), box: box?.offsetBy(dx: -frame.minX, dy: -frame.minY))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]).map { ($0, frame.width) }
    }
}

final class FreezeView: NSView {
    weak var freeze: Freeze?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = freeze?.highlight else { return }
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4)
        Freeze.colour.withAlphaComponent(0.08).setFill()
        path.fill()
        Freeze.colour.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    static func draw(number: Int, at spot: CGPoint, box: CGRect?) {
        if let box {
            let area = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            Freeze.colour.setStroke()
            area.lineWidth = 2
            area.stroke()
        }
        let drop = NSBezierPath()
        drop.move(to: CGPoint(x: -11, y: 11))
        drop.line(to: CGPoint(x: -11, y: 0))
        drop.appendArc(withCenter: .zero, radius: 11, startAngle: 180, endAngle: 450)
        drop.close()
        let place = NSAffineTransform()
        place.translateX(by: spot.x, yBy: spot.y - 11 * 2.squareRoot())
        place.rotate(byDegrees: -45)
        drop.transform(using: place as AffineTransform)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        let ring = drop.copy() as! NSBezierPath
        ring.lineWidth = 4
        ring.lineJoinStyle = .round
        NSColor.white.setStroke()
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
        Freeze.colour.setFill()
        drop.fill()
        let centre = CGPoint(x: spot.x, y: spot.y - 11 * 2.squareRoot())
        let text = NSAttributedString(string: "\(number)", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2))
    }
}
