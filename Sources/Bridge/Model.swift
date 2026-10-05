import AppKit
import BridgeCore

/// What the middle column shows: the bridges waiting on the user, all of them, or one project's.
enum Scope: Equatable {
    case waiting, all, project(String)

    var key: String {
        switch self { case .waiting: return "waiting"; case .all: return "all"; case .project(let p): return "project:" + p }
    }

    init(key: String) {
        if key == "all" { self = .all } else if key.hasPrefix("project:") { self = .project(String(key.dropFirst(8))) } else { self = .waiting }
    }
}

final class Model {
    var listing = Listing.load()
    // Kept in the state dir rather than UserDefaults, which every state dir of a
    // bundle shares: a scope left by one harness case leaked into the next.
    static let uiFile = Paths.stateDir.appendingPathComponent("ui.json")
    static func remembered(_ key: String) -> Any? {
        guard let data = try? Data(contentsOf: uiFile), let ui = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ui[key]
    }
    static func remember(_ value: Any?, _ key: String) {
        var ui = (try? Data(contentsOf: uiFile)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        ui[key] = value ?? NSNull()
        if let data = try? JSONSerialization.data(withJSONObject: ui, options: [.sortedKeys]) { try? data.write(to: uiFile, options: .atomic) }
    }
    var selected: String? { didSet { Self.remember(selected, "selected") } }
    var scope: Scope = Scope(key: Model.remembered("scope") as? String ?? "waiting") {
        didSet { Self.remember(scope.key, "scope"); if scope != oldValue { held = nil } }
    }
    /// Waiting as the user entered it. Membership is fixed on entry so that a
    /// bridge that stops waiting stays in place instead of the rows below jumping
    /// up under the cursor; new arrivals still join. Never saved.
    private var held: [String]?
    var showCrossed: Bool = Model.remembered("showCrossed") as? Bool ?? true { didSet { Self.remember(showCrossed, "showCrossed") } }
    var pages: [String: Page] = [:]
    var onChange: () -> Void = {}
    var waiters: [Waiter] = []
    var lives: [String: ClaudeSessions.Life] = [:]

    var selectedPage: Page? { selected.map { page(for: $0) } }

    func status(of entry: BridgeEntry) -> String {
        pages[entry.location]?.sidecar.status ?? Sidecar.peek(Paths.sidecar(for: entry.location)).status
    }

    func bridges(in scope: Scope) -> [BridgeEntry] {
        let all = listing.bridges.sorted { $0.presentedAt > $1.presentedAt }
        switch scope {
        case .waiting: return all.filter { !$0.crossed && status(of: $0) == "open" }
        case .all: return all.filter { !$0.crossed } + (showCrossed ? all.filter { $0.crossed } : [])
        case .project(let p): return all.filter { $0.project == p && !$0.crossed } + (showCrossed ? all.filter { $0.project == p && $0.crossed } : [])
        }
    }

    func shown() -> [BridgeEntry] {
        guard scope == .waiting else { return bridges(in: scope) }
        let live = bridges(in: .waiting).map(\.location)
        var kept = held ?? live
        for loc in live where !kept.contains(loc) { kept.append(loc) }
        let entries = listing.bridges.sorted { $0.presentedAt > $1.presentedAt }.filter { kept.contains($0.location) }
        held = entries.map(\.location)
        return entries
    }

    /// A held row that no longer waits: answered, or crossed by its agent, since the user entered.
    func isQuiet(_ entry: BridgeEntry) -> Bool {
        scope == .waiting && (entry.crossed || status(of: entry) != "open")
    }

    func listening(_ entry: BridgeEntry) -> Bool {
        waiters.contains { $0.session == entry.session || $0.locations.contains(entry.location) }
    }

    func unheard(_ entry: BridgeEntry) -> String? {
        guard !entry.crossed, status(of: entry) == "open", !listening(entry) else { return nil }
        switch lives[entry.session] ?? ClaudeSessions.life(of: entry.session) {
        case .gone: return "session ended"
        case .working: return "agent working"
        default: return "no agent waiting"
        }
    }

    func resolved(_ entry: BridgeEntry) -> String? {
        let comments = (pages[entry.location]?.sidecar ?? Sidecar.peek(Paths.sidecar(for: entry.location))).comments
        guard !comments.isEmpty else { return nil }
        return "\(comments.filter { $0.state == "done" }.count)/\(comments.count)"
    }

    func waitingCount(in project: String? = nil) -> Int {
        listing.bridges.filter { (project == nil || $0.project == project) && !$0.crossed && status(of: $0) == "open" }.count
    }

    func settleSelection() {
        let shown = shown()
        if let selected, shown.contains(where: { $0.location == selected }) { return }
        selected = shown.first?.location
    }

    func changed() {
        try? listing.save()
        onChange()
    }

    func page(for location: String) -> Page {
        if let p = pages[location] { return p }
        let p = Page(location: location, model: self)
        pages[location] = p
        p.load()
        return p
    }

    func present(_ locations: [String], cwd: String, session: String, ground: Ground?) {
        let project = Ground.projectRoot(for: cwd)
        for loc in locations {
            if listing.entry(loc) != nil {
                listing.update(loc) { e in
                    e.presentedAt = Date(); e.unread = true; e.crossed = false; e.session = session; e.project = project
                }
            } else {
                listing.bridges.append(BridgeEntry(location: loc, project: project, session: session))
            }
            let page = page(for: loc)
            page.presented(Presentation(session: session, cwd: cwd, ground: ground))
        }
        if let first = locations.first {
            selected = first
            if !shown().contains(where: { $0.location == first }) { scope = .project(project) }
        }
        changed()
    }

    func cross(_ location: String, _ crossed: Bool) {
        if crossed { Notify.withdraw(listing.entry(location)) }
        listing.update(location) { $0.crossed = crossed; if crossed { $0.unread = false } }
        changed()
    }

    func remove(_ location: String) {
        Notify.withdraw(listing.entry(location))
        listing.bridges.removeAll { $0.location == location }
        pages[location]?.close()
        pages[location] = nil
        if selected == location { selected = nil; settleSelection() }
        changed()
    }

    func reset(_ location: String) {
        remove(location)
        try? FileManager.default.removeItem(at: Paths.sidecar(for: location))
    }

    func markRead(_ location: String) {
        Notify.withdraw(listing.entry(location))
        guard listing.entry(location)?.unread == true else { return }
        listing.update(location) { $0.unread = false }
        changed()
    }

    func markUnread(_ location: String) {
        listing.update(location) { $0.unread = true; $0.presentedAt = Date() }
        changed()
    }

    func setTitle(_ title: String, for location: String) {
        guard let e = listing.entry(location), e.title != title, !title.isEmpty else { return }
        listing.update(location) { $0.title = title }
        changed()
    }
}
