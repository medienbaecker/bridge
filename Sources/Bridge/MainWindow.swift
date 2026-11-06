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

    static let newBridge = NSToolbarItem.Identifier("new")
    static let point = NSToolbarItem.Identifier("point")
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

    var split: NSSplitViewController!
    let projects: ProjectsController
    static let bridgesSeparator = NSToolbarItem.Identifier("bridgesTrackingSeparator")
    static let listName = NSToolbarItem.Identifier("listName")
    static let docTitle = NSToolbarItem.Identifier("documentTitle")
    let listHeader = TitleLabel()
    let docTitleView = TitleLabel()

    var toolbarItems: [NSToolbarItem] {
        (window?.toolbar?.items ?? []).filter { [Self.newBridge, Self.point, Self.send].contains($0.itemIdentifier) }
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

    func send(_ page: Page, from window: NSWindow?) {
        guard page.isDraft else { page.send(); return }
        guard let window, let content = window.contentView else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Send to", action: nil, keyEquivalent: "").isEnabled = false
        for recipient in model.agentsByWork() {
            let item = menu.addItem(withTitle: recipient.label, action: #selector(sendTo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [recipient.session, page.location]
        }
        if menu.items.count == 1 { menu.addItem(withTitle: "No Claude sessions running", action: nil, keyEquivalent: "").isEnabled = false }
        let mouse = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let clicked = NSApp.currentEvent.map { $0.type == .leftMouseUp || $0.type == .leftMouseDown } ?? false
        let top = content.convert(NSPoint(x: 0, y: window.contentLayoutRect.maxY), from: nil).y
        let at = clicked && content.bounds.contains(mouse) ? mouse : NSPoint(x: content.bounds.maxX - menu.size.width - 8, y: top)
        menu.popUp(positioning: nil, at: at, in: content)
    }

    @objc func sendTo(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        _ = sendDraft(pair[1], to: pair[0])
    }

    func sendDraft(_ location: String, to session: String) -> Bool {
        guard model.agents[session] != nil, model.listing.entry(location) != nil else { return false }
        let page = model.page(for: location)
        guard page.isDraft, !page.sidecar.blank else { return false }
        model.hand(location, to: session)
        if let cwd = model.agents[session]?.cwd, !cwd.isEmpty {
            let project = Ground.projectRoot(for: cwd)
            model.listing.update(location) { $0.project = project }
            model.changed()
        }
        page.send()
        return true
    }

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
        window?.toolbar?.validateVisibleItems()
        window?.title = page?.title ?? "Bridge"
        listHeader.show(ScopeCell.name(of: model.scope, model: model))
        docTitleView.show(page?.title ?? "")
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // AppKit puts the window title after the sidebar separator, over the list, and
        // handing that identifier to the second divider hangs the toolbar. So the
        // window's title is hidden and the toolbar carries its own two titles.
        [.toggleSidebar, .sidebarTrackingSeparator, Self.listName, .flexibleSpace, Self.newBridge, Self.bridgesSeparator, Self.docTitle, .flexibleSpace, Self.point, .space, Self.send]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.bridgesSeparator { return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split.splitView, dividerIndex: 1) }
        if id == Self.listName {
            let item = NSToolbarItem(itemIdentifier: id)
            listHeader.edge = { [weak self] in self?.sidebar.titleEdge ?? 0 }
            item.view = listHeader
            item.label = "List"
            return item
        }
        if id == Self.docTitle {
            let item = NSToolbarItem(itemIdentifier: id)
            docTitleView.edge = { [weak self] in (self?.content.view.convert(NSPoint.zero, to: nil).x ?? 0) + 21 }
            item.view = docTitleView
            item.label = "Document"
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = true
        item.target = self
        item.action = #selector(toolbarAction(_:))
        switch id {
        case Self.newBridge:
            item.label = Model.untitled; item.toolTip = "Write a bridge to an agent (⌘N)"
            item.image = Self.symbol("square.and.pencil", Model.untitled)
        case Self.point:
            item.label = "Point"; item.toolTip = "Freeze the screen and point at something"
            item.image = Self.symbol("mappin.and.ellipse", "Point")
        case Self.send:
            item.toolTip = "Send your answer"
            Self.styleSend(item, "Send")
        default: return nil
        }
        return item
    }

    /// A bordered item is as wide as its image, and symbols differ in width, so every
    /// toolbar symbol gets one size to keep the capsule the same in every state.
    static func symbol(_ name: String, _ description: String) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) else { return nil }
        // Drawn into a fixed canvas because a symbol image keeps its own width whatever `size` says.
        let canvas = NSSize(width: 24, height: 18)
        let image = NSImage(size: canvas, flipped: false) { rect in
            let size = glyph.size
            let at = NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height)
            glyph.draw(in: at, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    static func sendImage(_ state: String) -> NSImage? {
        state == "Sent" ? symbol("clock", "Sent") : symbol("paperplane", "Send")
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
        case Self.send:
            let state = page?.sendLabel ?? "Send"
            Self.styleSend(item, state)
            item.toolTip = page?.sendToolTip ?? "Send your answer"
            guard let page else { return false }
            if page.isDraft {
                item.toolTip = "Pick the agent it goes to"
                return !page.sidecar.blank
            }
            return page.viewingVersion == nil
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
        case "send": return toolbarItems.first { $0.itemIdentifier.rawValue == command }.map(validateToolbarItem) ?? false
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
        case "cleanup": model.crossEnded(); return true
        case "new": model.newBridge(); return true
        case "settings": (NSApp.delegate as? AppDelegate)?.showSettings(); return true
        case "freeze": (NSApp.delegate as? AppDelegate)?.freeze(fromBridge: argument == "front"); return true
        case "point": (NSApp.delegate as? AppDelegate)?.freeze(); return true
        case "freeze-mark":
            let n = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            guard let freeze = Freeze.current, n.count == 2 || n.count == 4 else { return false }
            let points = stride(from: 0, to: n.count, by: 2).map { [n[$0], n[$0 + 1]] }
            freeze.page.call("""
                const fire = (type, [x, y], buttons) => {
                  const target = document.elementFromPoint(x, y);
                  target.dispatchEvent(new (type === 'click' ? MouseEvent : PointerEvent)(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, buttons }));
                };
                fire('pointerdown', points[0], 1);
                if (points[1]) fire('pointermove', points[1], 1);
                fire('pointerup', points[points.length - 1], 0);
                fire('click', points[points.length - 1], 0);
                """, ["points": points])
            return true
        case "freeze-hover":
            let n = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            guard let freeze = Freeze.current, n.count == 2 else { return false }
            freeze.hover(CGPoint(x: n[0], y: n[1]))
            return true
        case "freeze-note":
            guard let freeze = Freeze.current else { return false }
            freeze.page.call("""
                const box = document.querySelector('.bridge-composer:popover-open textarea');
                box.value = text;
                box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }));
                """, ["text": argument ?? ""])
            return true
        case "freeze-send":
            guard let freeze = Freeze.current, let n = argument.flatMap(Int.init) else { return false }
            freeze.page.call("document.querySelectorAll('.bridge-agents button')[n].click()", ["n": n])
            return true
        case "freeze-cancel":
            guard let freeze = Freeze.current else { return false }
            freeze.page.call("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))")
            return true
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
        case "send":
            guard windows[page.location] == nil else { return false }
            send(page, from: window)
        case "attach":
            guard let argument else { return false }
            page.attach([URL(fileURLWithPath: argument)])
        case "sendto": if !sendDraft(page.location, to: argument ?? "") { return false }
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
        container.subviews.forEach { $0.removeFromSuperview() }
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

class TitleLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false; isBordered = false; drawsBackground = false
        font = .titleBarFont(ofSize: NSFont.systemFontSize)
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
        }
        var view: NSView? = self
        while let ancestor = view {
            ancestor.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(align), name: NSView.frameDidChangeNotification, object: ancestor)
            view = ancestor.superview
        }
        NotificationCenter.default.addObserver(self, selector: #selector(align), name: NSWindow.didResizeNotification, object: window)
        keyChanged()
        align()
    }
    @objc private func keyChanged() { textColor = window?.isKeyWindow == true ? .labelColor : .secondaryLabelColor }

    var edge: (() -> CGFloat)?
    @objc private func align() {
        guard let edge, window != nil else { return }
        let indent = (edge() - convert(NSPoint.zero, to: nil).x).rounded()
        if indent >= 0, indent != self.indent { self.indent = indent }
    }

    var indent: CGFloat = 0 { didSet { show(stringValue) } }
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
