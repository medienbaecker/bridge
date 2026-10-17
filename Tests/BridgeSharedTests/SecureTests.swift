import Foundation
import Testing
import CryptoKit
@testable import BridgeShared

struct Side {
    let id = UUID().uuidString
    let key = Curve25519.KeyAgreement.PrivateKey()
    var pub: Data { key.publicKey.rawRepresentation }
}

func paired() throws -> (Side, Side, Data) {
    let a = Side(), b = Side()
    let t = Pairing.transcript(initiator: a.id, a.pub, responder: b.id, b.pub)
    let secretA = try Pairing.secret(a.key, theirs: b.pub, transcript: t)
    let secretB = try Pairing.secret(b.key, theirs: a.pub, transcript: t)
    #expect(secretA == secretB)
    return (a, b, secretA)
}

func session(secret clientSecret: Data, _ serverSecret: Data) throws -> (Channel, Channel)? {
    let c = Side(), s = Side()
    let ch = Hello(id: c.id, key: c.pub), sh = Hello(id: s.id, key: s.pub)
    let t = Handshake.transcript(client: ch, server: sh)
    guard Handshake.verify(Handshake.proof("client", t, secret: clientSecret), role: "client", t, secret: serverSecret),
          Handshake.verify(Handshake.proof("server", t, secret: serverSecret), role: "server", t, secret: clientSecret) else { return nil }
    return (try Handshake.channel(c.key, theirs: s.pub, transcript: t, secret: clientSecret, client: true),
            try Handshake.channel(s.key, theirs: c.pub, transcript: t, secret: serverSecret, client: false))
}

@Test func bothMacsSeeTheSameFourWords() throws {
    let a = Side(), b = Side()
    let words = Pairing.words(Pairing.transcript(initiator: a.id, a.pub, responder: b.id, b.pub))
    #expect(words.count == 4)
    #expect(words == Pairing.words(Pairing.transcript(initiator: a.id, a.pub, responder: b.id, b.pub)))
    #expect(Pairing.commitment(a.pub) != Pairing.commitment(b.pub))
}

@Test func aSessionCarriesMessagesBothWays() throws {
    let (_, _, secret) = try paired()
    var (client, server) = try #require(try session(secret: secret, secret))
    let up = try client.seal(Data("cursor".utf8), type: 3)
    #expect(try server.open(up, type: 3) == Data("cursor".utf8))
    let down = try server.seal(Data(count: 3_000_000), type: 4)
    #expect(try client.open(down, type: 4).count == 3_000_000)
}

@Test func aMacWithTheWrongSecretIsRefused() throws {
    let (_, _, secret) = try paired()
    let (_, _, other) = try paired()
    #expect(try session(secret: secret, other) == nil)
}

@Test func aTamperedReplayedOrRetypedMessageIsRefused() throws {
    let (_, _, secret) = try paired()
    var (client, server) = try #require(try session(secret: secret, secret))
    var sealed = try client.seal(Data("pick grid".utf8), type: 1)
    var flipped = sealed
    flipped[0] ^= 1
    #expect(throws: (any Error).self) { try server.open(flipped, type: 1) }
    #expect(throws: (any Error).self) { try server.open(sealed, type: 2) }
    #expect(try server.open(sealed, type: 1) == Data("pick grid".utf8))
    #expect(throws: (any Error).self) { try server.open(sealed, type: 1) }
    sealed = try client.seal(Data("next".utf8), type: 1)
    #expect(try server.open(sealed, type: 1) == Data("next".utf8))
}

@Test func aHelloRoundTrips() throws {
    let hello = Hello(id: UUID().uuidString, key: Side().pub)
    #expect(Hello(hello.data) == hello)
    #expect(Hello(Data(count: 10)) == nil)
}
