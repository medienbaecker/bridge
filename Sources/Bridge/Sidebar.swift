import AppKit
import BridgeCore

final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        enum Kind { case bridge(BridgeEntry) }
        let kind: Kind
        var children: [Node] = []
        init(_ kind: Kind) { self.kind = kind }
    }

    let model: Model
    let outline = RowMenuOutlineView()
    var outlineWidth: NSLayoutConstraint!

    /// The list's content is inset by the floating projects sidebar and the toolbar.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scroll = outline.enclosingScrollView else { return }
        let insets = NSEdgeInsets(top: view.safeAreaInsets.top + 6, left: view.safeAreaInsets.left, bottom: 0, right: 0)
        if scroll.contentInsets.left != insets.left || scroll.contentInsets.top != insets.top { scroll.contentInsets = insets }
        if outlineWidth.constant != -insets.left { outlineWidth.constant = -insets.left }
    }
    var roots: [Node] = []
    var onSelect: (String?) -> Void = { _ in }
    var onRowCommand: (String, [String]) -> Void = { _, _ in }
    var reloading = false

    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .custom
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 0
        outline.autoresizesOutlineColumn = true
        outline.allowsMultipleSelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }
        outline.backgroundColor = .clear
        scroll.documentView = outline
        // With overlay scrollers the outline comes out 10 pt wider than its clip, and
        // the selection pill runs to the visible edge. Pinned to the clip, it cannot.
        outline.translatesAutoresizingMaskIntoConstraints = false
        outlineWidth = outline.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        outlineWidth.isActive = true
        // Insets are set in viewDidLayout: the automatic ones crowded the top of the list against the titlebar.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // The empty-list label is a sibling of the scroll view: a scroll view tiles its
        // own subviews and drew nothing of a label added to it.
        let host = NSView()
        host.addSubview(scroll)
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: host.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: host.safeAreaLayoutGuide.centerXAnchor),
            empty.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor, constant: 40),
        ])
        view = host
    }

    let empty = NSTextField(labelWithString: "")
    var emptyText: String { empty.isHidden ? "" : empty.stringValue }
    /// For the harness: the empty-list label's frame, window points from the top-left.
    var emptyFrame: [String: JSONValue] {
        guard let w = view.window else { return [:] }
        let f = empty.convert(empty.bounds, to: nil)
        return ["x": .number(Double(f.minX)), "y": .number(Double(w.frame.height - f.maxY)), "width": .number(Double(f.width)), "height": .number(Double(f.height))]
    }

    func reload() {
        reloading = true
        defer { reloading = false }
        let keep = selectedLocations
        roots = model.shown().map { Node(.bridge($0)) }
        empty.stringValue = model.scope == .waiting ? "Nothing waiting" : "No bridges"
        empty.isHidden = !roots.isEmpty
        outline.reloadData()
        var rows = IndexSet()
        let multi = keep.count > 1 && model.selected.map { keep.contains($0) } == true
        for loc in (multi ? keep : [model.selected].compactMap { $0 }) {
            if let node = node(for: loc) { let row = outline.row(forItem: node); if row >= 0 { rows.insert(row) } }
        }
        if rows.isEmpty { outline.deselectAll(nil) } else { outline.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    func row(for location: String) -> Int {
        guard let node = node(for: location) else { return -1 }
        return outline.row(forItem: node)
    }

    // The clicked row, or the whole selection when the click landed inside it.
    func locations(forRow row: Int) -> [String] {
        let rows = outline.selectedRowIndexes.contains(row) ? Array(outline.selectedRowIndexes) : [row]
        return rows.compactMap { r in
            if case .bridge(let e) = (outline.item(atRow: r) as? Node)?.kind { return e.location }
            return nil
        }
    }

    var selectedLocations: [String] {
        outline.selectedRowIndexes.compactMap { r in
            if case .bridge(let e) = (outline.item(atRow: r) as? Node)?.kind { return e.location }
            return nil
        }
    }

    func contextMenu(forRow row: Int) -> NSMenu? {
        let targets = locations(forRow: row)
        guard !targets.isEmpty else { return nil }
        let entries = targets.compactMap { model.listing.entry($0) }
        let menu = NSMenu()
        func item(_ title: String, _ command: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = menu.addItem(withTitle: title, action: #selector(rowCommand(_:)), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.representedObject = [command, targets] as [Any]
        }
        let plural = targets.count > 1 ? " \(targets.count) Bridges" : ""
        if entries.contains(where: { !$0.crossed }) { item("Cross" + plural, "cross", "e") }
        if entries.contains(where: { $0.crossed }) { item("Uncross" + plural, "uncross", "E", [.command, .shift]) }
        menu.addItem(.separator())
        if targets.count == 1, entries.first?.kind != .url { item("Reveal in Finder", "reveal", "R", [.command, .shift]) }
        item("Remove from List", "remove", "\u{8}")
        return menu
    }

    @objc func rowCommand(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Any], let command = pair[0] as? String, let targets = pair[1] as? [String] else { return }
        onRowCommand(command, targets)
    }

    func node(for location: String) -> Node? {
        for root in roots {
            if case .bridge(let e) = root.kind, e.location == location { return root }
        }
        return nil
    }

    func rowText(for entry: BridgeEntry) -> String {
        var parts = [entry.title, Self.ago(entry.presentedAt)]
        if isWaiting(entry) { parts.append("waiting") }
        if entry.unread { parts.append("unread") }
        if entry.crossed { parts.append("crossed") }
        return parts.joined(separator: " · ")
    }

    func isWaiting(_ entry: BridgeEntry) -> Bool {
        guard !entry.crossed else { return false }
        let status = model.pages[entry.location]?.sidecar.status ?? Sidecar.peek(Paths.sidecar(for: entry.location)).status
        return status == "open"
    }

    static func ago(_ date: Date, from now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch (item as? Node)?.kind {
        case .bridge(let entry): return subtitle(for: entry) == nil ? 30 : 44
        default: return 30
        }
    }

    /// Only in the lists that cross projects: in a project's own list it would be
    /// the same word on every row.
    func subtitle(for entry: BridgeEntry) -> String? {
        guard model.scope == .waiting || model.scope == .all else { return nil }
        var parts = [entry.projectName].filter { !$0.isEmpty }
        if let why = model.unheard(entry) { parts.append(why) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if case .bridge = (item as? Node)?.kind { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        if case .bridge = (item as? Node)?.kind { return BridgeRowView() }
        return nil
    }

    func geometry() -> [String: JSONValue] {
        guard let scroll = outline.enclosingScrollView else { return [:] }
        // On macOS 26 the projects sidebar floats over this list, so the visible column
        // starts at the safe-area inset; pixel checks scan from there.
        let inset = scroll.contentInsets.left
        let clip = scroll.contentView.bounds.width - inset
        var out: [String: JSONValue] = [
            "clip": .number(Double(clip)), "table": .number(Double(outline.bounds.width)),
            "columnX": .number(Double(scroll.convert(scroll.bounds, to: nil).minX + inset)),
            "safeLeft": .number(Double(inset)),
            "scroller": .string(scroll.scrollerStyle == .legacy ? "legacy" : "overlay"),
        ]
        if let row = outline.selectedRowIndexes.first, let rv = outline.rowView(atRow: row, makeIfNecessary: false) as? BridgeRowView {
            // No pill geometry here: the source list draws its own selection, so a computed
            // rectangle would not reflect what is on screen.
            out["emphasized"] = .bool(rv.isEmphasized)
            out["timeColor"] = .string(rv.timeColorName)
            out["rowFrame"] = .string("\(rv.frame)")
            if let win = rv.window {
                let f = rv.convert(rv.bounds, to: nil)
                out["rowInWindow"] = .object(["x": .number(Double(f.minX)), "top": .number(Double(win.frame.height - f.maxY)), "width": .number(Double(f.width)), "height": .number(Double(f.height))])
            }
            out["column"] = .number(Double(outline.tableColumns.first?.width ?? -1))
            if let cell = rv.cell {
                out["titleX"] = .number(Double(cell.title.convert(cell.title.bounds, to: nil).minX))
                out["dotX"] = .number(Double(cell.dot.convert(cell.dot.bounds, to: nil).minX))
                out["timeX"] = .number(Double(cell.time.convert(cell.time.bounds, to: nil).minX))
                out["titleRight"] = .number(Double(cell.title.convert(cell.title.bounds, to: nil).maxX))
            }
            out["intercell"] = .number(Double(outline.intercellSpacing.width))
            out["outlineFrame"] = .string("\(outline.frame)")
            out["clipBounds"] = .string("\(scroll.contentView.bounds)")
            out["selectionStyle"] = .number(Double(outline.selectionHighlightStyle.rawValue))
            // The harness window is never key, so the active mapping is reported rather than observed.
            out["activeTimeColor"] = .string(BridgeRowView.timeColorName(selected: true, emphasized: true))
        }
        var v: NSView? = view
        var vibrant = false
        // macOS 26 hosts a sidebar split item in its glass effect view; earlier systems in a visual effect view.
        while let x = v {
            if let e = x as? NSVisualEffectView, e.material == .sidebar { vibrant = true; break }
            if String(describing: type(of: x)) == "NSGlassEffectView" { vibrant = true; break }
            v = x.superview
        }
        out["vibrant"] = .bool(vibrant)
        out["intercellHeight"] = .number(Double(outline.intercellSpacing.height))
        out["rows"] = .array((0..<outline.numberOfRows).compactMap { r in
            guard let cell = outline.view(atColumn: 0, row: r, makeIfNecessary: false) as? BridgeCell else { return nil }
            return .object(["title": .string(cell.title.stringValue), "dim": .bool(cell.dim), "struck": .bool(cell.struck), "unread": .bool(cell.unread),
                            "resolved": .string(cell.notes.stringValue)])
        })
        var chain: [String] = []
        v = view
        while let x = v { chain.append(String(describing: type(of: x)) + ((x as? NSVisualEffectView).map { " material=\($0.material.rawValue)" } ?? "")); v = x.superview }
        out["ancestry"] = .array(chain.map { .string($0) })
        return out
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        switch node.kind {
        case .bridge(let entry):
            let cell = outline.makeView(withIdentifier: .init("bridge"), owner: nil) as? BridgeCell ?? BridgeCell()
            cell.configure(entry, waiting: isWaiting(entry), quiet: model.isQuiet(entry), from: subtitle(for: entry), resolved: model.resolved(entry))
            return cell
        }
    }

    static func headerCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .init("group")
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            // Sits low in its row so the row's gap falls above it.
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        if case .bridge(let e) = (outline.item(atRow: outline.selectedRow) as? Node)?.kind {
            onSelect(e.location)
        }
    }
}

final class RowMenuOutlineView: NSOutlineView {
    var menuProvider: (Int) -> NSMenu? = { _ in nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        return menuProvider(row)
    }
}

final class PlainLabel: NSTextField {
    override var allowsVibrancy: Bool { false }
}

final class Dot: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

final class BridgeRowView: NSTableRowView {
    override var isSelected: Bool { didSet { restyle() } }
    override var isEmphasized: Bool { didSet { restyle() } }
    var cell: BridgeCell? { subviews.lazy.compactMap { $0 as? BridgeCell }.first }
    var timeColorName: String { Self.timeColorName(selected: isSelected, emphasized: isEmphasized) }

    static func timeColorName(selected: Bool, emphasized: Bool) -> String {
        guard selected else { return "tertiaryLabelColor" }
        return emphasized ? "alternateSelectedControlTextColor" : "secondaryLabelColor"
    }

    override func didAddSubview(_ subview: NSView) { super.didAddSubview(subview); restyle() }

    func restyle() {
        let colour: NSColor = isSelected
            ? (isEmphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85) : .secondaryLabelColor)
            : .tertiaryLabelColor
        cell?.time.textColor = colour
        cell?.notes.textColor = colour
        needsDisplay = true
    }

}

final class BridgeCell: NSTableCellView {
    let dot = Dot()
    let title = PlainLabel(labelWithString: "")
    let time = PlainLabel(labelWithString: "")
    let notes = PlainLabel(labelWithString: "")
    let project = PlainLabel(labelWithString: "")
    private var oneLine: [NSLayoutConstraint] = []
    private var twoLine: [NSLayoutConstraint] = []

    override var allowsVibrancy: Bool { false }

    init() {
        super.init(frame: .zero)
        identifier = .init("bridge")
        for v in [dot, title, time, project, notes] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        project.lineBreakMode = .byTruncatingTail
        project.maximumNumberOfLines = 1
        project.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        project.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        time.textColor = .tertiaryLabelColor
        time.alignment = .right
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        notes.font = time.font
        notes.textColor = .tertiaryLabelColor
        notes.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The title is not the cell's textField outlet: AppKit restyles that one on every
        // background-style pass, wiping its colour and strike.
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7), dot.heightAnchor.constraint(equalToConstant: 7),
            // Every title starts 25 pt into the column, where the header over it starts.
            // The unread dot's room at the trailing edge is always kept, so a title's
            // truncation point does not move when the bridge is read.
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            notes.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            notes.trailingAnchor.constraint(equalTo: dot.leadingAnchor, constant: -6),
            notes.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -6),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The pill is inset 10 from the row and the cell reaches the row's edge, so the
            // time needs room to stay inside the pill.
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The subtitle truncates on its own: a long project name must not shorten the title.
            project.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            project.trailingAnchor.constraint(lessThanOrEqualTo: notes.leadingAnchor, constant: -8),
        ])
        oneLine = [title.centerYAnchor.constraint(equalTo: centerYAnchor)]
        // Two lines sit centred about the row's middle as one block, so the pill keeps
        // the same air above and below as on a single line. The offsets were measured
        // from a rendered pill.
        twoLine = [
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            project.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ]
        NSLayoutConstraint.activate(oneLine)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var text = ""
    private(set) var dim = false
    private(set) var struck = false

    func configure(_ entry: BridgeEntry, waiting: Bool, quiet: Bool = false, from: String? = nil, resolved: String? = nil) {
        text = entry.title
        let name = (from?.isEmpty == false) ? from : nil
        project.stringValue = name ?? ""
        project.isHidden = name == nil
        NSLayoutConstraint.deactivate(name == nil ? twoLine : oneLine)
        NSLayoutConstraint.activate(name == nil ? oneLine : twoLine)
        // Quiet: held in Waiting after it stopped waiting.
        dim = entry.crossed || quiet
        struck = entry.crossed
        restyle()
        time.stringValue = SidebarController.ago(entry.presentedAt)
        notes.stringValue = resolved ?? ""
        notes.toolTip = resolved.map { "\($0) notes resolved" }
        unread = entry.unread
        dot.toolTip = entry.unread ? "Unread" : nil
        paintDot()
    }

    private(set) var unread = false

    // An accent dot on the accent pill would vanish, so on the emphasized pill it
    // takes the pill's text colour.
    private func paintDot() {
        dot.color = unread ? (backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .controlAccentColor) : .clear
    }

    // AppKit restyles on every background-style change, so the title style is
    // applied again after it.
    override var backgroundStyle: NSView.BackgroundStyle { didSet { restyle(); paintDot() } }

    private func restyle() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let colour: NSColor = backgroundStyle == .emphasized
            ? (dim ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.7) : .alternateSelectedControlTextColor)
            : (dim ? .secondaryLabelColor : .labelColor)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        if struck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        title.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        // On the emphasized pill a secondary grey would disappear into the accent.
        project.textColor = backgroundStyle == .emphasized
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(dim ? 0.55 : 0.7)
            : (dim ? .tertiaryLabelColor : .secondaryLabelColor)
    }
}

/// The offer of a newer build, as a quiet row in the list's own column, with a
/// pill only on hover.
final class UpdateRow: NSView {
    let pill = NSView()
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?
    let tip: String
    var text = "" { didSet { label.stringValue = text; toolTip = tip } }

    init(symbol: String = "arrow.triangle.2.circlepath", tip: String = "Relaunch into the new build") {
        self.tip = tip
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 6
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [pill, icon, label] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 1), pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21), icon.widthAnchor.constraint(equalToConstant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor }
    override func mouseExited(with event: NSEvent) { pill.layer?.backgroundColor = nil }
    override func mouseUp(with event: NSEvent) { onPress?() }
}
