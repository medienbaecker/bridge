import Foundation
import CryptoKit
import BridgeCore
import BridgeShared

final class Sharing {
    let link: Link
    unowned let model: Model
    var shares = Shares.load()
    var cursors: [String: [String: JSONValue]] = [:]
    var colours: [String: String] = [:]
    var records: [String: SharedRecord] = [:]
    var drafts: [String: [String: [String: JSONValue]]] = [:]

    init(link: Link, model: Model) {
        self.link = link
        self.model = model
        model.onCursor = { [weak self] location, anchor in self?.moved(location, anchor) }
        model.onReady = { [weak self] page in self?.ready(page) }
        link.onMessage = { [weak self] peer, message in self?.received(message, from: peer) }
        link.onDrop = { [weak self] peer in self?.dropped(peer) }
        link.onConnect = { [weak self] _ in self?.sendRecords() }
        model.onSaved = { [weak self] page in self?.saved(page) }
        model.onRewrite = { [weak self] page in self?.rewritten(page) }
        model.onDraft = { [weak self] location, key, value in
            guard let self, let id = self.share(at: location) else { return }
            self.link.send(["kind": .string("draft"), "share": .string(id), "person": .string(Person.current), "key": .string(key), "value": value])
        }
    }

    func share(at location: String) -> String? { shares.first { $0.location == location }?.id }

    func share(_ location: String) throws -> JSONValue {
        guard !link.sessions.isEmpty else { throw LinkError("no other Mac with Bridge is connected right now") }
        let bundle = try PageBundle.make(page: URL(fileURLWithPath: location))
        let title = model.listing.entry(location)?.title ?? BridgeEntry.defaultTitle(location)
        let id = share(at: location) ?? UUID().uuidString
        if share(at: location) == nil { shares.append(Share(id: id, location: location, from: Person.current, title: title)) }
        try update(id) { $0.origins = bundle.origins; $0.synced = Self.hash(bundle.content) }
        let rec = try record(id) ?? SharedRecord(person: Person.current)
        records[id] = rec
        try rec.absorb(model.page(for: location).sidecar)
        try store(id)
        link.send([
            "kind": .string("share"), "share": .string(id), "from": .string(Person.current), "title": .string(title),
            "record": .string(rec.save().base64EncodedString()),
        ].merging(Self.encode(bundle)) { a, _ in a })
        if let page = model.pages[location], page.ready { ready(page) }
        model.onChange()
        return .object(["share": .string(id), "to": .array(link.sessions.values.map { .string($0.peer.name) })])
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func encode(_ bundle: PageBundle) -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "html": .string(bundle.html), "main": .string(bundle.main),
            "files": .object(bundle.files.mapValues { .string($0.base64EncodedString()) }),
        ]
        if let binary = bundle.binary { out["binary"] = .string(binary.base64EncodedString()) }
        if let data = bundle.pageData { out["pageData"] = .string(data.base64EncodedString()) }
        return out
    }

    static func decode(_ message: [String: JSONValue]) -> PageBundle? {
        guard let html = message["html"]?.stringValue, case .object(let encoded)? = message["files"] else { return nil }
        var files: [String: Data] = [:]
        for (name, value) in encoded { files[name] = value.stringValue.flatMap { Data(base64Encoded: $0) } ?? Data() }
        var bundle = PageBundle(html: html, files: files)
        bundle.main = message["main"]?.stringValue ?? "page.html"
        bundle.binary = message["binary"]?.stringValue.flatMap { Data(base64Encoded: $0) }
        bundle.pageData = message["pageData"]?.stringValue.flatMap { Data(base64Encoded: $0) }
        return bundle
    }

    func update(_ id: String, _ change: (inout Share) -> Void) throws {
        guard let i = shares.firstIndex(where: { $0.id == id }) else { return }
        change(&shares[i])
        try Shares.save(shares)
    }

    func rewritten(_ page: Page) {
        guard let share = shares.first(where: { $0.location == page.location }) else { return }
        let known = Dictionary((share.origins ?? [:]).map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        guard let bundle = try? PageBundle.make(page: URL(fileURLWithPath: share.location), known: known), Self.hash(bundle.content) != share.synced else { return }
        let clock = (share.clock ?? 0) + 1
        try? update(share.id) {
            $0.origins = ($0.origins ?? [:]).merging(bundle.origins) { a, _ in a }
            $0.synced = Self.hash(bundle.content)
            $0.clock = clock
            $0.writer = link.me
        }
        link.send([
            "kind": .string("page"), "share": .string(share.id), "by": .string(Person.current),
            "clock": .number(Double(clock)), "writer": .string(link.me),
        ].merging(Self.encode(bundle)) { a, _ in a })
    }

    func receivePage(_ id: String, _ message: [String: JSONValue]) throws {
        guard let share = shares.first(where: { $0.id == id }), let bundle = Self.decode(message) else { return }
        let files = bundle.files
        let folder = Shares.folder.appendingPathComponent(id)
        let clock = message["clock"]?.intValue ?? 0, writer = message["writer"]?.stringValue ?? ""
        guard share.older(than: clock, by: writer) else { throw LinkError("an older rewrite arrived after a newer one; kept the newer") }
        try update(id) { $0.synced = Self.hash(bundle.content); $0.clock = clock; $0.writer = writer }
        if share.received {
            _ = try bundle.install(into: folder)
            return
        }
        var origins = share.origins ?? [:]
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("files"), withIntermediateDirectories: true)
        for (name, data) in files where origins[name] == nil {
            guard name.hasPrefix("files/"), !name.contains(".."), !name.dropFirst(6).contains("/") else { throw PageBundle.Unsafe(name: name) }
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            origins[name] = folder.appendingPathComponent(name).path
        }
        try update(id) { $0.origins = origins }
        let target = URL(fileURLWithPath: share.location)
        if let data = bundle.pageData { try data.write(to: Paths.dataFile(for: share.location), options: .atomic) }
        if let binary = bundle.binary {
            try binary.write(to: target, options: .atomic)
        } else {
            try Data(PageBundle.restore(bundle.html, origins: origins, folder: folder).utf8).write(to: target, options: .atomic)
        }
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
        let typing = drafts[id] ?? [:]
        let list: [JSONValue] = Set(people.keys).union(typing.keys).sorted().filter { $0 != Person.current }.map { person in
            .object(["person": .string(person), "color": colours[person].map { .string($0) } ?? .null,
                     "answers": .object(people[person] ?? [:]), "drafts": .object(typing[person] ?? [:])])
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
        case "draft":
            guard let person = message["person"]?.stringValue, let key = message["key"]?.stringValue else { return }
            let value = message["value"] ?? .null
            drafts[id, default: [:]][person, default: [:]][key] = value == .null ? nil : value
            drawPeople(id)
        case "page":
            do {
                try receivePage(id, message)
                if let share = shares.first(where: { $0.id == id }), let page = model.pages[share.location], page.ready {
                    page.call("__bridge.toast(text)", ["text": "\(message["by"]?.stringValue ?? peer.name)'s agent rewrote the page"])
                }
            } catch { Env.log("page from \(peer.name): \(error)") }
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
        guard let bundle = Self.decode(message) else { return }
        let page = try bundle.install(into: Shares.folder.appendingPathComponent(id)).path
        let from = message["from"]?.stringValue ?? peer.name
        let title = message["title"]?.stringValue ?? "Shared page"
        if share(at: page) == nil { shares.append(Share(id: id, location: page, from: from, title: title)) }
        try update(id) { $0.synced = Self.hash(bundle.content) }
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
        for id in drafts.keys where drafts[id]?[peer.name] != nil {
            drafts[id]?[peer.name] = nil
            drawPeople(id)
        }
        for id in cursors.keys where cursors[id]?[peer.name] != nil {
            cursors[id]?[peer.name] = nil
            draw(id)
        }
    }
}
