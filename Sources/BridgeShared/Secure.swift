import Foundation
import CryptoKit
import BridgeCore

public struct Peer: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var secret: Data
    public var pairedAt: Date

    public init(id: String, name: String, secret: Data, pairedAt: Date = Date()) {
        self.id = id; self.name = name; self.secret = secret; self.pairedAt = pairedAt
    }
}

public enum Pairing {
    public static func commitment(_ key: Data) -> Data { Data(SHA256.hash(data: key)) }

    public static func transcript(initiator: String, _ initiatorKey: Data, responder: String, _ responderKey: Data) -> Data {
        Data(SHA256.hash(data: Data("bridge-pair-v1".utf8) + Data(initiator.utf8) + Data(responder.utf8) + initiatorKey + responderKey))
    }

    public static func words(_ transcript: Data) -> [String] {
        transcript.prefix(4).map { pairingWords[Int($0)] }
    }

    public static func secret(_ mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, transcript: Data) throws -> Data {
        let shared = try mine.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: theirs))
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("bridge pairing secret v1".utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }
}

public struct Hello: Equatable, Sendable {
    public var id: String
    public var key: Data
    public var nonce: Data

    public static let size = 36 + 32 + 16

    public init(id: String, key: Data, nonce: Data = Data((0..<16).map { _ in UInt8.random(in: 0...255) })) {
        self.id = id; self.key = key; self.nonce = nonce
    }

    public init?(_ data: Data) {
        guard data.count == Self.size else { return nil }
        let bytes = Data(data)
        id = String(decoding: bytes.prefix(36), as: UTF8.self)
        key = bytes.subdata(in: 36..<68)
        nonce = bytes.subdata(in: 68..<84)
    }

    public var data: Data { Data(id.utf8).prefix(36) + key + nonce }
}

public enum Handshake {
    public static func transcript(client: Hello, server: Hello) -> Data {
        Data("bridge-link-v1".utf8) + client.data + server.data
    }

    public static func proof(_ role: String, _ transcript: Data, secret: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(role.utf8) + transcript, using: SymmetricKey(data: secret)))
    }

    public static func verify(_ proof: Data, role: String, _ transcript: Data, secret: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Data(role.utf8) + transcript, using: SymmetricKey(data: secret))
    }

    public static func channel(_ mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, transcript: Data, secret: Data, client: Bool) throws -> Channel {
        let shared = try mine.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: theirs))
        let salt = Data(HMAC<SHA256>.authenticationCode(for: transcript, using: SymmetricKey(data: secret)))
        let up = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("client to server".utf8), outputByteCount: 32)
        let down = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("server to client".utf8), outputByteCount: 32)
        return client ? Channel(send: up, receive: down) : Channel(send: down, receive: up)
    }
}

public struct Channel: Sendable {
    let sendKey: SymmetricKey
    let receiveKey: SymmetricKey
    var sent: UInt64 = 0
    var received: UInt64 = 0

    init(send: SymmetricKey, receive: SymmetricKey) { sendKey = send; receiveKey = receive }

    static func nonce(_ n: UInt64) -> ChaChaPoly.Nonce {
        try! ChaChaPoly.Nonce(data: Data(count: 4) + withUnsafeBytes(of: n.bigEndian) { Data($0) })
    }

    public mutating func seal(_ data: Data, type: Int) throws -> Data {
        let box = try ChaChaPoly.seal(data, using: sendKey, nonce: Self.nonce(sent), authenticating: Data(String(type).utf8))
        sent += 1
        return Data(box.ciphertext) + box.tag
    }

    public mutating func open(_ data: Data, type: Int) throws -> Data {
        guard data.count >= 16 else { throw CryptoKitError.authenticationFailure }
        let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(received), ciphertext: data.dropLast(16), tag: data.suffix(16))
        let plain = try ChaChaPoly.open(box, using: receiveKey, authenticating: Data(String(type).utf8))
        received += 1
        return plain
    }
}

public enum Peers {
    public static var file: URL { Paths.stateDir.appendingPathComponent("peers.json") }

    public static func load() -> [Peer] {
        (try? Data(contentsOf: file)).flatMap { try? JSON.decoder.decode([Peer].self, from: $0) } ?? []
    }

    public static func save(_ peers: [Peer]) throws {
        try JSON.encoder.encode(peers).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
