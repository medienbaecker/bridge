import AppKit
import Network
import CryptoKit
import BridgeCore
import BridgeShared

enum Wire {
    static let pairHello = 1, pairCommit = 2, pairKey = 3, pairConfirm = 4
    static let hello = 10, proof = 11
    static let sealed = 20
}

typealias Connection = NetworkConnection<TLV>

struct LinkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class Session {
    let peer: Peer
    let connection: Connection
    var channel: Channel
    var queue: [Data] = []
    var sending = false

    init(peer: Peer, connection: Connection, channel: Channel) {
        self.peer = peer; self.connection = connection; self.channel = channel
    }

    func send(_ message: [String: JSONValue]) {
        guard let data = try? JSON.compact.encode(message) else { return }
        queue.append(data)
        guard !sending else { return }
        sending = true
        Task { @MainActor in
            while !queue.isEmpty {
                let plain = queue.removeFirst()
                guard let sealed = try? channel.seal(plain, type: Wire.sealed) else { continue }
                do { try await connection.send(sealed, type: Wire.sealed) } catch { queue.removeAll(); break }
            }
            sending = false
        }
    }
}

final class Link {
    static let service = "_bridge._tcp"

    let me = Person.device
    let group = ProcessInfo.processInfo.environment["BRIDGE_LINK_GROUP"] ?? ""
    var peers: [Peer] = Peers.load()
    var sessions: [String: Session] = [:]
    var connecting: Set<String> = []
    var nearby: [String: Bonjour.Endpoint] = [:]
    var seen: [Bonjour.Endpoint] = []
    var pairingUntil: Date?
    var pairingWith: String?
    var words: [String]?
    var confirm: CheckedContinuation<Bool, Never>?
    var onMessage: (Peer, [String: JSONValue]) -> Void = { _, _ in }
    var onChange: () -> Void = {}
    var onDrop: (Peer) -> Void = { _ in }
    var onConnect: (Peer) -> Void = { _ in }
    var onWords: (String, [String]) -> Void = { _, _ in }
    private var listener: Task<Void, Never>?
    private var browser: Task<Void, Never>?

    var pairing: Bool { pairingUntil.map { $0 > Date() } ?? false }

    func start() {
        listen()
        browse()
    }

    func listen() {
        listener?.cancel()
        var txt = NWTXTRecord()
        txt["id"] = me
        txt["name"] = Person.current
        if !group.isEmpty { txt["group"] = group }
        let provider = BonjourListenerProvider(name: Person.current, type: Self.service, txtRecord: txt)
        listener = Task { [weak self] in
            do {
                let listener = try NetworkListener(for: provider) { TLV { TCP() } }
                try await listener.run { connection in
                    await self?.accept(connection)
                }
            } catch { Env.log("link listener: \(error)") }
        }
    }

    func browse() {
        browser = Task { [weak self] in
            let browser = NetworkBrowser(for: .bonjour(Self.service, includeTxtRecord: true))
            do {
                let _: Bonjour.Endpoint = try await browser.run { endpoints in
                    Task { @MainActor in self?.saw(endpoints) }
                    return .continue
                }
            } catch { Env.log("link browser: \(error)") }
        }
    }

    func attempt(_ id: String, _ work: @escaping () async -> Void) {
        connecting.insert(id)
        let task = Task {
            await work()
            connecting.remove(id)
            if sessions[id] == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self.map { $0.saw($0.seen) } } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.connecting.contains(id), self.sessions[id] == nil, self.words == nil else { return }
            task.cancel()
            self.connecting.remove(id)
            if self.pairingWith != nil, self.words == nil { self.pairingWith = nil }
            self.saw(self.seen)
        }
    }

    func saw(_ endpoints: [Bonjour.Endpoint]) {
        seen = endpoints
        let unpaired = endpoints.filter { e in
            guard let id = e.txtRecord["id"], id != me, (e.txtRecord["group"] ?? "") == group else { return false }
            return !peers.contains { $0.id == id }
        }
        let now = Dictionary(unpaired.map { ($0.txtRecord["id"]!, $0) }, uniquingKeysWith: { a, _ in a })
        if Set(now.keys) != Set(nearby.keys) { nearby = now; onChange() } else { nearby = now }
        for endpoint in endpoints {
            guard let id = endpoint.txtRecord["id"], id != me, me < id, !connecting.contains(id), (endpoint.txtRecord["group"] ?? "") == group else { continue }
            if pairing, pairingWith == nil, !peers.contains(where: { $0.id == id }) {
                attempt(id) { await self.pair(Connection(to: endpoint) { TLV { TCP() } }, initiator: true) }
            } else if let peer = peers.first(where: { $0.id == id }), sessions[id] == nil {
                attempt(id) { await self.open(Connection(to: endpoint) { TLV { TCP() } }, as: peer) }
            }
        }
    }

    func accept(_ connection: Connection) async {
        do {
            let first = try await connection.receive()
            switch first.metadata.type {
            case Wire.pairHello where pairingWith == nil:
                await pair(connection, initiator: false, hello: first.content)
            case Wire.hello:
                try await serve(connection, hello: first.content)
            default:
                break
            }
        } catch { Env.log("link accept: \(error)") }
    }

    // MARK: Pairing

    func startPairing(for seconds: TimeInterval = 120) {
        pairingUntil = Date().addingTimeInterval(seconds)
        onChange()
        saw(seen)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.onChange() }
    }

    var nearbyNames: [String] { nearby.values.compactMap { $0.txtRecord["name"] }.sorted() }

    func pair(with name: String) {
        guard pairingWith == nil, let (id, endpoint) = nearby.first(where: { $0.value.txtRecord["name"] == name }), !connecting.contains(id) else { return }
        pairingWith = name
        attempt(id) { await self.pair(Connection(to: endpoint) { TLV { TCP() } }, initiator: true) }
    }

    func answer(_ yes: Bool) {
        confirm?.resume(returning: yes)
        confirm = nil
    }

    func pair(_ connection: Connection, initiator: Bool, hello: Data? = nil) async {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let pub = key.publicKey.rawRepresentation
        func expect(_ type: Int) async throws -> Data {
            let message = try await connection.receive()
            guard message.metadata.type == type else { throw LinkError("pairing: expected \(type), got \(message.metadata.type)") }
            return message.content
        }
        do {
            let mine = try JSON.compact.encode(["id": me, "name": Person.current])
            if initiator { try await connection.send(mine, type: Wire.pairHello) }
            var first = hello
            if first == nil { first = try await expect(Wire.pairHello) }
            let theirs = try JSON.decoder.decode([String: String].self, from: first ?? Data())
            if !initiator { try await connection.send(mine, type: Wire.pairHello) }
            guard let id = theirs["id"], let name = theirs["name"] else { throw LinkError("pairing: no id") }
            pairingWith = name
            let peerKey: Data
            if initiator {
                try await connection.send(Pairing.commitment(pub), type: Wire.pairCommit)
                peerKey = try await expect(Wire.pairKey)
                try await connection.send(pub, type: Wire.pairKey)
            } else {
                let commitment = try await expect(Wire.pairCommit)
                try await connection.send(pub, type: Wire.pairKey)
                peerKey = try await expect(Wire.pairKey)
                guard Pairing.commitment(peerKey) == commitment else { throw LinkError("pairing: commitment mismatch") }
            }
            let transcript = initiator ? Pairing.transcript(initiator: me, pub, responder: id, peerKey) : Pairing.transcript(initiator: id, peerKey, responder: me, pub)
            words = Pairing.words(transcript)
            onChange()
            onWords(name, words ?? [])
            let yes = await withCheckedContinuation { confirm = $0 }
            guard yes else { throw LinkError("pairing: declined here") }
            try await connection.send(transcript, type: Wire.pairConfirm)
            guard try await expect(Wire.pairConfirm) == transcript else { throw LinkError("pairing: declined there") }
            let peer = Peer(id: id, name: name, secret: try Pairing.secret(key, theirs: peerKey, transcript: transcript))
            peers.removeAll { $0.id == id }
            peers.append(peer)
            try Peers.save(peers)
            pairingUntil = nil
        } catch { Env.log("\(error)") }
        answer(false)
        pairingWith = nil
        words = nil
        onChange()
    }

    // MARK: Sessions

    func open(_ connection: Connection, as peer: Peer) async {
        do {
            let key = Curve25519.KeyAgreement.PrivateKey()
            let mine = Hello(id: me, key: key.publicKey.rawRepresentation)
            try await connection.send(mine.data, type: Wire.hello)
            let reply = try await connection.receive()
            guard reply.metadata.type == Wire.hello, let theirs = Hello(reply.content), theirs.id == peer.id else { throw LinkError("link: not \(peer.name)") }
            let transcript = Handshake.transcript(client: mine, server: theirs)
            try await connection.send(Handshake.proof("client", transcript, secret: peer.secret), type: Wire.proof)
            let proof = try await connection.receive()
            guard proof.metadata.type == Wire.proof, Handshake.verify(proof.content, role: "server", transcript, secret: peer.secret) else { throw LinkError("link: \(peer.name) did not prove itself") }
            try await run(Session(peer: peer, connection: connection, channel: try Handshake.channel(key, theirs: theirs.key, transcript: transcript, secret: peer.secret, client: true)))
        } catch { Env.log("link open \(peer.name): \(error)") }
    }

    func serve(_ connection: Connection, hello: Data) async throws {
        guard let theirs = Hello(hello), let peer = peers.first(where: { $0.id == theirs.id }) else { throw LinkError("link: unknown Mac") }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let mine = Hello(id: me, key: key.publicKey.rawRepresentation)
        try await connection.send(mine.data, type: Wire.hello)
        let transcript = Handshake.transcript(client: theirs, server: mine)
        let proof = try await connection.receive()
        guard proof.metadata.type == Wire.proof, Handshake.verify(proof.content, role: "client", transcript, secret: peer.secret) else { throw LinkError("link: \(peer.name) did not prove itself") }
        try await connection.send(Handshake.proof("server", transcript, secret: peer.secret), type: Wire.proof)
        try await run(Session(peer: peer, connection: connection, channel: try Handshake.channel(key, theirs: theirs.key, transcript: transcript, secret: peer.secret, client: false)))
    }

    func run(_ session: Session) async throws {
        sessions[session.peer.id] = session
        onConnect(session.peer)
        onChange()
        defer {
            if sessions[session.peer.id] === session { sessions[session.peer.id] = nil }
            onDrop(session.peer)
            onChange()
        }
        while true {
            let message = try await session.connection.receive()
            guard message.metadata.type == Wire.sealed else { continue }
            let plain = try session.channel.open(message.content, type: Wire.sealed)
            if let object = try? JSON.decoder.decode([String: JSONValue].self, from: plain) { onMessage(session.peer, object) }
        }
    }

    func send(_ message: [String: JSONValue]) {
        for session in sessions.values { session.send(message) }
    }

    var state: JSONValue {
        .object([
            "device": .string(me),
            "pairing": .bool(pairing),
            "pairingWith": pairingWith.map { .string($0) } ?? .null,
            "words": words.map { .array($0.map { .string($0) }) } ?? .null,
            "peers": .array(peers.map { .string($0.name) }),
            "nearby": .array(nearbyNames.map { .string($0) }),
            "connected": .array(sessions.values.map { .string($0.peer.name) }.sorted { "\($0)" < "\($1)" }),
        ])
    }
}
