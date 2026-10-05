import AppKit
import BridgeCore

/// The left column: the two smart scopes, then the projects with their waiting
/// counts, and the update row at its foot.
final class ProjectsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum Row: Equatable { case scope(Scope), heading }

    let model: Model
    let table = NSTableView()
    let update = UpdateRow()
    let pileup = UpdateRow(symbol: "hourglass", tip: "Agent processes waiting for an answer; click to list them")
    var rows: [Row] = []
    var onSelect: (Scope) -> Void = { _ in }
    var onRelaunch: (() -> Void)?
    private var reloading = false

    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.additionalSafeAreaInsets = NSEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowSizeStyle = .custom
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        table.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        update.isHidden = true
        update.onPress = { [weak self] in self?.onRelaunch?() }
        pileup.isHidden = true
        pileup.onPress = { [weak self] in self?.listWaiters() }
        let stack = NSStackView(views: [scroll, pileup, update])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        view = stack
    }

    func reload() {
        reloading = true
        defer { reloading = false }
        rows = [.scope(.waiting), .scope(.all)]
        let projects = model.listing.projects
        if !projects.isEmpty { rows.append(.heading); rows += projects.map { .scope(.project($0)) } }
        table.reloadData()
        if let i = rows.firstIndex(of: .scope(model.scope)) { table.selectRowIndexes([i], byExtendingSelection: false) }
    }

    func showUpdate(_ text: String?) {
        update.isHidden = text == nil
        if let text { update.text = text }
        fitFoot()
    }

    func showPileup(_ text: String?) {
        pileup.isHidden = text == nil
        if let text { pileup.text = text }
        fitFoot()
    }

    private func fitFoot() {
        (view as? NSStackView)?.edgeInsets.bottom = update.isHidden && pileup.isHidden ? 0 : 12
    }

    func listWaiters() {
        let menu = NSMenu()
        let now = Date()
        for w in model.waiters {
            let project = model.listing.bridges.first { $0.session == w.session }?.projectName ?? w.session.prefix(8).description
            let item = menu.addItem(withTitle: "\(project) · \(w.kind) · \(SidebarController.ago(w.started, from: now)) · \(w.megabytes) MB", action: nil, keyEquivalent: "")
            item.toolTip = "pid \(w.pid)"
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 10, y: pileup.bounds.maxY), in: pileup)
    }

    func pileupGeometry() -> [String: JSONValue] {
        guard !pileup.isHidden, let win = pileup.window else { return [:] }
        view.layoutSubtreeIfNeeded()
        let f = pileup.convert(pileup.bounds, to: nil)
        return ["top": .number(Double(win.frame.height - f.maxY)), "height": .number(Double(f.height)), "x": .number(Double(f.minX)), "width": .number(Double(f.width)),
                "text": .string(pileup.text)]
    }

    /// For the harness: the row's frame in window coordinates, its text and the width that text wants.
    func updateGeometry() -> [String: JSONValue] {
        guard !update.isHidden, let win = update.window else { return [:] }
        view.layoutSubtreeIfNeeded()
        let f = update.convert(update.bounds, to: nil)
        return ["top": .number(Double(win.frame.height - f.maxY)), "height": .number(Double(f.height)), "x": .number(Double(f.minX)), "width": .number(Double(f.width)),
                "labelX": .number(Double(update.label.convert(update.label.bounds, to: nil).minX)),
                "textWidth": .number(Double(update.label.intrinsicContentSize.width)), "text": .string(update.text)]
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row] == .heading ? 24 : 28 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row] != .heading }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .heading:
            let cell = tableView.makeView(withIdentifier: .init("heading"), owner: nil) as? NSTableCellView ?? SidebarController.headerCell()
            cell.identifier = .init("heading")
            cell.textField?.stringValue = "Projects"
            return cell
        case .scope(let scope):
            let cell = tableView.makeView(withIdentifier: ScopeCell.id, owner: nil) as? ScopeCell ?? ScopeCell()
            cell.show(scope, model: model)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, table.selectedRow >= 0, case .scope(let scope) = rows[table.selectedRow] else { return }
        onSelect(scope)
    }

    var vibrant: Bool {
        var v: NSView? = view
        while let x = v {
            if let e = x as? NSVisualEffectView, e.material == .sidebar { return true }
            if String(describing: type(of: x)) == "NSGlassEffectView" { return true }
            v = x.superview
        }
        return false
    }

    /// For the harness: the rows as shown, and the selected one.
    func dump() -> [String: JSONValue] {
        ["scope": .string(model.scope.key), "vibrant": .bool(vibrant), "rows": .array(rows.compactMap { row in
            guard case .scope(let s) = row else { return nil }
            let i = rows.firstIndex(of: row)!
            let f = table.convert(table.rect(ofRow: i), to: nil)
            let top = table.window.map { $0.frame.height - f.maxY } ?? 0
            return .object(["key": .string(s.key), "name": .string(ScopeCell.name(of: s)), "count": .number(Double(ScopeCell.count(of: s, model: model))),
                            "top": .number(Double(top)), "height": .number(Double(f.height))])
        })]
    }
}

/// A scope's row: symbol, name, and the count of bridges waiting on the user.
final class ScopeCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("scope")
    let icon = NSImageView()
    let name = PlainLabel(labelWithString: "")
    let count = PlainLabel(labelWithString: "")

    override var allowsVibrancy: Bool { false }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        icon.contentTintColor = .secondaryLabelColor
        for v in [icon, name, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        textField = name
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), icon.widthAnchor.constraint(equalToConstant: 18),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    static func name(of scope: Scope) -> String {
        switch scope { case .waiting: return "Waiting"; case .all: return "All"; case .project(let p): return (p as NSString).lastPathComponent }
    }

    static func count(of scope: Scope, model: Model) -> Int {
        switch scope { case .waiting: return model.waitingCount(); case .all: return model.listing.bridges.filter { !$0.crossed }.count; case .project(let p): return model.waitingCount(in: p) }
    }

    func show(_ scope: Scope, model: Model) {
        let symbol: String
        switch scope { case .waiting: symbol = "tray.full"; case .all: symbol = "tray.2"; case .project: symbol = "folder" }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: Self.name(of: scope))?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        name.stringValue = Self.name(of: scope)
        let n = Self.count(of: scope, model: model)
        count.stringValue = n > 0 ? "\(n)" : ""
    }
}
