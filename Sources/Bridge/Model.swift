import AppKit
import BridgeCore

/// What the middle column shows: the bridges waiting on the user, all of them, or one project's.
enum Scope: Equatable {
    case waiting, all, project(String), agent(String)

    var key: String {
        switch self { case .waiting: return "waiting"; case .all: return "all"; case .project(let p): return "project:" + p; case .agent(let s): return "agent:" + s }
    }

    init(key: String) {
        if key == "all" { self = .all }
        else if key.hasPrefix("project:") { self = .project(String(key.dropFirst(8))) }
        else if key.hasPrefix("agent:") { self = .agent(String(key.dropFirst(6))) }
        else { self = .waiting }
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
    var onCursor: (String, JSONValue) -> Void = { _, _ in }
    var onReady: (Page) -> Void = { _ in }
    var onSaved: (Page) -> Void = { _ in }
    var onRewrite: (Page) -> Void = { _ in }
    var onDraft: (String, String, JSONValue) -> Void = { _, _, _ in }
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
        case .agent(let s): return all.filter { $0.session == s && !$0.crossed }
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

    var projectNames: [String: String] = [:]
    var abouts: [String: ClaudeSessions.About] = [:]

    func about(_ session: String) -> ClaudeSessions.About {
        if let known = abouts[session], known.topic != nil { return known }
        let found = ClaudeSessions.about(session)
        abouts[session] = found
        return found
    }

    func projectName(_ cwd: String) -> String {
        if let name = projectNames[cwd] { return name }
        let name = (Ground.projectRoot(for: cwd) as NSString).lastPathComponent
        projectNames[cwd] = name
        return name
    }

    func agentName(_ session: String, cwd: String) -> String {
        if !cwd.isEmpty { return projectName(cwd) }
        if let known = about(session).cwd { return projectName(known) }
        if let entry = listing.bridges.filter({ $0.session == session }).max(by: { $0.presentedAt < $1.presentedAt }) { return entry.projectName }
        return "session \(session.prefix(4))"
    }

    func agentLabel(_ session: String, cwd: String) -> String {
        let name = agentName(session, cwd: cwd)
        return about(session).topic.map { "\(name) · “\($0)”" } ?? name
    }

    func agents() -> [ClaudeSessions.Live] {
        ClaudeSessions.live().sorted { agentLabel($0.session, cwd: $0.cwd) < agentLabel($1.session, cwd: $1.cwd) }
    }

    func hand(_ location: String, to session: String) {
        guard listing.entry(location) != nil else { return }
        let page = page(for: location)
        if session.isEmpty {
            page.sidecar.presented = nil
            page.save()
        } else {
            let cwd = ClaudeSessions.live().first { $0.session == session }?.cwd.nilIfEmpty ?? about(session).cwd ?? page.sidecar.presented?.cwd ?? ""
            page.presented(Presentation(session: session, cwd: cwd, ground: cwd.isEmpty ? nil : Ground.current(in: cwd)))
        }
        listing.update(location) { $0.session = session }
        changed()
    }

    func page(for location: String) -> Page {
        if let p = pages[location] { return p }
        let p = Page(location: location, model: self)
        pages[location] = p
        p.load()
        return p
    }

    func present(_ locations: [String], cwd: String, session: String, ground: Ground?, links: String?, site: String?) {
        let project = Ground.projectRoot(for: cwd)
        for loc in locations {
            let siteChanged = pages[loc] != nil && listing.entry(loc)?.site != site
            if listing.entry(loc) != nil {
                listing.update(loc) { e in
                    e.presentedAt = Date(); e.unread = true; e.crossed = false; e.session = session; e.project = project; e.links = links; e.site = site
                }
            } else {
                var entry = BridgeEntry(location: loc, project: project, session: session)
                entry.links = links
                entry.site = site
                listing.bridges.append(entry)
            }
            let page = page(for: loc)
            page.presented(Presentation(session: session, cwd: cwd, ground: ground))
            if siteChanged { page.load() }
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
