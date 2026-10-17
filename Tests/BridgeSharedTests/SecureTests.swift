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
    let secretA = try Identity.secret(a.key, me: a.id, theirs: b.pub, them: b.id)
    let secretB = try Identity.secret(b.key, me: b.id, theirs: a.pub, them: a.id)
    #expect(secretA == secretB)
    return (a, b, secretA)
}

func session(secret clientSecret: Data, _ serverSecret: Data) throws -> (Channel, Channel)? {
    let c = Side(), s = Side()
    let ch = Hello(id: c.id, key: c.pub, identity: Side().pub), sh = Hello(id: s.id, key: s.pub, identity: Side().pub)
    let t = Handshake.transcript(client: ch, server: sh)
    guard Handshake.verify(Handshake.proof("client", t, secret: clientSecret), role: "client", t, secret: serverSecret),
          Handshake.verify(Handshake.proof("server", t, secret: serverSecret), role: "server", t, secret: clientSecret) else { return nil }
    return (try Handshake.channel(c.key, theirs: s.pub, transcript: t, secret: clientSecret, client: true),
            try Handshake.channel(s.key, theirs: c.pub, transcript: t, secret: serverSecret, client: false))
}

@Test func aThirdMacCannotWorkOutTwoMacsSecret() throws {
    let (a, b, secret) = try paired()
    let c = Side()
    #expect(try Identity.secret(c.key, me: a.id, theirs: b.pub, them: b.id) != secret)
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
    let hello = Hello(id: UUID().uuidString, key: Side().pub, identity: Side().pub)
    #expect(Hello(hello.data) == hello)
    #expect(Hello(Data(count: 10)) == nil)
}
