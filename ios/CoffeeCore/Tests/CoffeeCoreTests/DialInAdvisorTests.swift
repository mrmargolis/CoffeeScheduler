import Foundation
import Testing

@testable import CoffeeCore

/// A cup with only what's given judged, at medium agitation unless said.
private func cup(
    _ ratings: [SensoryAttribute: Int] = [:], drawdown: Drawdown? = nil, flowProblem: Bool = false,
    character: Set<CharacterTag> = [], agitation: Agitation? = .medium
) -> CupTasting {
    CupTasting(ratings: ratings, drawdown: drawdown, flowProblem: flowProblem, character: character, agitation: agitation)
}

private func instruction(_ cup: CupTasting) -> String? {
    DialInAdvisor.advise(cup).suggestion?.instruction
}

@Suite struct DialInRuleTests {
    @Test(arguments: [
        (cup([.clarity: -1], flowProblem: true), "The bed stalled or channelled.", "Less agitation: medium → low"),
        (cup([.finish: -2], drawdown: .slow), "A slow drawdown with low clarity, finish or sweetness.", "Grind coarser"),
        (cup([.intensity: -1], drawdown: .fast), "A fast drawdown with low intensity.", "Grind finer"),
        (cup([.intensity: -1, .sweetness: -1, .acidity: -1]), "Intensity, sweetness and acidity all low.", "Grind finer"),
        (cup([.sweetness: -1], character: [.sharp]), "Low sweetness with sharp acidity.", "Grind finer"),
        (cup([.acidity: 0], character: [.bitter]), "Bitterness.", "Cooler water"),
        (cup([.clarity: -1, .intensity: 0]), "Muddy, or low clarity with enough intensity.", "Less agitation: medium → low"),
        (cup([.body: 1]), "Too much body.", "Less agitation: medium → low"),
        (cup([.acidity: -1, .sweetness: 0]), "Low acidity with enough sweetness.", "Grind coarser"),
        (cup([.intensity: -1, .sweetness: 0, .body: 0]), "Low intensity in an otherwise good cup.", "Shorter ratio (less water)"),
        (cup([.intensity: 2]), "Too intense.", "Longer ratio (more water)"),
        (cup([.sweetness: -1, .finish: -1]), "Low sweetness.", "Hotter water"),
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
        #expect(DialInAdvisor.advise(cup([.sweetness: -1])).diagnosis.first == "Low sweetness.")
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
}
