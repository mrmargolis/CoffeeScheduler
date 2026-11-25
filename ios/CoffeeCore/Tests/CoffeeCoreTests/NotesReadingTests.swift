import Foundation
import Testing

@testable import CoffeeCore

/// Answers with a fixed reading, as the on-device model would.
private struct FakeReader: NotesReader {
    var reading: NotesReading?
    func read(_ notes: String) async -> NotesReading? { reading }
}

private func cup(character: [CharacterTag: TagSource] = [:], flavours: [String] = []) -> CupEvaluation {
    CupEvaluation(beanID: "b", timestamp: 1, date: "2026-10-12", character: character, flavours: flavours, notes: "Sour. Peach.")
}

/// Read `cup`'s notes with `reader` and take the proposals.
private func propose(
    _ reader: FakeReader, to cup: inout CupEvaluation, rejected: Set<CharacterTag> = [], rejectedFlavours: Set<String> = []
) async -> [String] {
    guard let notes = cup.notes, let reading = await reader.read(notes) else { return [] }
    return cup.takeProposals(reading, rejected: rejected, rejectedFlavours: rejectedFlavours)
}

@Suite struct NotesProposalTests {
    @Test func proposalsAreMarkedAsTheModels() async {
        var cup = cup()
        let flavours = await propose(FakeReader(reading: NotesReading(character: [.sharp], flavours: ["peach"])), to: &cup)
        #expect(cup.character == [.sharp: .model])
        #expect(flavours == ["peach"])
        #expect(cup.flavours.isEmpty)
    }

    @Test func tagsTheDrinkerSetSurvive() async {
        var cup = cup(character: [.bitter: .user, .muddy: .user])
        _ = await propose(FakeReader(reading: NotesReading(character: [.sharp])), to: &cup)
        #expect(cup.character == [.bitter: .user, .muddy: .user, .sharp: .model])
    }

    @Test func aTagTheDrinkerSetStaysTheirsWhenAlsoProposed() async {
        var cup = cup(character: [.sharp: .user])
        _ = await propose(FakeReader(reading: NotesReading(character: [.sharp])), to: &cup)
        #expect(cup.character == [.sharp: .user])
    }

    @Test func aNewReadingReplacesTheModelsEarlierTags() async {
        var cup = cup(character: [.muddy: .model, .bitter: .user])
        _ = await propose(FakeReader(reading: NotesReading(character: [.sharp])), to: &cup)
        #expect(cup.character == [.bitter: .user, .sharp: .model])
    }

    @Test func acceptingMakesATagTheDrinkers() async {
        var cup = cup()
        _ = await propose(FakeReader(reading: NotesReading(character: [.sharp, .heavy])), to: &cup)
        cup.accept(.sharp)
        cup.accept(.bitter)  // not on the cup: nothing to accept
        #expect(cup.character == [.sharp: .user, .heavy: .model])
    }

    @Test func rejectedProposalsArentOfferedAgain() async {
        var cup = cup()
        let reader = FakeReader(reading: NotesReading(character: [.sharp, .muddy], flavours: ["peach", "jasmine"]))
        let flavours = await propose(reader, to: &cup, rejected: [.sharp], rejectedFlavours: ["peach"])
        #expect(cup.character == [.muddy: .model])
        #expect(flavours == ["jasmine"])
    }

    @Test func flavoursAlreadyOnTheCupArentOffered() async {
        var cup = cup(flavours: ["Peach"])
        let flavours = await propose(FakeReader(reading: NotesReading(flavours: ["peach", "honey"])), to: &cup)
        #expect(flavours == ["honey"])
    }

    @Test func noReadingChangesNothing() async {
        var cup = cup(character: [.bitter: .model])
        let flavours = await propose(FakeReader(reading: nil), to: &cup)
        #expect(cup.character == [.bitter: .model])
        #expect(flavours.isEmpty)
    }
}

@Suite struct NotesAnswerTests {
    @Test func readsBothLines() {
        let reading = NotesPrompt.reading(fromAnswer: "character: sharp, bitter\nflavours: Peach, pink flowers")
        #expect(reading == NotesReading(character: [.sharp, .bitter], flavours: ["peach", "pink flowers"]))
    }

    @Test func noneIsEmpty() {
        #expect(NotesPrompt.reading(fromAnswer: "character: none\nflavours: none") == NotesReading())
    }

    @Test func leniencyAboutCaseOrderAndDecoration() {
        let reading = NotesPrompt.reading(fromAnswer: "Here you go.\nFlavors: \"cherry\", cherry, honey.\n**Character:** Muddy, smoky")
        #expect(reading == NotesReading(character: [.muddy], flavours: ["cherry", "honey"]))
    }

    @Test func longPhrasesAndCharacterWordsArentFlavours() {
        let reading = NotesPrompt.reading(fromAnswer: "flavours: bitter, peach, a sweet thing on the tail end")
        #expect(reading.flavours == ["peach"])
    }

    @Test func atMostSixFlavours() {
        let reading = NotesPrompt.reading(fromAnswer: "flavours: a, b, c, d, e, f, g")
        #expect(reading.flavours.count == 6)
    }

    @Test func thePromptCarriesTheNotes() {
        #expect(NotesPrompt.prompt(for: "50/150/240\nSour. Try finer.").hasSuffix("Notes:\n50/150/240\nSour. Try finer."))
    }
}
