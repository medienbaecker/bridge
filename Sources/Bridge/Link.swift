import AppKit
import Network
import CryptoKit
import BridgeCore
import BridgeShared

enum Wire {
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
    let identity = Identity.load()
    var peers: [Peer] = Peers.load()
    var sessions: [String: Session] = [:]
    var connecting: Set<String> = []
    var refused: Set<String> = []
    var seen: [Bonjour.Endpoint] = []
    var rebrowsing = false
    var onMessage: (Peer, [String: JSONValue]) -> Void = { _, _ in }
    var onChange: () -> Void = {}
    var onDrop: (Peer) -> Void = { _ in }
    var onConnect: (Peer) -> Void = { _ in }
    private var listener: Task<Void, Never>?
    private var browser: Task<Void, Never>?

    var key: Data { identity.publicKey.rawRepresentation }

    func start() {
        listen()
        browse()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self.map { $0.saw($0.seen) } }
        }
    }

    func listen() {
        listener?.cancel()
        var txt = NWTXTRecord()
        txt["id"] = me
        txt["name"] = Person.current
        txt["key"] = key.base64EncodedString()
        if !group.isEmpty { txt["group"] = group }
        let provider = BonjourListenerProvider(name: me, type: Self.service, txtRecord: txt)
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
            } catch {
                Env.log("link browser: \(error)")
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self?.browse() }
            }
        }
    }

    func attempt(_ id: String, _ work: @escaping () async -> Void) {
        connecting.insert(id)
        let task = Task {
            await work()
            connecting.remove(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.connecting.contains(id), self.sessions[id] == nil else { return }
            task.cancel()
            self.connecting.remove(id)
        }
    }

    func trust(_ id: String, name: String?, key: Data) -> Peer? {
        if let i = peers.firstIndex(where: { $0.id == id }) {
            guard peers[i].key == key else {
                if refused.insert(id).inserted { Env.log("link: \(peers[i].name) came back with another key; refused"); onChange() }
                return nil
            }
            if let name, peers[i].name != name { peers[i].name = name; try? Peers.save(peers); onChange() }
            return peers[i]
        }
        let peer = Peer(id: id, name: name ?? "Mac", key: key)
        peers.append(peer)
        try? Peers.save(peers)
        onChange()
        return peer
    }

    func saw(_ endpoints: [Bonjour.Endpoint]) {
        seen = endpoints
        if endpoints.contains(where: { $0.txtRecord["id"] == nil || $0.txtRecord["key"] == nil }), !rebrowsing {
            rebrowsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.rebrowsing = false
                self?.browser?.cancel()
                self?.browse()
            }
        }
        for endpoint in endpoints {
            guard let id = endpoint.txtRecord["id"], id != me, (endpoint.txtRecord["group"] ?? "") == group,
                  let key = endpoint.txtRecord["key"].flatMap({ Data(base64Encoded: $0) }), key.count == 32,
                  let peer = trust(id, name: endpoint.txtRecord["name"], key: key) else { continue }
            guard me < id, sessions[id] == nil, !connecting.contains(id) else { continue }
            attempt(id) { await self.open(Connection(to: endpoint) { TLV { TCP() } }, as: peer) }
        }
    }

    func accept(_ connection: Connection) async {
        do {
            let first = try await connection.receive()
            guard first.metadata.type == Wire.hello else { return }
            try await serve(connection, hello: first.content)
        } catch { Env.log("link accept: \(error)") }
    }

    func secret(_ peer: Peer) throws -> Data {
        try Identity.secret(identity, me: me, theirs: peer.key, them: peer.id)
    }

    func open(_ connection: Connection, as peer: Peer) async {
        do {
            let secret = try secret(peer)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let mine = Hello(id: me, key: ephemeral.publicKey.rawRepresentation, identity: key)
            try await connection.send(mine.data, type: Wire.hello)
            let reply = try await connection.receive()
            guard reply.metadata.type == Wire.hello, let theirs = Hello(reply.content), theirs.id == peer.id, theirs.identity == peer.key else { throw LinkError("link: not \(peer.name)") }
            let transcript = Handshake.transcript(client: mine, server: theirs)
            try await connection.send(Handshake.proof("client", transcript, secret: secret), type: Wire.proof)
            let proof = try await connection.receive()
            guard proof.metadata.type == Wire.proof, Handshake.verify(proof.content, role: "server", transcript, secret: secret) else { throw LinkError("link: \(peer.name) did not prove itself") }
            try await run(Session(peer: peer, connection: connection, channel: try Handshake.channel(ephemeral, theirs: theirs.key, transcript: transcript, secret: secret, client: true)))
        } catch { Env.log("link open \(peer.name): \(error)") }
    }

    func serve(_ connection: Connection, hello: Data) async throws {
        guard let theirs = Hello(hello), theirs.id != me else { throw LinkError("link: a hello that makes no sense") }
        guard let peer = trust(theirs.id, name: nil, key: theirs.identity) else { throw LinkError("link: refused a Mac whose key changed") }
        let secret = try secret(peer)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let mine = Hello(id: me, key: ephemeral.publicKey.rawRepresentation, identity: key)
        try await connection.send(mine.data, type: Wire.hello)
        let transcript = Handshake.transcript(client: theirs, server: mine)
        let proof = try await connection.receive()
        guard proof.metadata.type == Wire.proof, Handshake.verify(proof.content, role: "client", transcript, secret: secret) else { throw LinkError("link: \(peer.name) did not prove itself") }
        try await connection.send(Handshake.proof("server", transcript, secret: secret), type: Wire.proof)
        try await run(Session(peer: peer, connection: connection, channel: try Handshake.channel(ephemeral, theirs: theirs.key, transcript: transcript, secret: secret, client: false)))
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
            "peers": .array(peers.map { .string($0.name) }),
            "refused": .array(peers.filter { refused.contains($0.id) }.map { .string($0.name) }),
            "connected": .array(sessions.values.map { .string($0.peer.name) }.sorted { "\($0)" < "\($1)" }),
        ])
    }
}
