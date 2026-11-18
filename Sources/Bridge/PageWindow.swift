import AppKit
import BridgeCore

final class PageWindow: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let page: Page
    let content = ContentController()
    var onClose: () -> Void = {}

    init(page: Page) {
        self.page = page
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 480, height: 300)
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
        window.contentViewController = content
        window.setContentSize(NSSize(width: 760, height: 720))

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
        case MainWindow.send: return MainWindow.validateSend(item, for: page)
        case MainWindow.point: MainWindow.stylePoint(item, for: page); return true
        default: return true
        }
    }

    @objc func toolbarAction(_ sender: NSToolbarItem) { perform(sender.itemIdentifier.rawValue) }

    @objc func menuCommand(_ sender: NSMenuItem) { perform(sender.representedObject as? String ?? "") }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let command = item.representedObject as? String else { return true }
        let entry = page.model.listing.entry(page.location)
        switch command {
        case "send": return MainWindow.canSend(page)
        case "point": return true
        case "cross": return entry.map { !$0.crossed } ?? false
        case "uncross": return entry?.crossed ?? false
        case "remove":
            item.title = Paths.owned(page.location) ? "Move to Trash" : "Remove from List"
            return entry != nil
        default: return page.canPerform(command) ?? (NSApp.delegate as? AppDelegate)?.validateMenuItem(item) ?? false
        }
    }

    func perform(_ command: String) {
        let app = NSApp.delegate as? AppDelegate
        switch command {
        case "point": MainWindow.point(page)
        case "send": app?.window.send(page, from: window)
        case "cross": app?.window.cross([page.location], true)
        case "uncross": app?.window.cross([page.location], false)
        case "remove": app?.window.remove([page.location])
        default: guard page.perform(command) else { app?.perform(menu: command); return }
        }
        refresh()
    }

    func windowDidBecomeKey(_ notification: Notification) { page.countCommits() }

    func windowWillClose(_ notification: Notification) {
        content.show(page: nil)
        onClose()
    }
}
