import Foundation
import Testing

@testable import CoffeeCore

@Suite struct BagLabelTests {
    private typealias Line = BagLabel.Line

    @Test func matchesAKnownRoasterAndTakesTheBiggestOtherLineForTheCoffee() {
        let lines = [
            Line("ONYX COFFEE LAB", height: 0.04),
            Line("Colombia La Fortuna", height: 0.08),
            Line("Washed · Caturra", height: 0.03),
            Line("Net Wt 10oz", height: 0.02),
        ]
        let reading = BagLabel.read(lines, knownRoasters: ["Onyx Coffee Lab", "Sey"])
        #expect(reading == BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia La Fortuna"))
    }

    @Test func matchesARoasterWithoutItsAccents() {
        let lines = [Line("Pepe Jijon", height: 0.07), Line("Cafe Ayla", height: 0.03)]
        #expect(BagLabel.read(lines, knownRoasters: ["Café Ayla"]).roaster == "Café Ayla")
    }

    @Test func aRoasterMatchesOnlyWholeWords() {
        let lines = [Line("Seyfu Hambela", height: 0.08)]
        #expect(BagLabel.read(lines, knownRoasters: ["Sey"]) == BagLabel.Reading(roaster: "", coffee: "Seyfu Hambela"))
    }

    @Test func prefersTheLongestKnownRoaster() {
        let lines = [Line("Square Mile Coffee Roasters", height: 0.05), Line("Red Brick", height: 0.08)]
        #expect(BagLabel.read(lines, knownRoasters: ["Square Mile", "Square Mile Coffee Roasters"]).roaster == "Square Mile Coffee Roasters")
    }

    @Test func guessesTheRoasterAsTheNextBiggestLineWhenItIsUnknown() {
        let lines = [
            Line("Hanan Million", height: 0.09),
            Line("Tasting notes: peach, jasmine", height: 0.05),
            Line("Bombe", height: 0.06),
            Line("Ethiopia", height: 0.03),
        ]
        #expect(BagLabel.read(lines, knownRoasters: []) == BagLabel.Reading(roaster: "Bombe", coffee: "Hanan Million"))
    }

    @Test func joinsANameThatWrapsOntoASecondLine() {
        let lines = [Line("Reshad Ababulgu", height: 0.08), Line("White Honey", height: 0.075), Line("Ethiopia", height: 0.03)]
        #expect(BagLabel.read(lines, knownRoasters: []).coffee == "Reshad Ababulgu White Honey")
    }

    @Test func leavesOutWeightsDatesAddressesAndDetails() {
        #expect(!BagLabel.isCandidate("250g"))
        #expect(!BagLabel.isCandidate("12.10.2026"))
        #expect(!BagLabel.isCandidate("www.onyxcoffeelab.com"))
        #expect(!BagLabel.isCandidate("Process: Washed"))
        #expect(!BagLabel.isCandidate("1900 MASL"))
        #expect(!BagLabel.isCandidate("Roasted on Oct 3"))
        #expect(BagLabel.isCandidate("Finca Lerida"))
    }

    @Test func readsNothingFromAnEmptyLabel() {
        #expect(BagLabel.read([], knownRoasters: ["Sey"]) == BagLabel.Reading(roaster: "", coffee: ""))
    }

    @Test func searchesForTheCoffeeThenTheRoaster() throws {
        let url = try #require(BagLabel.searchURL(for: BagLabel.Reading(roaster: "Sey", coffee: "Pepe Jijón")))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.absoluteString.hasPrefix(BagLabel.searchPage + "?"))
        #expect(components.queryItems == [URLQueryItem(name: "q", value: "Pepe Jijón Sey")])
    }

    @Test func hasNoSearchWithNothingToSearchFor() {
        #expect(BagLabel.searchURL(for: BagLabel.Reading(roaster: " ", coffee: "")) == nil)
    }

    @Test func readsTheModelsAnswer() {
        let answer = "Sure!\n**Roaster:** Onyx Coffee Lab\nCoffee: Colombia La Fortuna\n"
        #expect(BagLabel.reading(fromModelAnswer: answer) == BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia La Fortuna"))
    }

    @Test func rejectsAnAnswerInTheWrongForm() {
        #expect(BagLabel.reading(fromModelAnswer: "I can't tell from this text.") == nil)
    }

    @Test func thePromptListsTheKnownRoastersAndTheLabel() {
        let prompt = BagLabel.prompt(for: [Line("Hanan Million", height: 0.1)], knownRoasters: ["Bombe", "Sey"])
        #expect(prompt.contains("Bombe, Sey"))
        #expect(prompt.hasSuffix("\n\nHanan Million"))
    }
}
