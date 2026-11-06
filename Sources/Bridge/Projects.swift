import AppKit
import BridgeCore

/// The left column: the two smart scopes, then the projects with their waiting
/// counts, and the update row at its foot.
final class ProjectsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum Row: Equatable { case scope(Scope), gap, more(Int) }


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
        scroll.automaticallyAdjustsContentInsets = false
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

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scroll = table.enclosingScrollView else { return }
        let top = view.safeAreaInsets.top + 16
        if scroll.contentInsets.top != top { scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0) }
    }

    func reload() {
        reloading = true
        defer { reloading = false }
        let drafts = Paths.drafts.path
        rows = [.scope(.waiting), .scope(.all), .gap]
        if model.listing.projects.contains(drafts) { rows += [.scope(.project(drafts)), .gap] }
        let mine = model.listing.projects.filter { $0 != drafts }
        let active = mine.filter { p in model.listing.bridges.contains { $0.project == p && !$0.crossed } }
        rows += active.map { .scope(.project($0)) }
        let rest = mine.filter { !active.contains($0) }
        if !rest.isEmpty {
            if model.showAllProjects { rows += rest.map { .scope(.project($0)) }; rows.append(.more(0)) } else { rows.append(.more(rest.count)) }
        }
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

    var optimalWidth: CGFloat {
        var widest: CGFloat = 0
        for row in 0..<table.numberOfRows {
            guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) else { continue }
            widest = max(widest, cell.fittingSize.width + view.frame.width - cell.frame.width)
        }
        return widest.rounded(.up)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if rows[row] == .gap { return 14 }
        return 28
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch rows[row] {
        case .scope: return true
        case .more:
            model.showAllProjects.toggle()
            DispatchQueue.main.async { self.reload() }
            return false
        default: return false
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .gap:
            return NSView()
        case .more(let n):
            let cell = tableView.makeView(withIdentifier: ScopeCell.id, owner: nil) as? ScopeCell ?? ScopeCell()
            cell.more(n == 0 ? "Fewer projects" : "\(n) more project\(n == 1 ? "" : "s")…")
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
    func key(_ row: Row) -> String? {
        switch row {
        case .scope(let s): return s.key
        case .more: return "more"
        case .gap: return nil
        }
    }

    func dump() -> [String: JSONValue] {
        return ["scope": .string(model.scope.key), "vibrant": .bool(vibrant), "rows": .array(rows.compactMap { row in
            guard case .scope(let s) = row else { return nil }
            let i = rows.firstIndex(of: row)!
            let f = table.convert(table.rect(ofRow: i), to: nil)
            let top = table.window.map { $0.frame.height - f.maxY } ?? 0
            return .object(["key": .string(s.key), "name": .string(ScopeCell.name(of: s, model: model)), "count": .number(Double(ScopeCell.count(of: s, model: model))), "countShown": .bool((table.view(atColumn: 0, row: i, makeIfNecessary: false) as? ScopeCell)?.count.stringValue.isEmpty == false),
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

    static func name(of scope: Scope, model: Model) -> String {
        switch scope {
        case .waiting: return "Waiting"
        case .all: return "All"
        case .project(let p): return p == Paths.drafts.path ? "Drafts" : (p as NSString).lastPathComponent
        }
    }

    static func count(of scope: Scope, model: Model) -> Int {
        switch scope {
        case .waiting: return model.waitingCount()
        case .all: return model.listing.bridges.filter { !$0.crossed }.count
        case .project(let p): return model.waitingCount(in: p)
        }
    }

    func more(_ text: String) {
        icon.image = nil
        name.stringValue = text
        name.textColor = .secondaryLabelColor
        count.stringValue = ""
    }

    func show(_ scope: Scope, model: Model) {
        toolTip = nil
        name.textColor = .labelColor
        let symbol: String
        icon.contentTintColor = .secondaryLabelColor
        switch scope {
        case .waiting: symbol = "tray.full"
        case .all: symbol = "tray.2"
        case .project(let p): symbol = p == Paths.drafts.path ? "doc" : "folder"
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: Self.name(of: scope, model: model))?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        name.stringValue = Self.name(of: scope, model: model)
        let n = Self.count(of: scope, model: model)
        if case .project = scope { count.stringValue = "" } else { count.stringValue = n > 0 ? "\(n)" : "" }
    }
}
