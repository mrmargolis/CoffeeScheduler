import Foundation
import Testing

@testable import CoffeeCore

/// A cup with only what's given judged, at medium agitation unless said.
private func cup(
    _ ratings: [SensoryAttribute: Int] = [:], drawdown: Drawdown? = nil, character: Set<CharacterTag> = [],
    agitation: Agitation? = .medium, tried: Set<DialInVariable> = []
) -> CupTasting {
    CupTasting(ratings: ratings, drawdown: drawdown, character: character, agitation: agitation, tried: tried)
}

private func instruction(_ cup: CupTasting) -> String? {
    DialInAdvisor.advise(cup).suggestion?.instruction
}

@Suite struct DialInRuleTests {
    @Test(arguments: [
        (cup([.finish: -2], drawdown: .slow), "A slow drawdown with low clarity, finish or sweetness.", "Grind coarser"),
        (cup([.intensity: -1], drawdown: .fast), "A fast drawdown with low intensity.", "Grind finer"),
        (cup([.intensity: -1, .sweetness: -1, .acidity: -1]), "Intensity, sweetness and acidity all low.", "Grind finer"),
        (cup([.sweetness: -1], character: [.sharp]), "Low sweetness with sharp acidity.", "Grind finer"),
        (cup([.acidity: 0], character: [.bitter]), "Tasted bitter.", "Cooler water"),
        (cup([.clarity: -1, .intensity: 0]), "Muddy, or low clarity with enough intensity.", "Less agitation: medium → low"),
        (cup([.body: 1]), "Body slightly high.", "Less agitation: medium → low"),
        (cup([.acidity: -1, .sweetness: 0]), "Low acidity with enough sweetness.", "Grind coarser"),
        (cup([.intensity: -1, .sweetness: 0, .body: 0]), "Low intensity in an otherwise good cup.", "Shorter ratio (less water)"),
        (cup([.intensity: 2]), "Flavour intensity much too high.", "Longer ratio (more water)"),
        (cup([.sweetness: -1, .finish: -1]), "Sweetness slightly low, finish length slightly low.", "Hotter water"),
    ])
    func eachRuleFiresOnItsPattern(cup: CupTasting, pattern: String, expected: String) {
        let advice = DialInAdvisor.advise(cup)
        #expect(advice.diagnosis.first == pattern)
        #expect(advice.suggestion?.instruction == expected)
    }

    @Test func anEarlierRuleWinsWhenSeveralMatch() {
        // Slow drawdown (rule 2) and all three low (rule 4)
        let advice = DialInAdvisor.advise(cup([.intensity: -1, .sweetness: -1, .acidity: -1], drawdown: .slow))
        #expect(advice.diagnosis.first == "A slow drawdown with low clarity, finish or sweetness.")
    }

    @Test func unratedAttributesDontCountAsNotLow() {
        // Low clarity, but intensity unrated: not rule 7, and nothing else matches
        #expect(DialInAdvisor.advise(cup([.clarity: -1])).next == .noSuggestion)
    }

    @Test func characterRulesNeedTheirTags() {
        // Low sweetness alone is the last rule, not "with sharp acidity"
        #expect(DialInAdvisor.advise(cup([.sweetness: -1])).diagnosis == ["Sweetness slightly low."])
    }

    @Test func aRuleThatOnlyRestatesARatingAddsNoLine() {
        #expect(DialInAdvisor.advise(cup([.sweetness: -2])).diagnosis == ["Sweetness much too low."])
    }

    @Test func theSuggestionCarriesItsEffectAndCriteria() throws {
        let suggestion = try #require(DialInAdvisor.advise(cup([.finish: -2, .sweetness: -1], drawdown: .slow)).suggestion)
        #expect(suggestion.move == DialInMove(.grind, .down))
        #expect(suggestion.expectedEffect == "A faster drawdown; clearer and sweeter, with a longer finish")
        #expect(suggestion.criteria.map(\.result) == ["Better", "Overshot: too far the other way", "No change", "Worse"])
        #expect(suggestion.criteria[2].next == "Go back, and try: less agitation")
    }
}

@Suite struct DialInAgitationTests {
    @Test func withoutAgitationGivenItsADirection() {
        #expect(instruction(cup([.body: 1], agitation: nil)) == "Less agitation")
    }

    @Test func alreadyLowFallsBackToTheAlternate() {
        #expect(instruction(cup([.body: 1], agitation: .low)) == "Grind coarser")
    }

    @Test func alreadyHighCantGoHigher() {
        #expect(DialInMove(.agitation, .up).isPossible(from: .high) == false)
        #expect(DialInMove(.agitation, .up).isPossible(from: .medium))
    }

    @Test func otherMovesAreAlwaysPossible() {
        #expect(DialInMove(.grind, .down).isPossible(from: .low))
        #expect(DialInMove(.temperature, .up).isPossible(from: .high))
    }
}

@Suite struct DialInTriedTests {
    /// Not sweet, not juicy, not punchy, after grind went both ways.
    private let flatFruit: [SensoryAttribute: Int] = [.sweetness: -2, .acidity: -1, .intensity: -1]

    @Test func aTriedChangeIsSkippedForTheRulesOtherMove() {
        #expect(instruction(cup(flatFruit)) == "Grind finer")
        #expect(instruction(cup(flatFruit, tried: [.grind])) == "Hotter water")
    }

    @Test func withTheOtherMoveTriedTooTheNoChangeStepSaysSo() throws {
        let suggestion = try #require(DialInAdvisor.advise(cup(flatFruit, tried: [.grind])).suggestion)
        #expect(suggestion.criteria[2].next == "Go back, tick temperature as tried, and rate the cup again")
    }

    @Test func bothMovesTriedLeavesADiagnosisWithoutASuggestion() {
        let advice = DialInAdvisor.advise(cup(flatFruit, tried: [.grind, .temperature]))
        #expect(advice.next == .noSuggestion)
        #expect(advice.diagnosis == ["Acidity slightly low, sweetness much too low, flavour intensity slightly low."])
    }

    @Test func triedAloneIsntAJudgementOfTheCup() {
        #expect(DialInAdvisor.advise(CupTasting(tried: [.grind])).next == .nothingRated)
    }
}

@Suite struct DialInAdviceOutcomeTests {
    @Test func everythingOnTargetIsNothingToChange() {
        let advice = DialInAdvisor.advise(cup([.acidity: 0, .sweetness: 0, .body: 0], drawdown: .normal))
        #expect(advice.next == .nothingToChange)
        #expect(advice.diagnosis == ["Everything you rated is on target."])
    }

    @Test func nothingJudgedSaysSo() {
        #expect(DialInAdvisor.advise(CupTasting()).next == .nothingRated)
        // Agitation alone isn't a judgement of the cup
        #expect(DialInAdvisor.advise(CupTasting(agitation: .high)).next == .nothingRated)
    }

    @Test func theDiagnosisNamesWhatsOffAndAnOddDrawdown() {
        let advice = DialInAdvisor.advise(cup([.sweetness: -1, .finish: -2, .acidity: 0], drawdown: .slow, character: [.muddy]))
        #expect(
            advice.diagnosis == [
                "A slow drawdown with low clarity, finish or sweetness.",
                "Sweetness slightly low, finish length much too low.",
                "Tasted muddy.",
                "The drawdown was slow.",
            ])
    }

    @Test func aProblemWithNoRuleGivesADiagnosisWithoutASuggestion() {
        let advice = DialInAdvisor.advise(cup([.acidity: 1]))
        #expect(advice.next == .noSuggestion)
        #expect(advice.diagnosis == ["Acidity slightly high."])
    }

    @Test func aSlowDrawdownAloneIsNamedButNotActedOn() {
        let advice = DialInAdvisor.advise(cup(drawdown: .slow))
        #expect(advice.next == .noSuggestion)
        #expect(advice.diagnosis == ["The drawdown was slow."])
    }
}
