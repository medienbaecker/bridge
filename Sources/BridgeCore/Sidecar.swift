import Foundation

public struct Say: Codable, Equatable, Sendable {
    public var by: String
    public var at: Date
    public var text: String
    public var kind: String

    public init(by: String, text: String, kind: String = "reply", at: Date = Date()) {
        self.by = by; self.text = text; self.kind = kind; self.at = at
    }
}

public struct Comment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var target: String
    public var state: String
    public var at: Date
    public var version: Int
    public var anchor: JSONValue
    public var said: [Say]
    public var lost: Bool?

    public init(id: String, text: String, target: String, anchor: JSONValue, version: Int, at: Date = Date()) {
        self.id = id; self.text = text; self.target = target; self.anchor = anchor
        self.version = version; self.at = at; self.state = "open"; self.said = []
    }
}

public struct Version: Codable, Equatable, Sendable {
    public var n: Int
    public var fingerprint: String
    public var at: Date
    public var answers: [String: JSONValue]
    public var sentAt: Date?
    public var questions: [String]
    public var defaults: [String]?

    public init(n: Int, fingerprint: String, at: Date, answers: [String: JSONValue], sentAt: Date?, questions: [String], defaults: [String]? = nil) {
        self.n = n; self.fingerprint = fingerprint; self.at = at
        self.answers = answers; self.sentAt = sentAt; self.questions = questions; self.defaults = defaults
    }
}

public struct Presentation: Codable, Equatable, Sendable {
    public var session: String
    public var at: Date
    public var cwd: String
    public var ground: Ground?

    public init(session: String, cwd: String, ground: Ground?, at: Date = Date()) {
        self.session = session; self.cwd = cwd; self.ground = ground; self.at = at
    }
}

public struct Sidecar: Codable, Equatable, Sendable {
    public var status: String = "open"
    public var version: Int = 1
    public var fingerprint: String?
    public var questions: [String] = []
    public var answers: [String: JSONValue] = [:]
    public var proposed: [String: JSONValue] = [:]
    public var sentAnswers: [String: JSONValue]?
    public var withdrawn: [String] = []
    public var sentAt: Date?
    public var closedAt: Date?
    public var collectedAt: Date?
    public var collectedBy: String?
    public var comments: [Comment] = []
    public var history: [Version] = []
    public var presented: Presentation?
    public var page: String?
    /// Fields this build does not know, carried through a save untouched.
    public var extra: [String: JSONValue] = [:]

    public init() {}

    public struct Unreadable: Error, CustomStringConvertible {
        public let url: URL
        public let reason: String
        public var description: String { "\(url.lastPathComponent) could not be read: \(reason)" }
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static func named(_ name: String) -> Key { Key(stringValue: name) }
    }

    private static let known: Set<String> = [
        "status", "version", "fingerprint", "questions", "answers", "defaults", "proposed", "sentAnswers", "withdrawn", "sentAt", "closedAt",
        "collectedAt", "collectedBy", "comments", "history", "presented", "page",
    ]

    // Forgiving in one direction only: a field that is missing takes its default,
    // a field this build does not know is kept, a field of the wrong shape fails
    // the whole decode so the file is refused rather than guessed at.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func field<T: Decodable>(_ name: String, or fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: .named(name)) ?? fallback
        }
        func optional<T: Decodable>(_ name: String) throws -> T? {
            try c.decodeIfPresent(T.self, forKey: .named(name))
        }
        status = try field("status", or: "open")
        version = try field("version", or: 1)
        fingerprint = try optional("fingerprint")
        questions = try field("questions", or: [])
        answers = try field("answers", or: [:])
        proposed = try field("proposed", or: [:])
        sentAnswers = try optional("sentAnswers")
        withdrawn = try field("withdrawn", or: [])
        let defaults: [String] = try field("defaults", or: [])
        for key in defaults { if let v = answers.removeValue(forKey: key) { proposed[key] = v } }
        sentAt = try optional("sentAt")
        closedAt = try optional("closedAt")
        collectedAt = try optional("collectedAt")
        collectedBy = try optional("collectedBy")
        comments = try field("comments", or: [])
        history = try field("history", or: [])
        presented = try optional("presented")
        page = try optional("page")
        for key in c.allKeys where !Self.known.contains(key.stringValue) {
            extra[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(status, forKey: .named("status"))
        try c.encode(version, forKey: .named("version"))
        try c.encodeIfPresent(fingerprint, forKey: .named("fingerprint"))
        try c.encode(questions, forKey: .named("questions"))
        try c.encode(answers, forKey: .named("answers"))
        if !proposed.isEmpty { try c.encode(proposed, forKey: .named("proposed")) }
        try c.encodeIfPresent(sentAnswers, forKey: .named("sentAnswers"))
        if !withdrawn.isEmpty { try c.encode(withdrawn, forKey: .named("withdrawn")) }
        try c.encodeIfPresent(sentAt, forKey: .named("sentAt"))
        try c.encodeIfPresent(closedAt, forKey: .named("closedAt"))
        try c.encodeIfPresent(collectedAt, forKey: .named("collectedAt"))
        try c.encodeIfPresent(collectedBy, forKey: .named("collectedBy"))
        try c.encode(comments, forKey: .named("comments"))
        try c.encode(history, forKey: .named("history"))
        try c.encodeIfPresent(presented, forKey: .named("presented"))
        try c.encodeIfPresent(page, forKey: .named("page"))
        for (key, value) in extra { try c.encode(value, forKey: .named(key)) }
    }

    /// A missing file is a fresh record; a file that is there but cannot be
    /// decoded is refused, so that nothing downstream writes over it.
    public static func load(_ url: URL) throws -> Sidecar {
        guard FileManager.default.fileExists(atPath: url.path) else { return Sidecar() }
        do {
            return try JSON.decoder.decode(Sidecar.self, from: try Data(contentsOf: url))
        } catch {
            throw Unreadable(url: url, reason: "\(error)")
        }
    }

    /// For a glance at the status where refusing would be noise (the sidebar); never before a write.
    public static func peek(_ url: URL) -> Sidecar { (try? load(url)) ?? Sidecar() }

    public func data() -> Data {
        (try? JSON.encoder.encode(self)) ?? Data()
    }

    public func save(_ url: URL) throws {
        try data().write(to: url, options: .atomic)
    }

    public static func modify(_ url: URL, _ change: (inout Sidecar) -> Void) throws {
        let lock = FileLock(url.appendingPathExtension("lock"))
        lock.acquire()
        defer { lock.release() }
        var s = try load(url)
        change(&s)
        try s.save(url)
    }

    public var openComments: [Comment] { comments.filter { $0.state != "done" } }

    public var answered: Bool { status == "sent" || status == "closed" }

    public var defaults: [String: JSONValue] { proposed.filter { answers[$0.key] == nil } }

    public static func own(_ v: Version) -> [String: JSONValue] { v.answers.filter { !(v.defaults ?? []).contains($0.key) } }
    public var stale: Bool { (sentAt ?? closedAt).map { Date().timeIntervalSince($0) > 2 * 3600 } ?? false }

    /// A note or a Send after the agent collected makes the bridge collectable
    /// again, so nothing the user writes goes undelivered.
    public var changedSinceCollected: Bool {
        guard let at = collectedAt else { return true }
        if let sent = sentAt, sent > at { return true }
        return comments.contains { c in c.at > at || c.said.contains { $0.by != "agent" && $0.at > at } }
    }

    public func collectable(by session: String) -> Bool {
        guard answered, changedSinceCollected else { return false }
        return presented?.session == session || stale
    }
}

public final class FileLock {
    let fd: Int32

    public init(_ url: URL) {
        fd = open(url.path, O_CREAT | O_RDWR, 0o644)
    }

    public func acquire() { if fd >= 0 { flock(fd, LOCK_EX) } }
    public func release() { if fd >= 0 { flock(fd, LOCK_UN) } }
    deinit { if fd >= 0 { close(fd) } }
}
