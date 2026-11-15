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
        guard let command = item.representedObject as? String else { return true }
        let entry = page.model.listing.entry(page.location)
        switch command {
        case "send": return page.viewingVersion == nil && !(page.isDraft && page.sidecar.blank)
        case "point", "new", "crossed": return true
        case "cross": return entry.map { !$0.crossed } ?? false
        case "uncross": return entry?.crossed ?? false
        case "remove":
            item.title = Paths.owned(page.location) ? "Move to Trash" : "Remove from List"
            return entry != nil
        default: return page.canPerform(command) ?? false
        }
    }

    func perform(_ command: String) {
        let app = NSApp.delegate as? AppDelegate
        switch command {
        case "point": app?.freeze()
        case "send": app?.window.send(page, from: window)
        case "new", "crossed": _ = app?.window.perform(command: command, argument: nil); app?.window.showWindow(nil)
        case "cross": page.model.cross(page.location, true)
        case "uncross": page.model.cross(page.location, false)
        case "remove": page.model.trash(page.location)
        default: guard page.perform(command) else { return }
        }
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        content.show(page: nil)
        onClose()
    }
}
