import AppKit
import WebKit
import BridgeCore

final class SplitController: NSSplitViewController {
    var optimalWidth: () -> CGFloat = { 0 }
    private var snapped = false

    override func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let position = proposedPosition
        guard dividerIndex == 0, let side = splitViewItems.first, !side.isCollapsed else { return position }
        let target = optimalWidth()
        guard target >= side.minimumThickness, target <= side.maximumThickness, abs(position - target) < 10 else {
            snapped = false
            return position
        }
        if !snapped, [.leftMouseDown, .leftMouseDragged].contains(NSApp.currentEvent?.type) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            snapped = true
        }
        return target
    }
}

final class MainWindow: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let model: Model
    let sidebar: SidebarController
    let content = ContentController()
    let notes = NotesController()
    let notesPopover = NSPopover()

    static let point = NSToolbarItem.Identifier("point")
    static let notesId = NSToolbarItem.Identifier("notes")
    static let send = NSToolbarItem.Identifier("send")

    init(model: Model) {
        self.model = model
        self.sidebar = SidebarController(model: model)
        self.projects = ProjectsController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Bridge"
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        // In test mode the frame is never autosaved: one saved off the screen's edge
        // would hand the harness frames cut at the display.
        if !Env.test { window.setFrameAutosaveName("Bridge.main") }
        window.center()
        // In test mode the window is centred on BRIDGE_SCREEN, a virtual screen out of the
        // user's way, or else on the largest screen, whole: the key window's screen may be
        // smaller or 1x, and the built-in one is too short.
        let named = NSScreen.screens.first { $0.localizedName == ProcessInfo.processInfo.environment["BRIDGE_SCREEN"] }
        if Env.test, let screen = named ?? NSScreen.screens.max(by: { $0.visibleFrame.width * $0.visibleFrame.height < $1.visibleFrame.width * $1.visibleFrame.height }) {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.midX - window.frame.width / 2, y: f.midY - window.frame.height / 2))
        }
        super.init(window: window)
        window.delegate = self

        let split = SplitController()
        split.splitView.dividerStyle = .thin
        split.optimalWidth = { [weak projects] in projects?.optimalWidth ?? 0 }
        self.split = split
        let side = NSSplitViewItem(sidebarWithViewController: projects)
        side.minimumThickness = 180
        side.maximumThickness = 280
        side.canCollapse = true
        side.holdingPriority = NSLayoutConstraint.Priority(260)
        let list = NSSplitViewItem(contentListWithViewController: sidebar)
        list.minimumThickness = 220
        list.maximumThickness = 400
        list.canCollapse = false
        list.holdingPriority = NSLayoutConstraint.Priority(255)
        // On macOS 26 the projects sidebar floats over this list, and AppKit shifted
        // the rows right without narrowing them, so the selection pill ran off the
        // edge. The list insets its own content instead (SidebarController.viewDidLayout).
        list.automaticallyAdjustsSafeAreaInsets = false
        list.titlebarSeparatorStyle = .line
        let page = NSSplitViewItem(viewController: content)
        page.minimumThickness = 480
        page.holdingPriority = NSLayoutConstraint.Priority(240)
        split.addSplitViewItem(side)
        split.addSplitViewItem(list)
        split.addSplitViewItem(page)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1180, height: 720))
        window.minSize = NSSize(width: 880, height: 400)
        split.splitView.setPosition(200, ofDividerAt: 0)
        split.splitView.setPosition(200 + 260, ofDividerAt: 1)

        let toolbar = NSToolbar(identifier: "Bridge.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        notesPopover.contentViewController = notes
        notesPopover.behavior = .transient
        notesPopover.contentSize = NSSize(width: 360, height: 240)
        notes.onSelect = { [weak self] id in
            self?.notesPopover.performClose(nil)
            self?.model.selectedPage?.reveal(id)
        }

        projects.onRelaunch = { (NSApp.delegate as? AppDelegate)?.relaunch() }
        projects.onSelect = { [weak self] scope in
            guard let self, model.scope != scope else { return }
            model.scope = scope
            model.settleSelection()
            refresh()
        }
        sidebar.onRowCommand = { [weak self] command, targets in
            guard let self else { return }
            switch command {
            case "cross": for t in targets { model.cross(t, true) }
            case "uncross": for t in targets { model.cross(t, false) }
            case "remove": for t in targets { model.remove(t) }
            case "reveal": if let t = targets.first { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t)]) }
            case "window": for t in targets { openWindow(t) }
            default: break
            }
            refresh()
        }
        sidebar.onSelect = { [weak self] loc in
            guard let self, model.selected != loc else { return }
            model.selected = loc
            if let loc { model.markRead(loc) }
            refresh()
        }
        sidebar.onDragOut = { [weak self] locations, topLeft in
            for (i, location) in locations.enumerated() {
                self?.openWindow(location, at: NSPoint(x: topLeft.x + CGFloat(i) * 24, y: topLeft.y - CGFloat(i) * 24))
            }
        }
        sidebar.onDragBegan = { [weak self] locations in self?.takeSnapshots(locations) }
        sidebar.windowPreview = { [weak self] location in self?.windowPreview(location) }
        sidebar.hasSnapshot = { [weak self] location in self?.snapshots[location] != nil }
        model.onChange = { [weak self] in self?.refresh() }
    }

    required init?(coder: NSCoder) { fatalError() }

    var pointShownOn = false
    var split: NSSplitViewController!
    let projects: ProjectsController
    static let bridgesSeparator = NSToolbarItem.Identifier("bridgesTrackingSeparator")
    static let listName = NSToolbarItem.Identifier("listName")
    static let docTitle = NSToolbarItem.Identifier("documentTitle")
    let listHeader = TitleLabel()
    let docTitleView = TitleLabel()

    static func pointImage(on: Bool) -> NSImage? {
        symbol("mappin.and.ellipse", on ? "Pointing" : "Point", tint: on ? .controlAccentColor : nil)
    }

    var toolbarItems: [NSToolbarItem] {
        (window?.toolbar?.items ?? []).filter { [Self.point, Self.notesId, Self.send].contains($0.itemIdentifier) }
    }

    var bannerText: String? { model.selectedPage?.bannerText }

    var windows: [String: PageWindow] = [:]
    var snapshots: [String: NSImage] = [:]

    func takeSnapshots(_ locations: [String]) {
        for location in locations {
            let web = model.page(for: location).webView
            guard web.window != nil, web.bounds.width > 0 else { continue }
            web.takeSnapshot(with: nil) { [weak self] image, _ in self?.snapshots[location] = image }
        }
    }

    func windowPreview(_ location: String) -> NSImage? {
        let title = model.listing.entry(location)?.title ?? (location as NSString).lastPathComponent
        let snapshot = snapshots[location]
        let width: CGFloat = 300, bar: CGFloat = 26
        let aspect = snapshot.map { min(max($0.size.height / max($0.size.width, 1), 0.5), 1.1) } ?? 0.75
        let body = NSSize(width: width, height: (width * aspect).rounded() + bar)
        let pad = SidebarController.previewPadding
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        return NSImage(size: NSSize(width: body.width + pad * 2, height: body.height + pad * 2), flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let frame = NSRect(x: pad, y: pad, width: body.width, height: body.height)
                let shape = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = 14
                shadow.shadowOffset = NSSize(width: 0, height: -5)
                shadow.set()
                NSColor.windowBackgroundColor.setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                NSColor.underPageBackgroundColor.setFill()
                NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: bar).fill()
                let pageRect = NSRect(x: frame.minX, y: frame.minY + bar, width: frame.width, height: frame.height - bar)
                NSColor.textBackgroundColor.setFill()
                pageRect.fill()
                if let snapshot {
                    let scale = pageRect.width / snapshot.size.width
                    let source = NSRect(x: 0, y: max(snapshot.size.height - pageRect.height / scale, 0), width: snapshot.size.width, height: min(pageRect.height / scale, snapshot.size.height))
                    snapshot.draw(in: NSRect(x: pageRect.minX, y: pageRect.minY, width: pageRect.width, height: source.height * scale), from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                NSGraphicsContext.restoreGraphicsState()
                for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                    color.setFill()
                    NSBezierPath(ovalIn: NSRect(x: frame.minX + 10 + CGFloat(i) * 18, y: frame.minY + bar / 2 - 6, width: 12, height: 12)).fill()
                }
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineBreakMode = .byTruncatingTail
                (title as NSString).draw(in: NSRect(x: frame.minX + 64, y: frame.minY + bar / 2 - 8, width: frame.width - 128, height: 16),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
                NSColor.separatorColor.setStroke()
                shape.lineWidth = 0.5
                shape.stroke()
            }
            return true
        }
    }

    func rememberWindows() {
        Model.remember(windows.map { ["location": $0.key, "frame": NSStringFromRect($0.value.window?.frame ?? .zero)] }, "windows")
    }

    func restoreWindows() {
        for saved in Model.remembered("windows") as? [[String: String]] ?? [] {
            guard let location = saved["location"], model.listing.entry(location) != nil else { continue }
            openWindow(location, frame: saved["frame"].map(NSRectFromString))
        }
    }

    func openWindow(_ location: String, at topLeft: NSPoint? = nil, frame: NSRect? = nil) {
        if let open = windows[location] {
            if let topLeft { open.window?.setFrameTopLeftPoint(topLeft) }
            open.showWindow(nil)
            return
        }
        let page = model.page(for: location)
        let pageWindow = PageWindow(page: page, near: window)
        pageWindow.onClose = { [weak self] in
            self?.windows[location] = nil
            self?.refresh()
        }
        windows[location] = pageWindow
        model.markRead(location)
        refresh()
        pageWindow.refresh()
        if let frame { pageWindow.window?.setFrame(frame, display: false) }
        pageWindow.showWindow(nil)
        if let topLeft { pageWindow.window?.setFrameTopLeftPoint(topLeft) }
    }

    var shownPage: Page? { model.selectedPage.flatMap { windows[$0.location] == nil ? $0 : nil } }

    func refresh() {
        projects.reload()
        sidebar.reload()
        for (location, pageWindow) in windows where model.listing.entry(location) == nil { pageWindow.close() }
        let page = model.selectedPage
        let away = page.flatMap { windows[$0.location] }
        content.show(page: away == nil ? page : nil)
        content.showAway(away.map { w in { w.showWindow(nil) } })
        for w in windows.values { w.refresh() }
        window?.subtitle = page?.bannerText ?? ""
        notes.page = page
        if notesPopover.isShown { notes.reload(); notesPopover.contentSize = notes.fittingSize }
        window?.toolbar?.validateVisibleItems()
        window?.title = page?.title ?? "Bridge"
        listHeader.show(ScopeCell.name(of: model.scope))
        docTitleView.show(page?.title ?? "")
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // AppKit puts the window title after the sidebar separator, over the list, and
        // handing that identifier to the second divider hangs the toolbar. So the
        // window's title is hidden and the toolbar carries its own two titles.
        [.toggleSidebar, .sidebarTrackingSeparator, Self.listName, Self.bridgesSeparator, Self.docTitle, .flexibleSpace, Self.point, Self.notesId, .space, Self.send]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.bridgesSeparator { return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split.splitView, dividerIndex: 1) }
        if id == Self.listName {
            let item = NSToolbarItem(itemIdentifier: id)
            listHeader.indent = 8.5
            item.view = listHeader
            item.label = "List"
            return item
        }
        if id == Self.docTitle {
            let item = NSToolbarItem(itemIdentifier: id)
            docTitleView.indent = listHeader.indent
            item.view = docTitleView
            item.label = "Document"
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = true
        item.target = self
        item.action = #selector(toolbarAction(_:))
        switch id {
        case Self.point:
            item.label = "Point"; item.toolTip = "Point at something and leave a note"
            item.image = Self.pointImage(on: false)
        case Self.notesId:
            item.label = "Notes"; item.toolTip = "Notes on this page"
            item.image = Self.symbol("text.bubble", "Notes")
        case Self.send:
            item.toolTip = "Send your answer"
            Self.styleSend(item, "Send")
        default: return nil
        }
        return item
    }

    /// A bordered item is as wide as its image, and symbols differ in width, so every
    /// toolbar symbol gets one size to keep the capsule the same in every state.
    static func symbol(_ name: String, _ description: String, tint: NSColor? = nil) -> NSImage? {
        guard var glyph = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) else { return nil }
        if let tint { glyph = glyph.withSymbolConfiguration(.init(paletteColors: [tint])) ?? glyph }
        // Drawn into a fixed canvas because a symbol image keeps its own width whatever `size` says.
        let canvas = NSSize(width: 24, height: 18)
        let image = NSImage(size: canvas, flipped: false) { rect in
            let size = glyph.size
            let at = NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height)
            glyph.draw(in: at, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = description
        return image
    }

    static func sendImage(_ state: String) -> NSImage? {
        switch state {
        case "Sent": return symbol("clock", "Sent")
        case "Send again": return symbol("paperplane.fill", "Send again")
        default: return symbol("paperplane", "Send")
        }
    }

    static func styleSend(_ item: NSToolbarItem, _ state: String) {
        item.label = state
        item.title = state == "Sent" ? "Sent" : "Send"
        item.image = sendImage(state)
        item.style = state == "Sent" ? .plain : .prominent
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let page = shownPage
        switch item.itemIdentifier {
        case Self.point:
            let on = page?.pointing ?? false
            item.image = Self.pointImage(on: on)
            pointShownOn = on
            return page != nil && page?.viewingVersion == nil && page?.kind != .pdf
        case Self.notesId: return page.map { !$0.sidecar.comments.isEmpty } ?? false
        case Self.send:
            let state = page?.sendLabel ?? "Send"
            Self.styleSend(item, state)
            item.toolTip = page?.sendToolTip ?? "Send your answer"
            return page.map { $0.viewingVersion == nil } ?? false
        default: return true
        }
    }

    @objc func toolbarAction(_ sender: NSToolbarItem) {
        _ = perform(command: sender.itemIdentifier.rawValue, argument: nil)
    }

    @objc func menuCommand(_ sender: NSMenuItem) {
        _ = perform(command: sender.representedObject as? String ?? "", argument: nil)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let command = item.representedObject as? String else { return true }
        let page = model.selectedPage
        let entry = model.selected.flatMap { model.listing.entry($0) }
        switch command {
        case "cross": return entry.map { !$0.crossed } ?? false
        case "uncross": return entry?.crossed ?? false
        case "remove": return entry != nil
        case "point", "send": return toolbarItems.first { $0.itemIdentifier.rawValue == command }.map(validateToolbarItem) ?? false
        case "reveal": return page.map { $0.kind != .url } ?? false
        case "zoom-in", "zoom-out", "zoom-reset": return shownPage != nil
        case "window": return page != nil
        case "previous": return page.map { ($0.viewingVersion ?? $0.sidecar.version) > 1 } ?? false
        case "next": return page?.viewingVersion != nil
        default: return true
        }
    }

    func perform(command: String, argument: String?) -> Bool {
        if command == "relaunch" { (NSApp.delegate as? AppDelegate)?.relaunch(); return true }
        switch command {
        case "select": return select(argument)
        case "resize":
            let parts = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            guard parts.count == 2, let w = window else { return false }
            var f = w.frame
            f.size = NSSize(width: parts[0], height: parts[1])
            w.setFrame(f, display: true)
            w.layoutIfNeeded()
            return true
        case "sidebarwidth":
            guard let w = argument.flatMap(Double.init) else { return false }
            split.splitViewItems[0].minimumThickness = w; split.splitViewItems[0].maximumThickness = w; window?.layoutIfNeeded()
            return true
        case "dragout":
            let parts = (argument ?? "").split(separator: " ").map(String.init)
            guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return false }
            sidebar.onDragOut([parts[0]], NSPoint(x: x, y: y)); return true
        case "closewindow": guard let w = argument.flatMap({ windows[$0] }) else { return false }; w.close(); return true
        case "project": model.scope = Scope(key: argument ?? "waiting"); model.settleSelection(); refresh(); return true
        case "crossed": model.showCrossed = argument == nil ? !model.showCrossed : argument == "show"; model.settleSelection(); refresh(); return true
        default: break
        }
        guard let page = model.selectedPage else { return false }
        switch command {
        case "window": openWindow(page.location); return true
        case "point": guard windows[page.location] == nil else { return false }; page.setPointing(!page.pointing)
        case "send": guard windows[page.location] == nil else { return false }; page.send()
        case "notes": if !toggleNotes() { return false }
        case "cross": for t in targets(page) { model.cross(t, true) }
        case "uncross": for t in targets(page) { model.cross(t, false) }
        case "remove": for t in targets(page) { model.remove(t) }
        case "previous": page.showVersion((page.viewingVersion ?? page.sidecar.version) - 1)
        case "next": page.showVersion((page.viewingVersion ?? page.sidecar.version) + 1)
        case "select-add":
            guard let argument else { return false }
            let row = sidebar.row(for: argument)
            guard row >= 0 else { return false }
            sidebar.outline.selectRowIndexes([row], byExtendingSelection: true)
        case "rowmenu-at":
            // Goes through the same override AppKit calls for a real right-click.
            guard let argument else { return false }
            let outline = sidebar.outline
            var point: NSPoint
            if argument == "empty" {
                point = outline.convert(NSPoint(x: 20, y: outline.bounds.height - 4), to: nil)
            } else {
                let row = sidebar.row(for: argument)
                guard row >= 0 else { return false }
                let rect = outline.rect(ofRow: row)
                point = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            }
            guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return false }
            let menu = outline.menu(for: event)
            rowMenuTitles = (menu?.items ?? []).filter { !$0.isSeparatorItem }.map { $0.title }
            rowMenuTargets = (menu?.items.first?.representedObject as? [Any])?.dropFirst().first as? [String] ?? []
        case "rowmenu":
            guard let argument else { return false }
            let row = sidebar.row(for: argument)
            guard row >= 0, let menu = sidebar.contextMenu(forRow: row) else { return false }
            rowMenuTitles = menu.items.filter { !$0.isSeparatorItem }.map { $0.title + ($0.keyEquivalent.isEmpty ? "" : " (" + ($0.keyEquivalentModifierMask.contains(.option) ? "⌥" : "") + ($0.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "") + "⌘" + ($0.keyEquivalent == "\u{8}" ? "⌫" : $0.keyEquivalent.uppercased()) + ")") }
        case "close": window?.performClose(nil)
        case "zoom-in": page.zoom = min(3, page.zoom + 0.1)
        case "zoom-out": page.zoom = max(0.5, page.zoom - 0.1)
        case "zoom-reset": page.zoom = 1
        case "reveal": if page.kind != .url { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: page.location)]) }
        case "sidebar": window?.contentViewController.map { ($0 as? NSSplitViewController)?.toggleSidebar(nil) }
        case "dump": print(Snapshot.dump(window!.contentView!.superview!).joined(separator: "\n"))
        case "scrollers": sidebar.outline.enclosingScrollView?.scrollerStyle = argument == "legacy" ? .legacy : .overlay
        case "columns":
            let parts = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            if parts.count == 2 {
                split.splitViewItems[0].minimumThickness = parts[0]; split.splitViewItems[0].maximumThickness = parts[0]
                split.splitViewItems[1].minimumThickness = parts[1]; split.splitViewItems[1].maximumThickness = parts[1]
                window?.layoutIfNeeded()
            }

        case "separator": window?.titlebarSeparatorStyle = argument == "none" ? .none : argument == "line" ? .line : .automatic
        case "front":
            // Only a regular app that LaunchServices activates gets the key window, so this takes focus.
            NSApp.setActivationPolicy(.regular)
            let o = Process(); o.executableURL = URL(fileURLWithPath: "/usr/bin/open"); o.arguments = ["-a", Bundle.main.bundlePath]; try? o.run()
        default: return false
        }
        refresh()
        return true
    }

    var rowMenuTitles: [String] = []
    var rowMenuTargets: [String] = []

    func targets(_ page: Page) -> [String] {
        let selected = sidebar.selectedLocations
        return selected.count > 1 ? selected : [page.location]
    }

    func select(_ location: String?) -> Bool {
        guard let location, let entry = model.listing.entry(location) else { return false }
        if !model.shown().contains(where: { $0.location == location }) { model.scope = .project(entry.project) }
        model.selected = location
        model.markRead(location)
        refresh()
        windows[location]?.showWindow(nil)
        return true
    }

    /// A transient popover does not open on a window that is not key, so the window
    /// is made key first. Returns whether the popover is showing afterwards.
    @discardableResult
    func toggleNotes() -> Bool {
        if notesPopover.isShown { notesPopover.performClose(nil); return true }
        guard let item = toolbarItems.first(where: { $0.itemIdentifier == Self.notesId }) else { return false }
        if window?.isKeyWindow == false { window?.makeKeyAndOrderFront(nil) }
        notes.reload()
        notesPopover.contentSize = notes.fittingSize
        notesPopover.show(relativeTo: item)
        return notesPopover.isShown
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let loc = model.selected { model.markRead(loc) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.selectedPage?.closed()
        return true
    }
}

final class ContentController: NSViewController {
    // The page runs under the titlebar so content scrolling beneath it blurs through
    // the titlebar material, as in Finder. The page's layout viewport is inset by the
    // same height, so nothing hides at scroll zero.
    let container = NSView()
    weak var shown: Page?
    private let away = NSStackView()
    private var bringBack: (() -> Void)?

    func showAway(_ action: (() -> Void)?) {
        bringBack = action
        away.isHidden = action == nil
    }

    @objc private func bringBackClicked() { bringBack?() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)
        let label = NSTextField(labelWithString: "Open in its own window")
        label.textColor = .secondaryLabelColor
        let button = NSButton(title: "Show Window", target: self, action: #selector(bringBackClicked))
        button.bezelStyle = .push
        away.orientation = .vertical
        away.spacing = 10
        away.addArrangedSubview(label)
        away.addArrangedSubview(button)
        away.isHidden = true
        away.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(away)
        NSLayoutConstraint.activate([
            away.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            away.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        inset()
    }

    func inset() {
        guard let web = shown?.webView else { return }
        let insets = NSEdgeInsets(top: view.safeAreaInsets.top, left: 0, bottom: 0, right: 0)
        if web.obscuredContentInsets.top != insets.top { web.obscuredContentInsets = insets }
    }

    func show(page: Page?) {
        guard shown !== page else { return }
        shown?.webView.removeFromSuperview()
        shown = page
        guard let page else { return }
        let web = page.webView
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        inset()
    }
}

final class NotesController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var page: Page?
    var onSelect: (String) -> Void = { _ in }
    let table = NSTableView()
    let empty = NSTextField(labelWithString: "No notes on this page")
    var rows: [Comment] = []
    static let width: CGFloat = 360
    static let rowHeight: CGFloat = 24

    var fittingSize: NSSize {
        NSSize(width: Self.width, height: rows.isEmpty ? 56 : min(CGFloat(rows.count) * Self.rowHeight + 12, 420))
    }

    static func preview(_ text: String, font: NSFont, width: CGFloat) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: attributes).width <= width }
        if fits(flat) { return flat }
        var out = ""
        for word in flat.split(separator: " ") {
            let next = out.isEmpty ? String(word) : out + " " + word
            if !fits(next + "…") { break }
            out = next
        }
        return (out.isEmpty ? String(flat.prefix(12)) : out) + "…"
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // Without this the first row sat on the panel's top edge and the fitting size's
        // 12 pt all lay under the last one.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.addTableColumn(NSTableColumn(identifier: .init("note")))
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        // Opaque and a shade off white so the panel has an edge over a white page: a
        // box border cannot follow the popover's corners, and the popover's own frame
        // draws no edge over white.
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.contentViewMargins = .zero
        box.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.965, alpha: 1)
        }
        box.contentView = scroll
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        scroll.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        view = box
    }



    func reload() {
        rows = page?.sidecar.comments.sorted { ($0.state == "done" ? 1 : 0, $1.at) < ($1.state == "done" ? 1 : 0, $0.at) } ?? []
        empty.isHidden = !rows.isEmpty
        preferredContentSize = fittingSize
        table.reloadData()
    }

    @objc func clicked() {
        guard table.clickedRow >= 0 else { return }
        onSelect(rows[table.clickedRow].id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NoteRow.id, owner: nil) as? NoteRow ?? NoteRow()
        cell.show(rows[row])
        return cell
    }

    /// For the harness: what the rows actually show, not the computed preview.
    var shown: [(text: String, fits: Bool)] {
        (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: false) as? NoteRow }.map { ($0.label.stringValue, $0.fits) }
    }

}

/// The text is cut at a word to the label's real width in `layout()`, so the
/// label never truncates mid-word itself.
final class NoteRow: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("note")
    let dot = NSView()
    let label = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    let glyph = NSImageView()
    var full = ""

    var fits: Bool { (label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width <= label.frame.width + 0.5 }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        count.textColor = .tertiaryLabelColor
        count.alignment = .right
        glyph.image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: "replies")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
        glyph.contentTintColor = .tertiaryLabelColor
        for v in [dot, label, glyph, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        textField = label
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: glyph.leadingAnchor, constant: -8),
            glyph.widthAnchor.constraint(equalToConstant: 12),
            glyph.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -3),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.widthAnchor.constraint(equalToConstant: 14),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ c: Comment) {
        full = c.text.replacingOccurrences(of: "\n", with: " ")
        label.stringValue = full
        label.textColor = c.state == "done" ? .secondaryLabelColor : .labelColor
        dot.layer?.backgroundColor = (c.state == "done" ? NSColor.tertiaryLabelColor : c.state == "working" ? NSColor.systemOrange : NSColor.controlAccentColor).cgColor
        let replies = c.said.filter { $0.kind == "reply" }.count
        count.stringValue = replies > 0 ? "\(replies)" : ""
        glyph.isHidden = replies == 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = label.frame.width
        guard width > 0 else { return }
        let preview = NotesController.preview(full, font: label.font!, width: width)
        if label.stringValue != preview { label.stringValue = preview }
    }
}

class TitleLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false; isBordered = false; drawsBackground = false
        font = .titleBarFont(ofSize: NSFont.systemFontSize)
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
        }
        keyChanged()
    }
    @objc private func keyChanged() { textColor = window?.isKeyWindow == true ? .labelColor : .secondaryLabelColor }

    /// Aligns the text with the list rows' titles (25 pt in) while the toolbar places
    /// the item at about 18. The indent is part of the width, or the toolbar cuts the last letter.
    var indent: CGFloat = 0
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += indent
        return size
    }
    func show(_ text: String) {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.lineBreakMode = .byTruncatingTail
        attributedStringValue = NSAttributedString(string: text, attributes: [.font: font ?? .titleBarFont(ofSize: NSFont.systemFontSize), .paragraphStyle: style])
        invalidateIntrinsicContentSize()
    }
}
