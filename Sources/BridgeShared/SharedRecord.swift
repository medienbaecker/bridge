import Foundation
import Automerge
import BridgeCore

public final class SharedRecord {
    public let doc: Document
    public let person: String

    public init(person: String) throws {
        doc = Document()
        self.person = person
        doc.actor = Self.actor(person)
        _ = try doc.putObject(obj: .ROOT, key: "picks", ty: .Map)
        _ = try doc.putObject(obj: .ROOT, key: "notes", ty: .Map)
        doc.commitWith(message: "start")
    }

    public init(bytes: Data, person: String) throws {
        doc = try Document(bytes)
        self.person = person
        doc.actor = Self.actor(person)
    }

    static func actor(_ person: String) -> ActorId {
        ActorId(data: Data("\(person)/\(UUID().uuidString)".utf8))!
    }

    public func save() -> Data { doc.save() }

    public func merge(_ other: SharedRecord) throws { try doc.merge(other: other.doc) }

    func map(_ key: String, in obj: ObjId = .ROOT) throws -> ObjId {
        guard case .Object(let id, .Map) = try doc.get(obj: obj, key: key) else { throw Malformed(what: key) }
        return id
    }

    func string(_ key: String, in obj: ObjId) throws -> String? {
        if case .Scalar(.String(let s)) = try doc.get(obj: obj, key: key) { return s }
        return nil
    }

    public func pick(_ key: String, _ value: JSONValue) throws {
        try doc.put(obj: map("picks"), key: "\(person)/\(key)", value: .String(Self.encode(value)))
        doc.commitWith(message: "pick \(key)")
    }

    public func clear(_ key: String) throws {
        try doc.delete(obj: map("picks"), key: "\(person)/\(key)")
        doc.commitWith(message: "clear \(key)")
    }

    public func add(_ comment: Comment) throws {
        let note = try doc.putObject(obj: map("notes"), key: comment.id, ty: .Map)
        try doc.put(obj: note, key: "comment", value: .String(Self.encode(comment)))
        try doc.put(obj: note, key: "state", value: .String(comment.state))
        _ = try doc.putObject(obj: note, key: "said", ty: .List)
        doc.commitWith(message: "note \(comment.id)")
    }

    public func reply(to id: String, _ say: Say) throws {
        guard case .Object(let said, .List) = try doc.get(obj: map(id, in: map("notes")), key: "said") else { throw Malformed(what: id) }
        try doc.insert(obj: said, index: doc.length(obj: said), value: .String(Self.encode(say)))
        doc.commitWith(message: "reply \(id)")
    }

    public func setState(_ id: String, _ state: String) throws {
        try doc.put(obj: map(id, in: map("notes")), key: "state", value: .String(state))
        doc.commitWith(message: "\(state) \(id)")
    }

    public var people: [String: [String: JSONValue]] {
        get throws {
            var out: [String: [String: JSONValue]] = [:]
            for (key, value) in try doc.mapEntries(obj: map("picks")) {
                guard case .Scalar(.String(let raw)) = value, let slash = key.firstIndex(of: "/") else { continue }
                out[String(key[..<slash]), default: [:]][String(key[key.index(after: slash)...])] = try Self.decode(JSONValue.self, raw)
            }
            return out
        }
    }

    public var comments: [Comment] {
        get throws {
            try doc.mapEntries(obj: map("notes")).compactMap { _, value -> Comment? in
                guard case .Object(let note, .Map) = value, let raw = try string("comment", in: note) else { return nil }
                var c = try Self.decode(Comment.self, raw)
                c.state = try string("state", in: note) ?? c.state
                if case .Object(let said, .List) = try doc.get(obj: note, key: "said") {
                    c.said = try doc.values(obj: said).compactMap { v in
                        guard case .Scalar(.String(let s)) = v else { return nil }
                        return try Self.decode(Say.self, s)
                    }
                }
                return c
            }.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        }
    }

    public func project(into sidecar: inout Sidecar) throws {
        let people = try people
        sidecar.people = people
        sidecar.answers = people[person] ?? [:]
        sidecar.comments = try comments
    }

    static func encode(_ value: some Encodable) throws -> String {
        String(decoding: try JSON.compact.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ raw: String) throws -> T {
        try JSON.decoder.decode(type, from: Data(raw.utf8))
    }

    public struct Malformed: Error, CustomStringConvertible {
        public let what: String
        public var description: String { "the shared record has no \(what)" }
    }
}
