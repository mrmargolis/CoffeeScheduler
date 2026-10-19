import Testing

@testable import CoffeeCore

@Suite struct BagDraftTests {
    /// A draft with the values given, each as sure as `certainty`.
    private func draft(
        _ certainty: Certainty, coffee: String = "", roaster: String = "", process: String = "", weight: Int? = nil
    ) -> BagDraft {
        var draft = BagDraft()
        draft.coffee = coffee
        draft.roaster = roaster
        draft.process = process
        draft.weightGrams = weight
        for field in BagField.allCases where draft.has(field) {
            draft.certainty[field] = certainty
        }
        return draft
    }

    @Test func fillsWhatsEmptyFromAnything() {
        let merged = draft(.stated, coffee: "Hanan Million").merging(draft(.guessed, roaster: "September", weight: 250))
        #expect([merged.coffee, merged.roaster] == ["Hanan Million", "September"])
        #expect(merged.weightGrams == 250)
    }

    @Test func aStatedValueReplacesAGuess() {
        // A photo's guesses, then the roaster's page
        let photo = draft(.guessed, coffee: "ETHIOPIA", roaster: "Proud Mary", process: "Natural")
        let page = draft(.stated, coffee: "Abana Estate", process: "Washed")
        let merged = photo.merging(page)
        #expect(merged.coffee == "Abana Estate")
        #expect(merged.process == "Washed")
        #expect(merged.roaster == "Proud Mary")  // The page had none: a blank doesn't clear it
        #expect(merged.certainty[.coffee] == .stated)
    }

    @Test func aGuessNeverReplacesAValue() {
        let merged = draft(.guessed, coffee: "Hanan Million").merging(draft(.guessed, coffee: "Brewing guide"))
        #expect(merged.coffee == "Hanan Million")
        let stated = draft(.stated, process: "Washed").merging(draft(.guessed, process: "Natural"))
        #expect(stated.process == "Washed")
    }

    @Test func aLaterStatedValueReplacesAnEarlierOne() {
        let merged = draft(.stated, process: "Washed").merging(draft(.stated, process: "Anaerobic Washed"))
        #expect(merged.process == "Anaerobic Washed")
    }

    @Test func nothingReplacesWhatsTyped() {
        var typed = BagDraft()
        typed.type("Final Frontier", in: .coffee)
        let merged = typed.merging(draft(.stated, coffee: "Honduras Nahun Fernandez"))
        #expect(merged.coffee == "Final Frontier")
        #expect(merged.certainty[.coffee] == .typed)
    }

    @Test func countsWhatAMergeFilledAndReplaced() {
        let before = draft(.guessed, coffee: "ETHIOPIA", process: "Natural")
        let after = before.merging(draft(.stated, coffee: "Abana Estate", roaster: "Proud Mary", process: "Natural"))
        #expect(before.changes(to: after) == (filled: 1, replaced: 1))  // The same process isn't a change
    }

    @Test func aKnownRoasterIsStated() {
        var draft = BagDraft()
        draft.take(BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia"), knownRoasters: ["Onyx Coffee Lab"])
        #expect(draft.certainty[.roaster] == .stated)
        #expect(draft.certainty[.coffee] == nil)
    }

    @Test func aLabelledValueIsStatedAndARecognisedOneGuessed() {
        let lines = ["Hanan Million", "Process: Natural", "Ethiopia"].enumerated().map {
            BagLabel.Line($1, x: 0.1, y: 0.9 - Double($0) * 0.1, width: 0.5, height: 0.02)
        }
        let details = BagLabel.details(in: lines, today: "2026-10-19")
        #expect(details.certainty[.process] == .stated)
        #expect(details.country == "Ethiopia")
        #expect((details.certainty[.country] ?? .guessed) == .guessed)
    }
}
