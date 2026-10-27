import Foundation
import Testing

@testable import CoffeeCore

@Suite struct BagLabelTests {
    /// A line at the left of the photo, `top` down from its top.
    private func line(_ text: String, top: Double, height: Double) -> BagLabel.Line {
        LabelPhotos.line(text, left: 0.1, top: top, width: 0.5, height: height)
    }

    private func isName(_ text: String) -> Bool {
        BagLabel.nameCandidate(line(text, top: 0.5, height: 0.02)) != nil
    }

    @Test func matchesAKnownRoasterAndTakesTheBiggestOtherLineForTheCoffee() {
        let lines = [
            line("ONYX COFFEE LAB", top: 0.1, height: 0.04),
            line("Colombia La Fortuna", top: 0.2, height: 0.08),
            line("Washed · Caturra", top: 0.3, height: 0.03),
            line("Net Wt 10oz", top: 0.4, height: 0.02),
        ]
        let reading = BagLabel.read(lines, knownRoasters: ["Onyx Coffee Lab", "Sey"])
        #expect(reading == BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia La Fortuna"))
    }

    @Test func aMonthInADateIsntARoaster() {
        // An H&S bag roasted in September, from someone who's bought from September Coffee
        for date in ["Roasted 18 September 2026", "ROASTED: SEPT 18", "Roasted in September", "Best before September 2027"] {
            let lines = [
                line("H&S", top: 0.1, height: 0.06),
                line("COFFEE ROASTERS", top: 0.165, height: 0.03),
                line("Gesha Village", top: 0.3, height: 0.07),
                line(date, top: 0.5, height: 0.02),
            ]
            let reading = BagLabel.read(lines, knownRoasters: ["September Coffee Company"])
            #expect(reading.roaster == "H&S COFFEE ROASTERS", "\(date)")
        }
    }

    @Test func aRoasterNamedForAMonthStillMatches() {
        for logo in ["SEPTEMBER COFFEE CO.", "September Coffee Roasters"] {
            let lines = [line(logo, top: 0.1, height: 0.04), line("Halo Beriti", top: 0.3, height: 0.08)]
            #expect(BagLabel.read(lines, knownRoasters: ["September Coffee Company"]).roaster == "September Coffee Company", "\(logo)")
        }
    }

    @Test func matchesARoasterWithoutItsAccents() {
        let lines = [line("Pepe Jijon", top: 0.1, height: 0.07), line("Cafe Ayla", top: 0.3, height: 0.03)]
        #expect(BagLabel.read(lines, knownRoasters: ["Café Ayla"]).roaster == "Café Ayla")
    }

    @Test func aRoasterMatchesOnlyWholeWords() {
        let lines = [line("Seyfu Hambela", top: 0.1, height: 0.08)]
        #expect(BagLabel.read(lines, knownRoasters: ["Sey"]) == BagLabel.Reading(roaster: "", coffee: "Seyfu Hambela"))
    }

    @Test func prefersTheLongestKnownRoaster() {
        let lines = [line("Square Mile Coffee Roasters", top: 0.1, height: 0.05), line("Red Brick", top: 0.3, height: 0.08)]
        let known = ["Square Mile", "Square Mile Coffee Roasters", "Mile"]
        #expect(BagLabel.read(lines, knownRoasters: known) == BagLabel.Reading(roaster: "Square Mile Coffee Roasters", coffee: "Red Brick"))
    }

    @Test func takesARoasterNamedOnOneLine() {
        let lines = [line("Putushio", top: 0.1, height: 0.05), line("Thankfully Coffee", top: 0.3, height: 0.03)]
        #expect(BagLabel.read(lines, knownRoasters: []) == BagLabel.Reading(roaster: "Thankfully Coffee", coffee: "Putushio"))
    }

    @Test func leavesTheRoasterBlankWhenNothingSaysWhich() {
        let lines = [
            line("Hanan Million", top: 0.1, height: 0.09),
            line("Tasting notes: peach, jasmine", top: 0.25, height: 0.05),
            line("Bombe", top: 0.35, height: 0.06),
            line("Ethiopia", top: 0.45, height: 0.03),
        ]
        #expect(BagLabel.read(lines, knownRoasters: []) == BagLabel.Reading(roaster: "", coffee: "Hanan Million"))
    }

    @Test func doesntJoinAProcessUnderTheName() {
        let lines = [line("Reshad Ababulgu", top: 0.3, height: 0.08), line("White Honey", top: 0.385, height: 0.075)]
        #expect(BagLabel.read(lines, knownRoasters: []).coffee == "Reshad Ababulgu")
    }

    @Test func leavesOutWeightsDatesAddressesAndDetails() {
        #expect(!isName("250g"))
        #expect(!isName("12.10.2026"))
        #expect(!isName("www.onyxcoffeelab.com"))
        #expect(!isName("Process: Washed"))
        #expect(!isName("1900 MASL"))
        #expect(!isName("Roasted on Oct 3"))
        #expect(!isName("Coffee Co."))
        #expect(isName("Finca Lerida"))
    }

    @Test func leavesOutListsOriginsVarietiesAndProcesses() {
        #expect(!isName("Green Apple, White Florals, Marshmallow"))
        #expect(!isName("golden raspberry · lemon sugar · lilac"))
        #expect(!isName("Landrace | Washed"))
        #expect(!isName("El Salvador"))
        #expect(!isName("HUILA, COLOMBIA"))
        #expect(isName("El Paraiso"))
        #expect(isName("Pink Bourbon"))
        #expect(BagLabel.nameCandidate(line("Danche | Ethiopia", top: 0.5, height: 0.02))?.text == "Danche")
    }

    @Test func readsNothingFromAnEmptyLabel() {
        #expect(BagLabel.read([], knownRoasters: ["Sey"]) == BagLabel.Reading(roaster: "", coffee: ""))
    }

    @Test func filtersByTheRoasterAndSearchesForTheCoffee() {
        // Bean Base's own format; its roaster filter matches part of a name
        let url = BagLabel.searchURL(for: BagLabel.Reading(roaster: "Thankfully Coffee", coffee: "Putushio"))
        #expect(
            url?.absoluteString
                == "https://www.loffeelabs.com/bean-base/search?f1=AND%3Aroaster%3AThankfully&f2=AND%3Asearch%3APutushio"
        )
    }

    @Test func filtersByTheDistinctivePartOfTheRoastersName() {
        func filter(_ roaster: String) -> String? {
            BagLabel.searchURL(for: BagLabel.Reading(roaster: roaster, coffee: ""))?.absoluteString
                .replacingOccurrences(of: BagLabel.searchPage + "?f1=AND%3Aroaster%3A", with: "")
        }
        #expect(filter("SEPTEMBER COFFEE CO.") == "SEPTEMBER")
        #expect(filter("Square Mile Coffee Roasters") == "Square%2520Mile")
        #expect(filter("H&S COFFEE ROASTERS") == "H%2526S")
        #expect(filter("Café Ayla") == "Caf%25C3%25A9%2520Ayla")
        #expect(filter("Coffee Collective") == "Collective")
        #expect(filter("Coffee Co") == "Coffee%2520Co")
    }

    @Test func leavesOutAnEmptyFilter() {
        let url = BagLabel.searchURL(for: BagLabel.Reading(roaster: " ", coffee: "Pepe Jijón"))
        #expect(url?.absoluteString == BagLabel.searchPage + "?f1=AND%3Asearch%3APepe%2520Jij%25C3%25B3n")
    }

    @Test func encodesCharactersThatWouldEndTheFilter() {
        let url = BagLabel.searchURL(for: BagLabel.Reading(roaster: "A&B", coffee: ""))
        #expect(url?.absoluteString == BagLabel.searchPage + "?f1=AND%3Aroaster%3AA%2526B")
    }

    @Test func hasNoSearchWithNothingToSearchFor() {
        #expect(BagLabel.searchURL(for: BagLabel.Reading(roaster: " ", coffee: "")) == nil)
    }

    @Test func searchesGoogleForTheRoastersFullNameAndTheCoffee() {
        let url = BagLabel.googleURL(for: BagLabel.Reading(roaster: "H&S Coffee Roasters", coffee: "Pepe Jijón"))
        #expect(url?.absoluteString == BagLabel.googlePage + "?q=H%26S%20Coffee%20Roasters%20Pepe%20Jij%C3%B3n")
    }

    @Test func searchesGoogleForWhicheverIsGiven() {
        let url = BagLabel.googleURL(for: BagLabel.Reading(roaster: " ", coffee: "Putushio"))
        #expect(url?.absoluteString == BagLabel.googlePage + "?q=Putushio")
        #expect(BagLabel.googleURL(for: BagLabel.Reading(roaster: "", coffee: " ")) == nil)
    }

    @Test func theModelsKnownRoasterHasToBeOnTheLabel() {
        // The model, told the user has bought from September Coffee, picks it from the roast date
        let lines = [
            line("H&S", top: 0.1, height: 0.06), line("COFFEE ROASTERS", top: 0.165, height: 0.03),
            line("Gesha Village", top: 0.3, height: 0.07), line("Roasted 18 September 2026", top: 0.5, height: 0.02),
        ]
        let model = BagLabel.Reading(roaster: "September Coffee Company", coffee: "Gesha Village")
        let guess = BagLabel.read(lines, knownRoasters: ["September Coffee Company"])
        let reading = BagLabel.checked(model, guess: guess, lines: lines, knownRoasters: ["September Coffee Company"])
        #expect(reading.roaster == "H&S COFFEE ROASTERS")
    }

    @Test func readsTheModelsAnswer() {
        let answer = "Sure!\n**Roaster:** Onyx Coffee Lab\nCoffee: Colombia La Fortuna\n"
        #expect(BagLabel.reading(fromModelAnswer: answer) == BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia La Fortuna"))
    }

    @Test func readsAModelAnswerThatGivesOnlyTheCoffee() {
        #expect(BagLabel.reading(fromModelAnswer: "Coffee: Putushio") == BagLabel.Reading(roaster: "", coffee: "Putushio"))
    }

    @Test func givesTheModelsRoasterItsNameInTheAppWhenOnlyTheModelFoundIt() {
        let lines = [line("onyx coffee lab", top: 0.1, height: 0.03), line("Colombia La Fortuna", top: 0.2, height: 0.08)]
        let model = BagLabel.Reading(roaster: "ONYX COFFEE LAB", coffee: "")
        let guess = BagLabel.Reading(roaster: "", coffee: "Colombia La Fortuna")
        let reading = BagLabel.checked(model, guess: guess, lines: lines, knownRoasters: ["Sey", "Onyx Coffee Lab"])
        #expect(reading == BagLabel.Reading(roaster: "Onyx Coffee Lab", coffee: "Colombia La Fortuna"))
    }

    @Test func aKnownRoasterNeedsMoreThanOneLetterToMatch() {
        // "J Coffee" is "J" once "Coffee" is left out: a stray letter on the label isn't it
        let lines = [line("Gichathaini AA", top: 0.1, height: 0.08), line("J", top: 0.3, height: 0.02)]
        #expect(BagLabel.read(lines, knownRoasters: ["J Coffee"]).roaster == "")
    }

    @Test func rejectsAnAnswerInTheWrongForm() {
        #expect(BagLabel.reading(fromModelAnswer: "I can't tell from this text.") == nil)
    }

    @Test func thePromptListsTheKnownRoastersAndTheLabel() {
        let prompt = BagLabel.prompt(for: [line("Hanan Million", top: 0.1, height: 0.1)], knownRoasters: ["Bombe", "Sey"])
        #expect(prompt.contains("Bombe, Sey"))
        #expect(prompt.hasSuffix("\n\n[big] Hanan Million"))
    }
}
