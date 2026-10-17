import Foundation
import Testing
import BridgeCore
@testable import BridgeShared

func pair() throws -> (SharedRecord, SharedRecord) {
    let thomas = try SharedRecord(person: "thomas")
    let yoshie = try SharedRecord(bytes: thomas.save(), person: "yoshie")
    return (thomas, yoshie)
}

func meet(_ a: SharedRecord, _ b: SharedRecord) throws {
    try a.merge(b)
    try b.merge(a)
}

@Test func picksMadeApartKeepBothPeople() throws {
    let (thomas, yoshie) = try pair()
    try thomas.pick("layout", .string("grid"))
    try yoshie.pick("layout", .string("list"))
    try yoshie.pick("radius", .number(12))
    try meet(thomas, yoshie)

    var mine = Sidecar(), hers = Sidecar()
    try thomas.project(into: &mine)
    try yoshie.project(into: &hers)
    #expect(mine.answers == ["layout": .string("grid")])
    #expect(hers.answers == ["layout": .string("list"), "radius": .number(12)])
    #expect(mine.people == hers.people)
    #expect(mine.people["yoshie"]?["radius"] == .number(12))
}

@Test func aClearedPickIsGoneOnBothMacs() throws {
    let (thomas, yoshie) = try pair()
    try thomas.pick("layout", .string("grid"))
    try meet(thomas, yoshie)
    try thomas.clear("layout")
    try meet(thomas, yoshie)
    #expect(try yoshie.people["thomas"]?["layout"] == nil)
}

@Test func notesAndRepliesFromBothMacsMerge() throws {
    let (thomas, yoshie) = try pair()
    try thomas.add(Comment(id: "n1", text: "header too tall", target: "h1", anchor: .null, version: 1, at: Date(timeIntervalSince1970: 1), person: "thomas"))
    try meet(thomas, yoshie)
    try thomas.reply(to: "n1", Say(by: "agent", text: "shortened", person: "thomas"))
    try yoshie.reply(to: "n1", Say(by: "user", text: "still tall here", person: "yoshie"))
    try yoshie.add(Comment(id: "n2", text: "footer colour", target: "footer", anchor: .null, version: 1, at: Date(timeIntervalSince1970: 2), person: "yoshie"))
    try meet(thomas, yoshie)

    let notes = try thomas.comments
    #expect(notes.map(\.id) == ["n1", "n2"])
    #expect(notes[0].person == "thomas")
    #expect(Set(notes[0].said.map(\.text)) == ["shortened", "still tall here"])
    #expect(notes[1].person == "yoshie")
    #expect(try yoshie.comments == notes)
}

@Test func aNoteStateSetOnEitherMacArrivesOnTheOther() throws {
    let (thomas, yoshie) = try pair()
    try thomas.add(Comment(id: "n1", text: "x", target: "p", anchor: .null, version: 1, person: "thomas"))
    try meet(thomas, yoshie)
    try yoshie.setState("n1", "done")
    try meet(thomas, yoshie)
    #expect(try thomas.comments.first?.state == "done")
}

@Test func aRecordSurvivesSaveAndLoad() throws {
    let (thomas, _) = try pair()
    try thomas.pick("layout", .object(["columns": .number(3)]))
    let again = try SharedRecord(bytes: thomas.save(), person: "thomas")
    #expect(try again.people["thomas"]?["layout"] == .object(["columns": .number(3)]))
}
