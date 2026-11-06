import AppKit
import BridgeCore

final class PageWindow: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let page: Page
    let content = ContentController()
    var onClose: () -> Void = {}

    init(page: Page, near main: NSWindow?) {
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
        window.cascadeTopLeft(from: (NSApp.keyWindow ?? main).map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? .zero)

        let toolbar = NSToolbar(identifier: "Bridge.page")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.show(page: page)
        window?.title = page.title
        window?.subtitle = page.bannerText ?? ""
        window?.toolbar?.validateVisibleItems()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, MainWindow.point, .space, MainWindow.send]
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
        case MainWindow.point: item.label = "Point"; item.image = MainWindow.symbol("mappin.and.ellipse", "Point")
        case MainWindow.send: MainWindow.styleSend(item, "Send")
        default: return nil
        }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case MainWindow.send:
            MainWindow.styleSend(item, page.sendLabel)
            item.toolTip = page.sendToolTip
            return page.viewingVersion == nil
        default: return true
        }
    }

    @objc func toolbarAction(_ sender: NSToolbarItem) { perform(sender.itemIdentifier.rawValue) }

    @objc func menuCommand(_ sender: NSMenuItem) { perform(sender.representedObject as? String ?? "") }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.representedObject as? String {
        case "send": return page.viewingVersion == nil && !(page.isDraft && page.sidecar.blank)
        case "reveal": return page.kind != .url
        case "point", "zoom-in", "zoom-out", "zoom-reset": return true
        case "previous": return (page.viewingVersion ?? page.sidecar.version) > 1
        case "next": return page.viewingVersion != nil
        default: return item.representedObject == nil
        }
    }

    func perform(_ command: String) {
        switch command {
        case "point": (NSApp.delegate as? AppDelegate)?.freeze()
        case "send": (NSApp.delegate as? AppDelegate)?.window.send(page, from: window)
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
