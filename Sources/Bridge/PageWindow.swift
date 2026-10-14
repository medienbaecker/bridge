import AppKit
import BridgeCore

final class PageWindow: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let page: Page
    let content = ContentController()
    let notes = NotesController()
    let notesPopover = NSPopover()
    var onClose: () -> Void = {}

    init(page: Page) {
        self.page = page
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "Bridge.page"
        window.minSize = NSSize(width: 480, height: 300)
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
        window.contentViewController = content
        window.setContentSize(NSSize(width: 760, height: 720))
        window.cascadeTopLeft(from: NSApp.keyWindow.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? .zero)

        let toolbar = NSToolbar(identifier: "Bridge.page")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        notes.page = page
        notesPopover.contentViewController = notes
        notesPopover.behavior = .transient
        notes.onSelect = { [weak self] id in
            self?.notesPopover.performClose(nil)
            self?.page.reveal(id)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.show(page: page)
        window?.title = page.title
        window?.subtitle = page.bannerText ?? ""
        if notesPopover.isShown { notes.reload(); notesPopover.contentSize = notes.fittingSize }
        window?.toolbar?.validateVisibleItems()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, MainWindow.point, MainWindow.notesId, MainWindow.send]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = true
        item.target = self
        item.action = #selector(toolbarAction(_:))
        switch id {
        case MainWindow.point: item.label = "Point"; item.image = MainWindow.pointImage(on: false)
        case MainWindow.notesId: item.label = "Notes"; item.image = MainWindow.symbol("text.bubble", "Notes")
        case MainWindow.send: item.label = "Send"; item.image = MainWindow.sendImage("Send")
        default: return nil
        }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case MainWindow.point:
            item.image = MainWindow.pointImage(on: page.pointing)
            return page.viewingVersion == nil && page.kind != .pdf
        case MainWindow.notesId: return !page.sidecar.comments.isEmpty
        case MainWindow.send:
            item.label = page.sendLabel
            item.image = MainWindow.sendImage(page.sendLabel)
            item.toolTip = page.sendToolTip
            return page.viewingVersion == nil
        default: return true
        }
    }

    @objc func toolbarAction(_ sender: NSToolbarItem) { perform(sender.itemIdentifier.rawValue) }

    @objc func menuCommand(_ sender: NSMenuItem) { perform(sender.representedObject as? String ?? "") }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.representedObject as? String {
        case "point": return page.viewingVersion == nil && page.kind != .pdf
        case "send": return page.viewingVersion == nil
        case "reveal": return page.kind != .url
        case "zoom-in", "zoom-out", "zoom-reset": return true
        case "previous": return (page.viewingVersion ?? page.sidecar.version) > 1
        case "next": return page.viewingVersion != nil
        default: return item.representedObject == nil
        }
    }

    func perform(_ command: String) {
        switch command {
        case "point": page.setPointing(!page.pointing)
        case "send": page.send()
        case "notes":
            if notesPopover.isShown { notesPopover.performClose(nil); break }
            guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == MainWindow.notesId }) else { break }
            notes.reload()
            notesPopover.contentSize = notes.fittingSize
            notesPopover.show(relativeTo: item)
        case "zoom-in": page.zoom = min(3, page.zoom + 0.1)
        case "zoom-out": page.zoom = max(0.5, page.zoom - 0.1)
        case "zoom-reset": page.zoom = 1
        case "reveal": if page.kind != .url { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: page.location)]) }
        case "previous": page.showVersion((page.viewingVersion ?? page.sidecar.version) - 1)
        case "next": page.showVersion((page.viewingVersion ?? page.sidecar.version) + 1)
        default: return
        }
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        content.show(page: nil)
        onClose()
    }
}
