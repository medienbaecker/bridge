import Foundation
import BridgeCore
import BridgeShared

final class Sharing {
    let link: Link
    unowned let model: Model
    var shares = Shares.load()
    var cursors: [String: [String: JSONValue]] = [:]
    var colours: [String: String] = [:]
    var records: [String: SharedRecord] = [:]

    init(link: Link, model: Model) {
        self.link = link
        self.model = model
        model.onCursor = { [weak self] location, anchor in self?.moved(location, anchor) }
        model.onReady = { [weak self] page in self?.ready(page) }
        link.onMessage = { [weak self] peer, message in self?.received(message, from: peer) }
        link.onDrop = { [weak self] peer in self?.dropped(peer) }
        link.onConnect = { [weak self] _ in self?.sendRecords() }
        model.onSaved = { [weak self] page in self?.saved(page) }
    }

    func share(at location: String) -> String? { shares.first { $0.location == location }?.id }

    func share(_ location: String) throws -> JSONValue {
        guard !link.sessions.isEmpty else { throw LinkError(link.peers.isEmpty ? "this Mac isn't paired with another: run bridge --pair on both" : "no paired Mac is connected right now") }
        let bundle = try PageBundle.make(page: URL(fileURLWithPath: location))
        let title = model.listing.entry(location)?.title ?? BridgeEntry.defaultTitle(location)
        let id = share(at: location) ?? UUID().uuidString
        if share(at: location) == nil {
            shares.append(Share(id: id, location: location, from: Person.current, title: title))
            try Shares.save(shares)
        }
        let rec = try record(id) ?? SharedRecord(person: Person.current)
        records[id] = rec
        try rec.absorb(model.page(for: location).sidecar)
        try store(id)
        link.send([
            "kind": .string("share"), "share": .string(id), "from": .string(Person.current), "title": .string(title),
            "html": .string(bundle.html), "files": .object(bundle.files.mapValues { .string($0.base64EncodedString()) }),
            "record": .string(rec.save().base64EncodedString()),
        ])
        if let page = model.pages[location], page.ready { ready(page) }
        model.onChange()
        return .object(["share": .string(id), "to": .array(link.sessions.values.map { .string($0.peer.name) })])
    }

    func recordURL(_ id: String) -> URL { Shares.folder.appendingPathComponent(id).appendingPathComponent("record.automerge") }

    func record(_ id: String) throws -> SharedRecord? {
        if let rec = records[id] { return rec }
        guard let data = try? Data(contentsOf: recordURL(id)) else { return nil }
        let rec = try SharedRecord(bytes: data, person: Person.current)
        records[id] = rec
        return rec
    }

    func store(_ id: String) throws {
        guard let rec = records[id] else { return }
        try FileManager.default.createDirectory(at: recordURL(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try rec.save().write(to: recordURL(id), options: .atomic)
    }

    func saved(_ page: Page) {
        guard let id = share(at: page.location), let rec = try? record(id), (try? rec.absorb(page.sidecar)) == true else { return }
        try? store(id)
        link.send(["kind": .string("record"), "share": .string(id), "record": .string(rec.save().base64EncodedString())])
    }

    func sendRecords() {
        for share in shares {
            guard let rec = try? record(share.id) else { continue }
            if let page = model.pages[share.location] { try? rec.absorb(page.sidecar) }
            link.send(["kind": .string("record"), "share": .string(share.id), "record": .string(rec.save().base64EncodedString())])
        }
    }

    func merge(_ id: String, _ encoded: String?) throws {
        guard let encoded, let data = Data(base64Encoded: encoded), let share = shares.first(where: { $0.id == id }) else { return }
        let incoming = try SharedRecord(bytes: data, person: Person.current)
        guard let rec = try record(id) else {
            records[id] = incoming
            try store(id)
            return try project(share)
        }
        if let page = model.pages[share.location] { try rec.absorb(page.sidecar) }
        try rec.merge(incoming)
        try store(id)
        try project(share)
    }

    func project(_ share: Share) throws {
        guard let rec = records[share.id] else { return }
        if let page = model.pages[share.location] {
            try rec.project(into: &page.sidecar)
            page.save()
            page.pushNotes()
            if page.ready { page.call("__bridge.answers(answers)", ["answers": page.any(.object(page.sidecar.answers))]) }
            drawPeople(share.id)
            model.onChange()
        } else {
            try Sidecar.modify(Paths.sidecar(for: share.location)) { s in try? rec.project(into: &s) }
        }
    }

    func drawPeople(_ id: String) {
        guard let share = shares.first(where: { $0.id == id }), let page = model.pages[share.location], page.ready, let rec = records[id] else { return }
        let people = (try? rec.people) ?? [:]
        let list: [JSONValue] = people.keys.sorted().filter { $0 != Person.current }.map { person in
            .object(["person": .string(person), "color": colours[person].map { .string($0) } ?? .null, "answers": .object(people[person] ?? [:])])
        }
        page.call("__bridge.people(list)", ["list": page.any(.array(list))])
    }

    func moved(_ location: String, _ anchor: JSONValue) {
        guard let id = share(at: location) else { return }
        link.send([
            "kind": .string("cursor"), "share": .string(id), "person": .string(Person.current),
            "color": Person.colour.map { .string($0) } ?? .null, "anchor": anchor,
        ])
    }

    func ready(_ page: Page) {
        guard let id = share(at: page.location) else { return }
        page.call("__bridge.trackCursor(true)")
        draw(id)
        if (try? record(id)) != nil { drawPeople(id) }
    }

    func draw(_ id: String) {
        guard let share = shares.first(where: { $0.id == id }), let page = model.pages[share.location], page.ready else { return }
        let list = (cursors[id] ?? [:]).values.sorted { ($0["person"]?.stringValue ?? "") < ($1["person"]?.stringValue ?? "") }
        page.call("__bridge.cursors(list)", ["list": page.any(.array(list))])
    }

    func received(_ message: [String: JSONValue], from peer: Peer) {
        guard let id = message["share"]?.stringValue else { return }
        switch message["kind"]?.stringValue {
        case "cursor":
            let person = message["person"]?.stringValue ?? peer.name
            if let colour = message["color"]?.stringValue, colours[person] != colour { colours[person] = colour; drawPeople(id) }
            if message["anchor"] == nil || message["anchor"] == .null {
                cursors[id]?[person] = nil
            } else {
                cursors[id, default: [:]][person] = .object(["person": .string(person), "color": message["color"] ?? .null, "anchor": message["anchor"] ?? .null])
            }
            draw(id)
        case "share":
            do {
                try install(id, message, from: peer)
                try merge(id, message["record"]?.stringValue)
            } catch { Env.log("share from \(peer.name): \(error)") }
        case "record":
            do { try merge(id, message["record"]?.stringValue) } catch { Env.log("record from \(peer.name): \(error)") }
        default:
            break
        }
    }

    func install(_ id: String, _ message: [String: JSONValue], from peer: Peer) throws {
        guard let html = message["html"]?.stringValue, case .object(let encoded)? = message["files"] else { return }
        var files: [String: Data] = [:]
        for (name, value) in encoded { files[name] = value.stringValue.flatMap { Data(base64Encoded: $0) } ?? Data() }
        let page = try PageBundle(html: html, files: files).install(into: Shares.folder.appendingPathComponent(id)).path
        let from = message["from"]?.stringValue ?? peer.name
        let title = message["title"]?.stringValue ?? "Shared page"
        if share(at: page) == nil {
            shares.append(Share(id: id, location: page, from: from, title: title))
            try Shares.save(shares)
        }
        if model.listing.entry(page) == nil {
            var entry = BridgeEntry(location: page, project: "Shared by \(from)", session: "")
            entry.title = title
            model.listing.bridges.append(entry)
        } else {
            model.listing.update(page) { $0.unread = true; $0.crossed = false; $0.presentedAt = Date() }
        }
        model.changed()
    }

    func dropped(_ peer: Peer) {
        for id in cursors.keys where cursors[id]?[peer.name] != nil {
            cursors[id]?[peer.name] = nil
            draw(id)
        }
    }
}
