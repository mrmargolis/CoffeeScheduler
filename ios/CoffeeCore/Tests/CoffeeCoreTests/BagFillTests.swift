import Testing

@testable import CoffeeCore

@Suite struct BagFillTests {
    private func draft(_ certainty: Certainty, _ values: [BagField: String]) -> BagDraft {
        var draft = BagDraft()
        for (field, text) in values {
            draft.restore(text, in: field)
            draft.certainty[field] = certainty
        }
        return draft
    }

    @Test func aStatedSameValueConfirmsAGuess() {
        let photo = draft(.guessed, [.roaster: "Coffee Collective", .producer: "Hambela Estate"])
        let page = draft(.stated, [.roaster: "Coffee Collective"])
        let (merged, fill) = photo.filling(with: page)
        #expect(!merged.isGuess(.roaster))
        #expect(merged.isGuess(.producer))
        #expect(fill.confirmed == [.roaster])
        #expect(fill.filled.isEmpty && fill.replaced.isEmpty)
    }

    @Test func aGuessOfTheSameValueConfirmsNothing() {
        let (merged, fill) = draft(.guessed, [.region: "Guji"]).filling(with: draft(.guessed, [.region: "Guji"]))
        #expect(merged.isGuess(.region))
        #expect(fill.fields.isEmpty)
    }

    @Test func recordsWhatItFilledAndWhatItReplaced() {
        let page = draft(.stated, [.coffee: "Hambela Natural", .region: "Guji"])
        let photo = draft(.stated, [.region: "Guji Zone", .weight: "250", .roastDate: "2026-10-14"])
        let (merged, fill) = page.filling(with: photo)
        #expect(fill.filled == [.roastDate, .weight])
        #expect(fill.replaced == [BagFill.Replacement(field: .region, old: "Guji")])
        #expect(merged.region == "Guji Zone")
        #expect(merged.coffee == "Hambela Natural")
    }

    @Test func puttingBackAReplacedValueKeepsIt() {
        var (merged, _) = draft(.stated, [.region: "Guji"]).filling(with: draft(.stated, [.region: "Guji Zone"]))
        merged.restore("Guji", in: .region)
        #expect(merged.region == "Guji")
        #expect(merged.merging(draft(.stated, [.region: "Sidama"])).region == "Guji")
    }

    @Test func summarisesAFill() {
        func fill(_ filled: Int, _ replaced: Int, _ confirmed: Int) -> String {
            BagFill(
                filled: Array(BagField.allCases.prefix(filled)),
                replaced: BagField.allCases.prefix(replaced).map { .init(field: $0, old: "") },
                confirmed: Array(BagField.allCases.prefix(confirmed))
            ).summary(from: "the page")
        }
        #expect(fill(1, 0, 0) == "Filled 1 field from the page.")
        #expect(fill(2, 1, 0) == "Filled 2 fields and replaced 1 from the page.")
        #expect(fill(0, 2, 0) == "Replaced 2 fields from the page.")
        #expect(fill(2, 1, 2) == "Filled 2 fields, replaced 1 and confirmed 2 guesses from the page.")
        #expect(fill(0, 0, 1) == "Confirmed 1 guess from the page.")
        #expect(fill(0, 0, 0) == "Nothing new from the page. Fill in the rest by hand.")
    }

    @Test func countsFilledFieldsAndGuesses() {
        var bag = draft(.guessed, [.producer: "Hambela Estate"])
        bag.type("Ethiopia", in: .country)
        #expect(bag.count(BagField.origin) == (filled: 2, guesses: 1))
    }

    @Test func linesUpTheOrigin() {
        let bag = draft(.stated, [.country: "Ethiopia", .region: "Guji", .process: "Natural", .notes: "Peach"])
        #expect(bag.originLine == "Ethiopia · Guji · Natural")
    }

    @Test func typingANewlineKeepsOneLine() {
        var bag = BagDraft()
        bag.type("Hambela\nNatural", in: .coffee)
        #expect(bag.coffee == "Hambela Natural")
    }
}
