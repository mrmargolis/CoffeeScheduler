import Foundation
import Testing

@testable import CoffeeCore

private func storeWithBean() throws -> CoffeeStore {
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))
    return store
}

private func cup(_ id: String, at timestamp: Double = 100, flavours: [String] = []) -> CupEvaluation {
    CupEvaluation(id: id, beanID: "uuid-1", timestamp: timestamp, date: "2024-02-01", flavours: flavours)
}

@Suite struct EvaluationTagTests {
    @Test func tagsAndNotesRoundTripWithTheirSource() throws {
        let store = try storeWithBean()
        var evaluation = cup("e1", flavours: ["stone fruit", "jasmine"])
        evaluation.character = [.sharp: .user, .muddy: .model]
        evaluation.notes = "Some sweet but short linger"
        try store.saveEvaluation(evaluation)

        #expect(try store.evaluations(beanID: "uuid-1") == [evaluation])
    }

    @Test func flavoursAreTrimmedDedupedAndBlankDropped() throws {
        let store = try storeWithBean()
        try store.saveEvaluation(cup("e1", flavours: [" Stone fruit ", "stone fruit", "", "  ", "Cocoa"]))
        #expect(try store.evaluations(beanID: "uuid-1").first?.flavours == ["Stone fruit", "Cocoa"])
    }

    @Test func blankNotesAreNone() throws {
        let store = try storeWithBean()
        var evaluation = cup("e1")
        evaluation.notes = "  \n "
        try store.saveEvaluation(evaluation)
        let saved = try #require(try store.evaluations(beanID: "uuid-1").first)
        #expect(saved.notes == nil)
        #expect(saved.character.isEmpty)
        #expect(saved.flavours.isEmpty)
    }

    @Test func usedFlavoursMostUsedFirstThenAlphabetical() throws {
        let store = try storeWithBean()
        try store.saveEvaluation(cup("e1", at: 1, flavours: ["Stone fruit", "jasmine"]))
        try store.saveEvaluation(cup("e2", at: 2, flavours: ["stone fruit", "Cocoa"]))
        try store.saveEvaluation(cup("e3", at: 3, flavours: ["Bergamot"]))

        #expect(try store.usedFlavours() == ["Stone fruit", "Bergamot", "Cocoa", "jasmine"])
    }

    @Test func unknownCharacterTagsInTheFileAreIgnored() {
        #expect(EvaluationTags.character(fromJSON: #"{"sharp":"user","papery":"user","bitter":"robot"}"#) == [.sharp: .user, .bitter: .user])
        #expect(EvaluationTags.character(fromJSON: "not json").isEmpty)
    }
}
