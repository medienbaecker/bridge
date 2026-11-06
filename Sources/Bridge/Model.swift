import AppKit
import CryptoKit
import BridgeCore

/// What the middle column shows: the bridges waiting on the user, all of them, or one project's.
enum Scope: Equatable {
    case waiting, all, project(String)

    var key: String {
        switch self { case .waiting: return "waiting"; case .all: return "all"; case .project(let p): return "project:" + p }
    }

    init(key: String) {
        if key == "all" { self = .all }
        else if key.hasPrefix("project:") { self = .project(String(key.dropFirst(8))) }
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
    var waiters: [Waiter] = []
    var agents: [String: ClaudeSessions.Live] = [:]

    func life(of session: String) -> ClaudeSessions.Life { ClaudeSessions.life(of: session, in: agents) }

    var selectedPage: Page? { selected.map { page(for: $0) } }

    func status(of entry: BridgeEntry) -> String {
        pages[entry.location]?.sidecar.status ?? Sidecar.peek(Paths.sidecar(for: entry.location)).status
    }

    func bridges(in scope: Scope) -> [BridgeEntry] {
        let all = listing.bridges.sorted { $0.presentedAt > $1.presentedAt }
        switch scope {
        case .waiting: return all.filter { !$0.crossed && status(of: $0) == "open" && attended($0) }
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
        agents[entry.session] != nil || waiters.contains { $0.locations.contains(entry.location) }
    }

    func unheard(_ entry: BridgeEntry) -> String? {
        guard !isDraft(entry), !entry.crossed, status(of: entry) == "open", !listening(entry) else { return nil }
        return life(of: entry.session) == .gone ? "session ended" : "no agent waiting"
    }

    func waitingCount(in project: String? = nil) -> Int {
        listing.bridges.filter { (project == nil || $0.project == project) && !$0.crossed && status(of: $0) == "open" && attended($0) }.count
    }


    func attended(_ entry: BridgeEntry) -> Bool {
        life(of: entry.session) != .gone
    }

    @discardableResult
    func crossEnded() -> Int {
        let endedAfter = Settings.endedAfter
        guard endedAfter > 0 else { return 0 }
        let now = Date()
        let ended = listing.bridges.filter { entry in
            !entry.crossed && !isDraft(entry) && now.timeIntervalSince(entry.presentedAt) > endedAfter
                && life(of: entry.session) == .gone
        }
        for entry in ended { cross(entry.location, true) }
        return ended.count
    }

    func settleSelection() {
        let shown = shown()
        if let selected, shown.contains(where: { $0.location == selected }) { return }
        selected = shown.first?.location
    }

    func changed() {
        try? listing.save()
        watchForUpdates()
        onChange()
    }

    var updateWatchers: [String: Watcher] = [:]
    var fingerprints: [String: SHA256.Digest] = [:]

    func watchForUpdates() {
        let open = Set(listing.bridges.filter { !$0.crossed && Kind.of($0.location) != .url }.map(\.location))
        for location in Set(updateWatchers.keys).subtracting(open) {
            updateWatchers[location] = nil
            fingerprints[location] = nil
        }
        for location in open.subtracting(updateWatchers.keys) {
            fingerprints[location] = Self.fingerprint(location)
            let directory = URL(fileURLWithPath: location).deletingLastPathComponent()
            updateWatchers[location] = Watcher(directory: directory, files: [location, Paths.dataFile(for: location).path]) { [weak self] in
                self?.fileUpdated(location)
            }
        }
    }

    static func fingerprint(_ location: String) -> SHA256.Digest? {
        guard let file = try? Data(contentsOf: URL(fileURLWithPath: location)) else { return nil }
        return SHA256.hash(data: file + ((try? Data(contentsOf: Paths.dataFile(for: location))) ?? Data()))
    }

    func fileUpdated(_ location: String) {
        guard let fingerprint = Self.fingerprint(location), fingerprint != fingerprints[location] else { return }
        fingerprints[location] = fingerprint
        if !Env.test, !NSApp.isActive { Notify.updated(listing.entry(location)) }
    }

    var showAllProjects: Bool = Model.remembered("showAllProjects") as? Bool ?? false { didSet { Self.remember(showAllProjects, "showAllProjects") } }

    func deliver(_ page: Page) {
        let s = page.sidecar
        guard s.answered, s.changedSinceCollected, let session = s.presented?.session,
              let agent = agents[session] ?? ClaudeSessions.live()[session],
              ClaudeSessions.post(s.handOver(page.location, cli: Flavor.name), to: agent) else { return }
        page.collected(by: session)
    }

    func deliver(toNew sessions: Set<String>) {
        for entry in listing.bridges where sessions.contains(entry.session) {
            if let page = pages[entry.location] { deliver(page); continue }
            let url = Paths.sidecar(for: entry.location)
            let s = Sidecar.peek(url)
            guard s.answered, s.changedSinceCollected, let session = s.presented?.session, let agent = agents[session],
                  ClaudeSessions.post(s.handOver(entry.location, cli: Flavor.name), to: agent) else { continue }
            try? Sidecar.modify(url) { $0.collectedAt = Date(); $0.collectedBy = session }
        }
    }

    func hand(_ location: String, to session: String) {
        guard listing.entry(location) != nil else { return }
        let page = page(for: location)
        page.sidecar.collectedAt = nil
        page.sidecar.collectedBy = nil
        if session.isEmpty {
            page.sidecar.presented = nil
            page.save()
        } else {
            let cwd = agents[session]?.cwd ?? page.sidecar.presented?.cwd ?? ""
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

    static let untitled = "New bridge"

    func isDraft(_ entry: BridgeEntry) -> Bool { Paths.inDrafts(entry.location) && entry.session.isEmpty }

    @discardableResult func newBridge(capture: Freeze? = nil) -> String? {
        let folder = Paths.drafts
        if capture == nil, let empty = listing.bridges.first(where: { isDraft($0) && !$0.crossed && (pages[$0.location]?.sidecar ?? Sidecar.peek(Paths.sidecar(for: $0.location))).blank }) {
            scope = .project(folder.path)
            selected = empty.location
            changed()
            return empty.location
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = format.string(from: Date())
        var file = folder.appendingPathComponent("\(stamp).html")
        var number = 2
        while FileManager.default.fileExists(atPath: file.path) { file = folder.appendingPathComponent("\(stamp)-\(number).html"); number += 1 }
        let template = Bundle.module.url(forResource: "web", withExtension: nil)!.appendingPathComponent("draft.html")
        guard var html = try? String(contentsOf: template, encoding: .utf8) else { return nil }
        var title = Self.untitled
        if let capture, !capture.notes.isEmpty {
            func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;") }
            var notes = capture.notes
            var list = ""
            for index in notes.indices {
                let path = file.deletingPathExtension().appendingPathExtension("\(index + 1).png")
                var image = ""
                if let (data, width) = capture.picture(of: index), (try? data.write(to: path)) != nil {
                    notes[index].picture = path.path
                    image = "<img src=\"\(escape(path.path))\" width=\"\(Int(width))\" alt=\"\">"
                }
                list += "<li>\(image)<p>\(escape(notes[index].text))</p></li>"
            }
            html = html.replacingOccurrences(of: "<!--capture-->", with: "<ol id=\"notes\">\(list)</ol>")
            try? Sidecar.modify(Paths.sidecar(for: file.path)) { $0.comments = notes }
            title = notes[0].text
        }
        guard (try? html.write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        var entry = BridgeEntry(location: file.path, project: folder.path, session: "")
        entry.title = title
        entry.unread = false
        listing.bridges.append(entry)
        scope = .project(folder.path)
        selected = file.path
        changed()
        return file.path
    }

    func lastPage(of session: String) -> BridgeEntry? {
        listing.bridges.filter { $0.session == session && !Paths.inDrafts($0.location) }.max { $0.presentedAt < $1.presentedAt }
    }

    struct Recipient {
        let session: String
        let name: String
        let page: String
        let project: String
        let busy: Bool
        var label: String { [page, project, busy ? "busy" : "idle"].filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    func agentsByWork() -> [Recipient] {
        let pages = Dictionary(uniqueKeysWithValues: agents.keys.map { ($0, lastPage(of: $0)) })
        let sorted = agents.values.sorted { a, b in
            if (a.life == .working) != (b.life == .working) { return a.life != .working }
            return (pages[a.session]??.presentedAt ?? .distantPast) > (pages[b.session]??.presentedAt ?? .distantPast)
        }
        return sorted.map { agent in
            Recipient(session: agent.session, name: ClaudeSessions.title(of: agent), page: pages[agent.session]??.title ?? "No page yet",
                      project: agent.cwd.isEmpty ? "" : (Ground.projectRoot(for: agent.cwd) as NSString).lastPathComponent, busy: agent.life == .working)
        }
    }

    func setTitle(_ title: String, for location: String) {
        guard let e = listing.entry(location), e.title != title, !title.isEmpty else { return }
        listing.update(location) { $0.title = title }
        changed()
    }
}
